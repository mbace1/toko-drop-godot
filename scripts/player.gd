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

## Invulnerability blinks are SQUARE, and they toggle the mesh rather than
## ramping alpha. The gel material is opaque with hashed alpha (so that SSS
## works at all — see gel.gdshader's header), and a smooth alpha ramp through
## a hash dithers the body into TV static, which reads as broken graphics
## rather than as i-frames. The source blinks square too (`VIS.hz` in
## player.js). 12Hz is the arcade-standard mercy flicker.
const MERCY_BLINK_HZ := 12.0
const DASH_BLINK_HZ := 22.0

# js/player.js sits the eyes at ed 0.4 forward / es 0.14 lateral / +0.16 up —
# INSIDE a radius-0.5 body, which works there because the browser's player is a
# transmissive gel you can see into. This port's gel is opaque (that is what
# buys it real SSS — see gel.gdshader), so embedded eyes are simply invisible;
# the first attempt rendered a blank white ball. They are placed ON the surface
# here instead: an angle up from the aim vector, and an angle either side of it.
const EYE_TILT := 0.42     # radians above the aim vector — into the camera
const EYE_SPREAD := 0.34   # radians either side
const EYE_SURFACE := 0.97  # fraction of RADIUS, so the eye breaks the surface

# ---- Rush Mode ------------------------------------------------------------
## Owner direction: the Rush weapon is "a shotgun type wider bullet". Five
## pellets across a wide arc, and they die early so the gun is a CLOSE-range
## answer — which is what keeps boosting the better option at any distance
## (RUSH_MODE.md: "prioritising boosting over shooting").
const SHOTGUN_PELLETS := 5
const SHOTGUN_SPREAD := 0.50      # radians, total arc
const SHOTGUN_RATE_MULT := 3.4    # far slower than the classic 0.09s
const RUSH_RIM := Color(1.0, 0.55, 0.10)     # hot
const BOOST_RIM := Color(0.45, 1.0, 1.0)     # invulnerable

## Set by main.gd each frame in Rush Mode. `rush_speed_mult` scales movement
## for the held boost; `rush_shotgun` swaps the weapon.
var rush_speed_mult := 1.0
var rush_shotgun := false
var rush_boosting := false

## The gun, from js/player.js's fire branch. A pod swaps this for the rest of
## the run (or until the next pod). LASER falls through to SINGLE there too —
## it is a piercing VISUAL in the browser, not a different firing pattern.
var weapon := "SINGLE"
## BURST fires one now and queues the rest; each entry is {t, dx, dz}.
var _burst: Array = []
## Rush's shield. Set by main.gd from RushRules.invulnerable(), which is true
## while boosting AND not firing — the trigger drops it (RUSH_MODE.md).
var rush_invuln := false

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
## Fired on every shot, so main.gd can hang the gun sound off it without the
## player knowing an audio kit exists (js/player.js has the same hook).
var on_shoot: Callable = Callable()

var _eye_l: Node3D
var _eye_r: Node3D
var _built := false

var invincible: bool:
	get: return _dash_time > 0.0 or _mercy_t > 0.0 or rush_invuln

var dashing: bool:
	get: return _dash_time > 0.0

## MAGNA's pull (main.js v144): dashing grants ~1.2s of pull immunity —
## momentum breaks the hold. Lives here (not in main.gd) because it decays
## off the same dash state main.gd has no other reason to poll every frame.
const MAGNA_IMMUNE_DUR := 1.2
var magna_immune_t := 0.0

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
	# Barely-cool white rather than pure white: at 1,1,1 the SSS and backlight
	# stack into a blown-out disc with no form at all, and the hero read as a
	# hole in the screen. The tint gives the scattering something to be.
	mat.set_shader_parameter("gel_color", Color(0.82, 0.91, 1.0))
	mat.set_shader_parameter("rim_color", REST_RIM)
	mat.set_shader_parameter("wobble_amp", 1.0)
	mat.set_shader_parameter("alpha_amt", 1.0)
	mat.set_shader_parameter("emission_intensity", 0.03)
	mat.set_shader_parameter("backlight_amt", 0.28)
	mesh.material_override = mat
	add_child(mesh)
	_build_eyes()
	reset()

## Kirby-style eyes, from js/player.js. They are the hero's whole identity —
## without them the player is a pale sphere with the visual weight of its own
## bullets, which is exactly how the first renders read. Numbers are the
## source's: SphereGeometry(0.13) scaled (0.55, 1.15, 0.4) in near-black, each
## carrying a small white reflection dot, sat EYE_FWD along the aim vector and
## EYE_SEP either side of it.
##
## Children of the Player node rather than of `mesh`, so the spring squash
## never stretches them.
func _build_eyes() -> void:
	_eye_l = _make_eye()
	_eye_r = _make_eye()
	add_child(_eye_l)
	add_child(_eye_r)

func _make_eye() -> Node3D:
	var holder := Node3D.new()

	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 10
	sm.rings = 6
	var eye := MeshInstance3D.new()
	eye.mesh = sm
	eye.scale = Vector3(0.55, 1.15, 0.4)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(0.067, 0.067, 0.067)
	eye.material_override = em
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(eye)

	var rm := SphereMesh.new()
	rm.radius = 0.042
	rm.height = 0.084
	rm.radial_segments = 6
	rm.rings = 4
	var refl := MeshInstance3D.new()
	refl.mesh = rm
	refl.position = Vector3(0.04, 0.05, -0.025)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color.WHITE
	refl.material_override = rmat
	refl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(refl)

	return holder

## Sits the eyes on the front of the body along the current aim, so the hero
## visibly LOOKS where it is shooting.
func _place_eyes() -> void:
	var fwd := Vector3(_last_aim.x, 0.0, _last_aim.y).normalized()
	var perp := Vector3(-fwd.z, 0.0, fwd.x)
	# Tilt the look direction up out of the floor plane so the eyes face the
	# camera rather than the far wall, then swing one each way around it.
	var look := (fwd * cos(EYE_TILT) + Vector3.UP * sin(EYE_TILT)).normalized()
	var r := RADIUS * EYE_SURFACE
	var ang := atan2(fwd.x, fwd.z)
	for pair in [[_eye_l, 1.0], [_eye_r, -1.0]]:
		var node: Node3D = pair[0]
		var side: float = pair[1]
		var dir := (look * cos(EYE_SPREAD) + perp * (side * sin(EYE_SPREAD))).normalized()
		node.position = dir * r
		node.rotation.y = ang

func reset() -> void:
	hp = MAX_HP
	max_hp = MAX_HP
	alive = true
	_mercy_t = 0.0
	_flash_t = 0.0
	_dash_time = 0.0
	_dash_cd = 0.0
	_fire_t = 0.0
	magna_immune_t = 0.0
	_sq = 1.0
	_sqv = 0.0
	rush_speed_mult = 1.0
	rush_boosting = false
	weapon = "SINGLE"
	_burst.clear()
	rush_invuln = false
	position = Vector3(0.0, RADIUS, 0.0)
	mat.set_shader_parameter("rim_color", REST_RIM)
	_show()
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

## True when a dash would actually happen. main.gd asks BEFORE calling dash()
## so it only plays the sound on a real dash, never on a press swallowed by the
## cooldown — a whoosh with no movement reads as an input that was dropped.
func can_dash() -> bool:
	return alive and _dash_time <= 0.0 and _dash_cd <= 0.0

## Starts the mercy window without touching HP — Rush counts lives elsewhere
## but still wants the i-frames and the flicker, so one hit is one hit.
func start_mercy() -> void:
	_flash_t = 0.25
	_mercy_t = MERCY_DURATION
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
	if dashing:
		magna_immune_t = MAGNA_IMMUNE_DUR
	elif magna_immune_t > 0.0:
		magna_immune_t -= delta
	_step_burst(delta, bullets)
	if _dash_cd > 0.0:
		_dash_cd -= delta
	if _fire_t > 0.0:
		_fire_t -= delta

	if _flash_t > 0.0:
		_flash_t -= delta
		mat.set_shader_parameter("rim_color", HIT_RIM)
	elif _mercy_t <= 0.0:
		# The gel shader already takes a per-instance rim colour, so Rush's
		# state rides on the body for free: cyan while boosting (invulnerable),
		# orange while hot, otherwise the resting blue.
		if rush_boosting:
			mat.set_shader_parameter("rim_color", BOOST_RIM)
		elif rush_speed_mult != 1.0 or rush_shotgun:
			mat.set_shader_parameter("rim_color", RUSH_RIM)
		else:
			mat.set_shader_parameter("rim_color", REST_RIM)

	if _dash_time > 0.0:
		_dash_time -= delta
		position.x += _dash_dir.x * DASH_SPEED * delta
		position.z += _dash_dir.y * DASH_SPEED * delta
		_blink(_dash_time, DASH_BLINK_HZ)
		if _dash_time <= 0.0:
			_dash_cd = DASH_CD
			if _mercy_t <= 0.0:
				_show()
	else:
		# Rush's boost is a HELD state, not a blink: it scales walking speed for
		# as long as it is held, rather than firing a 0.18s burst.
		position.x += move.x * SPEED * rush_speed_mult * delta
		position.z += move.y * SPEED * rush_speed_mult * delta

	if _mercy_t > 0.0:
		_mercy_t -= delta
		_blink(_mercy_t, MERCY_BLINK_HZ)
		if _mercy_t <= 0.0:
			_show()
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
	_place_eyes()

	var aim_valid: bool = aim["valid"]
	if aim_valid and _fire_t <= 0.0:
		var ax: float = aim["x"]
		var az: float = aim["z"]
		_last_aim = Vector2(ax, az)
		var ox: float = position.x + ax * (RADIUS + 0.3)
		var oz: float = position.z + az * (RADIUS + 0.3)
		if rush_shotgun:
			var base := atan2(az, ax)
			for i in SHOTGUN_PELLETS:
				var f := (float(i) / float(SHOTGUN_PELLETS - 1)) - 0.5
				var a := base + f * SHOTGUN_SPREAD
				bullets.spawn_dir(ox, oz, cos(a), sin(a), true)
			_fire_t = FIRE_RATE * SHOTGUN_RATE_MULT
		else:
			_fire_weapon(ox, oz, ax, az, bullets)
		if on_shoot.is_valid():
			on_shoot.call()

	mat.set_shader_parameter("wobble_time", Time.get_ticks_msec() / 1000.0)

## Square on/off blink driven off the remaining timer, so it always ends ON.
## The eyes blink WITH the body — a pair of eyes hanging in the air over a
## vanished hero looks like a bug, not like invulnerability.
func _blink(t_left: float, hz: float) -> void:
	var on := int(t_left * hz) % 2 == 0
	mesh.visible = on
	_eye_l.visible = on
	_eye_r.visible = on

func _show() -> void:
	mesh.visible = true
	_eye_l.visible = true
	_eye_r.visible = true
	mat.set_shader_parameter("alpha_amt", 1.0)

## js/player.js: SPREAD is 5 shots at PI/9, SPREAD2 is 7 at PI/10, BURST
## queues two more at 0.12/0.24, BURST2 four at 0.10..0.40, RAPID multiplies
## the fire rate by 0.45 and RAPID2 by 0.28.
func _fire_weapon(ox: float, oz: float, ax: float, az: float, bullets: BulletPool) -> void:
	var rate := FIRE_RATE
	match weapon:
		"SPREAD", "SPREAD2":
			var wide := weapon == "SPREAD2"
			var offsets := [-3, -2, -1, 0, 1, 2, 3] if wide else [-2, -1, 0, 1, 2]
			var step := PI / 10.0 if wide else PI / 9.0
			for o in offsets:
				var a := atan2(az, ax) + float(o) * step
				bullets.spawn_dir(ox, oz, cos(a), sin(a), true)
		"BURST", "BURST2":
			bullets.spawn_dir(ox, oz, ax, az, true)
			var delays := [0.10, 0.20, 0.30, 0.40] if weapon == "BURST2" else [0.12, 0.24]
			for d in delays:
				_burst.append({"t": d, "dx": ax, "dz": az})
		"RAPID":
			bullets.spawn_dir(ox, oz, ax, az, true)
			rate = FIRE_RATE * 0.45
		"RAPID2":
			bullets.spawn_dir(ox, oz, ax, az, true)
			rate = FIRE_RATE * 0.28
		_:
			# SINGLE, and LASER/LASER2 which fire the same way in the source.
			bullets.spawn_dir(ox, oz, ax, az, true)
	_fire_t = rate

## The queued half of a BURST. Runs on its own clock so the rest of the burst
## still arrives even if you stop holding the trigger — which is what makes
## burst a COMMITMENT rather than just a slower gun.
func _step_burst(delta: float, bullets: BulletPool) -> void:
	for i in range(_burst.size() - 1, -1, -1):
		_burst[i]["t"] -= delta
		if _burst[i]["t"] > 0.0:
			continue
		var dx: float = _burst[i]["dx"]
		var dz: float = _burst[i]["dz"]
		bullets.spawn_dir(position.x + dx * (RADIUS + 0.3),
			position.z + dz * (RADIUS + 0.3), dx, dz, true)
		if on_shoot.is_valid():
			on_shoot.call()
		_burst.remove_at(i)

func die() -> void:
	alive = false
	visible = false   # the eyes are children, so they go with it
