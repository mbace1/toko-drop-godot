## shepherd.gd
##
## SHEPHERD — the swarm game's own enemy. It never attacks and never closes.
## It holds a herding distance, circles there conducting, and DRAGS every other
## body inside its ring toward you. Kill it and the knot loosens.
##
## Stats from enemy.js's CFG table (line 511), whose comment is the design:
## *"fragile, slow, keeps its distance — the threat is what it does to the
## OTHERS, so it must be killable the moment you read the ring"*.
##   color 0x66ffcc, radius 0.6, speed 1.6, hp 3
##
## Along with SIREN this is the "side quest" shape (owner direction): the
## primary goal is the swarm in front of you, and this thing is why you have to
## break off and deal with something else.
class_name Shepherd
extends Enemy

const HOLD := 9.0               # enemy.js: `const hold = 9`
const BAND := 1.0
const FLEE_MULT := 1.15
const CIRCLE_MULT := 0.8        # in the pocket it orbits, conducting
const HERD_RADIUS := 7.5        # enemy.js SHEPHERD_RADIUS
const HERD_PULL := 1.9          # u/s dragged toward the player

func init() -> void:
	setup(Color(0.4, 1.0, 0.8), 0.6, 1.6, 3, false)
	revenge_dialect = Revenge.RING
	trail_interval = 0.10
	trail_size = 0.40

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var d := Vector2(dx, dz).length()
	if d < 0.001:
		return

	if d > HOLD + BAND:
		position.x += (dx / d) * move_speed() * delta
		position.z += (dz / d) * move_speed() * delta
	elif d < HOLD - BAND:
		# Too close. It is not a body — being next to you is not its job.
		position.x -= (dx / d) * move_speed() * FLEE_MULT * delta
		position.z -= (dz / d) * move_speed() * FLEE_MULT * delta
	else:
		position.x += (-dz / d) * move_speed() * CIRCLE_MULT * delta
		position.z += (dx / d) * move_speed() * CIRCLE_MULT * delta
	_clamp_to_arena()

## Drags one flockmate toward the player. Called by WaveDirector, which is the
## only thing that can see the rest of the swarm.
func herd(other: Enemy, player_pos: Vector3, delta: float) -> void:
	var ox := other.position.x - position.x
	var oz := other.position.z - position.z
	if ox * ox + oz * oz > HERD_RADIUS * HERD_RADIUS:
		return
	var px := player_pos.x - other.position.x
	var pz := player_pos.z - other.position.z
	var pd := Vector2(px, pz).length()
	if pd < 0.001:
		return
	other.position.x += (px / pd) * HERD_PULL * delta
	other.position.z += (pz / pd) * HERD_PULL * delta
