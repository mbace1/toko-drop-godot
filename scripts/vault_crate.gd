## vault_crate.gd
##
## VaultCrate (main.js v175 "living-arena objectives", class at line 1042):
## a locked crate that spawns wave >= 5 on every 4th wave (w%4==3), never on
## a boss wave. Shoot it 8 times and it cracks — a guaranteed weapon pod plus
## a cash bonus, sometimes a second score bonus. Every hit also PINGS the
## room: every living enemy within 9 units surges toward the player for
## 0.7s (`Enemy.surge_t`, the same field SIREN's scream already uses) — so
## cracking it open is a real decision under pressure, not a free chest.
##
## Divergence: main.js draws the ring as a `wireframe: true` box; this port
## has no equivalent one-line wireframe material, so it's an unshaded
## additive glow box instead — reads as "an energy cage", the same idea in a
## different material.
class_name VaultCrate
extends Node3D

const HP := 8
const HIT_R := 1.15
const SURGE_RADIUS := 9.0
const SURGE_DUR := 0.7

var hp := HP
var _flash_t := 0.0
var _box_mat: StandardMaterial3D
var _ring: MeshInstance3D

func build(x: float, z: float) -> void:
	position = Vector3(x, 0.55, z)

	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 1.1, 1.5)
	_box_mat = StandardMaterial3D.new()
	_box_mat.albedo_color = Color(0.533, 0.6, 0.667)
	_box_mat.metallic = 0.35
	_box_mat.roughness = 0.35
	_box_mat.emission_enabled = true
	_box_mat.emission = Color.BLACK
	var box := MeshInstance3D.new()
	box.mesh = bm
	box.material_override = _box_mat
	add_child(box)

	var rm := BoxMesh.new()
	rm.size = Vector3(1.66, 1.2, 1.66)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.35)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring = MeshInstance3D.new()
	_ring.mesh = rm
	_ring.material_override = ring_mat
	add_child(_ring)

func update(delta: float) -> void:
	_ring.rotate_y(delta * 0.5)
	if _flash_t > 0.0:
		_flash_t -= delta
		_box_mat.emission = Color(0.4, 0.267, 0.0) if sin(Time.get_ticks_msec() * 0.05) > 0.0 else Color.BLACK
	else:
		_box_mat.emission = Color.BLACK

func hit() -> void:
	hp -= 1
	_flash_t = 0.25

func cracked() -> bool:
	return hp <= 0
