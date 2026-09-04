## enemy.gd
##
## Shared base for every enemy body, ported from the common parts of
## toko-drop/js/enemy.js: one gel material per body (see shaders/gel.gdshader
## + PORT_BRIEF.md §0/§1), hit-wobble decay, the CPU spring-squash used on
## hit/land, and the telegraph→fire scaffolding every ranged type shares.
## Subclasses (globbo.gd, yela_cube.gd, spittor.gd, fanner.gd) own movement
## and decide what their volley looks like.
##
## Deliberately NOT driven by Godot's automatic _process/_physics_process —
## wave_director.gd calls update(delta) explicitly from main.gd's game loop,
## the same way main.js drives every enemy from one central loop. That is
## also what makes pausing free: nothing here runs unless main.gd calls it.
class_name Enemy
extends Node3D

const GEL_SHADER := preload("res://shaders/gel.gdshader")
const HIT_WOBBLE_DECAY := 1.1   # TUNING.fx.hitWobbleDecay
const DEATH_TIME := 0.28        # enemy.js updateDeath()
const DEATH_GROWTH := 1.3       # "pop growth 3.2x -> 2.3x" => scale 1 + t*1.3

## A corpse's retaliation SPEAKS THE SPECIES' LANGUAGE — TUNING.revenge.byType
## (tuning.js line 237). Gunners spit a slow aimed burst, arc species throw a
## slow fan, everything else blooms the classic ring.
enum Revenge { RING, AIMED, FAN }

var hp := 1
var max_hp := 1
var alive := true
var radius := 0.5
var speed := 2.5
var color := Color(0.0, 0.8, 0.67)

## Per-species motion-trail signature, from enemy.js's TRAIL_CFG (v36):
## interval is the cadence, size multiplies the body radius. Dangerous or fast
## species leave bolder streaks; a species absent from that table leaves none,
## which is why `trail_interval` defaults to 0.
var trail_interval := 0.0
var trail_size := 0.45

var trails: TrailPool       # set by WaveDirector; may be null
var drips: DripPool         # set by WaveDirector; may be null
## Only the blob family drips. The cubes are the same gel but read as
## SOLID (flat faces, no ripple, wobble_amp 0), and gel running off a
## hard-edged cube reads as a leak rather than as something moist.
var is_blob := true
var _drip_t := 0.0
var target: Node3D          # the player — chasers steer toward this
var bullets: BulletPool     # set by WaveDirector; null for melee-only types
## Q-035: the arena is the SOURCE. Game code shares main.gd's one Arena
## (WaveDirector hands it over in _spawn()); `half_x`/`half_z` read through
## to it as the room's SIZE. The setters exist for the tests, which build
## bodies by hand and assign a size — each assignment gives the body a
## private rectangle, which is exactly what those tests mean.
var arena: Arena = Arena.new(Arena.rect_shape(9.0, 9.0))
var half_x: float:
	get:
		return arena.half_x
	set(v):
		arena = Arena.new(Arena.rect_shape(v, arena.half_z))
var half_z: float:
	get:
		return arena.half_z
	set(v):
		arena = Arena.new(Arena.rect_shape(arena.half_x, v))
var _xz := Arena.XZ.new()   # scratch for per-frame boundary calls

## GAMEPLAY randomness only. WaveDirector hands every body the run's shared
## generator in _spawn(), which is what lets one seed reproduce one swarm; a
## body built outside the director (tests, tools) keeps this private one and
## behaves exactly as it always did.
##
## COSMETIC draws must NOT come from here. A shimmer or a particle that
## consumes from the gameplay stream makes the swarm depend on how much the
## player shot — see bullet_pool.gd's `phase` and
## design/DETERMINISM_AND_SEEDS.md §2.
var rng := RandomNumberGenerator.new()

## Ranged types set these in init(); melee types leave fire_interval at 0.
var bullet_color := Color(1.0, 0.33, 0.2)
var fire_interval := 0.0

var mesh: MeshInstance3D
var mat: ShaderMaterial

## SPLIT-ON-DEATH contract, shared because splitters come from both families:
## SPLITTA is a blob, REDD_CUBE and PURP_CUBE are cubes, and GDScript has no
## multiple inheritance to hang a common Splitter base off. A species with
## child_count 0 simply never splits.
var child_count := 0
var child_kind := ""
var child_scatter := 1.5
## Read by WaveDirector after this body dies, so it can place the children.
var wants_children := false

## Set by subclasses in init(); the fallback is RING (TUNING.revenge.fallback).
var revenge_dialect := Revenge.RING

## Per-species silhouette scale (TUNING.blob.shape / .shapes), applied on top
## of the spring squash every frame by _update_common().
var base_shape := Vector3.ONE

var _dying := false
var _death_t := 0.0
## FULLY opaque at rest. Translucency is SSS's job now, not alpha's — and
## since the gel uses hashed alpha to stay in the opaque pass, any value below
## 1.0 dithers pixels away and speckles the body with visible static. Alpha is
## only for bodies on their way OUT (the death pop, the i-frame flicker).
var _base_alpha := 1.0
## SIREN's scream sets this; while it runs the body moves at 1.6x
## (enemy.js line 1393). Read by every species through `move_speed()`, so a
## surge lifts the WHOLE swarm rather than one hand-picked type.
var surge_t := 0.0

## Spawn VARIANT and elite AFFIX (tuning.js waves.variants / waves.affixes).
## A variant changes the body's numbers; an affix changes its BEHAVIOUR, and
## main.js is explicit that each one has "its own visible tell" — an elite you
## cannot tell apart from an ordinary body is just a longer health bar.
##   volatile - its corpse blooms a ring; strobes while alive
##   swift    - faster, and leaves a much bolder streak
##   anchored - does not move at all, and is tougher for it
var variant := "normal"
var affix := ""

## main.js setBoss(): every 8th wave (WaveDirector.RHYTHM.boss_every) promotes
## one spawned body to a boss — x3 HP, x1.5 size, and a gold aura ring on the
## floor so it reads as a boss before you have started shooting it. A boss
## ALWAYS rings on death regardless of its species' own revenge dialect
## (main.js: "a boss corpse is an arena event, not a duel").
var is_boss := false
var _boss_ring: MeshInstance3D
## PORT_BRIEF.md §2b puts verlet tentacles on ONE hero enemy, and the boss
## is that enemy: promotion already happens to exactly one body every 8th
## wave, so the per-segment CPU cost is naturally rate-limited without
## needing a separate cap. Swarm bodies stay bare (the brief's own answer
## for those is a baked VAT, which is a later pass).
var _tentacles: Array[Tentacle] = []
## The dome from `gel_geo.gd` is a UNIT mesh shared by every blob, so it
## carries the body radius here. Deliberately NOT folded into
## `base_shape`: that is a PROPORTION (1.05/0.82/1.05), and the tentacle
## roots and the boss ring both read it as one via `radius * base_shape.x`.
## Cubes are built at their real size already, so theirs stays 1.
var _mesh_unit := 1.0

func apply_boss() -> void:
	is_boss = true
	hp = int(ceil(float(hp) * 3.0))
	max_hp = hp
	base_shape *= 1.5
	_build_boss_ring()
	_build_tentacles()

## Five limbs spaced around the underside of the body — the brief asks for 4-6.
## They are grown from a ring slightly inside the silhouette and just below the
## equator, so they read as coming OUT of the blob rather than being stuck on.
func _build_tentacles() -> void:
	# Derived from the body's ACTUAL proportions, not from one radius. Bodies
	# here are squat domes as often as they are spheres (`base_shape` is a
	# non-uniform scale, and `mesh.position.y = radius * base_shape.y` is what
	# rests them on the floor), and two earlier attempts each failed on a shape
	# they were not tuned for:
	#   - rooting them UNDER the body put every root at floor height, so the
	#     floor clamp pinned the chain on frame one and the constraint solver
	#     could only splay the beads outward — a stiff star, not a limb;
	#   - rooting them near the AXIS at 0.45 of the width hid them completely
	#     inside a wide squat boss, where only the root bead poked through the
	#     top and the rest of every chain hung inside opaque gel.
	# Rooting at the RIM, level with the body's own centre height, works on
	# both: the limbs leave the silhouette and then fall.
	var rx: float = radius * base_shape.x      # half width
	var ry: float = radius * base_shape.y      # half height, and centre height
	var count := 5
	for i in count:
		var a := TAU * float(i) / float(count)
		var t := Tentacle.new()
		add_child(t)
		t.build(
			Vector3(cos(a) * rx * 0.88, ry * 1.05, sin(a) * rx * 0.88),
			maxf(0.09, rx * 0.13),
			maxf(0.11, ry * 0.28),
			color)
		_tentacles.append(t)

func _build_boss_ring() -> void:
	var r: float = radius * base_shape.x * 1.7
	var m := TorusMesh.new()
	m.inner_radius = r * 0.82
	m.outer_radius = r
	m.rings = 40
	_boss_ring = MeshInstance3D.new()
	_boss_ring.mesh = m
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(1.0, 0.8, 0.2, 0.6)
	_boss_ring.material_override = rm
	_boss_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boss_ring.position = Vector3(0.0, 0.04, 0.0)
	add_child(_boss_ring)

## Adaptive quality: main.gd lowers this when many bodies are alive at once,
## so the per-pixel SSS/backlight cost — the most expensive part of the gel
## shader, and the one that scales with TOTAL SCREEN AREA of gel rather than
## with any single system — comes down smoothly instead of the frame rate
## dropping off a cliff at the body cap.
static var quality := 1.0

var _trail_t := 0.0
var _vel := Vector2.ZERO     # measured, not declared — every species moves itself
var _prev_pos := Vector2.ZERO
var _t := 0.0                # free-running clock, also drives the gel ripple
var _fire_t := 0.0           # counts UP toward fire_interval (enemy.js `_t`)
var _telegraph_t := 0.0      # counts DOWN through the wind-up
var _is_telegraphing := false
var _inflate := 0.0          # extra scale during a telegraph (SPITTOR's tell)
var _hit_wobble := 0.0
var _sq := 1.0
var _sqv := 0.0

## Builds the mesh + gel material. is_cube selects a BoxMesh (flat-faced,
## no ripple — TUNING cube family) vs a SphereMesh (blob family, rippling).
func setup(p_color: Color, p_radius: float, p_speed: float, p_hp: int, is_cube: bool) -> void:
	is_blob = not is_cube
	color = p_color
	radius = p_radius
	speed = p_speed
	hp = p_hp
	max_hp = p_hp

	# The browser's own geometry, rebuilt from its SDF — see `gel_geo.gd`.
	# Blobs share ONE dome mesh sized per body by scale (its `BLOB_GEO`);
	# cubes get a rounded box, because `RoundedBoxGeometry(s, s, s, 4, 0.18)`
	# is what the original uses and a plain box is a different silhouette.
	var m: Mesh
	if is_cube:
		m = GelGeo.rounded_box(radius * 1.8, 0.18)
	else:
		m = GelGeo.dome()
		_mesh_unit = radius

	mesh = MeshInstance3D.new()
	mesh.mesh = m
	# The dome's origin is already its FLOOR CONTACT point, so it needs no lift
	# — that is the whole reason the browser translates the geometry. The cube
	# is centred, so it still does.
	mesh.position.y = 0.0 if not is_cube else radius
	# TUNING.blob.shape — "squat grounded baseline" {x:1.05, y:0.82, z:1.05}.
	# The browser's blobs are flattened domes sitting ON the floor, not balls
	# resting on one point; a plain sphere reads as a marble.
	if not is_cube:
		# TUNING.blob.shape — the browser's "squat grounded baseline". It scales
		# the dome, which already sits on the floor; no vertical offset.
		base_shape = Vector3(1.05, 0.82, 1.05)

	mat = ShaderMaterial.new()
	mat.shader = GEL_SHADER
	mat.set_shader_parameter("gel_color", color)
	mat.set_shader_parameter("rim_color", color.lightened(0.55))
	mat.set_shader_parameter("wobble_amp", 0.0 if is_cube else 1.0)
	# Dew on the JELL-O bodies only (PORT_BRIEF.md §3). The cube family is the
	# same gel but reads as solid, and beads of condensation on a hard-edged
	# block read as dirt rather than as something moist — the same reason the
	# cubes do not drip.
	mat.set_shader_parameter("dew_amount", 0.0 if is_cube else 0.42)
	# Tiled in UV, so a bigger body must not get bigger beads.
	mat.set_shader_parameter("dew_tiling", 13.0)
	mat.set_shader_parameter("alpha_amt", _base_alpha)
	mesh.material_override = mat
	add_child(mesh)

## Human-readable name, for the death screen's question. The browser keeps an
## ENEMY_LABEL table of these ("teal globbo", "red spittor") because a question
## has to name the thing the way a player would.
func display_name() -> String:
	var n: String = get_script().resource_path.get_file().get_basename()
	return n.replace("_", " ")

## Called once by WaveDirector right after position/target/bullets/half_* are
## set, in place of relying on _ready() ordering. Subclasses override to pick
## their stats + starting state (see globbo.gd / yela_cube.gd / spittor.gd).
func init() -> void:
	pass

## Returns true if this hit killed the enemy.
func take_hit(dmg: int) -> bool:
	if not alive:
		return false
	hp -= dmg
	_hit_wobble = 0.65   # TUNING.fx.hitWobbleStart
	_sqv -= 0.5
	if hp <= 0:
		die()
		return true
	return false

## Starts the death pop. The node is NOT freed here — WaveDirector moves it to
## its corpse list and keeps calling update_death() until the pop finishes, so
## a kill is something you SEE rather than a body vanishing mid-frame.
func die() -> void:
	alive = false
	if child_count > 0:
		wants_children = true
	_dying = true
	# The corpse inflates and bursts; limbs left swinging off it read as a
	# separate object that failed to clean up.
	for tent in _tentacles:
		tent.detach()
	_tentacles.clear()
	_death_t = DEATH_TIME

## Where this body's children should land, spread around where it fell.
## WHERE they land decides what happens next, so it draws from the run's
## gameplay stream (CLAUDE.md determinism rule).
func child_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a0 := rng.randf() * TAU
	for i in child_count:
		var a := a0 + (float(i) / float(child_count)) * TAU
		out.append(Vector3(
			position.x + cos(a) * child_scatter, 0.0,
			position.z + sin(a) * child_scatter))
	return out

## enemy.js updateDeath(): swells while fading on a SQUARED curve, so the body
## is mostly transparent by the time it is large — the death stays readable
## without a screen-filling flash. Returns true once the pop is over and the
## node can be freed.
func update_death(delta: float) -> bool:
	if not _dying:
		return true
	_death_t -= delta
	var t := 1.0 - maxf(_death_t, 0.0) / DEATH_TIME
	mesh.scale = base_shape * _mesh_unit * (1.0 + t * DEATH_GROWTH)
	mat.set_shader_parameter("alpha_amt", (1.0 - t) * (1.0 - t) * _base_alpha)
	# The pre-death thrash: strongest at onset, fading as it bursts.
	mat.set_shader_parameter("hit_wobble", maxf(0.0, _death_t / DEATH_TIME))
	if _death_t <= 0.0:
		_dying = false
		return true
	return false

## TUNING.revenge.palette — a corpse never wears living colours. Warm shifts to
## dark blood, yellow to poison green, cool to deep venom, so revenge fire and
## living fire read apart at a glance (main.js revengeColor()).
func revenge_color() -> Color:
	var c := bullet_color if fire_interval > 0.0 else color
	var h := c.h
	var sat := c.s
	var l := c.v
	if h >= 0.10 and h <= 0.22:                     # yellowLo / yellowHi
		return Color.from_hsv(0.285, maxf(sat, 0.75), 0.42)   # poison green
	elif h < 0.10 or h > 0.92:                      # warmHiCut
		return Color.from_hsv(h * 0.4 if h < 0.10 else h,
			minf(1.0, sat * 1.2), maxf(0.30, l * 0.55))       # dark blood
	return Color.from_hsv(h, minf(1.0, sat * 1.2), maxf(0.30, l * 0.5))  # deep venom

## Call from a subclass's update(delta) before its own movement. Advances the
## shared clock, decays hit-wobble and applies the spring squash (plus any
## telegraph inflate) to mesh.scale.
## The speed a species should actually move at this frame. Every subclass uses
## this instead of `speed` directly, which is what lets one SIREN scream make
## the entire arena lurch forward at once.
func move_speed() -> float:
	if affix == "anchored":
		return 0.0            # it holds its ground; that IS the modifier
	var m := 1.6 if surge_t > 0.0 else 1.0
	if affix == "swift":
		m *= 1.35
	return speed * m

## Applies a spawn variant. main.js: elite doubles HP and grows 1.2x,
## elitelite is a 1.5x HP bump with no size change.
func apply_variant(kind: String, with_affix: String) -> void:
	variant = kind
	affix = with_affix
	match kind:
		"elite":
			hp = int(ceil(float(hp) * 2.0))
			base_shape *= 1.2
		"elitelite":
			hp = int(ceil(float(hp) * 1.5))
	max_hp = hp
	if affix == "anchored":
		hp = int(ceil(float(hp) * 1.4))   # it cannot run, so it can take more
		max_hp = hp
	if affix == "swift":
		trail_interval = maxf(0.03, trail_interval * 0.6)
		trail_size = trail_size * 1.5
	_apply_variant_look()

## The tell. An elite reads as an elite before it reaches you, or the variant
## is a surprise rather than information.
func _apply_variant_look() -> void:
	if variant == "elite":
		mat.set_shader_parameter("rim_color", Color(1.0, 0.9, 0.35))
	elif variant == "elitelite":
		mat.set_shader_parameter("rim_color", Color(0.9, 0.8, 0.5))
	if affix == "anchored":
		mat.set_shader_parameter("rim_color", Color(0.6, 0.7, 0.9))

func _update_common(delta: float) -> void:
	_t += delta
	# Stepped here rather than from a _physics_process of their own, so that
	# pausing the game (which simply stops calling update()) freezes them too.
	for tent in _tentacles:
		tent.update(delta)
	if surge_t > 0.0:
		surge_t = maxf(0.0, surge_t - delta)
	_emit_trail(delta)
	_emit_drip(delta)
	if _hit_wobble > 0.0:
		_hit_wobble = maxf(0.0, _hit_wobble - HIT_WOBBLE_DECAY * delta)

	_sqv = (_sqv - (_sq - 1.0) * 0.28) * 0.84
	_sq = clampf(_sq + _sqv, 0.55, 1.55)
	var sxz := 1.0 / sqrt(maxf(_sq, 0.1))
	# The telegraph inflate multiplies the spring rather than replacing it, so
	# it composes with breathe/squash instead of stomping them (enemy.js
	# applies it inside the blob scale block for the same reason).
	var infl := 1.0 + _inflate
	mesh.scale = Vector3(sxz * infl, _sq * infl, sxz * infl) * base_shape * _mesh_unit

	mat.set_shader_parameter("wobble_time", _t)
	mat.set_shader_parameter("hit_wobble", _hit_wobble)
	mat.set_shader_parameter("sss_strength", 0.75 * quality)
	mat.set_shader_parameter("backlight_amt", 0.45 * quality)
	# VOLATILE strobes orange the whole time it is alive. The corpse ring it
	# blooms is only fair because the fuse was visible.
	if affix == "volatile":
		mat.set_shader_parameter("rim_color",
			Color(1.0, 0.5, 0.1) if sin(_t * 12.0) > 0.0 else Color(0.5, 0.2, 0.0))

## Measures this body's own velocity and drops a ghost behind it on the
## species' cadence. Velocity is measured rather than declared because every
## species moves itself differently (flops, pounces, spirals) and none of them
## report a velocity.
##
## The ghost spawns ONE BODY-RADIUS BEHIND the mover (main.js v100) — at the
## body's own position it is simply hidden inside it.
## PORT_BRIEF.md §3's "moist / dew" read: gel lets go of the body and falls.
## Rate is per-body and jittered so a crowd does not pulse in unison, and it
## scales with the adaptive `quality` knob so a full arena sheds droplets
## rather than the frame rate.
func _emit_drip(delta: float) -> void:
	if drips == null or not is_blob or not alive or _dying:
		return
	_drip_t -= delta
	if _drip_t > 0.0:
		return
	# Cosmetic draw: global randf(), never the director's RNG.
	_drip_t = (0.34 + randf() * 0.62) / maxf(0.25, quality)
	var rx: float = radius * base_shape.x
	var ry: float = radius * base_shape.y
	var a := randf() * TAU
	# Let go from the lower half of the silhouette, where gel would actually
	# run to, rather than from the top or the centre.
	drips.drip(
		position.x + cos(a) * rx * 0.80,
		ry * (0.35 + randf() * 0.35),
		position.z + sin(a) * rx * 0.80,
		color,
		maxf(0.06, rx * 0.115))

func _emit_trail(delta: float) -> void:
	var here := Vector2(position.x, position.z)
	if delta > 0.0:
		_vel = (here - _prev_pos) / delta
	_prev_pos = here

	if trails == null or trail_interval <= 0.0 or not alive:
		return
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = trail_interval
	var speed_now := _vel.length()
	if speed_now < 0.05:
		return                      # a body standing still leaves no streak
	var back := _vel / speed_now * radius * 1.1
	trails.spawn(position.x - back.x, radius * 0.9, position.z - back.y,
		color, radius * trail_size)

## Shared "hold your ground at arm's length" motion for the HOLDER archetype
## (TUNING.movement.roles.HOLDER). Closes when further than want+band, backs
## off when nearer than want-band, and stands still inside the band — the
## hysteresis is what stops it jittering on the boundary. Mirrors the
## SPITTOR/FANNER/BOTFLY cases in enemy.js. Returns the unit vector toward
## the target so callers can reuse it for aiming/strafing.
func _hold_at_range(delta: float, want: float, band: float, strafe: float = 0.0) -> Vector2:
	if target == null:
		return Vector2.ZERO
	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var dist := Vector2(dx, dz).length()
	if dist < 0.001:
		return Vector2.ZERO
	var nx := dx / dist
	var nz := dz / dist

	var radial := 0.0
	if dist > want + band:
		radial = 1.0
	elif dist < want - band:
		radial = -1.0

	# Perpendicular, for types that circle while they hold (FANNER).
	var px := -nz
	var pz := nx
	position.x += (nx * radial + px * strafe) * speed * delta
	position.z += (nz * radial + pz * strafe) * speed * delta
	_clamp_to_arena()
	return Vector2(nx, nz)

func _clamp_to_arena() -> void:
	# Q-035: the boundary is the Arena's question now (arena.gd). For the
	# rectangle this is the identical max/min expression, gated exactly.
	var c := arena.clamp_pt(position.x, position.z, radius, _xz)
	position.x = c.x
	position.z = c.z

## Drives the shared fire clock. Returns true on the single frame the volley
## should actually go off; the subclass then spawns whatever shape it fires.
## `windup` is the telegraph length — the wind-up is the whole point of these
## enemies, so it is not optional (enemy.js gives every shooter one).
func _tick_fire(delta: float, windup: float) -> bool:
	if fire_interval <= 0.0 or bullets == null:
		return false
	if not _is_telegraphing:
		_fire_t += delta
		if _fire_t >= fire_interval:
			_fire_t = 0.0
			_telegraph_t = windup
			_is_telegraphing = true
	if _is_telegraphing:
		_telegraph_t -= delta
		if _telegraph_t <= 0.0:
			_is_telegraphing = false
			_inflate = 0.0
			return true
	return false

## enemy.js `_ring()` — count shots evenly around the circle, rotated so that
## shot 0 points along `base`. Passing the angle toward the player as `base`
## is what makes a symmetric ring read as aimed at you.
func _ring(x: float, z: float, count: int, base: float) -> void:
	for i in count:
		var a := base + (float(i) / float(count)) * TAU
		bullets.spawn_dir(x, z, cos(a), sin(a), false, bullet_color)

## A fan of `count` shots spanning `span` radians, centred on `base`.
func _fan(x: float, z: float, count: int, span: float, base: float) -> void:
	if count <= 1:
		bullets.spawn_dir(x, z, cos(base), sin(base), false, bullet_color)
		return
	for i in count:
		var a := base - span * 0.5 + float(i) * (span / float(count - 1))
		bullets.spawn_dir(x, z, cos(a), sin(a), false, bullet_color)

## Angle from this enemy toward the player, in the XZ plane.
func _angle_to_target() -> float:
	if target == null:
		return 0.0
	return atan2(target.position.z - position.z, target.position.x - position.x)

## Overridden by subclasses; base does nothing but the common upkeep.
func update(delta: float) -> void:
	_update_common(delta)
