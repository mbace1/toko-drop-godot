## drip_pool.gd — gel that drips off a body, falls, and splats on the floor.
##
## `PORT_BRIEF.md` §3 ("GPU particles — dripping gel"), whose stated result is
## the requirement: *"droplets slide down the body, fall, splat on the floor
## and spread as concentric puddle rings. This is the 'moist / dew' read."*
##
## **Deliberately NOT `GPUParticles3D`, which is what §3's snippet reaches
## for.** That snippet's own performance note gives the reason it is wrong
## here — "thousands of particles at 60fps on mobile **via Vulkan**". This
## project ships to the web on `gl_compatibility` (WebGL2; see
## `project.godot`'s own comment under `[rendering]`), where the two things
## that snippet actually depends on — `collision_mode = COLLISION_RIGID` and a
## sub-emitter fired on collision — are not the safe bet they are under
## Vulkan. Building the landmark "moist" feature on a path that works on the
## desktop I test on and silently does nothing in the browser the game is
## played in is the exact shape of the `SystemFont` bug this port already
## shipped once (see `theme_kit.gd`).
##
## So this is one shared CPU pool drawn as a single `MultiMeshInstance3D` —
## the same pattern `debris_pool.gd` and `trail_pool.gd` already use here, for
## the same reasons: one draw call for every droplet in the arena, no
## per-enemy particle system, identical behaviour on both renderers, and a
## floor "collision" that is just `y <= 0` because the floor is a plane.
##
## Cosmetic randomness only — `randf()`, never the director's RNG. A draw that
## only decides how something LOOKS must not share the gameplay stream, or
## wave composition starts depending on how long a blob has been dripping
## (`CLAUDE.md`, and `bullet_pool.gd` carries the same warning).
class_name DripPool
extends Node3D

const POOL_SIZE := 256
const GRAVITY := -14.0
## A droplet clings and stretches on the way down, then goes flat when it
## lands. Two states, one pool, one draw call.
const STATE_FALL := 0
const STATE_SPLAT := 1
const SPLAT_LIFE := 0.55
const SPLAT_SPREAD := 3.4

var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _size := PackedFloat32Array()
var _life := PackedFloat32Array()
var _state := PackedInt32Array()
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
	for a in [_px, _py, _pz, _vy, _size, _life]:
		a.resize(POOL_SIZE)
	_state.resize(POOL_SIZE)
	_col.resize(POOL_SIZE)

	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 4

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.08
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Wet gel is brighter than the body it came off, not darker.
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)

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

## One droplet, released from a point on the body. `y` is where on the body it
## let go, so drips start at the surface rather than at the origin.
func drip(x: float, y: float, z: float, color: Color, size: float) -> void:
	if not _built:
		return
	var s := _next
	_next = (_next + 1) % POOL_SIZE
	_px[s] = x
	_py[s] = y
	_pz[s] = z
	_vy[s] = -0.4 - randf() * 0.5      # it lets go, it is not thrown
	_size[s] = size * (0.65 + randf() * 0.7)
	_life[s] = 3.0
	_state[s] = STATE_FALL
	_col[s] = color

func update(delta: float) -> void:
	if not _built:
		return
	var n := 0
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var xf := Transform3D()
		if _state[i] == STATE_FALL:
			_vy[i] += GRAVITY * delta
			_py[i] += _vy[i] * delta
			if _py[i] <= 0.02:
				# Landed. Become the splat rather than spawning a second
				# system for it — a sub-emitter is the thing §3 wanted a GPU
				# pipeline for, and one pool can simply change state.
				_py[i] = 0.02
				_state[i] = STATE_SPLAT
				_life[i] = SPLAT_LIFE
			else:
				_life[i] -= delta
				# Falling gel stretches along its fall — a round dot reads as
				# a pellet, not a drip.
				var stretch: float = clampf(1.0 + absf(_vy[i]) * 0.10, 1.0, 2.2)
				var sw: float = _size[i] / sqrt(stretch)
				xf = Transform3D(
					Basis().scaled(Vector3(sw, _size[i] * stretch, sw)),
					Vector3(_px[i], _py[i], _pz[i]))
				_mm.multimesh.set_instance_transform(n, xf)
				_mm.multimesh.set_instance_color(n, _col[i])
				n += 1
				continue

		# Splat: spread outward and flatten to nothing — the "concentric
		# puddle ring" read, done as one expanding disc.
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		var k: float = 1.0 - _life[i] / SPLAT_LIFE
		var spread: float = _size[i] * (1.0 + k * SPLAT_SPREAD)
		var flat: float = _size[i] * 0.18 * (1.0 - k)
		var c: Color = _col[i]
		c.a = 1.0 - k
		xf = Transform3D(
			Basis().scaled(Vector3(spread, maxf(flat, 0.001), spread)),
			Vector3(_px[i], 0.02, _pz[i]))
		_mm.multimesh.set_instance_transform(n, xf)
		_mm.multimesh.set_instance_color(n, c)
		n += 1
	_mm.multimesh.visible_instance_count = n

## Read-only accessors, for tests. The lifecycle here (fall -> land -> splat
## -> gone) is the whole feature, and it is invisible to a screenshot of any
## single frame.
func live_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n

func peek_y(i: int) -> float:
	return _py[i]

func peek_state(i: int) -> int:
	return _state[i]

func clear() -> void:
	for i in POOL_SIZE:
		_life[i] = 0.0
	if _built:
		_mm.multimesh.visible_instance_count = 0
