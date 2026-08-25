## wave_director.gd
##
## Spawns each wave from a BUDGET rather than a flat count, which is how the
## browser build actually composes waves (tuning.js §waves, the v217 "Wave
## Director v1" that moved spawn tables out of main.js into data).
##
## Three tables come across directly:
##
##  - `POOL` — EnemyType -> [minWave, budgetCost] (tuning.js line 148). A type
##    cannot appear before its minWave, and costs its price out of the wave
##    budget. That single table is what makes waves escalate in KIND and not
##    just in number.
##  - budget curve — base 5, ramp 1.8/wave to a knee at wave 10, then 0.8/wave
##    (tuning.js line 184), with the early ease that shaves 15% at wave 1 and
##    is gone by wave 6.
##  - `shooterPlan` — ranged types are capped at 1 on wave 1 growing to 5 by
##    ~wave 12 (tuning.js line 200). Without this cap a budget spend happily
##    fills the arena with artillery and the wave becomes unreadable.
##
## Only 6 of the roster's ~40 types are ported so far — see PORT_STATUS.md.
class_name WaveDirector
extends Node3D

signal wave_started(n: int)
signal wave_cleared(n: int)
signal siren_screamed(at: Vector3)

# name -> [min_wave, cost, is_shooter]
const POOL := {
	"GLOBBO":      [1, 1, false],
	"YELA_CUBE":   [1, 1, false],
	"SPITTOR":     [1, 2, true],
	"FANNER":      [1, 2, true],
	"ORANGE_CUBE": [2, 2, true],
	"WEEVA":       [2, 3, true],
	"SLUDGE_CUBE": [3, 2, false],
	"SPLITTA":     [3, 3, false],
	"REDD_CUBE":   [4, 3, false],
	"PURP_CUBE":   [5, 3, false],
	"TORO":        [6, 5, false],
	# The "side quest" bodies: they never attack you, they make everything
	# else worse, and dealing with them costs you the thing you were doing.
	"SHEPHERD":    [4, 4, false],
	"SIREN":       [7, 5, false],
}

## Children are spawned BY a parent's death, never drawn from the wave budget,
## so they are deliberately absent from POOL.
const CHILD_TYPES := ["GLOBBO", "REDD_MINI", "PURP_MINI"]

# tuning.js waves.scale.budget
const B_BASE := 5.0
const B_RAMP := 1.8
const B_POST := 0.8
const B_KNEE := 10
const EARLY_UNTIL := 6
const EARLY_BASE := 0.85
const EARLY_STEP := 0.03

# tuning.js waves.shooterPlan
const SHOOTER_CAP_BASE := 1
const SHOOTER_CAP_PER_WAVES := 3
const SHOOTER_CAP_MAX := 5

# tuning.js waves.caps.normal
const BODY_CAP_BASE := 4
const BODY_CAP_PER := 1
const BODY_CAP_MAX := 14

# tuning.js revenge — "revenge is slow: the graze game, not a wall"
const REV_SPEED_MULT := 0.6
const REV_AIMED_COUNT := 3
const REV_AIMED_SPREAD := 0.14
const REV_FAN_COUNT := 5
const REV_FAN_SPREAD := 0.5
const REV_RING_SMALL := 4
const REV_RING_BIG := 7
const REV_RING_BIG_RADIUS := 0.75
## main.js guards revenge with `bullets.active.length < 240` so a mass grave
## cannot exhaust the pool and leave the living unable to shoot.
const REV_POOL_GUARD := 240

## The run's GAMEPLAY random stream. Every draw that decides what happens —
## which type spawns, where it lands, which way a body flops — comes from here
## and from the copy handed to each body in _spawn(). Cosmetic draws stay on
## the global rng (see bullet_pool.gd's `phase`), so a seeded run cannot be
## shifted by how much the player shot. design/DETERMINISM_AND_SEEDS.md §4.
##
## Left unseeded by default, so an ordinary run is as random as it ever was.
var rng := RandomNumberGenerator.new()

var wave := 0
## Rush Mode drives difficulty from its own LEVEL rather than from how many
## waves have been cleared, so that levelling down actually makes the next
## wave easier. 0 = off (classic uses `wave`).
var level_override := 0
var half_x := 9.0
var half_z := 9.0
var target: Node3D
var bullets: BulletPool
var trails: TrailPool
var poison: PoisonField

## Challenge rule filters (design/CAMPAIGN_LEVELS.md archetypes). ARTILLERY
## puts the shooters under a spotlight instead of mixed three-deep into a
## swarm; SWARM is its exact complement. GRAVEYARD multiplies revenge volleys,
## which makes kill ORDER and spacing the puzzle rather than aim.
var only_shooters := false
var only_melee := false
var revenge_mult := 1
## FOCUS levels drop the support species' minWave to 1, so the level is about
## them rather than about waiting for them.
var force_support := false
var enemies_root: Node3D
var enemies: Array[Enemy] = []
## Bodies mid-death-pop. They are out of `enemies` (so they cannot be shot
## again and do not hold up a wave clear) but still on screen until the pop
## finishes.
var corpses: Array[Enemy] = []

## tuning.js waves.scale.budget — ramps to the knee, then flattens.
func budget_for(w: int) -> float:
	var b := B_BASE + B_RAMP * float(mini(w, B_KNEE) - 1)
	if w > B_KNEE:
		b += B_POST * float(w - B_KNEE)
	if w < EARLY_UNTIL:
		b *= EARLY_BASE + EARLY_STEP * float(w - 1)
	return b

func shooter_cap_for(w: int) -> int:
	if only_shooters:
		return body_cap_for(w)      # ARTILLERY: the cap stops being the limit
	return mini(SHOOTER_CAP_MAX, SHOOTER_CAP_BASE + int(float(w) / float(SHOOTER_CAP_PER_WAVES)))

func body_cap_for(w: int) -> int:
	var cap := mini(BODY_CAP_MAX, BODY_CAP_BASE + BODY_CAP_PER * w)
	return int(cap * 1.6) if only_melee else cap     # SWARM: more bodies

## The number difficulty is read from: the Rush level when one is set,
## otherwise the wave count.
func difficulty() -> int:
	return level_override if level_override > 0 else wave

func start_wave() -> void:
	wave += 1
	# difficulty(), not `wave`: Rush drives escalation from its own LEVEL, which
	# moves DOWN when you lose a life, and composition has to follow it.
	var d := difficulty()
	_spawn(compose(d, budget_for(d), shooter_cap_for(d), body_cap_for(d)))
	wave_started.emit(wave)

## Spends a budget on types eligible at wave `w`, never exceeding `shooter_cap`
## ranged bodies or `body_cap` bodies in total. Bails out when nothing
## affordable is left rather than looping forever on an unspendable remainder.
##
## Split out of start_wave() so a second CADENCE can reuse it without forking
## it: design/RUSH_MODE.md §3.2 holds a STANDING pressure — spending a little
## every tick — rather than spending a whole wave at once. Two copies of a
## ported table would drift apart, which is exactly the failure CLAUDE.md's
## porting discipline exists to prevent.
func compose(w: int, budget: float, shooter_cap: int, body_cap: int) -> Array[String]:
	var picks: Array[String] = []
	var shooters_left := shooter_cap
	var bodies_left := body_cap
	var eligible := _eligible_for(w)

	while budget > 0.0 and bodies_left > 0:
		var affordable: Array[String] = []
		for name in eligible:
			var cost: float = POOL[name][1]
			var is_shooter: bool = POOL[name][2]
			if cost <= budget and (not is_shooter or shooters_left > 0):
				affordable.append(name)
		if affordable.is_empty():
			break
		var pick: String = affordable[rng.randi() % affordable.size()]
		picks.append(pick)
		budget -= float(POOL[pick][1])
		bodies_left -= 1
		if POOL[pick][2]:
			shooters_left -= 1

	return picks

func _eligible_for(w: int) -> Array[String]:
	var out: Array[String] = []
	for name in POOL.keys():
		var min_wave: int = POOL[name][0]
		if force_support and (name == "SHEPHERD" or name == "SIREN"):
			min_wave = 1
		if min_wave > w:
			continue
		var is_shooter: bool = POOL[name][2]
		if only_shooters and not is_shooter:
			continue
		if only_melee and is_shooter:
			continue
		out.append(name)
	# A filter that leaves nothing eligible would spawn an empty wave, which
	# reads as a broken level. Fall back to the unfiltered pool.
	if out.is_empty():
		for name in POOL.keys():
			if POOL[name][0] <= w:
				out.append(name)
	return out

## Places the wave on an ELLIPSE at 0.6× the arena half-extents, evenly spaced
## with a little jitter — main.js's "spawns fresh enemies at 0.6 × HALF radius",
## per axis. The arena is 38 x 22, so a circle of the smaller half-extent would
## bunch every wave into a narrow band down the middle and leave the wide ends
## of the room empty.
func _spawn(picks: Array[String]) -> void:
	var rx := 0.6 * half_x
	var rz := 0.6 * half_z
	var n := picks.size()
	for i in n:
		var a := (float(i) / float(maxi(n, 1))) * TAU + rng.randf() * 0.4 - 0.2
		var e := _make(picks[i])
		enemies_root.add_child(e)
		e.position = Vector3(cos(a) * rx, 0.0, sin(a) * rz)
		e.half_x = half_x
		e.half_z = half_z
		e.target = target
		e.bullets = bullets
		e.trails = trails
		if e is SludgeCube:
			(e as SludgeCube).poison = poison
		# Hand over the run's gameplay stream BEFORE init() — subclasses draw
		# from it there (globbo's pounce phase, fanner's strafe, weeva's spiral).
		e.rng = rng
		e.init()
		enemies.append(e)

func _make(name: String) -> Enemy:
	match name:
		"GLOBBO":      return Globbo.new()
		"YELA_CUBE":   return YelaCube.new()
		"SPITTOR":     return Spittor.new()
		"FANNER":      return Fanner.new()
		"ORANGE_CUBE": return OrangeCube.new()
		"WEEVA":       return Weeva.new()
		"SLUDGE_CUBE": return SludgeCube.new()
		"SPLITTA":     return Splitta.new()
		"REDD_CUBE":   return ReddCube.new()
		"PURP_CUBE":   return PurpCube.new()
		"TORO":        return Toro.new()
		"SHEPHERD":    return Shepherd.new()
		"SIREN":       return Siren.new()
		"REDD_MINI":   return ReddMini.new()
		"PURP_MINI":   return PurpMini.new()
	push_error("WaveDirector: unknown enemy '%s'" % name)
	return Globbo.new()

func update(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if not is_instance_valid(e):
			enemies.remove_at(i)
			continue
		if not e.alive:
			# Just died: fire its revenge, hand over any children it was
			# carrying, then move it to the corpse list so the pop plays out
			# without blocking the wave clear.
			enemies.remove_at(i)
			_fire_revenge(e)
			if e.wants_children:
				_split(e)
			corpses.append(e)
			continue
		e.update(delta)

	_run_support(delta)

	for i in range(corpses.size() - 1, -1, -1):
		var c := corpses[i]
		if not is_instance_valid(c):
			corpses.remove_at(i)
			continue
		if c.update_death(delta):
			corpses.remove_at(i)
			c.queue_free()

	if enemies.is_empty() and wave > 0:
		wave_cleared.emit(wave)

## SPLITTA's death is a spawn. The children are added to the LIVE list, so a
## wave is not clear until they are dealt with too — which is the whole reason
## the species is worth 3 budget rather than 1.
## Any body carrying children hands them over on death. SPLITTA drops GLOBBOs,
## REDD_CUBE a pack of REDD_MINIs, PURP_CUBE a bigger pack of PURP_MINIs.
func _split(parent: Enemy) -> void:
	parent.wants_children = false
	for p in parent.child_positions():
		var c := _make(parent.child_kind)
		enemies_root.add_child(c)
		c.position = Vector3(
			clampf(p.x, -half_x + 1.0, half_x - 1.0), 0.0,
			clampf(p.z, -half_z + 1.0, half_z - 1.0))
		c.half_x = half_x
		c.half_z = half_z
		c.target = target
		c.bullets = bullets
		c.trails = trails
		c.rng = rng          # children inherit the run's gameplay stream
		c.init()
		enemies.append(c)

## The support species act on the SWARM, not on the player, so they are run
## here where the whole list is visible. A SIREN scream surges everything in
## reach; a SHEPHERD drags its flock toward you every frame.
func _run_support(delta: float) -> void:
	if target == null:
		return
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		if e is Siren:
			var s := e as Siren
			if not s.scream_ready:
				continue
			s.scream_ready = false
			for w in enemies:
				if w == e or not is_instance_valid(w) or not w.alive:
					continue
				if w is Siren:
					continue          # screamers do not surge each other
				var dx := w.position.x - s.position.x
				var dz := w.position.z - s.position.z
				if dx * dx + dz * dz < Siren.SURGE_RADIUS * Siren.SURGE_RADIUS:
					w.surge_t = Siren.SURGE_TIME
			siren_screamed.emit(s.position)
		elif e is Shepherd:
			var h := e as Shepherd
			for w in enemies:
				if w == e or not is_instance_valid(w) or not w.alive:
					continue
				if w is Shepherd:
					continue
				h.herd(w, target.position, delta)

## CLOSE COMBAT: the dead shoot back (main.js onKill(), v187/v220). The volley
## SPEAKS THE SPECIES' LANGUAGE — a gunner's corpse spits a slow aimed burst,
## an arc species throws a slow fan, everything else blooms the classic ring —
## all of it at 0.6x speed and in the revenge palette, so it demands its own
## strategy rather than imitating living fire.
func _fire_revenge(e: Enemy) -> void:
	if bullets == null or target == null:
		return
	if bullets.active.size() >= REV_POOL_GUARD:
		return
	var col := e.revenge_color()
	var ex := e.position.x
	var ez := e.position.z

	match e.revenge_dialect:
		Enemy.Revenge.AIMED, Enemy.Revenge.FAN:
			var aimed: bool = e.revenge_dialect == Enemy.Revenge.AIMED
			var count := REV_AIMED_COUNT if aimed else REV_FAN_COUNT
			var spread := REV_AIMED_SPREAD if aimed else REV_FAN_SPREAD
			var bx := target.position.x - ex
			var bz := target.position.z - ez
			var base := atan2(bz, bx) if Vector2(bx, bz).length() > 1e-3 else rng.randf() * TAU
			for j in count * revenge_mult:
				var a := base + (float(j) - float(count - 1) * 0.5) * spread
				bullets.spawn_dir(ex, ez, cos(a), sin(a), false, col, false, REV_SPEED_MULT)
		_:
			var n := REV_RING_BIG if e.radius > REV_RING_BIG_RADIUS else REV_RING_SMALL
			var a0 := rng.randf() * TAU
			for j in n * revenge_mult:
				var a := a0 + (float(j) / float(n)) * TAU
				bullets.spawn_dir(ex, ez, cos(a), sin(a), false, col, false, REV_SPEED_MULT)

func clear() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for c in corpses:
		if is_instance_valid(c):
			c.queue_free()
	corpses.clear()
	wave = 0
