## poison_field.gd — the lingering patches SLUDGE_CUBE leaves behind.
##
## The browser build draws these as flat additive decals that fade over their
## life (`TUNING.fx.poisonLife` 8s). Same idea here: one MultiMesh of flat
## discs just above the floor, so a whole floor's worth of patches costs one
## draw call.
##
## They are a GAMEPLAY object, not decoration — `damages_at()` is what makes
## a dead SLUDGE still shape where you can stand. Kept as its own node rather
## than living inside SludgeCube so the patches outlive the body that made
## them, which is the entire point of an 8-second life on a 2-HP enemy.
class_name PoisonField
extends Node3D

const LIFE := 8.0               # TUNING.fx.poisonLife
const POOL_SIZE := 64
const TICK := 0.6               # seconds between damage ticks on one player

var _x := PackedFloat32Array()
var _z := PackedFloat32Array()
var _r := PackedFloat32Array()
var _life := PackedFloat32Array()
var _count := 0
var _mm: MultiMeshInstance3D
var _built := false
var _tick_t := 0.0

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true
	_x.resize(POOL_SIZE); _z.resize(POOL_SIZE)
	_r.resize(POOL_SIZE); _life.resize(POOL_SIZE)

	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 0.02
	m.radial_segments = 16

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# MIX, not ADD. SLUDGE lays a patch every 0.5s while it walks, so patches
	# overlap constantly; additively they compounded into one blown-out white
	# blob that read as an explosion rather than as ground you should avoid.
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1.0)

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

func add(x: float, z: float, r: float) -> void:
	var i := _count
	if _count < POOL_SIZE:
		_count += 1
	else:
		var worst := 0
		var worst_life := INF
		for k in POOL_SIZE:
			if _life[k] < worst_life:
				worst_life = _life[k]
				worst = k
		i = worst
	_x[i] = x; _z[i] = z; _r[i] = r
	_life[i] = LIFE

func update(delta: float) -> void:
	if not _built:
		return
	if _tick_t > 0.0:
		_tick_t -= delta
	var n := 0
	for i in _count:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		var f: float = _life[i] / LIFE
		var xf := Transform3D(
			Basis().scaled(Vector3(_r[i], 1.0, _r[i])),
			Vector3(_x[i], 0.03, _z[i]))
		_mm.multimesh.set_instance_transform(n, xf)
		# Sickly green, fading as the patch dies. Alpha stays low so a stack of
		# patches darkens the floor rather than erasing it.
		_mm.multimesh.set_instance_color(n, Color(0.40, 0.80, 0.10, f * 0.34))
		n += 1
	_mm.multimesh.visible_instance_count = n
	if n == 0:
		_count = 0

## True if the point is standing in poison AND this field is due a tick. The
## cooldown lives here rather than on the player so that standing in three
## overlapping patches is not three times the damage — it is a bad place to
## stand, not an instant death.
func damages_at(x: float, z: float) -> bool:
	if _tick_t > 0.0:
		return false
	for i in _count:
		if _life[i] <= 0.0:
			continue
		var dx := x - _x[i]
		var dz := z - _z[i]
		if dx * dx + dz * dz < _r[i] * _r[i]:
			_tick_t = TICK
			return true
	return false

func clear() -> void:
	for i in POOL_SIZE:
		_life[i] = 0.0
	_count = 0
	_tick_t = 0.0
	if _built:
		_mm.multimesh.visible_instance_count = 0
