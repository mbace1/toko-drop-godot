## siren.gd
##
## SIREN — never touches you, and makes everything that does far worse. It
## hovers at mid range, backs off when pressed, and every few seconds inhales
## and SCREAMS: every body inside its reach surges to 1.6× speed for three
## seconds.
##
## Stats from enemy.js's CFG table (line 505):
##   color 0xbb66ff, radius 0.75, speed 1.2, hp 3
## tuning.js line 156 says what it is for outright: *"screamer — surges the
## pack, kill it first"*.
##
## This is the "side quest" shape (owner direction, 2026-08-25): a body that
## pulls focus off the primary goal. It is fragile and it is running away, so
## chasing it costs you the thing you were doing — and not chasing it costs
## you more.
class_name Siren
extends Enemy

const HOLD := 9.0               # enemy.js: `const keep = 9`
const BAND := 1.0
const FLEE_MULT := 1.3          # it backs off FASTER than it advances
const INHALE := 0.8             # the tell
const SCREAM_MIN := 3.5
const SCREAM_RAND := 1.5
const SURGE_RADIUS := 7.0       # main.js SIREN_RADIUS
const SURGE_TIME := 3.0         # main.js: w._surgeT = 3
const INHALE_SWELL := 0.45      # it visibly fills up before it screams

## Read and cleared by WaveDirector, which owns the swarm the scream acts on.
var scream_ready := false

var _inhale_t := 0.0
var _scream_t := 0.0

func init() -> void:
	setup(Color(0.733, 0.4, 1.0), 0.75, 1.2, 3, false)
	revenge_dialect = Revenge.RING
	trail_interval = 0.10
	trail_size = 0.40
	_scream_t = SCREAM_MIN + rng.randf() * SCREAM_RAND

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return

	# Coward support: holds a band, and runs harder than it chases.
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var d := Vector2(dx, dz).length()
	if d > 0.001:
		if d > HOLD + BAND:
			position.x += (dx / d) * move_speed() * delta
			position.z += (dz / d) * move_speed() * delta
		elif d < HOLD - BAND:
			position.x -= (dx / d) * move_speed() * FLEE_MULT * delta
			position.z -= (dz / d) * move_speed() * FLEE_MULT * delta
		_clamp_to_arena()

	if _inhale_t > 0.0:
		_inhale_t -= delta
		# The tell: it swells and strobes while filling up. A scream with no
		# wind-up would be an unavoidable difficulty spike.
		var k := 1.0 - _inhale_t / INHALE
		_inflate = INHALE_SWELL * k
		mat.set_shader_parameter("rim_color",
			Color(0.6, 0.3, 1.0) if sin(_t * 20.0) > 0.0 else Color(0.13, 0.0, 0.27))
		if _inhale_t <= 0.0:
			_inflate = 0.0
			scream_ready = true
			_scream_t = SCREAM_MIN + rng.randf() * SCREAM_RAND
			mat.set_shader_parameter("rim_color", color.lightened(0.55))
	else:
		_scream_t -= delta
		if _scream_t <= 0.0:
			_inhale_t = INHALE
