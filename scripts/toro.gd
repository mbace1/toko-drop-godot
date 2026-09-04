## toro.gd
##
## TORO — an upright wheel that winds up, tells you exactly where it is going,
## and then goes. The most dangerous body in the ported roster and the most
## honest: everything about the attack is visible before it starts.
##
## Stats from enemy.js's CFG table (line 499):
##   color 0x4488cc, radius 1.0, speed 5.0, hp 6
## Movement role COMMIT (TUNING.movement.byType) — "chargers are committed to
## the line". It does not dodge and it cannot steer mid-dash.
##
## The state machine and every number come from TUNING.toro (tuning.js line 56)
## and TOKO_DROP_PORT_BRIEF.md Part 4:
##
##   idle creep -> revring (1.6s) -> telegraph (0.5s) -> dash (22 -> 14) -> recover (0.8s)
##
## Part 4 is specific about the tell, and it is the reason the species works:
## the indicator is not a fixed-length line, it is raycast to the arena wall so
## the **arrowhead tip sits exactly at the impact point**. You are not told
## "it is coming this way", you are told precisely where it will stop.
class_name Toro
extends Enemy

enum Phase { IDLE, REV, TELEGRAPH, DASH, RECOVER }

const REV_TIME := 1.6           # TUNING.toro.revTime
const TELEGRAPH_TIME := 0.5     # TUNING.toro.telegraphTime
const DASH_SPEED := 22.0        # TUNING.toro.dashSpeed
const DASH_MIN := 14.0          # TUNING.toro.dashMin
const DASH_DECEL := 8.0         # TUNING.toro.dashDecel
const RECOVER_TIME := 0.8       # TUNING.toro.recoverTime
const DIR_SNAP_DEG := 45.0      # TUNING.toro.dirSnapDeg
const INDICATOR_WIDTH := 0.34   # TUNING.toro.indicatorWidth
const INDICATOR_FLASH_HZ := 25.0
const ARROW_RADIUS := 0.5       # TUNING.toro.arrow.radius
const ARROW_LENGTH := 0.9       # TUNING.toro.arrow.length
const RIM_SPIKES := 5           # TUNING.toro.rimSpikes
const IDLE_CREEP := 0.35        # fraction of `speed` while winding up

var _phase: int = Phase.IDLE
var _phase_t := 0.0
var _dash_dir := Vector2(1.0, 0.0)
var _dash_speed := 0.0
var _spin := 0.0

var _wheel: Node3D
var _indicator: Node3D
var _shaft: MeshInstance3D
var _arrow: MeshInstance3D
var _ind_mat: StandardMaterial3D

func init() -> void:
	setup(Color(0.267, 0.533, 0.8), 1.0, 5.0, 6, false)
	trail_interval = 0.035      # enemy.js TRAIL_CFG — thickest streak in the game
	trail_size = 0.85
	revenge_dialect = Revenge.RING
	_phase_t = 1.2 + rng.randf() * 0.8
	_build_wheel()
	_build_indicator()

## An upright wheel: a torus standing on its rim with spikes around it, inside
## a yaw group that faces the dash direction. The torus spins about the axle,
## so during a dash it visibly ROLLS rather than sliding.
func _build_wheel() -> void:
	# setup() gives every blob a sphere. TORO is not a blob — it is a wheel, and
	# leaving the sphere in place buried the torus inside a ball (which is
	# exactly how the first render came out). `mesh` stays as the transform
	# holder the squash and the yaw are applied to; it just draws nothing.
	mesh.mesh = null
	_wheel = Node3D.new()
	mesh.add_child(_wheel)

	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.52
	torus.outer_radius = radius
	torus.rings = 20
	var tm := MeshInstance3D.new()
	tm.mesh = torus
	tm.material_override = mat
	# TorusMesh lies flat; stand it on its rim so it is a WHEEL, not a ring on
	# the floor. The yaw group then points that wheel along the dash line.
	tm.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_wheel.add_child(tm)

	for i in RIM_SPIKES:
		var a: float = (float(i) / float(RIM_SPIKES)) * TAU
		var spike := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, radius * 0.42, 0.14)
		spike.mesh = bm
		spike.material_override = mat
		spike.position = Vector3(0.0, cos(a) * radius, sin(a) * radius)
		spike.rotation = Vector3(a, 0.0, 0.0)
		_wheel.add_child(spike)

## The tell. A shaft scaled in Z to the EXACT dash length, plus a cone whose
## tip lands on the impact point (PORT_BRIEF Part 4). Parented to the arena,
## not to the body, so it does not inherit the wheel's spin.
func _build_indicator() -> void:
	_indicator = Node3D.new()
	add_child(_indicator)

	_ind_mat = StandardMaterial3D.new()
	_ind_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ind_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ind_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ind_mat.albedo_color = Color(0.4, 0.75, 1.0, 0.0)

	var shaft := BoxMesh.new()
	shaft.size = Vector3(INDICATOR_WIDTH, 0.04, 1.0)
	_shaft = MeshInstance3D.new()
	_shaft.mesh = shaft
	_shaft.material_override = _ind_mat
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_indicator.add_child(_shaft)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = ARROW_RADIUS
	cone.height = ARROW_LENGTH
	cone.radial_segments = 3          # the source's 3-sided arrowhead
	_arrow = MeshInstance3D.new()
	_arrow.mesh = cone
	_arrow.material_override = _ind_mat
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_indicator.add_child(_arrow)

	_indicator.visible = false

## Distance from here to the arena wall along `dir` — what the indicator has to
## be scaled to so its tip is the impact point.
func dash_length(dir: Vector2) -> float:
	# Q-035: the slab test is Arena.ray_edge (arena.gd), the same expression
	# TORO always inlined, r = 0. `dir` is snapped to eight headings, so the
	# old 1e-4 guard and ray_edge's exact-zero test never disagree.
	var best := arena.ray_edge(position.x, position.z, dir.x, dir.y, 0.0)
	return maxf(0.5, best if best < INF else half_x)

## 45-degree snapping (TUNING.toro.dirSnapDeg). A charger that can aim at any
## angle is unreadable; one that commits to eight lines can be stepped off.
func _snapped_dir_to_target() -> Vector2:
	if target == null:
		return _dash_dir
	var to := Vector2(target.position.x - position.x, target.position.z - position.z)
	if to.length() < 1e-4:
		return _dash_dir
	var step := deg_to_rad(DIR_SNAP_DEG)
	var a: float = round(to.angle() / step) * step
	return Vector2(cos(a), sin(a))

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return
	_phase_t -= delta

	match _phase:
		Phase.IDLE:
			_creep(delta)
			_spin = 3.0
			if _phase_t <= 0.0:
				_phase = Phase.REV
				_phase_t = REV_TIME
		Phase.REV:
			_creep(delta)
			# Spin accelerates through the wind-up (enemy.js: 3 + ramp * 8).
			var ramp := 1.0 - clampf(_phase_t / REV_TIME, 0.0, 1.0)
			_spin = 3.0 + ramp * 8.0
			_dash_dir = _snapped_dir_to_target()
			if _phase_t <= 0.0:
				_phase = Phase.TELEGRAPH
				_phase_t = TELEGRAPH_TIME
				_show_indicator(true)
		Phase.TELEGRAPH:
			# The line is LOCKED here. Committing before the flash is what makes
			# stepping off it a real decision rather than a reaction test.
			_spin = 11.0
			_update_indicator()
			if _phase_t <= 0.0:
				_phase = Phase.DASH
				_dash_speed = DASH_SPEED
				_show_indicator(false)
		Phase.DASH:
			_dash_speed = maxf(DASH_MIN, _dash_speed - DASH_DECEL * delta)
			position.x += _dash_dir.x * _dash_speed * delta
			position.z += _dash_dir.y * _dash_speed * delta
			# Rolls at the speed it travels: spin = v / rim radius.
			_spin = _dash_speed / maxf(radius, 0.01)
			# Q-035: "touching or past the wall" is sdf + r >= 0 — the exact
			# equivalent of |x| >= hx-r or |z| >= hz-r on the rectangle.
			if arena.sdf(position.x, position.z) + radius >= 0.0:
				_clamp_to_arena()
				_phase = Phase.RECOVER
				_phase_t = RECOVER_TIME
				_sqv -= 0.8                      # it hits the wall and squashes
		Phase.RECOVER:
			_spin = maxf(0.0, _spin - 9.0 * delta)
			if _phase_t <= 0.0:
				_phase = Phase.IDLE
				_phase_t = 0.8 + rng.randf() * 0.8

	# The yaw group faces the dash line; the wheel spins about its axle.
	mesh.rotation.y = atan2(_dash_dir.x, _dash_dir.y)
	_wheel.rotate_x(_spin * delta)

func _creep(delta: float) -> void:
	if target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var d := Vector2(dx, dz).length()
	if d < 0.6:
		return
	position.x += (dx / d) * speed * IDLE_CREEP * delta
	position.z += (dz / d) * speed * IDLE_CREEP * delta
	_clamp_to_arena()

func _show_indicator(on: bool) -> void:
	_indicator.visible = on
	if on:
		_update_indicator()

func _update_indicator() -> void:
	var reach := dash_length(_dash_dir)
	var ang := atan2(_dash_dir.x, _dash_dir.y)
	_indicator.rotation.y = ang
	_indicator.position = Vector3(0.0, 0.05, 0.0)

	# Shaft runs from the body to the wall; the cone's TIP sits on the impact
	# point, so its centre is half its length short of it.
	_shaft.scale = Vector3(1.0, 1.0, reach)
	_shaft.position = Vector3(0.0, 0.0, reach * 0.5)
	_arrow.position = Vector3(0.0, 0.0, reach - ARROW_LENGTH * 0.5)
	_arrow.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	# The source's opacity flash: sin(t * 25).
	var f := 0.35 + 0.45 * absf(sin(_t * INDICATOR_FLASH_HZ))
	_ind_mat.albedo_color = Color(0.4, 0.75, 1.0, f)

## True while the wheel is actually charging — main.gd can read this later if
## a dashing TORO should hit harder than a creeping one.
func is_charging() -> bool:
	return _phase == Phase.DASH
