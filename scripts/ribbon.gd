## ribbon.gd
##
## THE RIBBON (Q-042) — upstream v251. The body is its own recent path: a
## strip swept along the positions the head has occupied, sampled BY DISTANCE
## (its length is a design number, not a frame-rate artefact), tapering to
## nothing at the tail — enemy.js `_buildRibbon` / `_updateRibbon`.
##
## Stats from enemy.js's CFG: color 0x66ddee, radius 0.40, speed 2.6, hp 4.
## TUNING.arc.ribbon: 22 samples 0.30 apart, 0.34 wide.
##
## GAMEPLAY reads the samples (the hit test is upstream's, sample for sample);
## the strip drawn through them is this build's own: a Catmull-Rom through the
## same samples, three points per span, both faces, in the gel material.
class_name Ribbon
extends ArcMover

const SAMPLES := 22
const STEP := 0.30
const WIDTH := 0.34

## world-space samples, head first
var trail: Array[Vector2] = []
var _strip := ImmediateMesh.new()

func init() -> void:
	setup(Color(0x66 / 255.0, 0xdd / 255.0, 0xee / 255.0), 0.40, 2.6, 4, false)
	_arc_init()
	trail.clear()
	for i in SAMPLES:
		trail.append(Vector2(position.x, position.z - i * STEP))
	# the strip IS the body: no dome at the head (upstream swaps the head's
	# geometry for the strip), and no squash — a flat strip has nothing to squash
	mesh.mesh = _strip
	base_shape = Vector3.ONE
	_mesh_unit = 1.0
	_rebuild_strip()

func update(delta: float) -> void:
	_update_common(delta)
	mesh.scale = Vector3.ONE
	if not alive or target == null:
		return
	_arc_steer(delta, target.position.x, target.position.z, move_speed())
	# a new sample only once the head has moved one STEP from the last
	if Vector2(position.x, position.z).distance_to(trail[0]) >= STEP:
		trail.pop_back()
		trail.push_front(Vector2(position.x, position.z))
	_rebuild_strip()

## enemy.js `hitTest` for the RIBBON: hittable along its length, at the width
## it has there — the head at the species radius.
func hit_test(x: float, z: float, r: float) -> bool:
	var n := trail.size()
	for i in n:
		var w := radius if i == 0 else WIDTH * (1.0 - float(i) / float(n))
		var dx := trail[i].x - x
		var dz := trail[i].y - z
		if dx * dx + dz * dz < (w + r) * (w + r):
			return true
	return false

## A strip fades on death; the dome's swell would stretch it across the room.
func update_death(delta: float) -> bool:
	if not _dying:
		return true
	_death_t -= delta
	var t := 1.0 - maxf(_death_t, 0.0) / DEATH_TIME
	mat.set_shader_parameter("alpha_amt", (1.0 - t) * (1.0 - t) * _base_alpha)
	if _death_t <= 0.0:
		_dying = false
		return true
	return false

func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _rebuild_strip() -> void:
	var n := trail.size()
	var local: Array[Vector2] = []
	for p in trail:
		local.append(Vector2(p.x - position.x, p.y - position.z))
	var pts: Array[Vector2] = []
	for s in n - 1:
		var p0 := local[maxi(0, s - 1)]
		var p3 := local[mini(n - 1, s + 2)]
		for k in 3:
			pts.append(_cr(p0, local[s], local[s + 1], p3, float(k) / 3.0))
	pts.append(local[n - 1])
	var m := pts.size()
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in m:
		var t := float(i) / float(m - 1)                  # 0 head, 1 tail
		var a := pts[maxi(0, i - 1)]
		var b := pts[mini(m - 1, i + 1)]
		var tan := (b - a)
		if tan.length() > 0.0:
			tan = tan.normalized()
		else:
			tan = Vector2(1, 0)
		var w := WIDTH * sin(minf(1.0, t * 6.0) * PI / 2.0) * (1.0 - t * t)
		var y := 0.30 + sin(t * PI) * 0.10                 # a slight arch, to catch light
		left.append(Vector3(pts[i].x - tan.y * w, y, pts[i].y + tan.x * w))
		right.append(Vector3(pts[i].x + tan.y * w, y, pts[i].y - tan.x * w))
	_strip.clear_surfaces()
	_strip.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for i in m - 1:
		# both windings, both lit from UP: the strip has no thickness and the
		# camera is above it, so whichever winding faces the camera is the top
		for face in 2:
			var q := [left[i], right[i], left[i + 1], right[i], right[i + 1], left[i + 1]]
			if face == 1:
				q = [left[i], left[i + 1], right[i], right[i], left[i + 1], right[i + 1]]
			for v in q:
				_strip.surface_set_normal(Vector3.UP)
				_strip.surface_add_vertex(v)
	_strip.surface_end()
