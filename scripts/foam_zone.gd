## foam_zone.gd
##
## CLEANSE FOAM (main.js `FoamZone`, class at line 1751): a circle of foam
## on the floor. Stand inside it and a charge ring fills over 1.2s straight;
## step out and it decays at 1.5x the rate, so it rewards COMMITMENT, not a
## quick tag. Fully charge it and every enemy bullet on screen vanishes —
## paid per bullet cleared (500 + 10/bullet) — a defensive panic button you
## have to stand still and earn.
##
## Spawns wave >= 6 on every 4th wave (w%4==2), never a boss wave — offset
## from VaultCrate's (w%4==3) and EscortBot's (w%4==1) beats so none of the
## three "living-arena" bonus events ever land on the same wave. Unlike
## vault/escort it is NOT swept at the next wave's setup — it lives out its
## own 12s life (or gets cleansed) independently, the same as Gates.
class_name FoamZone
extends Node3D

const RADIUS := 2.2
const LIFE := 12.0
const CHARGE_NEEDED := 1.2
const CHARGE_DECAY_MULT := 1.5
const BURST_DUR := 0.3

var life := LIFE
var charge := 0.0
var done := false
var burst_t := 0.0

var _disc_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _fill: MeshInstance3D

func build(x: float, z: float) -> void:
	position = Vector3(x, 0.02, z)

	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = RADIUS
	disc_mesh.bottom_radius = RADIUS
	disc_mesh.height = 0.02
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.albedo_color = Color(0.6, 0.933, 1.0, 0.16)
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = _disc_mat
	add_child(disc)

	# The rim ring — a TorusMesh lies flat by default (the same trick this
	# port already uses for WARDEN's/the boss's aura rings), no rotation
	# needed the way main.js's flat RingGeometry needs a -PI/2 X-rotation.
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = RADIUS - 0.12
	rim_mesh.outer_radius = RADIUS
	rim_mesh.rings = 32
	rim_mesh.ring_segments = 6
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_mat.albedo_color = Color(0.733, 0.957, 1.0, 0.5)
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = _rim_mat
	rim.position.y = 0.005
	add_child(rim)

	var fill_mesh := CylinderMesh.new()
	fill_mesh.top_radius = RADIUS
	fill_mesh.bottom_radius = RADIUS
	fill_mesh.height = 0.02
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.22)
	_fill = MeshInstance3D.new()
	_fill.mesh = fill_mesh
	_fill.material_override = _fill_mat
	_fill.position.y = 0.01
	_fill.scale = Vector3(0.001, 1.0, 0.001)
	add_child(_fill)

## Returns false once this zone is finished (life ran out, or the burst
## finished playing) — the caller removes it then.
func update(delta: float, player_pos: Vector3, player_alive: bool, t: float) -> bool:
	if done:
		burst_t -= delta
		var k := 1.0 - maxf(0.0, burst_t) / BURST_DUR
		_fill.scale = Vector3(1.0 + k * 1.6, 1.0, 1.0 + k * 1.6)
		_fill_mat.albedo_color.a = 0.35 * (1.0 - k)
		_rim_mat.albedo_color.a = 0.5 * (1.0 - k)
		_disc_mat.albedo_color.a = 0.16 * (1.0 - k)
		return burst_t > 0.0

	life -= delta
	if life <= 0.0:
		return false
	var dx := player_pos.x - position.x
	var dz := player_pos.z - position.z
	var inside := player_alive and dx * dx + dz * dz < RADIUS * RADIUS
	charge = clampf(charge + (delta if inside else -delta * CHARGE_DECAY_MULT), 0.0, CHARGE_NEEDED)
	var s := maxf(0.001, charge / CHARGE_NEEDED)
	_fill.scale = Vector3(s, 1.0, s)
	_rim_mat.albedo_color.a = 0.3 + (0.4 if inside else 0.12) * absf(sin(t * 6.0))
	_disc_mat.albedo_color.a = 0.16 * minf(1.0, life / 1.5)   # fade out if ignored
	return true

func is_charged() -> bool:
	return not done and charge >= CHARGE_NEEDED

## Quick expand + fade, then gone — the reward is applied by the caller
## (main.gd's `_cleanse_foam()`) the same frame this is called.
func begin_cleanse() -> void:
	done = true
	burst_t = BURST_DUR
