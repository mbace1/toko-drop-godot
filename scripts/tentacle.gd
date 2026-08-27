## tentacle.gd — a verlet chain of gel that hangs off a body and drags.
##
## `PORT_BRIEF.md` §2b ("Tentacles — verlet chain dragging on the floor") calls
## this THE target behaviour and the thing the browser build cannot do well:
## when the blob stops the tentacles pile and drag, when it moves fast they
## stretch and snap back, and gravity plus verlet integration gives both for
## free rather than needing an animation.
##
## Two deliberate divergences from the brief's own code sketch, both for
## reasons this repo already learned the hard way:
##
## 1. **Driven by an explicit `update(delta)`, never `_physics_process`.** The
##    brief's snippet uses `_physics_process`. `CLAUDE.md`'s architecture rule
##    is that enemies are stepped by `WaveDirector.update()` calling their own
##    `update()`, and that is what makes pause free — `main.gd` simply stops
##    calling it and nothing moves. A `_physics_process` here would keep the
##    tentacles swinging on the pause screen.
## 2. **Drawn as one `MultiMeshInstance3D` of tapered beads**, not a skinned
##    `Skeleton3D` or a rebuilt tube mesh (the brief offers both). One draw
##    call for the whole limb, no per-frame geometry allocation, and a chain of
##    gel beads suits a body that is already made of gel — `debris_pool.gd`
##    renders the same way for the same reason.
class_name Tentacle
extends Node3D

const SEGMENTS := 8
const DAMPING := 0.86
const GRAVITY := 9.8
const ITER := 3              # constraint relaxation passes
## Beads rest ON the floor rather than sinking into it. Their own radius, so a
## bead sits tangent to the plane instead of half-buried.
const FLOOR_Y := 0.0

## World-space verlet state. Kept in WORLD space, not local: the root is pinned
## to a point on a body that is itself moving, and the whole point of the
## effect is that the rest of the chain does NOT follow that movement rigidly.
var pos := PackedVector3Array()
var prev := PackedVector3Array()

var rest_len := 0.35
var bead_r := 0.16
var _mm: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _built := false
var _seeded := false

## `offset` is where on the body this limb grows from, in the body's own local
## space; `tent_radius` is the bead radius at the root (they taper to a third
## of it at the tip); `col` is the body's own gel colour.
func build(offset: Vector3, tent_radius: float, seg_len: float, col: Color) -> void:
	if _built:
		return
	_built = true
	position = offset
	bead_r = tent_radius
	rest_len = seg_len

	pos.resize(SEGMENTS)
	prev.resize(SEGMENTS)
	# NOT seeded here. `build()` is called from `apply_boss()`, which a caller
	# is free to invoke before the body has been added to the tree — and
	# `global_position` is only meaningful once it is (CLAUDE.md's rule about
	# never depending on _ready() timing applies just as much to reading a
	# global transform). The chain seeds itself on its first update instead,
	# where the body is definitely placed.

	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 8
	m.rings = 4

	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.12
	_mat.metallic = 0.0
	# Lit, and translucent the way the bodies are — an unlit chain of flat
	# colour reads as beads on a string rather than as gel hanging off a body.
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = SEGMENTS
	mm.visible_instance_count = SEGMENTS
	mm.mesh = m

	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.material_override = _mat
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The bead positions are already world-space, so this must NOT inherit the
	# body's transform — otherwise the limb is rotated and translated twice and
	# swings off into the arena.
	_mm.top_level = true
	add_child(_mm)

	for i in SEGMENTS:
		var k := float(i) / float(SEGMENTS - 1)
		mm.set_instance_color(i, Color(col.r, col.g, col.b, 1.0).lerp(col.darkened(0.25), k))

## Steps the chain. `delta` is the game's own, so a paused game freezes it.
func update(delta: float) -> void:
	if not _built or delta <= 0.0 or not is_inside_tree():
		return
	var root := global_position

	# First real frame: hang the chain straight down from wherever the body
	# actually is, so it starts as a limb rather than as eight coincident
	# points that explode outward as the constraints solve.
	if not _seeded:
		_seeded = true
		for i in SEGMENTS:
			var p := root + Vector3(0.0, -float(i) * rest_len, 0.0)
			pos[i] = p
			prev[i] = p
		_redraw()
		return

	# Integrate. i = 0 is pinned to the root, so it is skipped.
	var g := GRAVITY * delta * delta
	for i in range(1, SEGMENTS):
		var v: Vector3 = (pos[i] - prev[i]) * DAMPING
		prev[i] = pos[i]
		pos[i] = pos[i] + v
		pos[i].y -= g
	pos[0] = root

	# Relax the distance constraints, then put anything below the floor back on
	# it. Doing the floor clamp INSIDE the iteration (rather than once at the
	# end) is what makes a limb pile up and drag instead of sliding through.
	for _it in ITER:
		for i in range(SEGMENTS - 1):
			var a: Vector3 = pos[i]
			var b: Vector3 = pos[i + 1]
			var d := b - a
			var dist := d.length()
			if dist < 0.0001:
				continue
			var err := dist - rest_len
			var dir := d / dist
			if i > 0:
				pos[i] = pos[i] + dir * err * 0.5
			pos[i + 1] = pos[i + 1] - dir * err * 0.5
		pos[0] = root
		for i in SEGMENTS:
			var floor_y: float = FLOOR_Y + bead_r * _taper(i)
			if pos[i].y < floor_y:
				pos[i].y = floor_y

	_redraw()

func _redraw() -> void:
	var mm := _mm.multimesh
	for i in SEGMENTS:
		var s: float = bead_r * _taper(i)
		mm.set_instance_transform(i,
			Transform3D(Basis().scaled(Vector3(s, s, s)), pos[i]))

## Beads shrink along the chain, so the limb reads as a tentacle rather than as
## a uniform string of pearls.
func _taper(i: int) -> float:
	var k := float(i) / float(SEGMENTS - 1)
	# Only down to half. A sharper taper (the first pass went to 0.34) shrinks
	# the tip beads well below the segment spacing, and the limb stops being a
	# limb and becomes a dotted line — clearly visible in a capture of a real
	# boss, and invisible in every assertion about the chain.
	return lerpf(1.0, 0.5, k)

## Used when a body dies: the limbs should stop being stepped immediately
## rather than hanging in the arena for a frame while the corpse is cleaned up.
func detach() -> void:
	_built = false
	if is_instance_valid(_mm):
		_mm.visible = false
