## yela_cube.gd
##
## YELA CUBE — flops instead of sliding. Stats from enemy.js's config table
## ({color:0xffdd00, radius:0.7, speed:2.2, hp:2}); the edge-pivot flop math
## is TOKO_DROP_PORT_BRIEF.md Part 3: "pivot arc angle 135°→45°; displacement
## along dir = L + D·cos(ang) (0→2L); height = D·sin(ang) where L = half-
## extent, D = L·√2. Tip rotation 0→90° about axis up×dir. Land flat every
## flop." 50% of picks are diagonal, matching "YELA 50% diagonals" there.
class_name YelaCube
extends Enemy

enum FlopState { REST, FLOP }

var _dir := Vector2(1.0, 0.0)
var _origin := Vector2.ZERO
var _flop_t := 0.0
var _flop_dur := 0.25
var _rest_t := 0.0
var _state := FlopState.FLOP

func init() -> void:
	setup(Color(1.0, 0.867, 0.0), 0.7, 2.2, 2, true)
	_pick_dir()

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return
	if _state == FlopState.FLOP:
		_step_flop(delta)
	else:
		_rest_t -= delta
		if _rest_t <= 0.0:
			_origin = Vector2(position.x, position.z)
			_flop_t = 0.0
			_state = FlopState.FLOP

func _pick_dir() -> void:
	var diag := randf() < 0.5
	var angles := [PI / 4.0, 3.0 * PI / 4.0, -PI / 4.0, -3.0 * PI / 4.0] if diag \
		else [0.0, PI / 2.0, PI, -PI / 2.0]
	var a: float = angles[randi() % angles.size()]
	_dir = Vector2(cos(a), sin(a))
	var l := radius
	var cycle := (2.0 * l) / maxf(speed, 0.1)
	_flop_dur = minf(0.3, cycle * 0.65)
	_rest_t = maxf(0.0, cycle - _flop_dur)
	_origin = Vector2(position.x, position.z)
	_flop_t = 0.0
	_state = FlopState.FLOP

func _step_flop(delta: float) -> void:
	_flop_t += delta
	var t := clampf(_flop_t / _flop_dur, 0.0, 1.0)
	var l := radius
	var d := l * sqrt(2.0)
	var ang := deg_to_rad(lerpf(135.0, 45.0, t))
	var disp := l + d * cos(ang)
	var h := d * sin(ang)

	position.x = _origin.x + _dir.x * disp
	position.z = _origin.y + _dir.y * disp
	mesh.position.y = radius + maxf(0.0, h) * 0.6

	var axis := Vector3(_dir.y, 0.0, -_dir.x).normalized()
	mesh.transform.basis = Basis(axis, t * PI * 0.5)

	if t >= 1.0:
		mesh.transform.basis = Basis.IDENTITY
		mesh.position.y = radius
		position.x = _origin.x + _dir.x * (2.0 * l)
		position.z = _origin.y + _dir.y * (2.0 * l)

		var hx := half_x - radius
		var hz := half_z - radius
		if position.x > hx or position.x < -hx:
			_dir.x = -_dir.x
		if position.z > hz or position.z < -hz:
			_dir.y = -_dir.y
		position.x = clampf(position.x, -hx, hx)
		position.z = clampf(position.z, -hz, hz)

		_sqv -= 0.32   # landing squish
		_state = FlopState.REST
