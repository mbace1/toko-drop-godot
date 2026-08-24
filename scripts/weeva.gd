## weeva.gd
##
## WEEVA — a drifting spiral turret. It barely moves and it never stops firing:
## one bullet every 0.16s, each rotated a fixed step past the last, so it lays
## down a slow rotating spiral you walk out of rather than dodge.
##
## Stats from enemy.js's CFG table (line 489):
##   color 0x4422ee, radius 0.8, speed 0.6, hp 3,
##   bulletColor 0x6644ff, fireInterval 0.16
##
## That interval is the whole character: it is a STREAM, not a volley, and it is
## the first ported enemy with no wind-up at all. A telegraph on a 0.16s cadence
## would be permanently lit and would tell you nothing.
##
## Movement is enemy.js's WEEVA case — "drifting spiral turret: weaves while
## slowly closing on the player so it actually applies pressure instead of
## meandering in place":
##   x += (sin(t*0.7)*0.5 + nx*0.45) * speed * dt
##   z += (cos(t*0.5)*0.5 + nz*0.45) * speed * dt
class_name Weeva
extends Enemy

const SPIRAL_STEP := 0.38    # enemy.js rotSpeed base
const VIBRATE := 0.03        # TUNING.blob.weevaVibrate
const VIBRATE_HZ := 40.0

var _spiral_angle := 0.0

func init() -> void:
	setup(Color(0.267, 0.133, 0.933), 0.8, 0.6, 3, false)
	bullet_color = Color(0.4, 0.267, 1.0)
	fire_interval = 0.16
	revenge_dialect = Revenge.FAN     # TUNING.revenge.byType: WEEVA -> FAN
	# Taller drill dome — TUNING.blob.shapes.WEEVA {x:0.98, y:1.02, z:0.98}.
	base_shape = Vector3(0.98, 1.02, 0.98)
	mesh.position.y = radius * base_shape.y
	trail_interval = 0.06   # enemy.js TRAIL_CFG
	trail_size = 0.55
	_spiral_angle = randf() * TAU

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return

	if target != null:
		var dx := target.position.x - position.x
		var dz := target.position.z - position.z
		var dist := Vector2(dx, dz).length()
		if dist > 0.001:
			position.x += (sin(_t * 0.7) * 0.5 + (dx / dist) * 0.45) * speed * delta
			position.z += (cos(_t * 0.5) * 0.5 + (dz / dist) * 0.45) * speed * delta
		_clamp_to_arena()

	# The drill buzz: a fast scale jitter on top of the spring squash, so the
	# body visibly vibrates with the stream it is laying down.
	var buzz := 1.0 + sin(_t * VIBRATE_HZ) * VIBRATE
	mesh.scale *= buzz

	# No wind-up: pass 0 and _tick_fire returns true on the interval itself.
	if _tick_fire(delta, 0.0):
		bullets.spawn_dir(position.x, position.z,
			cos(_spiral_angle), sin(_spiral_angle), false, bullet_color)
		_spiral_angle += SPIRAL_STEP
