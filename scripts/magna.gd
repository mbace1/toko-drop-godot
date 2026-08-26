## magna.gd
##
## MAGNA — "lumbers to mid range and holds — the pull does the chasing"
## (enemy.js line 1573). It never fires a shot; the whole mechanic is
## dragging the player off their line, so it is a positioning problem layered
## on top of every OTHER enemy on screen rather than a threat of its own.
##
## Stats — CFG (enemy.js line 508):
##   color 0xff9944, radius 0.8, speed 0.9, hp 4, no bullets, no fire clock.
##
## The pull itself (main.js v144, `MAGNA_REACH`=11, `MAGNA_PULL`=1.1/s per
## magna, combined cap 2.0/s) is cross-cutting — it moves the PLAYER, is
## summed across every living Magna, and depends on the player's dash state
## (`player.magna_immune_t`) — so it lives in `main.gd`'s
## `_apply_magna_pull()`, not here, the same reason BAMBU's splashdown does
## not damage the player from inside `bambu.gd`. This script only owns its
## own body: holding range, and the amber tether line whose opacity mirrors
## exactly what main.gd decided about the pull this frame (`pull_active`).
class_name Magna
extends Enemy

const KEEP_RANGE := 8.0
const TETHER_WIDTH := 0.09
const TETHER_HEIGHT := 0.02
const TETHER_ON_BASE := 0.3
const TETHER_ON_WOBBLE := 0.15
const TETHER_LERP := 0.25

## Set by main.gd's `_apply_magna_pull()` every frame — true while this
## magna is actually holding the player (in reach, not immune, not
## point-blank). The tether visual reacts to this, and only this.
var pull_active := false

var _tether: MeshInstance3D
var _tether_mat: StandardMaterial3D
var _tether_opacity := 0.0

func init() -> void:
	setup(Color(1.0, 0.6, 0.267), 0.8, 0.9, 4, false)
	fire_interval = 0.0

	var tm := BoxMesh.new()
	tm.size = Vector3(TETHER_WIDTH, TETHER_HEIGHT, 1.0)
	_tether_mat = StandardMaterial3D.new()
	_tether_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tether_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tether_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tether_mat.albedo_color = Color(1.0, 0.667, 0.333, 0.0)
	_tether = MeshInstance3D.new()
	_tether.mesh = tm
	_tether.material_override = _tether_mat
	# Scene-level, like BAMBU's ring/blob: the tether spans TO the player, so
	# it cannot be a child of this body's own (squashing, wobbling) transform.
	get_parent().add_child(_tether)

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return
	if target != null:
		var dx := target.position.x - position.x
		var dz := target.position.z - position.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist > KEEP_RANGE + 1.0 and dist > 0.001:
			position.x += (dx / dist) * speed * delta
			position.z += (dz / dist) * speed * delta
			_clamp_to_arena()

		var mx := (position.x + target.position.x) * 0.5
		var mz := (position.z + target.position.z) * 0.5
		_tether.position = Vector3(mx, 0.45, mz)
		_tether.rotation.y = atan2(target.position.x - position.x, target.position.z - position.z)
		_tether.scale.z = maxf(0.01, dist)
		var want := (TETHER_ON_BASE + TETHER_ON_WOBBLE * absf(sin(_t * 6.0))) if pull_active else 0.0
		_tether_opacity += (want - _tether_opacity) * TETHER_LERP
		_tether_mat.albedo_color.a = _tether_opacity

## "the tether visual mirrors exactly this state" (enemy.js) — it must not
## keep glowing at a dead magna, or a corpse still reads as an active pull.
func die() -> void:
	super()
	pull_active = false
	if is_instance_valid(_tether):
		_tether.visible = false

func _exit_tree() -> void:
	if is_instance_valid(_tether):
		_tether.queue_free()
