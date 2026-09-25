## arc_mover.gd
##
## The v251 ARC-MOVERS' shared steering — RIBBON and SLUG (Q-042), ported
## from enemy.js `_arcSteer` (PROGRESSION_DESIGN.md §8.9 upstream).
##
## Steering with a TURN-RATE LIMIT, which no other body has: every other
## species re-points itself at the player each frame, and a dome hides that.
## A long body draws its own recent heading, so an instant turn would render
## as a corner. The serpentine is a heading OFFSET (the path curves), not a
## sideways shove (the body would crab). Numbers are TUNING.arc.
##
## A long body also hit-tests ITSELF along its length (`long_body`), which
## main.gd asks instead of the head circle. Subclasses own the body.
class_name ArcMover
extends Enemy

const TURN_RATE := 2.2     # TUNING.arc.turnRate — rad/s, the ceiling on a heading change
const WEAVE_HZ := 1.7      # TUNING.arc.weaveHz — the serpentine's rate
const WEAVE_AMP := 0.55    # TUNING.arc.weaveAmp — rad of heading offset at full swing

var heading := 0.0
var _weave := 0.0
var _clamp_r := 0.5   # the species' CFG radius — a boss's bigger body still clamps at it, as upstream

## Called from the subclass's init() once position is set: the browser starts
## the heading pointed at the arena's centre (`atan2(-z, -x)`). The weave phase
## is a gameplay draw — it bends the path — so it comes off the run's stream.
func _arc_init() -> void:
	long_body = true
	_clamp_r = radius
	heading = atan2(-position.z, -position.x)
	_weave = rng.randf() * TAU

## enemy.js `_arcSteer(dt, tx, tz, speed, arena)`, line for line.
func _arc_steer(delta: float, tx: float, tz: float, spd: float) -> void:
	var want := atan2(tz - position.z, tx - position.x)
	_weave += delta * WEAVE_HZ
	var desired := want + sin(_weave) * WEAVE_AMP
	var d := desired - heading
	while d > PI:
		d -= TAU
	while d < -PI:
		d += TAU
	var mx := TURN_RATE * delta
	heading += clampf(d, -mx, mx)
	var nx := position.x + cos(heading) * spd * delta
	var nz := position.z + sin(heading) * spd * delta
	var c := arena.clamp_pt(nx, nz, _clamp_r, _xz)
	if c.x != nx or c.z != nz:
		heading += TURN_RATE * delta * 2.0   # on a wall: bend off it
	position.x = c.x
	position.z = c.z
