## enemy.gd
##
## Shared base for every enemy body, ported from the common parts of
## toko-drop/js/enemy.js: one gel material per body (see shaders/gel.gdshader
## + PORT_BRIEF.md §0/§1), hit-wobble decay, the CPU spring-squash used on
## hit/land, and the telegraph→fire scaffolding every ranged type shares.
## Subclasses (globbo.gd, yela_cube.gd, spittor.gd, fanner.gd) own movement
## and decide what their volley looks like.
##
## Deliberately NOT driven by Godot's automatic _process/_physics_process —
## wave_director.gd calls update(delta) explicitly from main.gd's game loop,
## the same way main.js drives every enemy from one central loop. That is
## also what makes pausing free: nothing here runs unless main.gd calls it.
class_name Enemy
extends Node3D

const GEL_SHADER := preload("res://shaders/gel.gdshader")
const HIT_WOBBLE_DECAY := 1.1   # TUNING.fx.hitWobbleDecay
const DEATH_TIME := 0.28        # enemy.js updateDeath()
const DEATH_GROWTH := 1.3       # "pop growth 3.2x -> 2.3x" => scale 1 + t*1.3

## A corpse's retaliation SPEAKS THE SPECIES' LANGUAGE — TUNING.revenge.byType
## (tuning.js line 237). Gunners spit a slow aimed burst, arc species throw a
## slow fan, everything else blooms the classic ring.
enum Revenge { RING, AIMED, FAN }

var hp := 1
var max_hp := 1
var alive := true
var radius := 0.5
var speed := 2.5
var color := Color(0.0, 0.8, 0.67)

var target: Node3D          # the player — chasers steer toward this
var bullets: BulletPool     # set by WaveDirector; null for melee-only types
var half_x := 9.0
var half_z := 9.0

## Ranged types set these in init(); melee types leave fire_interval at 0.
var bullet_color := Color(1.0, 0.33, 0.2)
var fire_interval := 0.0

var mesh: MeshInstance3D
var mat: ShaderMaterial

## Set by subclasses in init(); the fallback is RING (TUNING.revenge.fallback).
var revenge_dialect := Revenge.RING

## Per-species silhouette scale (TUNING.blob.shape / .shapes), applied on top
## of the spring squash every frame by _update_common().
var base_shape := Vector3.ONE

var _dying := false
var _death_t := 0.0
## FULLY opaque at rest. Translucency is SSS's job now, not alpha's — and
## since the gel uses hashed alpha to stay in the opaque pass, any value below
## 1.0 dithers pixels away and speckles the body with visible static. Alpha is
## only for bodies on their way OUT (the death pop, the i-frame flicker).
var _base_alpha := 1.0
var _t := 0.0                # free-running clock, also drives the gel ripple
var _fire_t := 0.0           # counts UP toward fire_interval (enemy.js `_t`)
var _telegraph_t := 0.0      # counts DOWN through the wind-up
var _is_telegraphing := false
var _inflate := 0.0          # extra scale during a telegraph (SPITTOR's tell)
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
	# TUNING.blob.shape — "squat grounded baseline" {x:1.05, y:0.82, z:1.05}.
	# The browser's blobs are flattened domes sitting ON the floor, not balls
	# resting on one point; a plain sphere reads as a marble.
	if not is_cube:
		base_shape = Vector3(1.05, 0.82, 1.05)
		mesh.position.y = radius * base_shape.y

	mat = ShaderMaterial.new()
	mat.shader = GEL_SHADER
	mat.set_shader_parameter("gel_color", color)
	mat.set_shader_parameter("rim_color", color.lightened(0.55))
	mat.set_shader_parameter("wobble_amp", 0.0 if is_cube else 1.0)
	mat.set_shader_parameter("alpha_amt", _base_alpha)
	mesh.material_override = mat
	add_child(mesh)

## Called once by WaveDirector right after position/target/bullets/half_* are
## set, in place of relying on _ready() ordering. Subclasses override to pick
## their stats + starting state (see globbo.gd / yela_cube.gd / spittor.gd).
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

## Starts the death pop. The node is NOT freed here — WaveDirector moves it to
## its corpse list and keeps calling update_death() until the pop finishes, so
## a kill is something you SEE rather than a body vanishing mid-frame.
func die() -> void:
	alive = false
	_dying = true
	_death_t = DEATH_TIME

## enemy.js updateDeath(): swells while fading on a SQUARED curve, so the body
## is mostly transparent by the time it is large — the death stays readable
## without a screen-filling flash. Returns true once the pop is over and the
## node can be freed.
func update_death(delta: float) -> bool:
	if not _dying:
		return true
	_death_t -= delta
	var t := 1.0 - maxf(_death_t, 0.0) / DEATH_TIME
	mesh.scale = base_shape * (1.0 + t * DEATH_GROWTH)
	mat.set_shader_parameter("alpha_amt", (1.0 - t) * (1.0 - t) * _base_alpha)
	# The pre-death thrash: strongest at onset, fading as it bursts.
	mat.set_shader_parameter("hit_wobble", maxf(0.0, _death_t / DEATH_TIME))
	if _death_t <= 0.0:
		_dying = false
		return true
	return false

## TUNING.revenge.palette — a corpse never wears living colours. Warm shifts to
## dark blood, yellow to poison green, cool to deep venom, so revenge fire and
## living fire read apart at a glance (main.js revengeColor()).
func revenge_color() -> Color:
	var c := bullet_color if fire_interval > 0.0 else color
	var h := c.h
	var sat := c.s
	var l := c.v
	if h >= 0.10 and h <= 0.22:                     # yellowLo / yellowHi
		return Color.from_hsv(0.285, maxf(sat, 0.75), 0.42)   # poison green
	elif h < 0.10 or h > 0.92:                      # warmHiCut
		return Color.from_hsv(h * 0.4 if h < 0.10 else h,
			minf(1.0, sat * 1.2), maxf(0.30, l * 0.55))       # dark blood
	return Color.from_hsv(h, minf(1.0, sat * 1.2), maxf(0.30, l * 0.5))  # deep venom

## Call from a subclass's update(delta) before its own movement. Advances the
## shared clock, decays hit-wobble and applies the spring squash (plus any
## telegraph inflate) to mesh.scale.
func _update_common(delta: float) -> void:
	_t += delta
	if _hit_wobble > 0.0:
		_hit_wobble = maxf(0.0, _hit_wobble - HIT_WOBBLE_DECAY * delta)

	_sqv = (_sqv - (_sq - 1.0) * 0.28) * 0.84
	_sq = clampf(_sq + _sqv, 0.55, 1.55)
	var sxz := 1.0 / sqrt(maxf(_sq, 0.1))
	# The telegraph inflate multiplies the spring rather than replacing it, so
	# it composes with breathe/squash instead of stomping them (enemy.js
	# applies it inside the blob scale block for the same reason).
	var infl := 1.0 + _inflate
	mesh.scale = Vector3(sxz * infl, _sq * infl, sxz * infl) * base_shape

	mat.set_shader_parameter("wobble_time", _t)
	mat.set_shader_parameter("hit_wobble", _hit_wobble)

## Shared "hold your ground at arm's length" motion for the HOLDER archetype
## (TUNING.movement.roles.HOLDER). Closes when further than want+band, backs
## off when nearer than want-band, and stands still inside the band — the
## hysteresis is what stops it jittering on the boundary. Mirrors the
## SPITTOR/FANNER/BOTFLY cases in enemy.js. Returns the unit vector toward
## the target so callers can reuse it for aiming/strafing.
func _hold_at_range(delta: float, want: float, band: float, strafe: float = 0.0) -> Vector2:
	if target == null:
		return Vector2.ZERO
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var dist := Vector2(dx, dz).length()
	if dist < 0.001:
		return Vector2.ZERO
	var nx := dx / dist
	var nz := dz / dist

	var radial := 0.0
	if dist > want + band:
		radial = 1.0
	elif dist < want - band:
		radial = -1.0

	# Perpendicular, for types that circle while they hold (FANNER).
	var px := -nz
	var pz := nx
	position.x += (nx * radial + px * strafe) * speed * delta
	position.z += (nz * radial + pz * strafe) * speed * delta
	_clamp_to_arena()
	return Vector2(nx, nz)

func _clamp_to_arena() -> void:
	var hx := half_x - radius
	var hz := half_z - radius
	position.x = clampf(position.x, -hx, hx)
	position.z = clampf(position.z, -hz, hz)

## Drives the shared fire clock. Returns true on the single frame the volley
## should actually go off; the subclass then spawns whatever shape it fires.
## `windup` is the telegraph length — the wind-up is the whole point of these
## enemies, so it is not optional (enemy.js gives every shooter one).
func _tick_fire(delta: float, windup: float) -> bool:
	if fire_interval <= 0.0 or bullets == null:
		return false
	if not _is_telegraphing:
		_fire_t += delta
		if _fire_t >= fire_interval:
			_fire_t = 0.0
			_telegraph_t = windup
			_is_telegraphing = true
	if _is_telegraphing:
		_telegraph_t -= delta
		if _telegraph_t <= 0.0:
			_is_telegraphing = false
			_inflate = 0.0
			return true
	return false

## enemy.js `_ring()` — count shots evenly around the circle, rotated so that
## shot 0 points along `base`. Passing the angle toward the player as `base`
## is what makes a symmetric ring read as aimed at you.
func _ring(x: float, z: float, count: int, base: float) -> void:
	for i in count:
		var a := base + (float(i) / float(count)) * TAU
		bullets.spawn_dir(x, z, cos(a), sin(a), false, bullet_color)

## A fan of `count` shots spanning `span` radians, centred on `base`.
func _fan(x: float, z: float, count: int, span: float, base: float) -> void:
	if count <= 1:
		bullets.spawn_dir(x, z, cos(base), sin(base), false, bullet_color)
		return
	for i in count:
		var a := base - span * 0.5 + float(i) * (span / float(count - 1))
		bullets.spawn_dir(x, z, cos(a), sin(a), false, bullet_color)

## Angle from this enemy toward the player, in the XZ plane.
func _angle_to_target() -> float:
	if target == null:
		return 0.0
	return atan2(target.position.z - position.z, target.position.x - position.x)

## Overridden by subclasses; base does nothing but the common upkeep.
func update(delta: float) -> void:
	_update_common(delta)
