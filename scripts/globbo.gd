## globbo.gd
##
## GLOBBO — the base chaser blob. Stats and the lunging speed-pulse formula
## are lifted straight from the source: enemy.js's config table
## ({color:0x00ccaa, radius:0.55, speed:2.8, hp:1}) and
## TOKO_DROP_PORT_BRIEF.md Part 2 ("GLOBBO: chase speed pulses —
## speed × (max(0,sin(t·3+phase))² · 2.6 + 0.4) — lunging slime").
class_name Globbo
extends Enemy

var _phase := 0.0

func init() -> void:
	setup(Color(0.0, 0.8, 0.667), 0.55, 2.8, 1, false)
	_phase = randf() * TAU

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var dist := Vector2(dx, dz).length()
	if dist < 0.001:
		return
	var pulse := maxf(0.0, sin(_t * 3.0 + _phase))
	pulse = pulse * pulse * 2.6 + 0.4
	var nx := dx / dist
	var nz := dz / dist
	position.x += nx * speed * pulse * delta
	position.z += nz * speed * pulse * delta

	var hx := half_x - radius
	var hz := half_z - radius
	position.x = clampf(position.x, -hx, hx)
	position.z = clampf(position.z, -hz, hz)
