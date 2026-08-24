## orange_cube.gd
##
## ORANGE CUBE — flops toward you like a YELA, then stops and throws a WALL of
## bullets: six shots side by side, all travelling the same way, so you dodge
## around the wall rather than between the shots.
##
## Stats from enemy.js's CFG table (line 493):
##   color 0xff8800, radius 0.75, speed 1.4, hp 4,
##   bulletColor 0xff6600, fireInterval 3.2
##
## Movement reuses the cube flop (it is a cube; TOKO_DROP_PORT_BRIEF Part 3
## covers the whole family) but chooses its direction with intent instead of at
## random — enemy.js's ORANGE_CUBE case walks toward a point near the player
## and re-picks when it arrives or after 5s.
##
## The volley is enemy.js line 2046: the aim is SNAPPED to the nearest of eight
## compass directions, then `_totalShots` bullets are spread along the
## perpendicular across 4 units and all fired along that one direction. Snapping
## is what makes the wall readable — an arbitrary angle reads as a spray, an
## axis-aligned wall reads as a thing with a gap you can get around.
class_name OrangeCube
extends YelaCube

const TOTAL_SHOTS := 6       # enemy.js `_totalShots` starting value
const WALL_WIDTH := 4.0      # the (s/(n-1) - 0.5) * 4.0 spread
const WINDUP := 0.35
const RETARGET_TIME := 5.0
const ARRIVE_DIST := 2.6

const DIRS8: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.707, 0.707), Vector2(-0.707, 0.707),
	Vector2(0.707, -0.707), Vector2(-0.707, -0.707),
]

var _move_t := 0.0

func init() -> void:
	setup(Color(1.0, 0.533, 0.0), 0.75, 1.4, 4, true)
	bullet_color = Color(1.0, 0.4, 0.0)
	fire_interval = 3.2
	revenge_dialect = Revenge.AIMED   # TUNING.revenge.byType: ORANGE_CUBE -> AIMED
	_pick_dir()

## Flop toward the player, but on the cube's own eight-way grid — it commits to
## a direction for a whole flop, so it closes in steps rather than tracking.
func _choose_angle() -> float:
	if target == null:
		return super._choose_angle()
	var to := Vector2(target.position.x - position.x, target.position.z - position.z)
	if to.length() < 0.001:
		return super._choose_angle()
	return _snap8(to.normalized()).angle()

func _snap8(v: Vector2) -> Vector2:
	var best := DIRS8[0]
	var best_dot := -INF
	for d in DIRS8:
		var dot := d.dot(v)
		if dot > best_dot:
			best_dot = dot
			best = d
	return best

func update(delta: float) -> void:
	super.update(delta)
	if not alive:
		return

	# Re-aim the flop line periodically, or once it has arrived (enemy.js
	# re-picks its target at td < 2.6 or after 5s).
	_move_t += delta
	if target != null:
		var d := Vector2(target.position.x - position.x, target.position.z - position.z).length()
		if _move_t > RETARGET_TIME or d < ARRIVE_DIST:
			_move_t = 0.0
			_pick_dir()

	if _tick_fire(delta, WINDUP):
		_sqv -= 0.6
		_fire_wall()

func _fire_wall() -> void:
	if target == null:
		return
	var to := Vector2(target.position.x - position.x, target.position.z - position.z)
	if to.length() < 0.001:
		return
	var fd := _snap8(to.normalized())
	var perp := Vector2(-fd.y, fd.x)
	for i in TOTAL_SHOTS:
		var t := (float(i) / float(TOTAL_SHOTS - 1) - 0.5) * WALL_WIDTH
		bullets.spawn_dir(
			position.x + perp.x * t, position.z + perp.y * t,
			fd.x, fd.y, false, bullet_color)
