## escort_bot.gd
##
## EscortBot (main.js v175, class at line 1072): "a little soap-bot trundles
## wall to wall; deliver it alive and it gifts a weapon pod. Enemies never
## chase it — but stray fire and bodies kill it, so protecting it is pure
## positioning." Spawns wave >= 6 on every 4th wave (w%4==1), never on a boss
## wave, entering from one side wall and crossing to the other over ~14s.
##
## Divergence: main.js's dome is a HALF sphere (`SphereGeometry(..., 0, PI,
## 0, PI/2)`); Godot's SphereMesh has no partial-sphere option, so this is a
## flattened full sphere instead — same silhouette read (a rounded cap on a
## cylinder body), not worth an ArrayMesh for a decorative dome.
class_name EscortBot
extends Node3D

const HP := 2
const HIT_R := 0.75
const CROSS_TIME := 14.0

var hp := HP
var target_x := 0.0
var _speed := 0.0
var _flash_t := 0.0
var _body_mat: StandardMaterial3D

func build(half_x: float, half_z: float, rng: RandomNumberGenerator) -> void:
	var westward := rng.randf() < 0.5
	var start_x := (1.0 if westward else -1.0) * (half_x - 1.5)
	var z := (rng.randf() * 2.0 - 1.0) * (half_z - 4.0)
	target_x = -start_x
	_speed = (half_x * 2.0 - 3.0) / CROSS_TIME
	position = Vector3(start_x, 0.0, z)

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.957, 0.967, 1.0)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color.BLACK
	var trim_mat := StandardMaterial3D.new()
	trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trim_mat.albedo_color = Color(0.267, 0.867, 1.0)

	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.32
	body_mesh.bottom_radius = 0.4
	body_mesh.height = 0.5
	body_mesh.radial_segments = 10
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = _body_mat
	body.position.y = 0.3
	add_child(body)

	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.28
	dome_mesh.height = 0.32
	var dome := MeshInstance3D.new()
	dome.mesh = dome_mesh
	dome.material_override = _body_mat
	dome.position.y = 0.55
	add_child(dome)

	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.07
	eye_mesh.height = 0.14
	var eye := MeshInstance3D.new()
	eye.mesh = eye_mesh
	eye.material_override = trim_mat
	eye.position = Vector3((1.0 if target_x > start_x else -1.0) * 0.22, 0.6, 0.0)
	add_child(eye)

	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.02
	mast_mesh.bottom_radius = 0.02
	mast_mesh.height = 0.3
	mast_mesh.radial_segments = 5
	var mast := MeshInstance3D.new()
	mast.mesh = mast_mesh
	mast.material_override = trim_mat
	mast.position.y = 0.9
	add_child(mast)

## Returns true the instant it reaches the far wall.
func update(delta: float) -> bool:
	var dir := signf(target_x - position.x)
	position.x += dir * _speed * delta
	position.y = 0.04 * absf(sin(Time.get_ticks_msec() * 0.008))
	rotation.z = -dir * 0.06 * sin(Time.get_ticks_msec() * 0.01)
	if _flash_t > 0.0:
		_flash_t -= delta
		_body_mat.emission = Color(0.4, 0.067, 0.067)
	else:
		_body_mat.emission = Color.BLACK
	return (dir > 0.0 and position.x >= target_x) or (dir <= 0.0 and position.x <= target_x)

func hit() -> void:
	hp -= 1
	_flash_t = 0.3

func dead() -> bool:
	return hp <= 0
