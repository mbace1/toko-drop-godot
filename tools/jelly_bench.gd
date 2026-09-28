## jelly_bench.gd — Q-052: what a cut soft body COSTS, and whether it holds.
##   godot --headless --path . --script tools/jelly_bench.gd
## A boss-sized dome (GLOBBO 0.55 x the boss 1.5 x the blob shape), cut in two
## and stepped 90 frames at 60 Hz: particles, tets, ms per frame for BOTH
## halves, how much volume the solver kept, and whether it stayed on the floor.
extends SceneTree

func _init() -> void:
	var r := 0.55 * 1.05 * 1.5   # the boss GLOBBO's visual dome scale, x/z
	var h := 0.55 * 0.82 * 1.5   # and y
	for cells in [4, 5, 6, 8]:
		var jb := JellyBody.dome(r, h, cells)
		var v0 := jb.volume()
		var parts := jb.cut(Vector3.ZERO, Vector3(1, 0, 0))
		var halves: Array = parts.filter(func(q): return q != null)
		var n_p := 0
		var n_t := 0
		for q in halves:
			n_p += q.x.size()
			n_t += q.tets.size() / 4
		halves[0].kick(Vector3(1.6, 1.2, 0))
		if halves.size() > 1:
			halves[1].kick(Vector3(-1.6, 1.2, 0))
		var t0 := Time.get_ticks_usec()
		for f in 90:
			for q in halves:
				q.step(1.0 / 60.0)
				q.redraw()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 90.0
		var v1 := 0.0
		var miny := 1e9
		var finite := true
		for q in halves:
			v1 += q.volume()
			for pt in q.x:
				miny = minf(miny, pt.y)
				if not (is_finite(pt.x) and is_finite(pt.y) and is_finite(pt.z)):
					finite = false
		var gap: float = halves[0].x[0].x - halves[1].x[0].x if halves.size() > 1 else 0.0
		print("cells %d: %d particles, %d tets, %d halves — %.2f ms/frame — volume kept %.1f%% — min y %.3f — finite %s" % [cells, n_p, n_t, halves.size(), ms, 100.0 * v1 / v0, miny, finite])
		for q in halves:
			q.free()
		jb.free()
	quit()
