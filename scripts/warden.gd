## warden.gd
##
## WARDEN — the umbrella. It never attacks. It plods toward you so its aura
## drags the protected pack forward, and everything inside that aura shrugs
## off your shots.
##
## Stats from enemy.js's CFG table (line 503):
##   color 0x33ffdd, radius 0.85, speed 1.1, hp 5
## enemy.js's own comment: *"Shield-bearer: plods toward the player so its aura
## drags the protected pack forward. No attack — the threat is the umbrella."*
##
## The third "side quest" body, and the most demanding: SIREN makes the swarm
## faster and SHEPHERD makes it closer, but a WARDEN makes it UNKILLABLE until
## you deal with the warden. It is the clearest statement of the shape.
class_name Warden
extends Enemy

const AURA_RADIUS := 6.0
const STOP_DIST := 1.4

var _aura: MeshInstance3D

func init() -> void:
	setup(Color(0.2, 1.0, 0.867), 0.85, 1.1, 5, false)
	revenge_dialect = Revenge.RING
	trail_interval = 0.09
	trail_size = 0.5
	_build_aura()

## The aura has to be VISIBLE or the rule is invisible: a player whose shots
## stop working with no explanation reads it as a bug, not as a shield.
func _build_aura() -> void:
	# A RING, not a disc. The browser calls it `_auraRing` and that is the
	# right shape: a filled circle at this size erases the floor and the bodies
	# standing on it, which the first attempt did. A boundary should read as a
	# boundary.
	var m := TorusMesh.new()
	m.inner_radius = AURA_RADIUS - 0.18
	m.outer_radius = AURA_RADIUS
	m.rings = 48
	_aura = MeshInstance3D.new()
	_aura.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.2, 1.0, 0.867, 0.55)
	_aura.material_override = mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aura)

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var d := Vector2(dx, dz).length()
	if d > STOP_DIST:
		position.x += (dx / d) * move_speed() * delta
		position.z += (dz / d) * move_speed() * delta
		_clamp_to_arena()
	# The aura is a child of the BODY NODE, which already sits on the floor —
	# subtracting `radius` here put the ring under it, invisible.
	_aura.position = Vector3(0.0, 0.05, 0.0)
	var mat: StandardMaterial3D = _aura.material_override
	# enemy.js pulses it 0.30 +/- 0.13 so it reads as live rather than painted.
	mat.albedo_color.a = 0.42 + 0.16 * sin(_t * 3.1)

## Is this body under the umbrella? A WARDEN does not shield itself — it can
## always be killed, which is what keeps the rule fair.
func shields(other: Enemy) -> bool:
	if other == self:
		return false
	var dx := other.position.x - position.x
	var dz := other.position.z - position.z
	return dx * dx + dz * dz < AURA_RADIUS * AURA_RADIUS
