## splitta.gd
##
## SPLITTA — a big slow blob that is really three small fast ones. Killing it
## does not clear the space it occupied; it fills it.
##
## Stats from enemy.js's CFG table (line 490):
##   color 0x88ff22, radius 1.1, speed 1.0, hp 5
##
## Movement is the SCHOOL archetype's simple approach (enemy.js's SPLITTA case
## just closes on the player and stops at 1.2). The interest is entirely in the
## death: `_childType = GLOBBO`, `_childCount = 3` — *"always splits into 3
## small blobs (v99)"*.
##
## TOKO_DROP_PORT_BRIEF.md Part 2 asks for the split to be **visible before it
## happens**: "two child dome meshes (same material) embedded at (±0.6, 0.42,
## 0.15) local, scale 0.42". A body that suddenly becomes three bodies with no
## warning is a rule you learn by dying to it; carrying the children where you
## can see them makes it a rule you learn by looking.
class_name Splitta
extends Enemy

const CHILD_COUNT := 3        # enemy.js: "always splits into 3 small blobs"
const STOP_DIST := 1.2
const CHILD_SCATTER := 1.5    # how far the children are thrown on the split

func init() -> void:
	setup(Color(0.533, 1.0, 0.133), 1.1, 1.0, 5, false)
	trail_interval = 0.07     # enemy.js TRAIL_CFG
	trail_size = 0.60
	revenge_dialect = Revenge.RING
	child_count = CHILD_COUNT     # enemy.js: "always splits into 3 small blobs"
	child_kind = "GLOBBO"         # enemy.js _childType
	child_scatter = CHILD_SCATTER
	_add_child_domes()

## The tell: two smaller domes riding on the body, in the same material, so the
## split reads before it happens.
func _add_child_domes() -> void:
	for side in [-1.0, 1.0]:
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		sm.radial_segments = 16
		sm.rings = 10
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = mat        # shares the parent's gel material
		mi.scale = Vector3.ONE * 0.42
		mi.position = Vector3(side * 0.6, 0.42, 0.15)
		mesh.add_child(mi)

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var dist := Vector2(dx, dz).length()
	if dist > STOP_DIST:
		position.x += (dx / dist) * move_speed() * delta
		position.z += (dz / dist) * move_speed() * delta
		_clamp_to_arena()
