## redd_mini.gd
##
## REDD MINI — what a REDD CUBE becomes. Small, quick, one hit, and it comes
## straight at you: the pack is the threat, not the individual.
##
## Stats from enemy.js's CFG table (line 497):
##   color 0xff4433, radius 0.32, speed 3.2, hp 1
class_name ReddMini
extends Enemy

func init() -> void:
	setup(Color(1.0, 0.267, 0.2), 0.32, 3.2, 1, true)
	revenge_dialect = Revenge.RING

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var d := Vector2(dx, dz).length()
	if d > 0.4:
		position.x += (dx / d) * move_speed() * delta
		position.z += (dz / d) * move_speed() * delta
		_clamp_to_arena()
