## slug.gd
##
## THE SLUG (Q-042) — upstream v251, with v253's limits. A chain of gel domes,
## head first, each pulled to a fixed distance behind the one ahead (no
## springs: a slug must not wobble like a rope). Rebuilt from points on every
## change, so a split or a shortened chain is the same code path as a fresh
## one — enemy.js `_buildChain` / `_placeChain` / `_slugHit`.
##
## Stats from enemy.js's CFG: color 0x5fcc14, radius 0.46, speed 2.2, hp 11
## (hp IS the segment count). TUNING.arc.slug: 11 segments 0.50 apart, head
## radius 0.46 tapering to 0.18, and chains shorter than 4 do not split.
##
## THE RULE (owner): hit an END and the slug SHORTENS; hit the MIDDLE and it
## SPLITS — the back half is reversed, so its old rear is now a head pointed
## at you. Spraying makes two problems out of one; the clean kill is
## positional. A body born from a split never splits again (v253: one run had
## 22 splits and 43 bodies on the floor).
##
## Not ported: upstream's dash-EATS rule (`_slugCut`) belongs to CLOSE COMBAT,
## which this build does not have.
class_name Slug
extends ArcMover

const SEGMENTS := 11
const SPACING := 0.50
const HEAD_R := 0.46
const TAIL_R := 0.18
const MIN_SPLIT := 4

## [{mesh, r, x, z}] — head first; chain[0].mesh is `mesh`
var chain: Array = []
## Set by a middle hit: the back half, reversed. WaveDirector spawns the second
## animal from these next frame, as main.js does, and clears it.
var split_pts: Array = []
var no_split := false
var _hit_seg := -1
var _eye: MeshInstance3D

func init() -> void:
	setup(Color(0x5f / 255.0, 0xcc / 255.0, 0x14 / 255.0), HEAD_R, 2.2, SEGMENTS, false)
	max_hp = SEGMENTS
	_arc_init()
	var pts: Array = []
	for k in SEGMENTS:
		pts.append(Vector2(position.x - cos(heading) * k * SPACING, position.z - sin(heading) * k * SPACING))
	build_chain(pts)

## enemy.js `_buildChain(pts)`: the body is exactly these points, head first.
func build_chain(pts: Array) -> void:
	for g in chain:
		if g["mesh"] != mesh:
			(g["mesh"] as MeshInstance3D).queue_free()
	if _eye != null:
		_eye.queue_free()
	var n := pts.size()
	position.x = (pts[0] as Vector2).x
	position.z = (pts[0] as Vector2).y
	chain = []
	for i in n:
		var t := float(i) / float(n - 1) if n > 1 else 0.0
		var r := HEAD_R + (TAIL_R - HEAD_R) * t   # fat head, tapering tail
		var m: MeshInstance3D
		if i == 0:
			m = mesh
		else:
			m = MeshInstance3D.new()
			m.mesh = GelGeo.dome()
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # v252: the head casts, the tail does not
			m.scale = base_shape * r
			add_child(m)
		chain.append({ "mesh": m, "r": r, "x": (pts[i] as Vector2).x, "z": (pts[i] as Vector2).y })
	# the head's eye: the ONE mark that says which end you must attack from —
	# the rule is a coin flip if you cannot tell a head from a tail
	_eye = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = HEAD_R * 0.3
	sm.height = HEAD_R * 0.6
	_eye.mesh = sm
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color.WHITE
	_eye.material_override = em
	_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_eye)
	hp = n
	_place_chain()

## enemy.js `_placeChain()`: each segment is pulled to SPACING behind the one
## ahead of it, along the line it already lies on.
func _place_chain() -> void:
	chain[0]["x"] = position.x
	chain[0]["z"] = position.z
	for i in range(1, chain.size()):
		var a: Dictionary = chain[i - 1]
		var b: Dictionary = chain[i]
		var dx: float = b["x"] - a["x"]
		var dz: float = b["z"] - a["z"]
		var d := sqrt(dx * dx + dz * dz)
		if d == 0.0:
			d = 1.0
		b["x"] = a["x"] + (dx / d) * SPACING
		b["z"] = a["z"] + (dz / d) * SPACING
		(b["mesh"] as MeshInstance3D).position = Vector3(b["x"] - position.x, 0.0, b["z"] - position.z)
	var hr: float = chain[0]["r"]
	_eye.position = Vector3(cos(heading) * hr * 0.7, hr * 1.05 * 0.82, sin(heading) * hr * 0.7)

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return
	_arc_steer(delta, target.position.x, target.position.z, move_speed())
	_place_chain()

## The body hit-tests itself, segment by segment, and remembers which one took
## the shot — the rule needs to know WHERE it was hit.
func hit_test(x: float, z: float, r: float) -> bool:
	for i in chain.size():
		var g: Dictionary = chain[i]
		var dx: float = g["x"] - x
		var dz: float = g["z"] - z
		var rr: float = g["r"] + r
		if dx * dx + dz * dz < rr * rr:
			_hit_seg = i
			return true
	return false

## Contact asks the same body, but must NOT record a segment: upstream's
## `touches()` is `hitTest()`, so a touch overwrites which segment the next hit
## is charged to — and a hit that arrives without its own test (a gate's edge)
## would then split the animal where the PLAYER brushed it.
func touches(x: float, z: float, r: float) -> bool:
	var keep := _hit_seg
	var t := hit_test(x, z, r)
	_hit_seg = keep
	return t

## enemy.js `_slugHit`. Only a damage-1 hit is a shot; anything bigger is an
## environment kill (a bomb, a boost), which upstream also takes as the whole
## animal ("env kills set hp = 1 first").
func take_hit(dmg: int) -> bool:
	if not alive:
		return false
	_hit_wobble = 0.65
	_sqv -= 0.4
	var n := chain.size()
	var i := _hit_seg
	_hit_seg = -1
	if i < 0 or i >= n:
		i = 0   # no segment recorded (a gate's edge, a hazard): the head, which is where the body is
	if dmg > 1 or hp <= 1 or n <= 1:
		die()
		return true
	var pts: Array = []
	for g in chain:
		pts.append(Vector2(g["x"], g["z"]))
	if i == 0 or i == n - 1 or n < MIN_SPLIT or no_split:
		pts.remove_at(i)
		build_chain(pts)
		return false
	var front := pts.slice(0, i)
	var back := pts.slice(i + 1)
	back.reverse()
	build_chain(front)
	split_pts = back
	return false
