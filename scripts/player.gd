## player.gd
##
## Godot port of toko-drop/js/player.js. Constants and the update() sequence
## (dash → mercy flicker → clamp to arena → spring squash → fire) are kept in
## the same order and with the same numbers as the source so the feel matches.
## Not yet ported: eyes, dash ghost trail, muzzle flash, weapon-mode variants
## (SPREAD/BURST/HOMING/…) — see PORT_STATUS.md.
class_name Player
extends Node3D

const SPEED := 6.0
const DASH_SPEED := 26.0
const DASH_DUR := 0.18
const DASH_CD := 0.75
const FIRE_RATE := 0.09
const MAX_HP := 3
const MERCY_DURATION := 1.2
const RADIUS := 0.5

const GEL_SHADER := preload("res://shaders/gel.gdshader")
const REST_RIM := Color(0.6, 0.85, 1.0)
const HIT_RIM := Color(1.0, 0.15, 0.0)

var hp := MAX_HP
var max_hp := MAX_HP
var alive := false

var _mercy_t := 0.0
var _flash_t := 0.0
var _dash_dir := Vector2.ZERO
var _dash_time := 0.0
var _dash_cd := 0.0
var _fire_t := 0.0
var _last_aim := Vector2(1.0, 0.0)
var _sq := 1.0
var _sqv := 0.0

var mesh: MeshInstance3D
var mat: ShaderMaterial
var _built := false

var invincible: bool:
	get: return _dash_time > 0.0 or _mercy_t > 0.0

func _ready() -> void:
	build()

## Idempotent — see BulletPool.build() for why this isn't left to _ready()
## timing alone.
func build() -> void:
	if _built:
		return
	_built = true

	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	sm.radial_segments = 20
	sm.rings = 12
	mesh = MeshInstance3D.new()
	mesh.mesh = sm
	mat = ShaderMaterial.new()
	mat.shader = GEL_SHADER
	mat.set_shader_parameter("gel_color", Color(1.0, 1.0, 1.0))
	mat.set_shader_parameter("rim_color", REST_RIM)
	mat.set_shader_parameter("wobble_amp", 1.0)
	mat.set_shader_parameter("alpha_amt", 0.96)
	mat.set_shader_parameter("emission_intensity", 0.05)
	mesh.material_override = mat
	add_child(mesh)
	reset()

func reset() -> void:
	hp = MAX_HP
	max_hp = MAX_HP
	alive = true
	_mercy_t = 0.0
	_flash_t = 0.0
	_dash_time = 0.0
	_dash_cd = 0.0
	_fire_t = 0.0
	_sq = 1.0
	_sqv = 0.0
	position = Vector3(0.0, RADIUS, 0.0)
	mat.set_shader_parameter("rim_color", REST_RIM)
	mat.set_shader_parameter("alpha_amt", 0.96)
	visible = true

func hit() -> void:
	if invincible or not alive:
		return
	hp -= 1
	if hp <= 0:
		die()
		return
	_flash_t = 0.25
	_mercy_t = MERCY_DURATION
	_dash_time = 0.0
	_sqv -= 0.9

func dash(aim: Dictionary) -> void:
	if _dash_time > 0.0 or _dash_cd > 0.0:
		return
	var valid: bool = aim["valid"]
	_dash_dir = Vector2(aim["x"], aim["z"]) if valid else _last_aim
	_dash_time = DASH_DUR
	_sqv += 0.6

func update(delta: float, move: Vector2, aim: Dictionary, bullets: BulletPool, half_x: float, half_z: float) -> void:
	if not alive:
		return
	if _dash_cd > 0.0:
		_dash_cd -= delta
	if _fire_t > 0.0:
		_fire_t -= delta

	if _flash_t > 0.0:
		_flash_t -= delta
		mat.set_shader_parameter("rim_color", HIT_RIM)
	elif _mercy_t <= 0.0:
		mat.set_shader_parameter("rim_color", REST_RIM)

	if _dash_time > 0.0:
		_dash_time -= delta
		position.x += _dash_dir.x * DASH_SPEED * delta
		position.z += _dash_dir.y * DASH_SPEED * delta
		var blink := 0.35 + 0.65 * absf(sin(_dash_time * 55.0))
		mat.set_shader_parameter("alpha_amt", blink)
		if _dash_time <= 0.0:
			_dash_cd = DASH_CD
			if _mercy_t <= 0.0:
				mat.set_shader_parameter("alpha_amt", 0.96)
	else:
		position.x += move.x * SPEED * delta
		position.z += move.y * SPEED * delta

	if _mercy_t > 0.0:
		_mercy_t -= delta
		mat.set_shader_parameter("alpha_amt", 0.3 + 0.7 * absf(sin(_mercy_t * 12.0)))
		if _mercy_t <= 0.0:
			mat.set_shader_parameter("alpha_amt", 0.96)
			mat.set_shader_parameter("rim_color", REST_RIM)

	var hx := half_x - RADIUS
	var hz := half_z - RADIUS
	position.x = clampf(position.x, -hx, hx)
	position.z = clampf(position.z, -hz, hz)

	# Spring squash (player.js `_sq`/`_sqV`).
	_sqv = (_sqv - (_sq - 1.0) * 0.28) * 0.84
	_sq = clampf(_sq + _sqv, 0.55, 1.55)
	var sxz := 1.0 / sqrt(maxf(_sq, 0.1))
	mesh.scale = Vector3(sxz, _sq, sxz)

	var aim_valid: bool = aim["valid"]
	if aim_valid and _fire_t <= 0.0:
		var ax: float = aim["x"]
		var az: float = aim["z"]
		_last_aim = Vector2(ax, az)
		var ox: float = position.x + ax * (RADIUS + 0.3)
		var oz: float = position.z + az * (RADIUS + 0.3)
		bullets.spawn_dir(ox, oz, ax, az, true)
		_fire_t = FIRE_RATE

	mat.set_shader_parameter("wobble_time", Time.get_ticks_msec() / 1000.0)

func die() -> void:
	alive = false
	visible = false
