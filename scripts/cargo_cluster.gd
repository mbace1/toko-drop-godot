## cargo_cluster.gd
##
## The cargo convoy (main.js `CargoCluster`, class at line 1523): a formation
## of 3-5 golden goo-moths that flies in a straight line across the arena
## with a sinusoidal sweep, from one wave clock per wave (main.js: "3-8s
## into the wave — always overlaps live enemies"). They never attack — the
## whole event is a bonus window. Shoot them before they cross the far edge
## and they drop loot; leave any of them uncontested and you only lose the
## fastest payout, killing every one before any escapes.
##
## Base/Classic mode only (this port's own scoping — see main.gd's
## `_update_cargo()`): weapon pods are already suppressed outside base mode
## (`_rush_verbs()` guards the wave-kill pod roll the same way), and a
## convoy's whole point is dropping the pods Rush/Challenge runs deliberately
## don't want mixed into their own economy.
class_name CargoCluster
extends Node3D

const MIN_COUNT := 3
const COUNT_SPAN := 3          # 3 + [0..2] => 3-5
const SPEED_MIN := 5.5
const SPEED_SPAN := 2.0
const PERP_SPACING := 1.4
const CURVE_AMP_MIN := 3.0
const CURVE_AMP_SPAN := 5.0
const CURVE_FREQ_MIN := 0.7
const CURVE_FREQ_SPAN := 1.0
const BODY_R := 0.32
## main.js: `BULLET_R * BULLET_CONFIG.playerBulletScale + 0.32`. This port's
## player bullets don't carry that scale factor separately, so this is just
## BulletPool.BULLET_R + the moth's own hit padding — close enough that a
## moth still reads as "the thing your shots are landing on".
const HIT_R := 0.15 + 0.32

class Drone:
	var node: Node3D
	var body: MeshInstance3D
	var wing_l: MeshInstance3D
	var wing_r: MeshInstance3D
	var alive := true
	var escaped := false
	var base_perp := 0.0

var active := false
## Q-035: shares main.gd's Arena; half_x/half_z read through as the SIZE
## (the edge-spawn literals below are size questions and stay). Setters keep
## the hand-built tests working, each giving a private rectangle.
var arena: Arena = Arena.new(Arena.rect_shape(19.0, 11.0))
var half_x: float:
	get:
		return arena.half_x
	set(v):
		arena = Arena.new(Arena.rect_shape(v, arena.half_z))
var half_z: float:
	get:
		return arena.half_z
	set(v):
		arena = Arena.new(Arena.rect_shape(arena.half_x, v))
var drones: Array[Drone] = []

var _dx := 0.0
var _dz := 0.0
var _px := 0.0
var _pz := 0.0
var _speed := 0.0
var _curve_amp := 0.0
var _curve_freq := 0.0
var _curve_phase := 0.0
var _cx := 0.0
var _cz := 0.0
var _elapsed := 0.0

## `p_rng` is WaveDirector.rng — the convoy's spawn edge/curve/timing all
## affect what a player sees and when, so it draws from the gameplay stream
## rather than the global rng (design/DETERMINISM_AND_SEEDS.md): two Daily
## Run players on the same seed should see the same convoy at the same time.
func spawn(p_rng: RandomNumberGenerator) -> void:
	clear()
	var count := MIN_COUNT + p_rng.randi() % COUNT_SPAN
	var edge := p_rng.randi() % 4
	var sx := 0.0
	var sz := 0.0
	match edge:
		0:
			sx = (p_rng.randf() - 0.5) * half_x * 1.5
			sz = -(half_z + 3.0)
			_dx = 0.0; _dz = 1.0
		1:
			sx = (p_rng.randf() - 0.5) * half_x * 1.5
			sz = half_z + 3.0
			_dx = 0.0; _dz = -1.0
		2:
			sx = -(half_x + 3.0)
			sz = (p_rng.randf() - 0.5) * half_z * 1.5
			_dx = 1.0; _dz = 0.0
		_:
			sx = half_x + 3.0
			sz = (p_rng.randf() - 0.5) * half_z * 1.5
			_dx = -1.0; _dz = 0.0
	_speed = SPEED_MIN + p_rng.randf() * SPEED_SPAN
	_px = -_dz
	_pz = _dx
	_curve_amp = CURVE_AMP_MIN + p_rng.randf() * CURVE_AMP_SPAN
	_curve_freq = CURVE_FREQ_MIN + p_rng.randf() * CURVE_FREQ_SPAN
	_curve_phase = p_rng.randf() * TAU
	_cx = sx
	_cz = sz
	_elapsed = 0.0

	for i in count:
		var base_perp := (float(i) - float(count - 1) / 2.0) * PERP_SPACING
		var d := Drone.new()
		d.base_perp = base_perp
		_build_moth(d)
		add_child(d.node)
		d.node.position = Vector3(sx + _px * base_perp, 0.8, sz + _pz * base_perp)
		drones.append(d)
	active = true

func _build_moth(d: Drone) -> void:
	var container := Node3D.new()

	var bm := SphereMesh.new()
	bm.radius = BODY_R
	bm.height = BODY_R * 2.0
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.867, 0.333)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.867, 0.333)
	bmat.emission_energy_multiplier = 0.6
	var body := MeshInstance3D.new()
	body.mesh = bm
	body.material_override = bmat
	container.add_child(body)

	var wing_l := _make_wing(-1.0)
	var wing_r := _make_wing(1.0)
	container.add_child(wing_l)
	container.add_child(wing_r)

	d.node = container
	d.body = body
	d.wing_l = wing_l
	d.wing_r = wing_r

func _make_wing(side: float) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.52, 0.28)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(1.0, 0.933, 0.533, 0.6)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var w := MeshInstance3D.new()
	w.mesh = pm
	w.material_override = wmat
	w.position = Vector3(0.40 * side, 0.06, 0.0)
	return w

## Returns "alive" or "done" (every drone escaped or was killed).
func update(delta: float, t: float) -> String:
	if not active:
		return "done"
	_elapsed += delta
	_cx += _dx * _speed * delta
	_cz += _dz * _speed * delta
	var curve_off := sin(_curve_freq * _elapsed + _curve_phase) * _curve_amp
	var any_in_arena := false
	for i in drones.size():
		var d := drones[i]
		if not d.alive:
			continue
		var perp := d.base_perp + curve_off
		var px := _cx + _px * perp
		var pz := _cz + _pz * perp
		d.node.position.x = px
		d.node.position.z = pz
		var flap := sin(t * 12.0 + float(i) * 0.8) * 0.75
		d.wing_l.rotation.z = flap
		d.wing_r.rotation.z = -flap
		d.body.rotation.y = t * 1.5 + float(i) * 0.5
		# Q-035: "escaped" is `not contains(x, z, -slack)` — gated exactly
		# against the old |x| > hx+5 test in tests/arena_check.gd.
		if not arena.contains(px, pz, -5.0):
			d.escaped = true
			d.alive = false
			d.node.visible = false
		else:
			any_in_arena = true
	if not any_in_arena:
		active = false
		return "done"
	return "alive"

func kill(i: int) -> void:
	drones[i].alive = false
	drones[i].node.visible = false

## True only once every drone was actually SHOT — one escapee (even if the
## rest were killed) breaks the guaranteed-pod bonus (main.js:
## "Clearing every moth before any escape guarantees a weapon pod").
func all_killed() -> bool:
	for d in drones:
		if d.alive or d.escaped:
			return false
	return true

func clear() -> void:
	for d in drones:
		if is_instance_valid(d.node):
			d.node.queue_free()
	drones.clear()
	active = false
