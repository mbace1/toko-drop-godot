## jelly_body.gd
##
## Q-052 — A SOFT BODY YOU CAN CUT. A spike toward the "push on physics" half
## of this build (CLAUDE.md, "Which build leads"): a gel dome built from
## TETRAHEDRA and solved with XPBD — edge lengths and tet volumes as compliant
## constraints, a fixed step split into small substeps, one iteration each
## ("small steps" XPBD). A CUT is a vertical blade plane: every tetrahedron goes
## to the side its centroid lies on, and each side becomes its own body, still
## simulating, with its own copy of the particles along the seam.
##
## What you SEE is not the lattice. A smooth low-poly dome — the gel's own
## silhouette (a unit sphere raised 0.7 and cut at the floor, gel_geo.gd's
## dome) — is pinned to the tetrahedra by barycentric weights, so it stretches,
## wobbles and travels with them; the flesh exposed by a cut is the seam's tet
## faces. Both are drawn in the dying body's own gel material.
##
## PURELY A LOOK. Nothing here is gameplay: the pieces collide with nothing but
## the floor, hurt nothing, score nothing, and draw nothing from the run's
## gameplay stream — the kill, the revenge and the score all happened before a
## body is handed to this. So it is this build's to push under FOLLOW EXACTLY.
##
## Method: Macklin, Müller & Chentanez, "XPBD" (2016); the tetrahedral soft
## body and barycentric skinning of Müller's "Ten Minute Physics".
class_name JellyBody
extends MeshInstance3D

const GRAVITY := -9.8
const SUBSTEPS := 6
const EDGE_COMPLIANCE := 0.02     # larger = softer: the wobble
const VOL_COMPLIANCE := 0.0       # volume is held — jelly is incompressible
const DAMP := 1.6                 # 1/s on velocity: the wobble dies, the fall does not stop
const FRICTION := 0.6             # share of the tangential step undone on floor contact
const DOME_LIFT := 0.7            # gel_geo.gd DOME_CUT: the sphere's centre above the floor
const SEGS := 20                  # render dome: around
const RINGS := 8                  # render dome: up

# ── the unit template, cached per lattice resolution ─────────────────────────
class Template:
	var pts := PackedVector3Array()
	var tets := PackedInt32Array()
	var rv_tet := PackedInt32Array()     # render vertex -> its tet
	var rv_w := PackedVector4Array()     # render vertex -> barycentric weights
	var r_idx := PackedInt32Array()      # render triangles (outward, CCW from outside)
static var _templates := {}

static func _inside(q: Vector3) -> bool:
	return q.y >= -1e-6 and (q - Vector3(0.0, DOME_LIFT, 0.0)).length() <= 1.0 + 1e-6

static func _template(cells: int) -> Template:
	if _templates.has(cells):
		return _templates[cells]
	var T := Template.new()
	var top := 1.0 + DOME_LIFT
	var cell := 2.0 / float(cells)
	var ny := maxi(2, int(ceil(top / cell)))
	var cy := top / float(ny)
	var idx := {}
	var pts := []   # a plain Array: a lambda captures a Packed array by VALUE
	var corner := func(i: int, j: int, k: int) -> int:
		var key := Vector3i(i, j, k)
		if not idx.has(key):
			idx[key] = pts.size()
			pts.append(Vector3(-1.0 + i * cell, j * cy, -1.0 + k * cell))
		return idx[key]
	var perms := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	for i in cells:
		for j in ny:
			for k in cells:
				# keep a cube if any corner is inside: the tets then COVER the dome,
				# so every render vertex has a tet around it
				var any := false
				for c in 8:
					var q := Vector3(-1.0 + (i + (c & 1)) * cell, (j + ((c >> 1) & 1)) * cy, -1.0 + (k + ((c >> 2) & 1)) * cell)
					if _inside(q):
						any = true
						break
				if not any:
					continue
				for pm in perms:
					var c3 := Vector3i(i, j, k)
					T.tets.append(corner.call(c3.x, c3.y, c3.z))
					for a in pm:
						c3[a] += 1
						T.tets.append(corner.call(c3.x, c3.y, c3.z))
	T.pts = PackedVector3Array(pts)
	# the render dome: rings from the floor rim up to the crown, and a floor disc
	var rv := PackedVector3Array()
	var y0 := -DOME_LIFT                      # sphere-local y of the floor
	var a0 := asin(clampf(y0, -1.0, 1.0))     # latitude of the floor rim
	for ring in RINGS + 1:
		var lat := lerpf(a0, PI * 0.5, float(ring) / RINGS)
		for s in SEGS:
			var lon := TAU * float(s) / SEGS
			rv.append(Vector3(cos(lat) * cos(lon), sin(lat) + DOME_LIFT, cos(lat) * sin(lon)))
	var ctr := rv.size()
	rv.append(Vector3(0.0, 0.0, 0.0))         # floor centre
	for ring in RINGS:
		for s in SEGS:
			var a := ring * SEGS + s
			var b := ring * SEGS + (s + 1) % SEGS
			var c := a + SEGS
			var d := b + SEGS
			T.r_idx.append_array([a, c, b, b, c, d])
	for s in SEGS:
		T.r_idx.append_array([ctr, s, (s + 1) % SEGS])
	# orient every triangle OUTWARD (counter-clockwise seen from outside):
	# away from the sphere's centre, and down for the floor disc
	for f in T.r_idx.size() / 3:
		var a := rv[T.r_idx[3 * f]]
		var b := rv[T.r_idx[3 * f + 1]]
		var c := rv[T.r_idx[3 * f + 2]]
		var cen := (a + b + c) / 3.0
		var outward := Vector3.DOWN if cen.y < 1e-4 else cen - Vector3(0.0, DOME_LIFT, 0.0)
		if (b - a).cross(c - a).dot(outward) < 0.0:
			var tmp := T.r_idx[3 * f + 1]
			T.r_idx[3 * f + 1] = T.r_idx[3 * f + 2]
			T.r_idx[3 * f + 2] = tmp
	# pin every render vertex to the tet it is most inside
	T.rv_tet.resize(rv.size())
	T.rv_w.resize(rv.size())
	for i in rv.size():
		var best := -1e9
		for t in T.tets.size() / 4:
			var w := _bary(rv[i], T.pts[T.tets[4 * t]], T.pts[T.tets[4 * t + 1]], T.pts[T.tets[4 * t + 2]], T.pts[T.tets[4 * t + 3]])
			var m := minf(minf(w.x, w.y), minf(w.z, w.w))
			if m > best:
				best = m
				T.rv_tet[i] = t
				T.rv_w[i] = w
	_templates[cells] = T
	return T

static func _bary(q: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Vector4:
	var v0 := _vol(a, b, c, d)
	if absf(v0) < 1e-12:
		return Vector4(-1e9, -1e9, -1e9, -1e9)
	return Vector4(_vol(q, b, c, d) / v0, _vol(a, q, c, d) / v0, _vol(a, b, q, d) / v0, _vol(a, b, c, q) / v0)

func _bary_t(q: Vector3, t: int) -> Vector4:
	return _bary(q, x[tets[4 * t]], x[tets[4 * t + 1]], x[tets[4 * t + 2]], x[tets[4 * t + 3]])

static func _vol(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	return (b - a).cross(c - a).dot(d - a) / 6.0

# ── one body ─────────────────────────────────────────────────────────────────
var x := PackedVector3Array()     # particle positions, body-local
var p := PackedVector3Array()
var v := PackedVector3Array()
var tets := PackedInt32Array()
var rest_vol := PackedFloat32Array()
var edges := PackedInt32Array()
var rest_len := PackedFloat32Array()
var rv_tet := PackedInt32Array()  # render vertices pinned into THIS body's tets
var rv_w := PackedVector4Array()
var r_idx := PackedInt32Array()
var seam := PackedInt32Array()    # the cut's exposed faces, outward
var shape := Vector3.ONE   # the dome's scale: x/z radius, y scale (seam clipping)
var life := 1.3
var age := 0.0
var fade_mat: ShaderMaterial
var _im := ImmediateMesh.new()

## A dome of radius `sx` (x/z) and scale `sy` up — the same scale the body's
## visual dome wears (`radius * base_shape`).
static func dome(sx: float, sy: float, cells: int) -> JellyBody:
	var T := _template(cells)
	var jb := JellyBody.new()
	var pts := PackedVector3Array()
	for q in T.pts:
		pts.append(Vector3(q.x * sx, q.y * sy, q.z * sx))
	jb._build(pts, T.tets, PackedVector3Array())
	jb.shape = Vector3(sx, sy, sx)
	jb.rv_tet = T.rv_tet
	jb.rv_w = T.rv_w
	jb.r_idx = T.r_idx
	return jb

func _build(pts: PackedVector3Array, tl: PackedInt32Array, vel: PackedVector3Array) -> void:
	x = pts.duplicate()
	p = pts.duplicate()
	v = vel.duplicate()
	if v.size() != pts.size():
		v = PackedVector3Array()
		v.resize(pts.size())
	tets = tl
	rest_vol.resize(tl.size() / 4)
	var eset := {}
	for t in tl.size() / 4:
		var a := tl[4 * t]
		var b := tl[4 * t + 1]
		var c := tl[4 * t + 2]
		var d := tl[4 * t + 3]
		rest_vol[t] = _vol(x[a], x[b], x[c], x[d])
		for pr in [[a, b], [a, c], [a, d], [b, c], [b, d], [c, d]]:
			eset[Vector2i(mini(pr[0], pr[1]), maxi(pr[0], pr[1]))] = true
	edges = PackedInt32Array()
	rest_len = PackedFloat32Array()
	for e in eset:
		edges.append(e.x)
		edges.append(e.y)
		rest_len.append(x[e.x].distance_to(x[e.y]))
	mesh = _im

## Summed |volume| of the tets (the lattice's tets are of both handednesses,
## so the signed total is near zero by construction).
func volume() -> float:
	var s := 0.0
	for t in tets.size() / 4:
		s += absf(_vol(x[tets[4 * t]], x[tets[4 * t + 1]], x[tets[4 * t + 2]], x[tets[4 * t + 3]]))
	return s

## One frame: SUBSTEPS × (integrate, edges, volumes, floor, velocities).
func step(dt: float) -> void:
	var h := dt / float(SUBSTEPS)
	var n := x.size()
	var ae := EDGE_COMPLIANCE / (h * h)
	var av := VOL_COMPLIANCE / (h * h)
	var dampk := maxf(0.0, 1.0 - DAMP * h)
	var floor_y := -position.y   # the world floor, in body-local terms
	for _s in SUBSTEPS:
		for i in n:
			var vi := v[i]
			vi.y += GRAVITY * h
			vi *= dampk
			v[i] = vi
			p[i] = x[i]
			x[i] = x[i] + vi * h
		for e in rest_len.size():
			var i0 := edges[2 * e]
			var i1 := edges[2 * e + 1]
			var d := x[i0] - x[i1]
			var l := d.length()
			if l < 1e-9:
				continue
			var g := d * (-(l - rest_len[e]) / (2.0 + ae) / l)
			x[i0] = x[i0] + g
			x[i1] = x[i1] - g
		for t in rest_vol.size():
			var a := tets[4 * t]
			var b := tets[4 * t + 1]
			var c := tets[4 * t + 2]
			var d2 := tets[4 * t + 3]
			var xa := x[a]
			var xb := x[b]
			var xc := x[c]
			var xd := x[d2]
			var ga := (xd - xb).cross(xc - xb)
			var gb := (xc - xa).cross(xd - xa)
			var gc := (xd - xa).cross(xb - xa)
			var gd := (xb - xa).cross(xc - xa)
			var w := ga.length_squared() + gb.length_squared() + gc.length_squared() + gd.length_squared()
			if w < 1e-12:
				continue
			var dl := -((_vol(xa, xb, xc, xd) - rest_vol[t]) * 6.0) / (w + av)
			x[a] = xa + ga * dl
			x[b] = xb + gb * dl
			x[c] = xc + gc * dl
			x[d2] = xd + gd * dl
		for i in n:
			var xi := x[i]
			if xi.y < floor_y:
				var pi := p[i]
				xi.y = floor_y
				xi.x -= (xi.x - pi.x) * FRICTION
				xi.z -= (xi.z - pi.z) * FRICTION
				x[i] = xi
		for i in n:
			v[i] = (x[i] - p[i]) / h

## Cut with a vertical plane through `point` (body-local), normal `nrm`.
## Returns [side where (c - point)·nrm >= 0, the other side]; a side the plane
## missed is null. Render triangles go with the piece that owns all three of
## their vertices' tets; the seam's tet faces become each piece's cut flesh.
func cut(point: Vector3, nrm: Vector3) -> Array:
	var side := PackedInt32Array()
	side.resize(tets.size() / 4)
	for t in side.size():
		var ctr := (x[tets[4 * t]] + x[tets[4 * t + 1]] + x[tets[4 * t + 2]] + x[tets[4 * t + 3]]) * 0.25
		side[t] = 0 if (ctr - point).dot(nrm) >= 0.0 else 1
	# faces shared by two tets of DIFFERENT sides are the seam
	var owner := {}
	var seam_faces := [[], []]
	for t in side.size():
		var a := tets[4 * t]
		var b := tets[4 * t + 1]
		var c := tets[4 * t + 2]
		var d := tets[4 * t + 3]
		for f in [[a, b, c, d], [a, b, d, c], [a, c, d, b], [b, c, d, a]]:
			var s3 := [f[0], f[1], f[2]]
			s3.sort()
			var key := Vector3i(s3[0], s3[1], s3[2])
			if owner.has(key):
				var o: Array = owner[key]
				if side[o[0]] != side[t]:
					seam_faces[side[t]].append(f)
					seam_faces[side[o[0]]].append(o[1])
			else:
				owner[key] = [t, f]
	# FLATTEN THE SEAM: every particle on a seam face moves onto the blade, so
	# the cut is a plane and not the lattice's staircase. Done before the
	# pieces are built, so their rest shapes are the flattened ones — no pop.
	var onplane := {}
	for s in 2:
		for f in seam_faces[s]:
			for k in 3:
				onplane[f[k]] = true
	# ...and no further out than the dome itself: the lattice reaches past the
	# silhouette on purpose (so every skin vertex has a tet round it), and an
	# unclipped cut face showed that overhang as ragged fins round the flesh
	var xs := x.duplicate()
	for q in onplane:
		var pq := xs[q] - nrm * (xs[q] - point).dot(nrm)
		var u := Vector3(pq.x / shape.x, pq.y / shape.y - DOME_LIFT, pq.z / shape.z)
		if u.length() > 1.0:
			u = u.normalized()
			pq = Vector3(u.x * shape.x, (u.y + DOME_LIFT) * shape.y, u.z * shape.z)
			pq -= nrm * (pq - point).dot(nrm)   # back onto the blade
		pq.y = maxf(pq.y, 0.0)
		xs[q] = pq
	# the render surface, where it is NOW, for sorting its triangles by side
	var rp := PackedVector3Array()
	rp.resize(rv_tet.size())
	for i in rp.size():
		rp[i] = _rv_pos(i)
	var out := []
	for s in 2:
		var remap := {}
		var tmap := {}
		var px := PackedVector3Array()
		var pv := PackedVector3Array()
		var nt := PackedInt32Array()
		for t in side.size():
			if side[t] != s:
				continue
			tmap[t] = nt.size() / 4
			for k in 4:
				var q := tets[4 * t + k]
				if not remap.has(q):
					remap[q] = px.size()
					px.append(xs[q])
					pv.append(v[q])
				nt.append(remap[q])
		if nt.is_empty():
			out.append(null)
			continue
		var jb := JellyBody.new()
		jb._build(px, nt, pv)
		jb.shape = shape
		# render: a triangle belongs to the side its centre is on. Every vertex
		# of it is pinned to a tet of THIS piece — its own tet if that came
		# here, is not squashed by the flattening and holds it well, else the
		# nearby tet that holds it best — after moving a vertex that lies
		# across the blade onto it. A squashed tet is never used: barycentric
		# weights against a near-flat tet are enormous, and the skin explodes.
		var ctrs := PackedVector3Array()
		var vol_ok := PackedByteArray()
		var mean_v := 0.0
		for t in jb.tets.size() / 4:
			mean_v += absf(jb.rest_vol[t])
		mean_v /= maxf(1.0, jb.tets.size() / 4)
		for t in jb.tets.size() / 4:
			ctrs.append((jb.x[jb.tets[4 * t]] + jb.x[jb.tets[4 * t + 1]] + jb.x[jb.tets[4 * t + 2]] + jb.x[jb.tets[4 * t + 3]]) * 0.25)
			vol_ok.append(1 if absf(jb.rest_vol[t]) > 0.25 * mean_v else 0)
		var reach := 2.0 * pow(mean_v * 6.0, 1.0 / 3.0)   # about two cells
		var vmap := {}
		for f in r_idx.size() / 3:
			var tri := [r_idx[3 * f], r_idx[3 * f + 1], r_idx[3 * f + 2]]
			var cen: Vector3 = (rp[tri[0]] + rp[tri[1]] + rp[tri[2]]) / 3.0
			if (0 if (cen - point).dot(nrm) >= 0.0 else 1) != s:
				continue
			var ids := []
			for q in tri:
				if not vmap.has(q):
					vmap[q] = jb.rv_tet.size()
					var dq := (rp[q] - point).dot(nrm)
					var across := dq < 0.0 if s == 0 else dq > 0.0
					var at := rp[q] - nrm * dq if across else rp[q]
					var bt := -1
					var bw := Vector4.ZERO
					var best := -1e9
					if not across and tmap.has(rv_tet[q]):
						var t0: int = tmap[rv_tet[q]]
						if vol_ok[t0] == 1:
							var w0 := jb._bary_t(at, t0)
							var m0 := minf(minf(w0.x, w0.y), minf(w0.z, w0.w))
							if m0 > -0.25:
								bt = t0
								bw = w0
					if bt < 0:
						for r_try in [reach, reach * 2.0, 1e9]:
							for t in ctrs.size():
								if vol_ok[t] == 0 or ctrs[t].distance_to(at) > r_try:
									continue
								var w := jb._bary_t(at, t)
								var m := minf(minf(w.x, w.y), minf(w.z, w.w))
								if m > best:
									best = m
									bt = t
									bw = w
							if bt >= 0:
								break
					jb.rv_tet.append(bt)
					jb.rv_w.append(bw)
				ids.append(vmap[q])
			jb.r_idx.append_array(ids)
		for f in seam_faces[s]:
			var fa: int = remap[f[0]]
			var fb: int = remap[f[1]]
			var fc: int = remap[f[2]]
			var fd: Vector3 = x[f[3]]
			var n3 := (x[f[1]] - x[f[0]]).cross(x[f[2]] - x[f[0]])
			# outward = away from the face's own tet
			if n3.dot(fd - x[f[0]]) > 0.0:
				jb.seam.append_array([fa, fc, fb])
			else:
				jb.seam.append_array([fa, fb, fc])
		out.append(jb)
	return out

func kick(impulse: Vector3) -> void:
	for i in v.size():
		v[i] = v[i] + impulse

func _rv_pos(i: int) -> Vector3:
	var t := rv_tet[i]
	var w := rv_w[i]
	return x[tets[4 * t]] * w.x + x[tets[4 * t + 1]] * w.y + x[tets[4 * t + 2]] * w.z + x[tets[4 * t + 3]] * w.w

func redraw() -> void:
	_im.clear_surfaces()
	var rp := PackedVector3Array()
	rp.resize(rv_tet.size())
	for i in rp.size():
		rp[i] = _rv_pos(i)
	var rn := PackedVector3Array()
	rn.resize(rp.size())
	for f in r_idx.size() / 3:
		var a := r_idx[3 * f]
		var b := r_idx[3 * f + 1]
		var c := r_idx[3 * f + 2]
		var fn := (rp[b] - rp[a]).cross(rp[c] - rp[a])
		rn[a] += fn
		rn[b] += fn
		rn[c] += fn
	if r_idx.is_empty() and seam.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fade_mat)
	# Godot's front faces wind CLOCKWISE seen from outside: emit a, c, b
	for f in r_idx.size() / 3:
		for q in [r_idx[3 * f], r_idx[3 * f + 2], r_idx[3 * f + 1]]:
			_im.surface_set_normal(rn[q].normalized())
			_im.surface_add_vertex(rp[q])
	for f in seam.size() / 3:
		var a := seam[3 * f]
		var b := seam[3 * f + 1]
		var c := seam[3 * f + 2]
		var fn := (x[b] - x[a]).cross(x[c] - x[a]).normalized()
		for q in [a, c, b]:
			_im.surface_set_normal(fn)
			_im.surface_add_vertex(x[q])
	_im.surface_end()

## Step, draw, fade; false once it has faded out.
func advance(dt: float) -> bool:
	age += dt
	step(dt)
	redraw()
	if fade_mat != null:
		fade_mat.set_shader_parameter("alpha_amt", clampf(1.0 - (age - life * 0.5) / (life * 0.5), 0.0, 1.0))
	return age < life
