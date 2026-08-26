## bambu.gd
##
## BAMBU — a stationary segmented "cross-stalk" lobber (enemy.js "Part 5",
## TUNING.bambu). It never moves: the whole threat is a slow, telegraphed lob
## that has to be dodged AFTER it lands, not a bullet you weave.
##
## Attack cycle (enemy.js update(), the EnemyType.BAMBU branch):
##   WAITING       — counts down `fireInterval` (lobCooldown 4.0s).
##   TELEGRAPHING  — 0.7s. A flashing landing ring appears at
##                   playerPos ± lobSpread, and a charge orb climbs the stalk.
##   LOBBING       — 1.0s. A visible blob arcs from the stalk tip to the ring
##                   on a parabola (lobArcHeight 2.4), the ring flashing faster.
##   SPLASHDOWN    — main.js drains the landed lob: droplets, a shake, and
##                   player damage ONLY if still standing in the ring
##                   (RING_OUTER + PLAYER_RADIUS) — this port does that in
##                   main.gd's `_collide_bambu_lobs()`, the same "only
##                   reachable through input is a system the gate cannot see"
##                   reason `_collide_contact()` is its own method.
##
## Stats — CFG (enemy.js line 500) + TUNING.bambu:
##   color 0xaa8844, radius 0.7 (nominal — the LIVE radius scales with
##   segments left, `max(0.6, segs * 0.6)`), speed 0, hp = segment count,
##   bulletColor 0xddbb44, fireInterval TUNING.bambu.lobCooldown (4.0).
##
## Divergence, deliberately scoped down: the browser grows from 1 segment to
## 3 over its first ~0.5s after emerging from the floor (a cosmetic "rising
## tower" beat, `hp++` as each one appears). This port spawns pre-grown at
## full HP/segments — the growth window is under a second in the source and
## the emerge-from-floor scale animation isn't worth the state for it.
class_name Bambu
extends Enemy

const SEGMENTS := 3
const SEG_HEIGHT := 0.6
const FLARE_BOTTOM := 0.20
const FLARE_BOTTOM_STEP := 0.02
const FLARE_TOP := 0.36
const FLARE_TOP_STEP := 0.03
const LIP_SCALE := 1.14
const LIP_HEIGHT := 0.06

const LOB_TELEGRAPH := 0.7
const LOB_FLIGHT := 1.0
const LOB_COOLDOWN := 4.0
const LOB_ARC_HEIGHT := 2.4
const LOB_BLOB_R := 0.34
const LOB_SPREAD := 1.2
const RING_INNER := 0.55
const RING_OUTER := 0.95
const TELEGRAPH_HZ := 22.0
const FLIGHT_HZ := 40.0

enum LobState { WAITING, TELEGRAPHING, LOBBING }

var _stalk: Node3D
var _state := LobState.WAITING
var _wait_t := 1.3   # enemy.js: the first lob charges up almost immediately
var _phase_t := 0.0
var _lob_t := 0.0
var _lob_target := Vector2.ZERO
var _lob_start := Vector3.ZERO
var _lob_ring: MeshInstance3D
var _lob_ring_mat: StandardMaterial3D
var _lob_blob: MeshInstance3D
var _lob_blob_mat: StandardMaterial3D
## One splashdown's landing point, drained (once) by main.gd's
## `_collide_bambu_lobs()`. main.js's own name for this field is `_lobLanded`.
var _landed = null

func init() -> void:
	setup(Color(0.667, 0.533, 0.267), 0.7, 0.0, SEGMENTS, true)
	bullet_color = Color(0.867, 0.733, 0.267)
	fire_interval = LOB_COOLDOWN
	# The base sphere/box from setup() is a placeholder for every OTHER type;
	# BAMBU builds its own stacked stalk instead (same move TORO makes for
	# its wheel — mesh.mesh = null keeps `mesh` as the squash/wobble transform
	# holder without drawing a leftover ball underneath the real geometry).
	mesh.mesh = null
	_stalk = Node3D.new()
	mesh.add_child(_stalk)
	for i in SEGMENTS:
		_add_segment()
	# get_radius() (enemy.js line 1169): the live radius tracks segments, not
	# the nominal CFG value setup() just set.
	radius = maxf(0.6, float(SEGMENTS) * 0.6)

	# Scene-level, not stalk-children: enemy.js adds the ring/blob to `scene`
	# directly (not the tower's group) because the landing point is the
	# PLAYER's business, independent of where the tower happens to stand.
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = RING_INNER
	ring_mesh.outer_radius = RING_OUTER
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	_lob_ring_mat = StandardMaterial3D.new()
	_lob_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lob_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lob_ring_mat.albedo_color = Color(bullet_color.r, bullet_color.g, bullet_color.b, 0.6)
	_lob_ring = MeshInstance3D.new()
	_lob_ring.mesh = ring_mesh
	_lob_ring.material_override = _lob_ring_mat
	_lob_ring.visible = false
	get_parent().add_child(_lob_ring)

	var blob_mesh := SphereMesh.new()
	blob_mesh.radius = LOB_BLOB_R
	blob_mesh.height = LOB_BLOB_R * 2.0
	_lob_blob_mat = StandardMaterial3D.new()
	_lob_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lob_blob_mat.albedo_color = bullet_color
	_lob_blob_mat.emission_enabled = true
	_lob_blob_mat.emission = bullet_color
	_lob_blob_mat.emission_energy_multiplier = 1.4
	_lob_blob = MeshInstance3D.new()
	_lob_blob.mesh = blob_mesh
	_lob_blob.material_override = _lob_blob_mat
	_lob_blob.visible = false
	get_parent().add_child(_lob_blob)

## _makeBambuSeg (enemy.js line 1284): each segment is a tapered cylinder
## WIDER at the top than the bottom (a joint flaring upward), with a slightly
## wider "lip" ring sitting on top of it — the knuckle read.
func _add_segment() -> void:
	var i := _stalk.get_child_count()
	var bot_r := FLARE_BOTTOM + float(i) * FLARE_BOTTOM_STEP
	var top_r := FLARE_TOP + float(i) * FLARE_TOP_STEP

	var seg := Node3D.new()
	seg.position.y = float(i) * SEG_HEIGHT
	_stalk.add_child(seg)

	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = SEG_HEIGHT
	cm.radial_segments = 14
	var cyl := MeshInstance3D.new()
	cyl.mesh = cm
	cyl.position.y = SEG_HEIGHT * 0.5
	cyl.material_override = mat
	seg.add_child(cyl)

	var lm := CylinderMesh.new()
	lm.top_radius = top_r * LIP_SCALE
	lm.bottom_radius = top_r * LIP_SCALE
	lm.height = LIP_HEIGHT
	lm.radial_segments = 14
	var lip := MeshInstance3D.new()
	lip.mesh = lm
	lip.position.y = SEG_HEIGHT
	lip.material_override = mat
	seg.add_child(lip)

## hit() (enemy.js line 1303): every hit pops the TOP segment, regardless of
## how much HP it actually cost — the stalk visibly shortens hit-by-hit.
func take_hit(dmg: int) -> bool:
	var killed := super(dmg)
	if _stalk != null and _stalk.get_child_count() > 0:
		var top := _stalk.get_child(_stalk.get_child_count() - 1)
		_stalk.remove_child(top)
		top.queue_free()
		# get_radius() (enemy.js line 1169): the live radius tracks what's
		# actually left standing, not the nominal CFG value.
		radius = maxf(0.6, float(_stalk.get_child_count()) * 0.6)
	if killed:
		_cancel_lob()
	return killed

## "Hide any in-flight lob when BAMBU dies mid-cycle" (main.js comment above
## the splashdown drain) — a tower that is gone should not still be arcing a
## shot in from off-screen.
func _cancel_lob() -> void:
	if is_instance_valid(_lob_ring):
		_lob_ring.visible = false
	if is_instance_valid(_lob_blob):
		_lob_blob.visible = false
	_landed = null

func die() -> void:
	super()
	_cancel_lob()

## The ring/blob are scene-level siblings, not children, so they need their
## own cleanup whenever this body actually leaves the tree (queue_free(), or
## WaveDirector.clear() sweeping every enemy/corpse at once).
func _exit_tree() -> void:
	if is_instance_valid(_lob_ring):
		_lob_ring.queue_free()
	if is_instance_valid(_lob_blob):
		_lob_blob.queue_free()

## Consumes this run's splashdown, if one landed since the last call. Called
## by main.gd's `_collide_bambu_lobs()` every frame; returns null on every
## frame that isn't the exact one a lob lands on.
func drain_landed():
	var l = _landed
	_landed = null
	return l

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return
	match _state:
		LobState.WAITING:
			_wait_t -= delta
			if _wait_t <= 0.0 and target != null:
				_state = LobState.TELEGRAPHING
				_phase_t = LOB_TELEGRAPH
				_lob_t = 0.0
				_lob_target = Vector2(
					target.position.x + (rng.randf() * 2.0 - 1.0) * LOB_SPREAD,
					target.position.z + (rng.randf() * 2.0 - 1.0) * LOB_SPREAD)
				_lob_ring.position = Vector3(_lob_target.x, 0.02, _lob_target.y)
				_lob_ring.visible = true
		LobState.TELEGRAPHING:
			_phase_t -= delta
			_lob_t += delta
			_lob_ring_mat.albedo_color.a = 0.75 if sin(_lob_t * TELEGRAPH_HZ) > 0.0 else 0.2
			if _phase_t <= 0.0:
				_state = LobState.LOBBING
				_phase_t = LOB_FLIGHT
				_lob_start = Vector3(position.x, float(_stalk.get_child_count()) * SEG_HEIGHT, position.z)
				_lob_blob.visible = true
		LobState.LOBBING:
			_phase_t -= delta
			_lob_t += delta
			_lob_ring_mat.albedo_color.a = 0.85 if sin(_lob_t * FLIGHT_HZ) > 0.0 else 0.25
			var p := clampf(1.0 - _phase_t / LOB_FLIGHT, 0.0, 1.0)
			_lob_blob.position = Vector3(
				lerpf(_lob_start.x, _lob_target.x, p),
				_lob_start.y * (1.0 - p) + LOB_ARC_HEIGHT * 4.0 * p * (1.0 - p),
				lerpf(_lob_start.z, _lob_target.y, p))
			if _phase_t <= 0.0:
				_lob_blob.visible = false
				_lob_ring.visible = false
				_landed = Vector2(_lob_target.x, _lob_target.y)
				_state = LobState.WAITING
				_wait_t = fire_interval
