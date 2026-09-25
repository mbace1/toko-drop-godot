## crowd.gd
##
## THE SWARM'S SPACING (Q-043) — upstream v245's `js/crowd.js`, term for term.
## This build had NO body-to-body spacing at all: not v245's, and not the
## plain overlap resolve upstream had carried for the 244 versions before it.
## Bodies pursuing one point stacked into one body's width of gel.
##
## Three terms, in one pair walk (the reasoning lives in upstream's header):
##   RESOLVE  two bodies inside CONTACT are split apart by half the overlap each
##   COMFORT  a following distance: the body BEHIND (farther from the target,
##            and closing on it) is held back, up to `push` u/s at contact,
##            fading to nothing at comfort × contact
##   SLIDE    the body behind flows round the body ahead — the pair's tangent,
##            signed toward the target's side: a queue becomes a fan
##   PAD      the contact distance itself: 0.6 of air between two bodies
##
## A body not closing on the target is nobody's tailgater and is never held
## back; a boss never yields; an ANCHORED body is never moved. dt-scaled and
## rng-free. The clamp is the arena's RECTANGLE (half-extents), exactly as
## upstream's — not the level's region.
##
## `tools/crowd-parity.mjs` runs upstream's own crowd.js and this file on the
## same scenes and compares every body's final position.
class_name Crowd
extends RefCounted

## TUNING.crowd
const DEFAULTS := { "pad": 0.6, "comfort": 1.5, "push": 4.0, "slide": 5.0, "passes": 2 }

## `bodies`: Enemy-like — position, radius, alive, affix, crowd_vel, is_boss,
## crowd_nudge(dx, dz). `target`: the point they are all going for, or null
## (which disables COMFORT and SLIDE).
static func resolve(bodies: Array, dt: float, half_x: float, half_z: float, target, cfg: Dictionary = DEFAULTS) -> void:
	var pad: float = cfg.get("pad", 0.25)
	var comfort_k: float = maxf(1.0, cfg.get("comfort", 1.0))
	var push: float = cfg.get("push", 0.0)
	var slide: float = cfg.get("slide", 0.0)
	var passes: int = cfg.get("passes", 2)
	var has_t: bool = target != null
	var tx0 := 0.0
	var tz0 := 0.0
	if has_t:
		tx0 = (target as Vector2).x
		tz0 = (target as Vector2).y
	var n := bodies.size()
	for pass_i in passes:
		for i in n:
			var a = bodies[i]
			if not a.alive or a.affix == "anchored":
				continue
			for j in range(i + 1, n):
				var b = bodies[j]
				if not b.alive or b.affix == "anchored":
					continue
				var dx: float = a.position.x - b.position.x
				var dz: float = a.position.z - b.position.z
				var d := sqrt(dx * dx + dz * dz)
				if d <= 0.001:
					continue
				var contact: float = a.radius + b.radius + pad
				var comfort: float = contact * comfort_k
				if d >= comfort:
					continue
				var nx := dx / d
				var nz := dz / d
				var ax := 0.0
				var az := 0.0
				var bx := 0.0
				var bz := 0.0
				# RESOLVE — the old solver
				if d < contact:
					var over := (contact - d) * 0.5
					ax += nx * over
					az += nz * over
					bx -= nx * over
					bz -= nz * over
				# COMFORT and SLIDE — once per frame, in the first pass
				if pass_i == 0 and comfort > contact and has_t and (push > 0.0 or slide > 0.0):
					var k := 1.0 - maxf(0.0, d - contact) / (comfort - contact)
					var dax: float = a.position.x - tx0
					var daz: float = a.position.z - tz0
					var dbx: float = b.position.x - tx0
					var dbz: float = b.position.z - tz0
					var da := sqrt(dax * dax + daz * daz)
					var db := sqrt(dbx * dbx + dbz * dbz)
					var back_is_a := da > db
					var back = a if back_is_a else b
					var gd := da if back_is_a else db
					if not back.is_boss and gd > 1e-6:
						var gx: float = (tx0 - back.position.x) / gd
						var gz: float = (tz0 - back.position.z) / gd
						var cv: Vector2 = back.crowd_vel
						var closing := cv.x * gx + cv.y * gz
						if closing > 0.5:
							var h := k * push * dt
							var ttx := -nz
							var ttz := nx
							if ttx * gx + ttz * gz < 0.0:
								ttx = -ttx
								ttz = -ttz
							var m := k * slide * dt
							if back_is_a:
								ax += -gx * h + ttx * m
								az += -gz * h + ttz * m
							else:
								bx += -gx * h + ttx * m
								bz += -gz * h + ttz * m
				if ax != 0.0 or az != 0.0:
					a.crowd_nudge(ax, az)
					a.position.x = maxf(-half_x + a.radius, minf(half_x - a.radius, a.position.x))
					a.position.z = maxf(-half_z + a.radius, minf(half_z - a.radius, a.position.z))
				if bx != 0.0 or bz != 0.0:
					b.crowd_nudge(bx, bz)
					b.position.x = maxf(-half_x + b.radius, minf(half_x - b.radius, b.position.x))
					b.position.z = maxf(-half_z + b.radius, minf(half_z - b.radius, b.position.z))
