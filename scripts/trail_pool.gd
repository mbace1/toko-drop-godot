## trail_pool.gd — the swarm's motion trails.
##
## Port of main.js's `TrailPool` (v36/v100): pooled ghost spheres dropped
## behind every moving body, shrinking to nothing over 0.45s. Rendered as one
## MultiMesh, the same way BulletPool draws its field, so a full swarm's worth
## of afterimages is a single draw call.
##
## This is a readability feature more than a decoration. It is most of why the
## browser swarm reads as *flowing* rather than as a set of independently
## teleporting dots — you can see where a body has been, which is how you
## predict where it is going.
##
## Two details from the source that are easy to get wrong:
##  - the ghost spawns ONE BODY-RADIUS BEHIND the mover along its velocity
##    (v100), because at the mover's own position it is hidden inside the body
##  - the fade is a shrink to zero, not an alpha ramp
class_name TrailPool
extends Node3D

const POOL_SIZE := 220
const LIFE := 0.45

var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _z := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _col: Array[Color] = []
var _live := 0

var _mm: MultiMeshInstance3D
var _built := false

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true

	_x.resize(POOL_SIZE); _y.resize(POOL_SIZE); _z.resize(POOL_SIZE)
	_life.resize(POOL_SIZE); _size.resize(POOL_SIZE)
	_col.resize(POOL_SIZE)

	# SphereGeometry(1, 5, 3) in the source — deliberately coarse; these are
	# blurred afterimages, not bodies.
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 3

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 0.4)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = 0
	mm.mesh = m

	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.material_override = mat
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mm)

## Drops one ghost. Oldest slot is reused when the pool is full, which is what
## the source does — a trail that stops appearing under load reads as a bug.
func spawn(x: float, y: float, z: float, color: Color, size: float) -> void:
	var i := _live
	if _live < POOL_SIZE:
		_live += 1
	else:
		var worst := 0
		var worst_life := INF
		for k in POOL_SIZE:
			if _life[k] < worst_life:
				worst_life = _life[k]
				worst = k
		i = worst
	_x[i] = x; _y[i] = y; _z[i] = z
	_life[i] = LIFE
	_size[i] = size
	_col[i] = color

func update(delta: float) -> void:
	if not _built:
		return
	var n := 0
	for i in _live:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		# Shrink-to-zero fade, exactly as in the source.
		var f: float = _size[i] * (_life[i] / LIFE)
		var xf := Transform3D(Basis().scaled(Vector3(f, f, f)), Vector3(_x[i], _y[i], _z[i]))
		_mm.multimesh.set_instance_transform(n, xf)
		_mm.multimesh.set_instance_color(n, _col[i])
		n += 1
	_mm.multimesh.visible_instance_count = n
	# Compact once everything has expired, so `_live` cannot creep upward.
	if n == 0:
		_live = 0

func clear() -> void:
	for i in POOL_SIZE:
		_life[i] = 0.0
	_live = 0
	if _built:
		_mm.multimesh.visible_instance_count = 0
