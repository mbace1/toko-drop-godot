## enemy.gd
##
## Shared base for every enemy body, ported from the common parts of
## toko-drop/js/enemy.js: one gel material per body (see shaders/gel.gdshader
## + PORT_BRIEF.md §0/§1), hit-wobble decay and the CPU spring-squash used on
## hit/land. Subclasses (globbo.gd, yela_cube.gd) own their own movement.
##
## Deliberately NOT driven by Godot's automatic _process/_physics_process —
## wave_director.gd calls update(delta) explicitly from main.gd's game loop,
## the same way main.js drives every enemy from one central loop. That is
## also what makes pausing free: nothing here runs unless main.gd calls it.
class_name Enemy
extends Node3D

const GEL_SHADER := preload("res://shaders/gel.gdshader")
const HIT_WOBBLE_DECAY := 1.1   # TUNING.fx.hitWobbleDecay

var hp := 1
var max_hp := 1
var alive := true
var radius := 0.5
var speed := 2.5
var color := Color(0.0, 0.8, 0.67)

var target: Node3D          # the player — chasers steer toward this
var half_x := 9.0
var half_z := 9.0

var mesh: MeshInstance3D
var mat: ShaderMaterial

var _t := 0.0
var _hit_wobble := 0.0
var _sq := 1.0
var _sqv := 0.0

## Builds the mesh + gel material. is_cube selects a BoxMesh (flat-faced,
## no ripple — TUNING cube family) vs a SphereMesh (blob family, rippling).
func setup(p_color: Color, p_radius: float, p_speed: float, p_hp: int, is_cube: bool) -> void:
	color = p_color
	radius = p_radius
	speed = p_speed
	hp = p_hp
	max_hp = p_hp

	var m: Mesh
	if is_cube:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * radius * 1.5
		m = bm
	else:
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		sm.radial_segments = 24
		sm.rings = 14
		m = sm

	mesh = MeshInstance3D.new()
	mesh.mesh = m
	mesh.position.y = radius

	mat = ShaderMaterial.new()
	mat.shader = GEL_SHADER
	mat.set_shader_parameter("gel_color", color)
	mat.set_shader_parameter("rim_color", color.lightened(0.55))
	mat.set_shader_parameter("wobble_amp", 0.0 if is_cube else 1.0)
	mat.set_shader_parameter("alpha_amt", 0.9)
	mesh.material_override = mat
	add_child(mesh)

## Called once by WaveDirector right after position/target/half_x/half_z are
## set, in place of relying on _ready() ordering. Subclasses override to pick
## their stats + starting state (see globbo.gd / yela_cube.gd).
func init() -> void:
	pass

## Returns true if this hit killed the enemy.
func take_hit(dmg: int) -> bool:
	if not alive:
		return false
	hp -= dmg
	_hit_wobble = 0.65   # TUNING.fx.hitWobbleStart
	_sqv -= 0.5
	if hp <= 0:
		die()
		return true
	return false

func die() -> void:
	alive = false
	queue_free()

## Call from a subclass's update(delta) before its own movement. Advances the
## shared clock, decays hit-wobble and applies the spring squash to mesh.scale.
func _update_common(delta: float) -> void:
	_t += delta
	if _hit_wobble > 0.0:
		_hit_wobble = maxf(0.0, _hit_wobble - HIT_WOBBLE_DECAY * delta)

	_sqv = (_sqv - (_sq - 1.0) * 0.28) * 0.84
	_sq = clampf(_sq + _sqv, 0.55, 1.55)
	var sxz := 1.0 / sqrt(maxf(_sq, 0.1))
	mesh.scale = Vector3(sxz, _sq, sxz)

	mat.set_shader_parameter("wobble_time", _t)
	mat.set_shader_parameter("hit_wobble", _hit_wobble)

## Overridden by subclasses; base does nothing but the common upkeep.
func update(delta: float) -> void:
	_update_common(delta)
