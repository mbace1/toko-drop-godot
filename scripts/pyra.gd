## pyra.gd
##
## PYRA — a stationary spinner that throws a wide fan every 2.5s. It never
## moves, so it is entirely a positioning problem: the arena around it is what
## changes, not the thing itself.
##
## Stats from enemy.js's CFG table (line 500):
##   color 0xff9900, radius 1.0, speed 0, hp 4,
##   bulletColor 0xffcc44, fireInterval 2.5
## Movement role HUNTER in the browser, but its `speed` is 0 and its update is
## just `group.rotation.y += spinSpeed * dt` — it spins in place.
class_name Pyra
extends Enemy

const SPIN := 1.1
const WINDUP := 0.45
const FAN_COUNT := 7
const FAN_SPAN := 1.5       # radians

func init() -> void:
	setup(Color(1.0, 0.6, 0.0), 1.0, 0.0, 4, false)
	bullet_color = Color(1.0, 0.8, 0.267)
	fire_interval = 2.5
	revenge_dialect = Revenge.FAN
	# A pyramid, not a blob: it is the one body in the roster that never moves,
	# and the silhouette should say so before it fires.
	var pm := CylinderMesh.new()
	pm.top_radius = 0.0
	pm.bottom_radius = radius
	pm.height = radius * 2.0
	pm.radial_segments = 4
	mesh.mesh = pm

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return
	mesh.rotate_y(SPIN * delta)
	if _tick_fire(delta, WINDUP):
		_sqv -= 0.7
		_fan(position.x, position.z, FAN_COUNT, FAN_SPAN, _angle_to_target())
