## crowd_check.gd — Q-043. A port of upstream's `scripts/crowd-check.mjs`,
## check for check, against `scripts/crowd.gd`:
##
##   godot --headless --path . --script tests/crowd_check.gd
##
## Fake bodies pursue one point and the crowd keeps them apart each frame, as
## the director calls it. Pinned: the hard RESOLVE alone is the plain overlap
## solver; nine bodies arriving from ONE side spread round the target instead
## of piling; a body holding its ground is sheltered, not held back; anchored
## bodies never move; everything stays inside the clamp; a flop's origin
## follows every nudge; the fan is the same shape at 30 fps.
##
## It also prints every body's final position (`CROWD <scene> <i> x z`), which
## `tools/crowd-parity.mjs` compares against upstream's own crowd.js running
## the same scenes — the cross-build half of the gate.
extends SceneTree

const HX := 11.0
const HZ := 18.0
const DT := 1.0 / 60.0

var _checks := 0
var _fails := 0

class Body:
	extends RefCounted
	var position := Vector3.ZERO
	var radius := 0.45
	var alive := true
	var affix := ""
	var is_boss := false
	var crowd_vel := Vector2.ZERO
	var flopping := false
	var flop_origin := Vector2.ZERO
	func crowd_nudge(dx: float, dz: float) -> void:
		position.x += dx
		position.z += dz
		if flopping:
			flop_origin += Vector2(dx, dz)

func _ok(name: String, cond: bool, info := "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("✘ %s %s" % [name, info])
	else:
		print("  ok   %s" % name)

func _bodies(n: int, spread := 0.6, z0 := 7.0, r := 0.45) -> Array:
	var out := []
	for i in n:
		var b := Body.new()
		b.position = Vector3(float((i % 3) - 1) * spread, 0.0, z0 + float(i / 3) * 0.9)
		b.radius = r
		out.append(b)
	return out

## crowd-check.mjs `pursue`: the pursuit never stops, the arena clamps it, and
## flockmates pull on each other at the game's cohesion rate.
func _pursue(bs: Array, t: Vector2, speed: float, stop := 0.05, dt := DT) -> void:
	for b in bs:
		var dx: float = t.x - b.position.x
		var dz: float = t.y - b.position.z
		var d := sqrt(dx * dx + dz * dz)
		if d > stop:
			b.position.x += dx / d * speed * dt
			b.position.z += dz / d * speed * dt
			b.crowd_vel = Vector2(dx / d * speed, dz / d * speed)
		else:
			b.crowd_vel = Vector2.ZERO
		b.position.x = maxf(-HX + b.radius, minf(HX - b.radius, b.position.x))
		b.position.z = maxf(-HZ + b.radius, minf(HZ - b.radius, b.position.z))
		var cx := 0.0
		var cz := 0.0
		var n := 0
		for o in bs:
			if o == b:
				continue
			var ox: float = o.position.x - b.position.x
			var oz: float = o.position.z - b.position.z
			if ox * ox + oz * oz > 16.0:
				continue
			cx += ox
			cz += oz
			n += 1
		if n > 0:
			var gl := sqrt(cx * cx + cz * cz)
			if gl == 0.0:
				gl = 1.0
			b.position.x += (cx / gl) * 0.5 * dt
			b.position.z += (cz / gl) * 0.5 * dt

func _run(cfg: Dictionary, frames := 360, t := Vector2.ZERO) -> Array:
	var bs := _bodies(9)
	for f in frames:
		_pursue(bs, t, 3.0)
		Crowd.resolve(bs, DT, HX, HZ, t, cfg)
	return bs

func _pile_r(bs: Array, t: Vector2) -> float:
	var m := 0.0
	for b in bs:
		m = maxf(m, Vector2(b.position.x - t.x, b.position.z - t.y).length())
	return m

func _overlaps(bs: Array) -> int:
	var n := 0
	for i in bs.size():
		for j in range(i + 1, bs.size()):
			var a = bs[i]
			var b = bs[j]
			if Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length() < a.radius + b.radius - 1e-9:
				n += 1
	return n

func _coverage(bs: Array, t: Vector2) -> float:
	var ang := []
	for b in bs:
		ang.append(atan2(b.position.z - t.y, b.position.x - t.x))
	ang.sort()
	var gap := 0.0
	for i in ang.size():
		var nxt: float = ang[i + 1] if i + 1 < ang.size() else ang[0] + TAU
		gap = maxf(gap, nxt - ang[i])
	return (TAU - gap) * 180.0 / PI

func _nn(bs: Array) -> float:
	var s := 0.0
	for a in bs:
		var m := 1e9
		for b in bs:
			if a == b:
				continue
			m = minf(m, Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length())
		s += m
	return s / bs.size()

## crowd-check.mjs `oldSolver`: the inline overlap solver upstream carried for
## 244 versions, as the reference the hard RESOLVE must reproduce exactly.
func _old_solver(enemies: Array) -> void:
	for _pass in 2:
		for i in enemies.size():
			var a = enemies[i]
			if not a.alive:
				continue
			for j in range(i + 1, enemies.size()):
				var b = enemies[j]
				if not b.alive:
					continue
				var dx: float = a.position.x - b.position.x
				var dz: float = a.position.z - b.position.z
				var d := sqrt(dx * dx + dz * dz)
				var mn: float = a.radius + b.radius + 0.25
				if d < mn and d > 0.001 and a.affix != "anchored" and b.affix != "anchored":
					var over := (mn - d) * 0.5
					var nx := dx / d
					var nz := dz / d
					a.position.x += nx * over
					a.position.z += nz * over
					b.position.x -= nx * over
					b.position.z -= nz * over
					a.position.x = maxf(-HX + a.radius, minf(HX - a.radius, a.position.x))
					a.position.z = maxf(-HZ + a.radius, minf(HZ - a.radius, a.position.z))
					b.position.x = maxf(-HX + b.radius, minf(HX - b.radius, b.position.x))
					b.position.z = maxf(-HZ + b.radius, minf(HZ - b.radius, b.position.z))

func _dump(scene: String, bs: Array) -> void:
	for i in bs.size():
		print("CROWD %s %d %.15f %.15f" % [scene, i, bs[i].position.x, bs[i].position.z])

func _init() -> void:
	var OLD := { "pad": 0.25, "comfort": 1.0, "push": 0.0, "slide": 0.0, "passes": 2 }
	var T := Vector2.ZERO

	# ── 1. the hard resolve alone: fourteen bodies from a fixed LCG ─────────────
	# (the same generator crowd-check.mjs uses, so the parity tool can build the
	# identical scene on the other side)
	var seed_v := [7]
	var rnd := func() -> float:
		seed_v[0] = (seed_v[0] * 1103515245 + 12345) & 0x7fffffff
		return float(seed_v[0]) / float(0x7fffffff)
	var mk := func() -> Array:
		var out := []
		for i in 14:
			var b := Body.new()
			b.position = Vector3(rnd.call() * 4.0 - 2.0, 0.0, rnd.call() * 4.0 - 2.0)
			b.radius = 0.35 + rnd.call() * 0.7
			b.alive = rnd.call() > 0.1
			b.affix = "anchored" if rnd.call() > 0.85 else ""
			out.append(b)
		return out
	seed_v[0] = 7
	var rs: Array = mk.call()
	seed_v[0] = 7
	var ref: Array = mk.call()
	# the scene as built, for the parity tool (upstream's LCG multiplies in
	# doubles and loses bits past 2^53, so the other side builds FROM these)
	for i in rs.size():
		var b = rs[i]
		print("CROWDINIT resolve %d %.15f %.15f %.15f %d %s" % [i, b.position.x, b.position.z, b.radius, 1 if b.alive else 0, b.affix if b.affix != "" else "-"])
	_old_solver(ref)
	Crowd.resolve(rs, DT, HX, HZ, null, OLD)
	var same_old := true
	for i in rs.size():
		if rs[i].position != ref[i].position:
			same_old = false
	_ok("the hard resolve is exactly the plain overlap solver (comfort 1, no push, no slide)", same_old)
	_dump("resolve", rs)

	# ── 2. nine from one door: a fan, not a pile ────────────────────────────────
	var fresh := _run(Crowd.DEFAULTS)
	var stale := _run(OLD)
	var cov_f := _coverage(fresh, T)
	print("  old solver: nn=%.2f pile=%.2f cov=%.0f°  ·  v245: nn=%.2f pile=%.2f cov=%.0f°" % [_nn(stale), _pile_r(stale, T), _coverage(stale, T), _nn(fresh), _pile_r(fresh, T), cov_f])
	_ok("no two bodies overlap when they arrive", _overlaps(fresh) == 0, "overlaps=%d" % _overlaps(fresh))
	var nearest := 1e9
	for b in fresh:
		nearest = minf(nearest, Vector2(b.position.x, b.position.z).length())
	_ok("they still ARRIVE — the nearest body reaches the target", nearest < 0.6, "%.2f" % nearest)
	_ok("they spread round the target: coverage ≥ 240°", cov_f >= 240.0, "%.0f°" % cov_f)
	_ok("nearest-neighbour spacing is at least a quarter wider than the old solver left it", _nn(fresh) >= _nn(stale) * 1.25)
	_ok("the pack is wider than a pile: outermost body ≥ 1.2× the old radius", _pile_r(fresh, T) >= _pile_r(stale, T) * 1.2)
	_dump("fan", fresh)
	_dump("pile", stale)

	# a body holding its ground is sheltered, never held back
	var scene := func(cfg: Dictionary) -> float:
		var bs := _bodies(9)
		var holder := Body.new()
		holder.position = Vector3(0.0, 0.0, 6.0)
		holder.radius = 0.6
		bs.append(holder)
		var movers := bs.filter(func(x): return x != holder)
		for f in 240:
			_pursue(movers, T, 3.0)
			holder.crowd_vel = Vector2.ZERO
			Crowd.resolve(bs, DT, HX, HZ, T, cfg)
		return Vector2(holder.position.x, holder.position.z - 6.0).length()
	var cfg_off := Crowd.DEFAULTS.duplicate()
	cfg_off["push"] = 0.0
	cfg_off["slide"] = 0.0
	var on: float = scene.call(Crowd.DEFAULTS)
	var off: float = scene.call(cfg_off)
	_ok("a body holding its ground is shoved under half as far as without the new terms", on <= off * 0.5, "with=%.2f without=%.2f" % [on, off])

	var a1 := _run(Crowd.DEFAULTS)
	var a2 := _run(Crowd.DEFAULTS)
	var same := true
	for i in a1.size():
		if a1[i].position != a2[i].position:
			same = false
	_ok("deterministic — the same input gives the same swarm", same)

	var bs_a := _bodies(9)
	bs_a[4].affix = "anchored"
	var p4: Vector3 = bs_a[4].position
	for f in 120:
		_pursue(bs_a.filter(func(x): return x != bs_a[4]), T, 3.0)
		Crowd.resolve(bs_a, DT, HX, HZ, T, Crowd.DEFAULTS)
	_ok("an anchored body is never moved", bs_a[4].position == p4)

	var corner := _run(Crowd.DEFAULTS, 360, Vector2(HX - 0.2, HZ - 0.2))
	var inside := true
	for b in corner:
		# (1e-5, not upstream's 1e-9: a Node3D position is float32 here, and
		# 11 - 0.45 stored in float32 is a hair above 10.55)
		if absf(b.position.x) > HX - b.radius + 1e-5 or absf(b.position.z) > HZ - b.radius + 1e-5:
			inside = false
	_ok("every body stays inside the arena clamp", inside)

	var bs_f := _bodies(9)
	bs_f[2].flopping = true
	bs_f[2].flop_origin = Vector2(bs_f[2].position.x, bs_f[2].position.z)
	for f in 60:
		var px: float = bs_f[2].position.x
		var pz: float = bs_f[2].position.z
		_pursue(bs_f, T, 3.0)
		bs_f[2].flop_origin += Vector2(bs_f[2].position.x - px, bs_f[2].position.z - pz)
		Crowd.resolve(bs_f, DT, HX, HZ, T, Crowd.DEFAULTS)
	_ok("a flopping cube's tumble origin follows every nudge",
		absf(bs_f[2].flop_origin.x - bs_f[2].position.x) < 1e-9 and absf(bs_f[2].flop_origin.y - bs_f[2].position.z) < 1e-9)

	var half := _bodies(9)
	for f in 180:
		_pursue(half, T, 3.0, 0.05, DT * 2.0)
		Crowd.resolve(half, DT * 2.0, HX, HZ, T, Crowd.DEFAULTS)
	_ok("at half the frame rate the fan is the same shape (dt-scaled): coverage within 25°", absf(_coverage(half, T) - cov_f) <= 25.0,
		"30fps=%.0f° 60fps=%.0f°" % [_coverage(half, T), cov_f])

	print("CROWD: %s — %d/%d" % ["PASS" if _fails == 0 else "FAIL", _checks - _fails, _checks])
	quit(0 if _fails == 0 else 1)
