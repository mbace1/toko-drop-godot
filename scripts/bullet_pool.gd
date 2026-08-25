## bullet_pool.gd
##
## Godot equivalent of toko-drop/js/bullet.js: a fixed-size pool rendered with
## instanced draw calls instead of one node per bullet. The browser build uses
## three THREE.InstancedMesh (halo/core/shadow); this uses three MultiMesh
## instances the same way — spawn_dir() pops from the free list, update()
## steps + recycles, _render() rewrites every live instance's transform each
## frame and sets visible_instance_count (Godot's equivalent of the JS
## `.count = n` trick).
class_name BulletPool
extends Node3D

const POOL_SIZE := 300
const ENEMY_SPEED := 7.0
const PLAYER_SPEED := 24.0

class Bullet:
	var x := 0.0
	var z := 0.0
	var vx := 0.0
	var vz := 0.0
	var alive := false
	var is_player := false
	var fat := false
	var lifetime := 0.0
	var phase := 0.0
	var base_scale := 1.0
	var color := Color.WHITE
	## BOTFLY's shot steers toward the player each frame. bullet.js turns it a
	## FRACTION of the way rather than snapping, so it reads as homing and stays
	## dodgeable rather than becoming a guaranteed hit.
	var homing := false
	var turn_rate := 0.0

var _pool: Array[Bullet] = []
var active: Array[Bullet] = []

var _halo: MultiMeshInstance3D
var _core: MultiMeshInstance3D
var _shadow: MultiMeshInstance3D
var _built := false

func _ready() -> void:
	build()

## Idempotent — safe to call again right after add_child() rather than
## trusting _ready()'s exact timing (matters in headless/bare-SceneTree
## contexts such as tests/smoke.gd, where add_child() does not flush
## NOTIFICATION_READY synchronously).
func build() -> void:
	if _built:
		return
	_built = true

	for i in POOL_SIZE:
		_pool.append(Bullet.new())

	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 0.15
	halo_mesh.height = 0.3
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.vertex_color_use_as_albedo = true
	halo_mat.albedo_color = Color(1, 1, 1, 0.6)
	_halo = _make_multimesh(halo_mesh, halo_mat, true)

	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.075
	core_mesh.height = 0.15
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.albedo_color = Color(1, 1, 1, 0.96)
	_core = _make_multimesh(core_mesh, core_mat, false)

	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 1.0
	shadow_mesh.bottom_radius = 1.0
	shadow_mesh.height = 0.01
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0, 0, 0, 0.25)
	_shadow = _make_multimesh(shadow_mesh, shadow_mat, false)

func _make_multimesh(mesh: Mesh, material: Material, use_colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = 0
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(inst)
	return inst

## isPlayer -> is_player, fat -> bigger slow lob shot (BAMBU-style, unused yet
## but kept so enemy scripts can opt in without a pool API change later).
## speed_mult is what makes revenge fire readable: TUNING.revenge.speedMult is
## 0.6 — "revenge is slow — the graze game, not a wall".
func spawn_dir(x: float, z: float, dx: float, dz: float, is_player: bool, color = null, fat: bool = false, speed_mult: float = 1.0, homing: bool = false, turn_rate: float = 0.0) -> void:
	if _pool.is_empty():
		return
	var b: Bullet = _pool.pop_back()
	var speed := (PLAYER_SPEED if is_player else (3.5 if fat else ENEMY_SPEED)) * speed_mult
	b.x = x
	b.z = z
	b.vx = dx * speed
	b.vz = dz * speed
	b.alive = true
	b.is_player = is_player
	b.fat = fat
	b.lifetime = 4.0
	# COSMETIC — the shimmer phase changes nothing about where this bullet goes,
	# so it draws from the GLOBAL rng and deliberately not from the director's
	# gameplay generator. Sharing that stream would make wave composition depend
	# on how much the player shot, and two players on one seed would diverge from
	# the trigger (design/DETERMINISM_AND_SEEDS.md §2). Do not "tidy" this.
	b.phase = randf() * TAU
	b.color = color if color != null else (Color(0.4, 1.0, 0.8) if is_player else Color(1.0, 0.33, 0.2))
	b.base_scale = 3.0 if fat else (1.3 if is_player else 1.6)
	b.homing = homing
	b.turn_rate = turn_rate
	active.append(b)

## `toward` is the player's position; homing shots steer at it.
func update(delta: float, half_size: float, toward = null) -> void:
	for i in range(active.size() - 1, -1, -1):
		var b: Bullet = active[i]
		if not b.alive:
			_recycle_at(i)
			continue
		if b.homing and toward != null:
			# A TURN, not a snap (bullet.js _steerToward).
			var sp := Vector2(b.vx, b.vz).length()
			var to := Vector2(toward.x - b.x, toward.z - b.z)
			if to.length() > 0.001:
				var want := to.normalized() * sp
				var k := minf(1.0, b.turn_rate * delta)
				b.vx += (want.x - b.vx) * k
				b.vz += (want.y - b.vz) * k
		b.x += b.vx * delta
		b.z += b.vz * delta
		b.lifetime -= delta
		if b.lifetime <= 0.0 or absf(b.x) > half_size + 2.0 or absf(b.z) > half_size + 2.0:
			_recycle_at(i)
	_render()

func _recycle_at(i: int) -> void:
	var b: Bullet = active[i]
	b.alive = false
	active.remove_at(i)
	_pool.append(b)

func _render() -> void:
	var n := active.size()
	for i in n:
		var b: Bullet = active[i]
		var basis := Basis().scaled(Vector3.ONE * b.base_scale)
		var xform := Transform3D(basis, Vector3(b.x, 0.3, b.z))
		_halo.multimesh.set_instance_transform(i, xform)
		_halo.multimesh.set_instance_color(i, b.color)
		_core.multimesh.set_instance_transform(i, xform)

		var shadow_r := 0.5 if b.fat else 0.18
		var sbasis := Basis().scaled(Vector3(shadow_r, 1.0, shadow_r))
		_shadow.multimesh.set_instance_transform(i, Transform3D(sbasis, Vector3(b.x, 0.02, b.z)))
	_halo.multimesh.visible_instance_count = n
	_core.multimesh.visible_instance_count = n
	_shadow.multimesh.visible_instance_count = n

func clear() -> void:
	for i in range(active.size() - 1, -1, -1):
		_recycle_at(i)
	_render()
