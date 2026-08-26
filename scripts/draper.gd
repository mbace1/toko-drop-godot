## draper.gd
##
## DRAPER — "wall-weaver" (enemy.js v171, line 1885): holds range, faces the
## player (the loom itself IS the tell — nothing else in the roster turns to
## face you), strobes for 0.9s, then looms a 15-slot bullet curtain — marching
## straight at wherever it was aimed, with one 2-slot gap to escape through —
## rather than a shot that tracks you.
##
## Stats — CFG (enemy.js line 528):
##   color 0x9955ff, radius 0.8, speed 0.9, hp 5, bulletColor 0xcc88ff,
##   fireInterval 5.0. Geometry is a flat box (1.5 x 0.9 x 0.4 — "the loom"),
##   not the usual dome/cube silhouette.
class_name Draper
extends Enemy

const WANT_RANGE := 11.0
const RANGE_BAND := 1.5
const WINDUP_DUR := 0.9
const FIRE_RANGE := 17.0    # enemy.js: only arms the weave inside this
const CURTAIN_SLOTS := 15
const SLOT_SPACING := 0.85
const CURTAIN_SPEED_MULT := 0.72
const STROBE_HZ := 22.0

var _weave_t := 0.0
var _windup := 0.0
var _rim_default: Color

func init() -> void:
	setup(Color(0.6, 0.333, 1.0), 0.8, 0.9, 5, true)
	bullet_color = Color(0.8, 0.533, 1.0)
	fire_interval = 5.0
	revenge_dialect = Revenge.FAN
	# The loom, not the generic cube setup() built — a flat panel is the
	# whole reason it reads as something that turns to face you.
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.9, 0.4)
	mesh.mesh = bm
	_rim_default = color.lightened(0.55)
	_weave_t = 2.0 + rng.randf() * 2.0

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist > 0.001:
		var nx := dx / dist
		var nz := dz / dist
		if dist > WANT_RANGE + RANGE_BAND:
			position.x += nx * speed * delta
			position.z += nz * speed * delta
		elif dist < WANT_RANGE - RANGE_BAND:
			position.x -= nx * speed * delta
			position.z -= nz * speed * delta
		_clamp_to_arena()
		mesh.rotation.y = atan2(dx, dz)

	if _windup > 0.0:
		_windup -= delta
		mat.set_shader_parameter("rim_color",
			Color(0.333, 0.133, 0.667) if sin(_t * STROBE_HZ) > 0.0 else Color(0.067, 0.0, 0.133))
		if _windup <= 0.0:
			mat.set_shader_parameter("rim_color", _rim_default)
			_fire_curtain(dx, dz, dist)
			_weave_t = fire_interval
	else:
		_weave_t -= delta
		if _weave_t <= 0.0 and dist < FIRE_RANGE:
			_windup = WINDUP_DUR

## The march direction is locked to wherever the loom was FACING when the
## windup finished (`dx`/`dz`, the same values used to orient it) — it does
## not re-aim at the last instant, so the strobe is the whole warning.
func _fire_curtain(dx: float, dz: float, dist: float) -> void:
	if bullets == null or dist <= 0.001:
		return
	var fx := dx / dist
	var fz := dz / dist
	var px := -fz
	var pz := fx
	var gap := 2 + rng.randi() % 11   # slots 2..12
	for k in CURTAIN_SLOTS:
		if k == gap or k == gap + 1:   # the way through
			continue
		var o := float(k - 7) * SLOT_SPACING
		bullets.spawn_dir(position.x + px * o, position.z + pz * o, fx, fz,
			false, bullet_color, false, CURTAIN_SPEED_MULT)
