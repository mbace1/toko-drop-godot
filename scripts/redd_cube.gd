## redd_cube.gd
##
## REDD CUBE — a fast flopping cube that bursts into a pack of small rushers.
## Where SPLITTA is slow and its children are ordinary, REDD is quick and its
## children are quicker: killing it in a corner is how you get surrounded.
##
## Stats from enemy.js's CFG table (line 495):
##   color 0xff2211, radius 0.75, speed 1.9, hp 3
## Children: REDD_MINI (line 497) — `_childCount = min(8, 4 + rTier * 2)`,
## so four at base tier.
class_name ReddCube
extends YelaCube

func init() -> void:
	setup(Color(1.0, 0.133, 0.067), 0.75, 1.9, 3, true)
	child_count = 4              # min(8, 4 + tier*2), base tier
	child_kind = "REDD_MINI"
	child_scatter = 1.7
	revenge_dialect = Revenge.RING
	_pick_dir()
