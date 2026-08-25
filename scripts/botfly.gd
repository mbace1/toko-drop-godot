## botfly.gd
##
## BOTFLY — a flying bot that holds a mid-range band, drifts tangentially, and
## fires slow HOMING shots so the pressure comes from changing angles rather
## than from volume.
##
## Stats from enemy.js's CFG table (line 502):
##   color 0xff55bb, radius 0.5, speed 2.0, hp 2,
##   bulletColor 0xff66ee, fireInterval 3.8
##
## The shot is the point: enemy.js launches it at the player then lets
## bullet.js steer it each frame at turnRate 1.8 and speedMult 0.62 — the
## comment says *"slow homing shot ... speedMult 0.62 keeps it outrunnable"*.
## A homing bullet you cannot outrun is a hit with extra steps.
class_name Botfly
extends Enemy

const HOLD := 8.0
const BAND := 1.5
const ORBIT := 0.8
const HOVER := 0.22
const TURN_RATE := 1.8      # enemy.js homing turn rate
const SPEED_MULT := 0.62    # "keeps it outrunnable"

var _orbit_dir := 1.0

func init() -> void:
	setup(Color(1.0, 0.333, 0.733), 0.5, 2.0, 2, false)
	bullet_color = Color(1.0, 0.4, 0.933)
	fire_interval = 3.8
	revenge_dialect = Revenge.AIMED
	trail_interval = 0.09
	trail_size = 0.4
	_orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var d := _hold_at_range(delta, HOLD, BAND, _orbit_dir * ORBIT)
	# It FLIES: the bob is what tells you the shots come from above the floor.
	mesh.position.y = radius + 0.35 + sin(_t * 3.0) * HOVER

	if _tick_fire(delta, 0.35):
		if d == Vector2.ZERO:
			return
		_sqv -= 0.5
		bullets.spawn_dir(position.x, position.z, d.x, d.y, false,
			bullet_color, false, SPEED_MULT, true, TURN_RATE)
