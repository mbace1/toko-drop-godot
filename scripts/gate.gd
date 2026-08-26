## gate.gd
##
## Gate (main.js v175 "M5b gates, round 2", class at line 942): a laser
## barrier between two posts. Dash through it and it pays out — RISK gates
## alternate green/red on a readable 1.6s cycle (dash on green pays DOUBLE,
## red is a harmless dud), DRIFT gates wander slowly so the late-game route
## keeps changing. Every enemy that touches the beam takes damage too — it
## is a hazard for them as much as a reward for you.
##
## Spawning (main.js line 5295-5298, ported into main.gd's `_on_wave_started`):
## from wave 3, one new gate per wave, capped at 2 alive at once (the oldest
## is evicted, not just deactivated, when a 3rd would spawn). `risk` from
## wave 5 (35% chance); `drift` from wave 10.
class_name Gate
extends Node3D

const HALF_SEP := 2.0
const BEAM_LEN := 4.0
const BEAM_HALF_LEN := 2.0     # hits_point()'s "along the beam" half-length
const BEAM_WIDTH := 0.2        # hits_point()'s "across the beam" half-width
const DRIFT_SPEED := 0.4
const RISK_CYCLE := 1.6
const DMG_COOLDOWN := 0.5
const GREEN := Color(0.267, 1.0, 0.533)
const RED := Color(1.0, 0.267, 0.333)

var risk := false
var drift := false
var alive := true
var green := true
var angle := 0.0
var dmg_cooldown := 0.0
var _drift_dir := Vector2.ZERO

var _laser: MeshInstance3D
var _glow: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D

func build(x: float, z: float, p_angle: float, p_risk: bool, p_drift: bool,
		rng: RandomNumberGenerator) -> void:
	position = Vector3(x, 0.0, z)
	angle = p_angle
	risk = p_risk
	drift = p_drift
	if drift:
		var da := rng.randf() * TAU
		_drift_dir = Vector2(cos(da), sin(da)) * DRIFT_SPEED

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.533, 0.533, 0.6)
	post_mat.metallic = 0.4
	post_mat.roughness = 0.35
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.25
	post_mesh.bottom_radius = 0.25
	post_mesh.height = 1.8
	# Posts sit fixed relative to THIS node's own transform (children, not
	# independently-repositioned meshes the way main.js's flat x/z fields
	# need) — drift then only has to move `position`, and everything below
	# rides along with it for free.
	var dx := cos(angle + PI / 2.0) * HALF_SEP
	var dz := sin(angle + PI / 2.0) * HALF_SEP
	var p1 := MeshInstance3D.new()
	p1.mesh = post_mesh
	p1.material_override = post_mat
	p1.position = Vector3(dx, 0.9, dz)
	add_child(p1)
	var p2 := MeshInstance3D.new()
	p2.mesh = post_mesh
	p2.material_override = post_mat
	p2.position = Vector3(-dx, 0.9, -dz)
	add_child(p2)

	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.albedo_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.7)
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(BEAM_LEN, 0.25, 0.5)
	_laser = MeshInstance3D.new()
	_laser.mesh = laser_mesh
	_laser.material_override = _laser_mat
	_laser.position = Vector3(0.0, 0.9, 0.0)
	# Posts run along (-sin a, cos a); ported verbatim from main.js's own
	# rotation formula (its comment: three.js Y-rotation maps local +X to
	# (cos θ, -sin θ), so the beam has to rotate by -(angle + π/2) to line
	# up with the posts).
	_laser.rotation.y = -(angle + PI / 2.0)
	add_child(_laser)

	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.28)
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(BEAM_LEN, 0.7, 1.1)
	_glow = MeshInstance3D.new()
	_glow.mesh = glow_mesh
	_glow.material_override = _glow_mat
	_glow.position = _laser.position
	_glow.rotation.y = _laser.rotation.y
	add_child(_glow)

func update(delta: float, t: float, half_x: float, half_z: float) -> void:
	if not alive:
		return
	var pulse := 0.5 + 0.4 * sin(t * 8.0)
	var col := GREEN
	if risk:
		green = int(t / RISK_CYCLE) % 2 == 0
		col = GREEN if green else RED
	_laser_mat.albedo_color = Color(col.r, col.g, col.b, pulse)
	_glow_mat.albedo_color = Color(col.r, col.g, col.b, 0.12 + 0.18 * pulse)
	if drift:
		position.x += _drift_dir.x * delta
		position.z += _drift_dir.y * delta
		if absf(position.x) > half_x - 3.0:
			_drift_dir.x *= -1.0
		if absf(position.z) > half_z - 3.0:
			_drift_dir.y *= -1.0
	if dmg_cooldown > 0.0:
		dmg_cooldown -= delta

## "Used up" — the beam goes out, but (unlike being evicted by a 3rd gate
## spawning) the posts stay as a marker of where it was.
func deactivate() -> void:
	alive = false
	_laser.visible = false
	_glow.visible = false

## Approximate capsule check against the beam's own axis (not the posts) —
## ported directly from main.js's `hitsPoint()`.
func hits_point(px: float, pz: float, radius: float) -> bool:
	if not alive:
		return false
	var dx := px - position.x
	var dz := pz - position.z
	var ax := -sin(angle)
	var az := cos(angle)
	var para := dx * ax + dz * az
	var perp_x := dx - para * ax
	var perp_z := dz - para * az
	var perp_dist := sqrt(perp_x * perp_x + perp_z * perp_z)
	return absf(para) < BEAM_HALF_LEN and perp_dist < BEAM_WIDTH + radius
