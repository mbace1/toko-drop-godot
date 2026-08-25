## bulwark.gd
##
## BULWARK — a plate walker whose FRONT is bulletproof. It walks straight at
## you, faster than the blob pack, daring you to flank; shots landing on its
## front arc are shrugged off.
##
## Stats from enemy.js's CFG table (line 504):
##   color 0x7f93c4, radius 0.9, speed 1.5, hp 4
##
## The plate rule is main.js line 8358 (v140): *"shots landing on the FRONT arc
## (~±60° of its facing) are shrugged off — flank it"*. The facing turns at a
## LIMITED rate, which is the other half of the design: *"a quick side-step
## stays a real answer (the plate can't snap-track)"*. A shield that tracks
## instantly is not a puzzle, it is just more HP.
class_name Bulwark
extends Enemy

const TURN_RATE := 2.2      # rad/s — deliberately slow enough to out-step
const BLOCK_DOT := 0.5      # cos(60 degrees): the protected arc
const STOP_DIST := 1.3

var face := Vector2(0.0, 1.0)
var _plate: MeshInstance3D

func init() -> void:
	setup(Color(0.498, 0.576, 0.769), 0.9, 1.5, 4, false)
	revenge_dialect = Revenge.RING
	trail_interval = 0.08
	trail_size = 0.5
	_build_plate()

func _build_plate() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(radius * 2.0, radius * 1.2, 0.16)
	_plate = MeshInstance3D.new()
	_plate.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.62, 0.70, 0.85)
	pm.metallic = 0.7
	pm.roughness = 0.35
	_plate.material_override = pm
	mesh.add_child(_plate)

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var d := Vector2(dx, dz).length()
	if d < 0.001:
		return
	if d > STOP_DIST:
		position.x += (dx / d) * move_speed() * delta
		position.z += (dz / d) * move_speed() * delta
		_clamp_to_arena()

	# Limited turn rate: the plate cannot snap onto you.
	var want := Vector2(dx / d, dz / d)
	face = face.lerp(want, minf(1.0, TURN_RATE * delta)).normalized()
	mesh.rotation.y = atan2(face.x, face.y)
	_plate.position = Vector3(0.0, radius * 0.2, radius + 0.2)

## True if a shot arriving from this world point lands on the plate.
func blocks(from_x: float, from_z: float) -> bool:
	var hx := from_x - position.x
	var hz := from_z - position.z
	var hl := Vector2(hx, hz).length()
	if hl < 0.001:
		return false
	return (hx / hl) * face.x + (hz / hl) * face.y > BLOCK_DOT
