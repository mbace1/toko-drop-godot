## arena.gd — the playable region, as a signed-distance field. Q-031.
##
## A port of the browser's `toko-drop/js/arena.js` (v236, P0 of upstream's
## LEVEL_EDITOR_DESIGN.md §7). Read that file's header first; this one keeps
## its contract and its two oddities on purpose:
##
##   * `clamp` reproduces `Math.max(-h, Math.min(h, v))` AS WRITTEN — the
##     nested max/min, in that order — including what it does when h < 0.
##   * `ring_point` is `cos(a)·halfX·k, sin(a)·halfZ·k`: on a box that is an
##     inscribed ELLIPSE, not the boundary. It is what the spawn ring has
##     always been, in both builds. Being right and being identical are
##     different goals, and this file's job is the second.
##
## Two determinism rules, because seeded wave schedules are gated exactly:
##   1. `random_point` draws from `rng` EXACTLY twice, x then z, for every
##      shape. Rejection sampling is banned — a variable draw count would
##      desynchronise every seeded schedule the moment a level used a
##      non-rectangular shape.
##   2. Nothing here reads a clock or a global random source. `update(t)`
##      takes its time as an argument.
##
## Owner decision 2026-09-04: a body left outside a MOVING shape is PUSHED
## along the SDF gradient. That is `clamp()` on a shape with no closed form —
## `_march_in` below — so the rule needs no new code, only a moving shape to
## apply it to (upstream P3, not started anywhere).
##
## Pure: no nodes, no scene, no rendering. `tests/arena_check.gd` runs it in a
## bare SceneTree with no GPU, the way `scripts/arena-check.mjs` runs the
## original in bare node.
class_name Arena
extends RefCounted

const KIND_RECT := "rect"
const KIND_CIRCLE := "circle"
const KIND_UNION := "union"
const KIND_INTERSECT := "intersect"

## A point on the floor, in DOUBLES. GDScript `float` is 64-bit; Vector2's
## components are 32-bit, and returning one rounded every result — the gate
## caught -3.3 coming back as -3.29999995231628. Positions only round when a
## caller stores them into a Vector3, which is what the game does today, so
## nothing changes; but half_x/half_z feed further arithmetic and MUST stay
## double. Methods take an optional `out` to write into, as upstream does,
## so a per-frame per-body call need not allocate.
class XZ:
	var x := 0.0
	var z := 0.0
	func _init(x_ := 0.0, z_ := 0.0) -> void:
		x = x_
		z = z_
	func set_xz(x_: float, z_: float) -> XZ:
		x = x_
		z = z_
		return self


# ── Shapes ──────────────────────────────────────────────────────────────────
# A shape is `kind`, `sdf(x, z)` and `aabb()`, and MAY carry closed-form
# clamp / ring_point / inset_point / ray_edge (`closed_form = true`). sdf is
# signed distance in world units: < 0 inside, 0 on the edge, > 0 outside —
# the same sign convention as the gel dome's SDF in gel_geo.gd.

class Shape:
	var kind := ""
	var closed_form := false
	func sdf(_x: float, _z: float) -> float:
		return 0.0
	## The bounding box as XZ(halfX, halfZ).
	func aabb() -> XZ:
		return XZ.new()
	func clamp_pt(_x: float, _z: float, _r: float, out: XZ) -> XZ:
		return out
	func ring_point(_angle: float, _k: float, out: XZ) -> XZ:
		return out
	func inset_point(_angle: float, _inset: float, out: XZ) -> XZ:
		return out
	func ray_edge(_x: float, _z: float, _dx: float, _dz: float, _r: float) -> float:
		return 0.0
	## Moving shapes advance here; a static shape ignores it.
	func update(_t: float) -> void:
		pass


## The current arena, and the only shape wired up (same as upstream P0).
class RectShape extends Shape:
	var half_x: float
	var half_z: float

	func _init(hx: float, hz: float) -> void:
		kind = KIND_RECT
		closed_form = true
		half_x = hx
		half_z = hz

	func sdf(x: float, z: float) -> float:
		return maxf(absf(x) - half_x, absf(z) - half_z)

	func aabb() -> XZ:
		return XZ.new(half_x, half_z)

	## Exactly the expression the containment sites inline, nested max/min in
	## this order. NOT clampf(): for the degenerate h < 0 case the two differ,
	## and this is the one both builds have always run.
	func clamp_pt(x: float, z: float, r: float, out: XZ) -> XZ:
		var hx := half_x - r
		var hz := half_z - r
		return out.set_xz(maxf(-hx, minf(hx, x)), maxf(-hz, minf(hz, z)))

	## The spawn ring: an ellipse inscribed in the box, touching it at the four
	## axis points. Not the boundary — see the header.
	func ring_point(angle: float, k: float, out: XZ) -> XZ:
		return out.set_xz(cos(angle) * half_x * k, sin(angle) * half_z * k)

	## Pull in by a fixed number of world units rather than by a factor. On a
	## box that is a different ellipse.
	func inset_point(angle: float, inset: float, out: XZ) -> XZ:
		return out.set_xz(cos(angle) * (half_x - inset), sin(angle) * (half_z - inset))

	## Slab test — the exact expression TORO's dash telegraph inlines.
	func ray_edge(x: float, z: float, dx: float, dz: float, r: float) -> float:
		var bx := half_x - r
		var bz := half_z - r
		var tx := INF
		if dx > 0.0:
			tx = (bx - x) / dx
		elif dx < 0.0:
			tx = (-bx - x) / dx
		var tz := INF
		if dz > 0.0:
			tz = (bz - z) / dz
		elif dz < 0.0:
			tz = (-bz - z) / dz
		return minf(tx, tz)


## Not wired to anything yet. Here so a level file is a level file, not a
## module (upstream P1).
class CircleShape extends Shape:
	var cx: float
	var cz: float
	var r: float

	func _init(cx_: float, cz_: float, r_: float) -> void:
		kind = KIND_CIRCLE
		cx = cx_
		cz = cz_
		r = r_

	func sdf(x: float, z: float) -> float:
		# hypot in doubles — Vector2.length() would go through 32-bit.
		return sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz)) - r

	func aabb() -> XZ:
		return XZ.new(absf(cx) + r, absf(cz) + r)


## union = min(d…), intersect = max(d…). The owner's worked example — "three
## overlapping circles create a moving common area" — is intersect(circle,
## circle, circle) with animated centres. That is the whole of shape algebra.
class CombineShape extends Shape:
	var parts: Array = []

	func _init(kind_: String, parts_: Array) -> void:
		kind = kind_
		parts = parts_

	func sdf(x: float, z: float) -> float:
		var d: float = parts[0].sdf(x, z)
		for i in range(1, parts.size()):
			var di: float = parts[i].sdf(x, z)
			d = minf(d, di) if kind == KIND_UNION else maxf(d, di)
		return d

	## Union grows to hold every part; intersection can only shrink, but a
	## conservative (union) box is still correct for camera fit and UV, and is
	## the only one computable without sampling. Deliberately loose.
	func aabb() -> XZ:
		var hx := 0.0
		var hz := 0.0
		for p in parts:
			var b: XZ = p.aabb()
			hx = maxf(hx, b.x)
			hz = maxf(hz, b.z)
		return XZ.new(hx, hz)

	func update(t: float) -> void:
		for p in parts:
			p.update(t)


static func rect_shape(half_x: float, half_z: float) -> RectShape:
	return RectShape.new(half_x, half_z)

static func circle_shape(cx: float, cz: float, r: float) -> CircleShape:
	return CircleShape.new(cx, cz, r)

static func union_shape(parts: Array) -> CombineShape:
	return CombineShape.new(KIND_UNION, parts)

static func intersect_shape(parts: Array) -> CombineShape:
	return CombineShape.new(KIND_INTERSECT, parts)

# ── Arena ───────────────────────────────────────────────────────────────────

var shape: Shape
## The region's bounding box. "How BIG is the room" stays a fair question for
## a shape of any kind (camera fit, floor plane, set dressing); "where is the
## boundary" is what the methods below answer. Upstream §8: splitting those
## two is what made P0 a day instead of a fortnight.
var half_x := 0.0
var half_z := 0.0


func _init(s: Shape = null) -> void:
	if s != null:
		set_shape(s)


func set_shape(s: Shape) -> void:
	shape = s
	var b := s.aabb()
	half_x = b.x
	half_z = b.z


## Convenience for the one shape in use, so a resize on an orientation flip
## does not have to build a shape by hand.
func set_rect(hx: float, hz: float) -> void:
	set_shape(RectShape.new(hx, hz))


func sdf(x: float, z: float) -> float:
	return shape.sdf(x, z)


## A body of radius r fits entirely inside when its centre is at least r in.
func contains(x: float, z: float, r := 0.0) -> bool:
	return shape.sdf(x, z) + r <= 0.0


## Nearest point that holds a body of radius r. Writes into `out` if given.
func clamp_pt(x: float, z: float, r := 0.0, out: XZ = null) -> XZ:
	if out == null:
		out = XZ.new()
	if shape.closed_form:
		return shape.clamp_pt(x, z, r, out)
	return _march_in(x, z, r, out)


## Generic fallback for shapes with no closed-form clamp: walk down the SDF
## gradient until the body fits. Finite-difference normal, a few FIXED steps —
## fixed so cost is predictable and the result is deterministic. This IS the
## owner's "push along the gradient" rule for moving shapes.
func _march_in(x: float, z: float, r: float, out: XZ) -> XZ:
	const EPS := 1e-3
	for i in 8:
		var d := shape.sdf(x, z) + r
		if d <= 0.0:
			break
		var gx := shape.sdf(x + EPS, z) - shape.sdf(x - EPS, z)
		var gz := shape.sdf(x, z + EPS) - shape.sdf(x, z - EPS)
		var len := sqrt(gx * gx + gz * gz)
		if len == 0.0:
			len = 1.0
		x -= (gx / len) * d
		z -= (gz / len) * d
	return out.set_xz(x, z)


## The spawn ring: where an enemy enters from. `k` is the old `edge` factor.
func ring_point(angle: float, k := 1.0, out: XZ = null) -> XZ:
	if out == null:
		out = XZ.new()
	if shape.closed_form:
		return shape.ring_point(angle, k, out)
	# General shapes: bisect along the ray to find where the region ends, then
	# scale by k the way the box's inscribed ellipse does. Fixed step count.
	var dx := cos(angle)
	var dz := sin(angle)
	var reach := sqrt(half_x * half_x + half_z * half_z)
	var lo := 0.0
	var hi := reach
	for i in 24:
		var mid := (lo + hi) * 0.5
		if shape.sdf(dx * mid, dz * mid) < 0.0:
			lo = mid
		else:
			hi = mid
	return out.set_xz(dx * lo * k, dz * lo * k)


## Same ray, pulled in by a fixed distance instead of scaled by a factor.
func inset_point(angle: float, inset: float, out: XZ = null) -> XZ:
	if out == null:
		out = XZ.new()
	if shape.closed_form:
		return shape.inset_point(angle, inset, out)
	ring_point(angle, 1.0, out)
	var d := sqrt(out.x * out.x + out.z * out.z)
	var k := (d - inset) / d if d > inset else 0.0
	return out.set_xz(out.x * k, out.z * k)


## How far a body of radius r can travel from (x, z) along the unit direction
## (dx, dz) before it leaves the region. TORO's dash telegraph is drawn from
## this, so it has to be the real distance, not an estimate.
func ray_edge(x: float, z: float, dx: float, dz: float, r := 0.0) -> float:
	if shape.closed_form:
		return shape.ray_edge(x, z, dx, dz, r)
	# General shapes: sphere-trace. Steps are bounded and the step size comes
	# from the SDF itself, so a concave region cannot be stepped over.
	var far := sqrt(half_x * half_x + half_z * half_z) * 2.0
	var t := 0.0
	var i := 0
	while i < 48 and t < far:
		var d := -(shape.sdf(x + dx * t, z + dz * t) + r)   # distance to the wall
		if d <= 1e-3:
			return t
		t += maxf(d, 1e-3)
		i += 1
	return minf(t, far)


## A point inside, `margin` world units clear of the boundary. `rng` is a
## Callable returning a float in [0, 1) — pass `some_rng.randf`. Consumes
## EXACTLY two draws, x then z, for every shape — see the header.
func random_point(rng: Callable, margin := 0.0, out: XZ = null) -> XZ:
	if out == null:
		out = XZ.new()
	var x: float = (rng.call() * 2.0 - 1.0) * (half_x - margin)
	var z: float = (rng.call() * 2.0 - 1.0) * (half_z - margin)
	if shape.kind == KIND_RECT:
		return out.set_xz(x, z)
	# Non-rectangular: pull the AABB sample inside rather than redrawing.
	return clamp_pt(x, z, margin, out)


## Moving shapes advance here. The rectangle does not move; upstream P3 is
## where this stops being a no-op.
func update(t: float) -> void:
	shape.update(t)
	set_shape(shape)
