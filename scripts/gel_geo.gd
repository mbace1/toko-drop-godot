## gel_geo.gd — the SDF-built bodies: the gel dome, and the rounded cube.
##
## Closes two silhouette regressions that had gone untracked in this port. Both
## were primitive swaps made early, and neither was recorded as a decision:
##
## 1. **The blob dome.** The browser builds ONE shared `BLOB_GEO` used by all
##    twelve blob types (`enemy.js`): a dense unit sphere shrink-wrapped onto
##    the signed-distance field `smax(length(p) - 1, -y - domeCut, domeRound)`,
##    with normals taken from the SDF gradient. That is the single piece of
##    genuinely custom geometry in the whole browser project, and it is what
##    makes a blob read as a *gel dome sitting on the floor* rather than as a
##    ball. This port had replaced it with a `SphereMesh` squashed by a
##    non-uniform scale, which reproduces the proportions but not the shape:
##    a scaled sphere has no flat, rounded-off underside.
## 2. **The cube corners.** The browser uses `RoundedBoxGeometry(..., 4, 0.18)`
##    — a box with 0.18 rounded edges. This port used a plain `BoxMesh`, so the
##    cube family had hard corners the original never had.
##
## Both are rebuilt here from the browser's own SDF, so the shapes are derived
## rather than eyeballed. The maths — `smin`/`smax`, the 24-step binary search
## between 0.05 and 2.4, the 0.003 gradient epsilon, detail 72 — is its maths.
class_name GelGeo

## `TUNING.blob` in the browser: "geometry: gel dome =
## smax(length(p)-1, -p.y-domeCut, domeRound), origin at floor contact".
const DOME_CUT := 0.7
const DOME_ROUND := 0.22
## The browser's `sdfGeometry(sdf, 72)` — a 72 x round(72*0.66) UV sphere.
const DETAIL := 72
## The cube needs far less: see `rounded_box`.
const BOX_DETAIL := 40
const SEARCH_LO := 0.05
const SEARCH_HI := 2.4
const SEARCH_STEPS := 24
const GRAD_EPS := 0.003

static var _dome: ArrayMesh = null
static var _boxes := {}

## Polynomial smooth-min, and its max. Verbatim from `enemy.js`.
static func smin(a: float, b: float, k: float) -> float:
	var h: float = maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25

static func smax(a: float, b: float, k: float) -> float:
	return -smin(-a, -b, k)

## The blob dome. ONE mesh shared by every blob body, sized per enemy through
## `mesh.scale` — the same arrangement the browser uses, and the reason this is
## cached rather than rebuilt: it is a few thousand vertices of CPU work and
## there is no reason to pay it per enemy, per wave.
##
## The origin is translated to the FLOOR CONTACT point, so a body rests at
## y = 0 and every squash/breathe/drag scale anchors to the ground instead of
## making the body float. Callers must therefore NOT add the old
## `mesh.position.y = radius` offset.
static func dome() -> ArrayMesh:
	if _dome != null:
		return _dome
	var sdf := func(p: Vector3) -> float:
		return smax(p.length() - 1.0, -p.y - DOME_CUT, DOME_ROUND)
	_dome = _sdf_mesh(sdf, Vector3(0.0, DOME_CUT, 0.0))
	return _dome

## The rounded cube. `size` is the full width and `radius` the corner rounding,
## matching `RoundedBoxGeometry(size, size, size, 4, radius)`.
##
## Cached per (size, radius) rather than built from one unit mesh, because the
## browser's rounding is an ABSOLUTE 0.18 against a size that varies with the
## enemy's radius — scaling a single unit cube would make the rounding
## proportional instead, which is a different shape on every body.
static func rounded_box(size: float, radius: float) -> ArrayMesh:
	var key := "%.4f|%.4f" % [size, radius]
	if _boxes.has(key):
		return _boxes[key]
	var b := size * 0.5 - radius
	var sdf := func(p: Vector3) -> float:
		var q := Vector3(absf(p.x) - b, absf(p.y) - b, absf(p.z) - b)
		var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
		var inside: float = minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
		return outside + inside - radius
	# Coarser than the dome on purpose. A UV sphere wrapped onto FLAT faces
	# gives them a radial vertex distribution the browser's RoundedBoxGeometry
	# does not have, and at dome density that reads as a faint crosshatch
	# across each face under a glossy material. The silhouette — which is the
	# whole point of this — is carried by the rounded edges, not by face
	# tessellation, so the faces can afford to be much cheaper.
	var m := _sdf_mesh(sdf, Vector3.ZERO, BOX_DETAIL)
	_boxes[key] = m
	return m

## Shrink-wraps a UV sphere onto `sdf`. Each vertex is pushed along its own
## direction to the field's zero crossing by binary search, and its normal is
## read from the field's gradient — which is what gives the dome an exact
## normal on the rounded underside instead of a sphere's.
static func _sdf_mesh(sdf: Callable, offset: Vector3, detail := DETAIL) -> ArrayMesh:
	var w := detail
	var h := int(round(float(detail) * 0.66))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	for iy in range(h + 1):
		var v := float(iy) / float(h)
		var theta := v * PI
		for ix in range(w + 1):
			var u := float(ix) / float(w)
			var phi := u * TAU
			var dir := Vector3(
				-cos(phi) * sin(theta),
				cos(theta),
				sin(phi) * sin(theta)).normalized()

			var lo := SEARCH_LO
			var hi := SEARCH_HI
			for _s in SEARCH_STEPS:
				var mid := (lo + hi) * 0.5
				if sdf.call(dir * mid) < 0.0:
					lo = mid
				else:
					hi = mid
			var t := (lo + hi) * 0.5
			var p := dir * t

			var e := GRAD_EPS
			var n := Vector3(
				sdf.call(p + Vector3(e, 0, 0)) - sdf.call(p - Vector3(e, 0, 0)),
				sdf.call(p + Vector3(0, e, 0)) - sdf.call(p - Vector3(0, e, 0)),
				sdf.call(p + Vector3(0, 0, e)) - sdf.call(p - Vector3(0, 0, e)))
			if n.length() < 0.000001:
				n = dir
			verts.append(p + offset)
			norms.append(n.normalized())
			uvs.append(Vector2(u, v))

	var row := w + 1
	for iy in range(h):
		for ix in range(w):
			# Winding taken from three.js SphereGeometry verbatim. Its names are
			# a=(iy,ix+1) b=(iy,ix) c=(iy+1,ix) d=(iy+1,ix+1), pushing (a,b,d)
			# and (b,c,d). Getting this wrong does not error — it silently
			# inverts every face, and the dome renders as a hollow ring because
			# you are looking at its inside.
			var tl := iy * row + ix          # three.js `b`
			var tr := tl + 1                 # three.js `a`
			var bl := (iy + 1) * row + ix    # three.js `c`
			var br := bl + 1                 # three.js `d`
			# Skip the degenerate triangle at each pole, as a UV sphere must.
			if iy != 0:
				idx.append_array([tr, tl, br])
			if iy != h - 1:
				idx.append_array([tl, bl, br])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
