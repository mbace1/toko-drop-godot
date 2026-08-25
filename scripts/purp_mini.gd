## purp_mini.gd
##
## PURP MINI — the fastest body in the ported roster, and the smallest. Five of
## them arrive at once, which is the whole point of PURP CUBE.
##
## Stats from enemy.js's CFG table (line 498):
##   color 0xdd66ff, radius 0.26, speed 3.8, hp 1
class_name PurpMini
extends Enemy

func init() -> void:
	setup(Color(0.867, 0.4, 1.0), 0.26, 3.8, 1, true)
	revenge_dialect = Revenge.RING

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var d := Vector2(dx, dz).length()
	if d > 0.35:
		position.x += (dx / d) * speed * delta
		position.z += (dz / d) * speed * delta
		_clamp_to_arena()
