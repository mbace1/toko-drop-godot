## powerup_pool.gd — the things kills leave on the floor.
##
## The browser drops weapon PODS from kills; you walk over one and your gun
## changes for the rest of the run (or until the next pod). `WEAPON_PODS` in
## main.js is the table: S/S2 spread, B/B2 burst, L/L2 laser, R/R2 rapid, each
## with its own colour, and level-2 variants that only start dropping later.
##
## Two rules carried over from the source that matter more than they look:
##  - **H/H2 are NOT in the drop pool.** enemy.js v88: *"homing is
##    enemy-exclusive now (BOTFLY fires homing shots)"*. The firing mode stays
##    implemented in case a pod is ever re-added, but the player does not get
##    the enemy's signature toy.
##  - **Pods EXPIRE.** A pod that waits forever turns every kill into deferred
##    shopping; one that fades makes taking it a decision you make now, while
##    the arena is still dangerous.
class_name PowerupPool
extends Node3D

const POOL_SIZE := 16
const LIFE := 12.0
const PICKUP_R := 1.15
const BOB := 0.22

## id -> {mode, color, level}. Mirrors main.js's WEAPON_PODS.
const PODS := {
	"S":  {"mode": "SPREAD",  "color": Color(1.0, 0.8, 0.267),  "level": 1},
	"S2": {"mode": "SPREAD2", "color": Color(1.0, 0.933, 0.067), "level": 2},
	"B":  {"mode": "BURST",   "color": Color(0.267, 1.0, 0.8),  "level": 1},
	"B2": {"mode": "BURST2",  "color": Color(0.067, 1.0, 0.933), "level": 2},
	"L":  {"mode": "LASER",   "color": Color(1.0, 0.2, 0.333),  "level": 1},
	"L2": {"mode": "LASER2",  "color": Color(1.0, 0.067, 0.2),  "level": 2},
	"R":  {"mode": "RAPID",   "color": Color(0.667, 0.333, 1.0), "level": 1},
	"R2": {"mode": "RAPID2",  "color": Color(0.8, 0.133, 1.0),  "level": 2},
}
const LV1 := ["S", "B", "L", "R"]
const LV2 := ["S2", "B2", "L2", "R2"]
## main.js: level-2 pods only from wave 4, and only 28% of the time even then.
const LV2_FROM_WAVE := 4
const LV2_CHANCE := 0.28

## Non-weapon walk-over pickups (main.js `Powerup`/`NON_WEAPON_COLORS`).
## That class covers 8 types; `hp`/`invincible`/`firerate`/`item`/`key`/
## `potion` are either KAIKKI-mode shaped pickups (a key that looks like a
## key, a flask that looks like a flask — a different mode's own art, not a
## gap here) or player buffs this port has no slot for yet. Only the two
## CLASSIC-mode value drops this port's OWN systems (the cargo convoy,
## VaultCrate) actually roll for are ported: an instant score nugget, and a
## timed x2 SCORE MULTIPLIER (`main.gd`'s `score_mult_t`).
const VALUES := {
	"score":     {"color": Color(0.533, 1.0, 0.533)},
	"scoremult": {"color": Color(1.0, 0.867, 0.2)},
}

signal taken(mode: String, color: Color)
## `value` only means something for VALUES ids — 0 for "scoremult", which
## pays a fixed duration rather than an amount.
signal value_taken(kind: String, value: int, color: Color)

var _x := PackedFloat32Array()
var _z := PackedFloat32Array()
var _life := PackedFloat32Array()
var _id: Array[String] = []
var _value := PackedInt32Array()
var _mm: MultiMeshInstance3D
var _built := false

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true
	_x.resize(POOL_SIZE); _z.resize(POOL_SIZE); _life.resize(POOL_SIZE)
	_id.resize(POOL_SIZE)
	_value.resize(POOL_SIZE)

	# An octahedron reads as a PICKUP at a glance: nothing else in the arena
	# is a faceted spinning solid, so it never gets lost among the bodies.
	var m := SphereMesh.new()
	# Big enough to notice across the arena: a pickup you do not see is a
	# pickup you do not take.
	m.radius = 0.46
	m.height = 1.2
	m.radial_segments = 4
	m.rings = 2

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 2.2
	mat.roughness = 0.2

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = 0
	mm.mesh = m

	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.material_override = mat
	add_child(_mm)

## Rolls a pod id for the current wave. Level 2 only from wave 4, and only
## sometimes even then (main.js randomWeaponPodId).
func roll(wave: int, rng: RandomNumberGenerator) -> String:
	if wave >= LV2_FROM_WAVE and rng.randf() < LV2_CHANCE:
		return LV2[rng.randi() % LV2.size()]
	return LV1[rng.randi() % LV1.size()]

func drop(x: float, z: float, id: String, value: int = 0) -> void:
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			continue
		_x[i] = x; _z[i] = z
		_life[i] = LIFE
		_id[i] = id
		_value[i] = value
		return
	# Full: the oldest one goes, rather than the drop being silently lost.
	var worst := 0
	var worst_life := INF
	for i in POOL_SIZE:
		if _life[i] < worst_life:
			worst_life = _life[i]
			worst = i
	_x[worst] = x; _z[worst] = z
	_life[worst] = LIFE
	_id[worst] = id
	_value[worst] = value

## Steps the pods and collects any the player is standing on.
func update(delta: float, player_pos: Vector3, t: float) -> void:
	if not _built:
		return
	var n := 0
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue

		var dx := player_pos.x - _x[i]
		var dz := player_pos.z - _z[i]
		var is_pod: bool = PODS.has(_id[i])
		if dx * dx + dz * dz < PICKUP_R * PICKUP_R:
			_life[i] = 0.0
			if is_pod:
				var def: Dictionary = PODS[_id[i]]
				taken.emit(String(def["mode"]), def["color"])
			else:
				var vdef: Dictionary = VALUES[_id[i]]
				value_taken.emit(_id[i], _value[i], vdef["color"])
			continue

		var def2: Dictionary = PODS[_id[i]] if is_pod else VALUES[_id[i]]
		var y := 0.55 + sin(t * 3.0 + float(i)) * BOB
		var b := Basis(Vector3.UP, t * 1.8 + float(i))
		# Blink out over the last two seconds, so "it is about to go" is a
		# thing you can see rather than a thing you learn by losing one.
		var vis: bool = _life[i] > 2.0 or int(_life[i] * 8.0) % 2 == 0
		if not vis:
			continue
		_mm.multimesh.set_instance_transform(n, Transform3D(b, Vector3(_x[i], y, _z[i])))
		_mm.multimesh.set_instance_color(n, def2["color"])
		n += 1
	_mm.multimesh.visible_instance_count = n

func clear() -> void:
	for i in POOL_SIZE:
		_life[i] = 0.0
	if _built:
		_mm.multimesh.visible_instance_count = 0
