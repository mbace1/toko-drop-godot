## arena_check.gd — Q-031's gate: the rectangle survives being reimplemented.
##
## A port of upstream's `scripts/arena-check.mjs`, check for check. Every
## check compares an Arena method against the LITERAL expression the call
## site inlines, at the shipped arena sizes, and demands exact equality — not
## a tolerance. A tolerance here would hide precisely the drift that makes a
## seeded wave schedule diverge. Everything is compared in 64-bit: the module
## returns `Arena.XZ`, not Vector2, precisely so this can be exact. It also pins the two determinism rules from
## arena.gd's header.
##
## Bare SceneTree, no GPU. Run on every edit to scripts/arena.gd:
##   godot --headless --script tests/arena_check.gd
extends SceneTree

var _checks := 0
var _fails := 0

func _eq(name: String, got, want) -> void:
	_checks += 1
	var same: bool
	if got is float and want is float:
		# Exact, like Object.is — except we do not distinguish -0.0 from 0.0,
		# which GDScript's == already treats as equal and nothing here
		# depends on.
		same = (got == want) or (is_nan(got) and is_nan(want))
	else:
		same = got == want
	if not same:
		_fails += 1
		printerr("FAIL %s\n    got  %s\n    want %s" % [name, str(got), str(want)])

func _ok(name: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL %s" % name)

func _init() -> void:
	# The three shipped presets, plus a scrolling-arena scale (arenaScale 1.6).
	var sizes := [[11.0, 18.0], [19.0, 11.0], [15.0, 11.0], [11.0 * 1.6, 18.0 * 1.6], [6.0, 6.0], [11.0, 7.0]]

	for hxz in sizes:
		var hx: float = hxz[0]
		var hz: float = hxz[1]
		var a := Arena.new(Arena.rect_shape(hx, hz))
		var tag := "%sx%s" % [hx, hz]

		_eq(tag + " aabb halfX", a.half_x, hx)
		_eq(tag + " aabb halfZ", a.half_z, hz)

		# ── sdf sign convention ──────────────────────────────────────────
		_ok(tag + " sdf centre inside", a.sdf(0.0, 0.0) < 0.0)
		_eq(tag + " sdf on +x wall", a.sdf(hx, 0.0), 0.0)
		_eq(tag + " sdf on +z wall", a.sdf(0.0, hz), 0.0)
		_ok(tag + " sdf outside", a.sdf(hx + 3.0, 0.0) > 0.0)

		# ── clamp == max(-h, min(h, v)), per axis, radius and all ────────
		for r in [0.0, 0.5, 0.6, 1.2, 2.4, hx + 4.0]:   # last is degenerate h < 0
			for x in [-99.0, -hx, -3.3, 0.0, 0.001, 7.77, hx, 99.0]:
				for z in [-99.0, -hz, -1.1, 0.0, 4.25, hz, 99.0]:
					var p := a.clamp_pt(x, z, r)
					var bx: float = hx - r
					var bz: float = hz - r
					_eq("%s clamp r=%s x" % [tag, r], p.x, maxf(-bx, minf(bx, x)))
					_eq("%s clamp r=%s z" % [tag, r], p.z, maxf(-bz, minf(bz, z)))

		# ── ring_point == cos(a)*halfX*k, sin(a)*halfZ*k (the spawn ring) ─
		# An inscribed ELLIPSE, not the box boundary. Deliberate, load-bearing.
		for k in [0.85, 0.95, 0.99, 1.0]:
			for i in 64:
				var ang := (float(i) / 64.0) * TAU
				var p := a.ring_point(ang, k)
				_eq("%s ringPoint k=%s x" % [tag, k], p.x, cos(ang) * hx * k)
				_eq("%s ringPoint k=%s z" % [tag, k], p.z, sin(ang) * hz * k)

		# ── inset_point == cos(a)*(halfX-m), sin(a)*(halfZ-m) ────────────
		for m in [1.0, 1.5, 2.0, 4.0]:
			for i in 16:
				var ang := (float(i) / 16.0) * TAU
				var p := a.inset_point(ang, m)
				_eq("%s insetPoint m=%s x" % [tag, m], p.x, cos(ang) * (hx - m))
				_eq("%s insetPoint m=%s z" % [tag, m], p.z, sin(ang) * (hz - m))

		# ── ray_edge == TORO's slab test, INF on a zero component ─────────
		for r in [0.0, 1.2, 2.2]:
			for d in [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0], [0.6, 0.8], [-0.6, -0.8], [0.8, -0.6]]:
				for pt in [[0.0, 0.0], [3.0, -4.0], [-hx + 1.0, hz - 1.0]]:
					var dx: float = d[0]
					var dz: float = d[1]
					var px: float = pt[0]
					var pz: float = pt[1]
					var bx: float = hx - r
					var bz: float = hz - r
					var tx := INF
					if dx > 0.0:
						tx = (bx - px) / dx
					elif dx < 0.0:
						tx = (-bx - px) / dx
					var tz := INF
					if dz > 0.0:
						tz = (bz - pz) / dz
					elif dz < 0.0:
						tz = (-bz - pz) / dz
					_eq("%s rayEdge r=%s d=%s,%s p=%s,%s" % [tag, r, dx, dz, px, pz],
						a.ray_edge(px, pz, dx, dz, r), minf(tx, tz))

		# ── contains(x, z, -slack) == the old "escaped the arena" test ────
		for slack in [5.0]:
			for pt in [[0.0, 0.0], [hx + 4.9, 0.0], [hx + 5.1, 0.0], [0.0, hz + 5.1], [hx + 6.0, hz + 6.0]]:
				var x: float = pt[0]
				var z: float = pt[1]
				var old_escaped: bool = absf(x) > hx + slack or absf(z) > hz + slack
				_eq("%s escape %s,%s" % [tag, x, z], not a.contains(x, z, -slack), old_escaped)

		# ── random_point: two draws, x then z, exactly the old expression ─
		for margin in [0.0, 2.0, 3.0]:
			var seq := [0.125, 0.875, 0.5, 0.0, 1.0, 0.333]
			var counter := [0]
			var rng := func() -> float:
				var v: float = seq[counter[0] % seq.size()]
				counter[0] += 1
				return v
			var p := a.random_point(rng, margin)
			_eq("%s randomPoint draw count m=%s" % [tag, margin], counter[0], 2)
			_eq("%s randomPoint x m=%s" % [tag, margin], p.x, (seq[0] * 2.0 - 1.0) * (hx - margin))
			_eq("%s randomPoint z m=%s" % [tag, margin], p.z, (seq[1] * 2.0 - 1.0) * (hz - margin))

		# update() is a no-op for a rectangle and must not move the box.
		a.update(12.5)
		_eq(tag + " update leaves halfX", a.half_x, hx)
		_eq(tag + " update leaves halfZ", a.half_z, hz)

	# ── The shapes nothing wires up yet, but a level file will ──────────────
	# Not "nothing changes" checks — these prove the algebra is right, so P1
	# is a level file rather than a debugging session.
	var c := Arena.new(Arena.circle_shape(0.0, 0.0, 7.0))
	_eq("circle sdf centre", c.sdf(0.0, 0.0), -7.0)
	_eq("circle sdf edge", c.sdf(7.0, 0.0), 0.0)
	_eq("circle aabb", c.half_x, 7.0)

	# The owner's worked example: three overlapping circles, their COMMON area.
	var tri := Arena.new(Arena.intersect_shape([
		Arena.circle_shape(-3.0, 0.0, 8.0), Arena.circle_shape(3.0, 0.0, 8.0), Arena.circle_shape(0.0, 3.0, 8.0)]))
	_eq("intersect kind", tri.shape.kind, Arena.KIND_INTERSECT)
	_ok("intersect: centre is inside", tri.sdf(0.0, 0.0) < 0.0)
	_ok("intersect: x=9 is outside (union would say inside)", tri.sdf(9.0, 0.0) > 0.0)
	var uni := Arena.new(Arena.union_shape([
		Arena.circle_shape(-3.0, 0.0, 8.0), Arena.circle_shape(3.0, 0.0, 8.0), Arena.circle_shape(0.0, 3.0, 8.0)]))
	_ok("union: x=9 is inside", uni.sdf(9.0, 0.0) < 0.0)

	# clamp with no closed form falls back to the gradient march — the owner's
	# PUSH rule — and must land a point that actually fits.
	var q := tri.clamp_pt(40.0, 40.0, 0.0)
	_ok("intersect clamp lands inside (push along the gradient)", tri.sdf(q.x, q.z) <= 1e-2)
	q = tri.clamp_pt(0.0, 0.0, 0.0)
	_eq("intersect clamp leaves an inside point alone x", q.x, 0.0)
	_eq("intersect clamp leaves an inside point alone z", q.z, 0.0)

	# ray_edge by sphere-trace: two circles at ±3 radius 8 meet the +x axis at 5.
	var lens := Arena.new(Arena.intersect_shape([Arena.circle_shape(-3.0, 0.0, 8.0), Arena.circle_shape(3.0, 0.0, 8.0)]))
	_ok("lens rayEdge ~ 5", absf(lens.ray_edge(0.0, 0.0, 1.0, 0.0, 0.0) - 5.0) < 0.01)

	# Determinism rule 1 holds for non-rectangles too: still exactly two draws.
	var n := [0]
	var rng2 := func() -> float:
		n[0] += 1
		return 0.9
	q = tri.random_point(rng2, 1.0)
	_eq("non-rect randomPoint draw count", n[0], 2)
	_ok("non-rect randomPoint lands inside", tri.sdf(q.x, q.z) <= 1e-2)

	# ring_point on a general shape is a ray-march, and must land on the edge.
	q = lens.ring_point(0.0, 1.0)
	_ok("lens ringPoint ~ edge", absf(q.x - 5.0) < 0.01 and absf(q.z) < 1e-9)

	print("%d/%d arena checks passed" % [_checks - _fails, _checks])
	if _fails > 0:
		printerr("ARENA: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("ARENA: PASS - the rectangle survives being an SDF")
		quit(0)
