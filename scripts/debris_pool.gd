## debris_pool.gd — the gel that comes off a body when it is hit or killed.
##
## `TUNING.fx` in the browser build: `hitDroplets` 8, `killDroplets` 22,
## `killChunks` 5. A kill throws gel outward; a hit spits a few droplets. Both
## are the difference between "the enemy's alive flag went false" and "you
## burst it".
##
## One MultiMesh, ballistic integration on the CPU, floor bounce. Kept off
## `GPUParticles3D` deliberately for now: these need to be spawnable from the
## exact frame a body dies with the body's own colour, and a CPU pool of a few
## hundred is far cheaper to reason about than a particle system per enemy.
## PORT_BRIEF.md §3/§5 wants GPU particles eventually — that is a later pass,
## and this is the shape it will replace.
class_name DebrisPool
extends Node3D

const POOL_SIZE := 320
const GRAVITY := -26.0
const BOUNCE := -0.34
const FRICTION := 0.86
const LIFE := 0.85

var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _vz := PackedFloat32Array()
var _size := PackedFloat32Array()
var _life := PackedFloat32Array()
var _col: Array[Color] = []
var _next := 0

var _mm: MultiMeshInstance3D
var _built := false

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true
	for a in [_px, _py, _pz, _vx, _vy, _vz, _size, _life]:
		a.resize(POOL_SIZE)
	_col.resize(POOL_SIZE)

	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 4

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.15
	mat.metallic = 0.0
	# Lit, not unlit: these are lumps of the same gel the bodies are made of,
	# and unlit spheres of a flat colour read as confetti.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

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
	add_child(_mm)

## `spread` is the outward speed; `up` biases the initial lift.
func burst(x: float, z: float, count: int, color: Color, size: float,
		spread := 6.0, up := 5.0) -> void:
	for i in count:
		var s := _next
		_next = (_next + 1) % POOL_SIZE
		var a := randf() * TAU
		var r := randf()
		_px[s] = x
		_py[s] = 0.35 + randf() * 0.5
		_pz[s] = z
		_vx[s] = cos(a) * spread * (0.35 + r)
		_vy[s] = up * (0.4 + randf())
		_vz[s] = sin(a) * spread * (0.35 + r)
		_size[s] = size * (0.5 + randf() * 0.8)
		_life[s] = LIFE * (0.7 + randf() * 0.6)
		_col[s] = color

func update(delta: float) -> void:
	if not _built:
		return
	var n := 0
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		_vy[i] += GRAVITY * delta
		_px[i] += _vx[i] * delta
		_py[i] += _vy[i] * delta
		_pz[i] += _vz[i] * delta
		if _py[i] < 0.06:
			_py[i] = 0.06
			_vy[i] *= BOUNCE
			_vx[i] *= FRICTION
			_vz[i] *= FRICTION
		# Shrink out over the last third, so nothing vanishes mid-air.
		var f: float = _size[i] * minf(1.0, _life[i] / (LIFE * 0.34))
		_mm.multimesh.set_instance_transform(n,
			Transform3D(Basis().scaled(Vector3(f, f, f)),
				Vector3(_px[i], _py[i], _pz[i])))
		_mm.multimesh.set_instance_color(n, _col[i])
		n += 1
	_mm.multimesh.visible_instance_count = n

func clear() -> void:
	for i in POOL_SIZE:
		_life[i] = 0.0
	if _built:
		_mm.multimesh.visible_instance_count = 0
