## sludge_cube.gd
##
## SLUDGE CUBE — the slow one that makes the floor worse. It ploughs rather
## than dodges (MASS in TUNING.movement.byType) and leaves a poison patch
## behind it that lingers long after the body has gone.
##
## Stats from enemy.js's CFG table (line 494):
##   color 0xaaee00, radius 0.65, speed 0.75, hp 2
##
## Cadence from TUNING.fx: `poisonInterval` 0.5, `poisonLife` 8. That eight
## seconds is the point — the patch outlives the enemy by a long way, so a
## SLUDGE that is already dead is still shaping where you can go.
class_name SludgeCube
extends YelaCube

const POISON_INTERVAL := 0.5    # TUNING.fx.poisonInterval
const POISON_RADIUS := 1.15

var poison: PoisonField         # set by WaveDirector
var _poison_t := 0.0

func init() -> void:
	setup(Color(0.667, 0.933, 0.0), 0.65, 0.75, 2, true)
	trail_interval = 0.0        # not in TRAIL_CFG — it is slow, and it leaves a patch instead
	revenge_dialect = Revenge.RING
	_pick_dir()

func update(delta: float) -> void:
	super.update(delta)
	if not alive:
		return
	if poison == null:
		return
	_poison_t -= delta
	if _poison_t <= 0.0:
		_poison_t = POISON_INTERVAL
		poison.add(position.x, position.z, POISON_RADIUS)
