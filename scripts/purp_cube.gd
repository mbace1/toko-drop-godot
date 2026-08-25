## purp_cube.gd
##
## PURP CUBE — the other splitter, and the bigger burst: five children rather
## than REDD's four, and faster ones. Its revenge speaks FAN rather than RING
## (TUNING.revenge.byType), so its corpse throws an arc instead of a bloom.
##
## Stats from enemy.js's CFG table (line 496):
##   color 0xcc44ff, radius 0.75, speed 1.6, hp 3
## Children: PURP_MINI (line 498) — `_childCount = 5 + pTier * 2`, so five at
## base tier.
class_name PurpCube
extends YelaCube

func init() -> void:
	setup(Color(0.8, 0.267, 1.0), 0.75, 1.6, 3, true)
	bullet_color = Color(0.8, 0.4, 1.0)
	child_count = 5              # 5 + tier*2, base tier
	child_kind = "PURP_MINI"
	child_scatter = 1.9
	revenge_dialect = Revenge.FAN
	_pick_dir()
