## rush_director.gd
##
## RUSH MODE — design/RUSH_MODE.md, design/RUSH_TIERS_AND_LEVELS.md. Normal is
## a wave game: start_wave() spends a budget, the arena empties, wave_cleared
## fires, repeat. Rush deletes the gap between those two states — there is no
## clear condition, the arena is held at a STANDING pressure by a director
## that refills as fast as you kill, and the run ends on a clock or a third
## hit, whichever comes first.
##
## Extends WaveDirector rather than forking it: budget_for() / shooter_cap_for()
## / body_cap_for() / compose() / cost_of() / _fire_revenge() / _step_bodies()
## all come from the parent unchanged. Escalation runs off elapsed TIME rather
## than clears (a virtual wave), and spawning trickles through a pipeline of
## telegraphed pending bodies instead of landing all at once — everything else
## about how a body is priced, capped and composed is the SAME ported table
## Normal mode uses. Two copies of that table drifting apart is exactly the
## failure CLAUDE.md's porting discipline exists to prevent.
##
## PARITY — see RUSH_MODE.md's "Parity risk" section. Every constant below is
## either marked PROPOSED (unverified against tuning.js — mbace1/Suds-Jack could
## not be attached this session) or SPECIFIED (a direct product decision, not
## sourced from the browser build, still subject to reconciliation once parity
## is checked). None of them is a port.
class_name RushDirector
extends WaveDirector

## SPECIFIED (product decision) — how long a run lasts before earned time can no
## longer extend it. design/RUSH_MODE.md §2.
const RUSH_DURATION := 180.0
## PROPOSED — seconds of clock a kill buys back, capped at RUSH_DURATION so a
## strong player cannot extend indefinitely (which would collapse the mode back
## into plain endless — the whole reason the cap exists).
const RUSH_TIME_PER_KILL := 0.35

## PROPOSED — one virtual wave every this many seconds of ELAPSED time (not
## wall-clock — see update_rush()). Escalation is time-driven so the ported
## budget/cap curves can be reused unmodified. RUSH_MODE.md §3.1.
const RUSH_WAVE_SECONDS := 12.0
## PROPOSED — a whole-wave budget spent in one burst is unplayable held
## STANDING; this scales it down to a sustainable target. RUSH_MODE.md §3.2.
const RUSH_PRESSURE := 0.55

## PROPOSED — minimum spacing between telegraph STARTS, not between a
## telegraph finishing and the next one starting. Several telegraphs are
## deliberately allowed in flight at once: waiting for one to resolve before
## starting the next caps supply at 1/(gap+telegraph) bodies/s, which is below
## the rate an average player already kills at (RUSH_MODE.md §3.3,
## RUSH_TIERS_AND_LEVELS.md §5 — this is the bug that math surfaced).
const RUSH_SPAWN_GAP := 0.35
## PROPOSED — matches SPITTOR's wind-up (enemy.gd), a tell duration the player
## has already been taught. RUSH_MODE.md §3.4.
const RUSH_TELEGRAPH_TIME := 0.45
## PROPOSED — no Rush spawn lands closer than this to the player. RUSH_MODE.md §3.4.
const RUSH_SPAWN_SAFE := 6.0
## Retries before giving up on finding a safe edge angle and placing at the
## furthest-from-player angle tried. Keeps placement bounded in a corner, where
## a naive "just resample" loop can run long odds against the safe radius.
const SPAWN_PLACEMENT_TRIES := 8

## SPECIFIED — a kill keeps the chain alive for this long; only an IDLE clock
## breaks it, never taking a hit (design decision: losing HP is already the
## game's harshest punishment, so the chain should not also be wiped by it —
## RUSH_MODE.md §4, and there is deliberately no method on this class that
## reduces heat in response to damage, so a hit cannot break the chain by
## construction, not just by convention).
const RUSH_HEAT_WINDOW := 4.0
## PROPOSED — once the window lapses, heat ramps LINEARLY to 0 over this many
## seconds (not an instant reset — a player crossing the arena to the next
## cluster should not be punished for the traversal, only for stalling).
const RUSH_HEAT_DECAY := 1.0
const RUSH_HEAT_MULT_PER := 0.15
const RUSH_HEAT_MULT_CAP := 2.0   # multiplier tops out at 1.0 + 2.0 = x3.0

## Monotonic — drives virtual-wave escalation. Only ever advances inside
## update_rush(delta); main.gd pauses by not calling update() at all, so this
## cannot be Time.get_ticks_msec() or a Timer without reintroducing the exact
## bug that pattern would cause (RUSH_MODE.md §3.5).
var elapsed := 0.0
## Depletes each tick, refills on a kill, clamped to [0, RUSH_DURATION]. The
## run is over once this hits 0.
var time_left := RUSH_DURATION

var heat := 0.0
var heat_peak := 0.0
var kills := 0
var _heat_timer := 0.0     # counts down from RUSH_HEAT_WINDOW on each kill
var _heat_decay_from := 0.0
var _heat_decay_t := 0.0

## Bodies committed to spawn but not yet alive: {"type": String, "pos": Vector3,
## "t": float}. Several may be in flight at once — see RUSH_SPAWN_GAP above.
var _pending: Array[Dictionary] = []
var _since_last_spawn_start := 999.0   # large so the very first spawn is not gated

func start_rush() -> void:
	elapsed = 0.0
	time_left = RUSH_DURATION
	heat = 0.0
	heat_peak = 0.0
	kills = 0
	_heat_timer = 0.0
	_heat_decay_from = 0.0
	_heat_decay_t = 0.0
	_pending.clear()
	_since_last_spawn_start = 999.0
	wave = 1   # so _step_bodies' callers that check `wave > 0` see a running mode

func is_over() -> bool:
	return time_left <= 0.0

func virtual_wave_for(t: float) -> int:
	return 1 + int(floor(t / RUSH_WAVE_SECONDS))

func target_pressure_for(t: float) -> float:
	return budget_for(virtual_wave_for(t)) * RUSH_PRESSURE

## Sum of POOL cost across every LIVING body. Recomputed from the live list
## rather than tracked as a running total that increments on spawn and
## decrements on death — a splitter turning one kill into three children would
## silently desync a running total (design/SPLIT_ENEMIES.md §3: "recompute, do
## not decrement").
func live_pressure() -> float:
	var total := 0.0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			total += WaveDirector.cost_of(e.type_name)
	return total

func _pending_pressure() -> float:
	var total := 0.0
	for p in _pending:
		total += WaveDirector.cost_of(p["type"])
	return total

func _shooter_count(list: Array) -> int:
	var n := 0
	for e in list:
		if e is Dictionary:
			if WaveDirector.is_shooter_type(e["type"]):
				n += 1
		elif is_instance_valid(e) and e.alive and WaveDirector.is_shooter_type(e.type_name):
			n += 1
	return n

func multiplier() -> float:
	return 1.0 + minf(heat * RUSH_HEAT_MULT_PER, RUSH_HEAT_MULT_CAP)

## Called by the collision loop in place of main.gd's inline Normal-mode score
## math. Raises heat, banks earned time, and returns the score this kill is
## worth so the caller can add it to the run total.
func register_kill(max_hp: int) -> int:
	kills += 1
	heat += 1.0
	heat_peak = maxf(heat_peak, heat)
	_heat_timer = RUSH_HEAT_WINDOW
	_heat_decay_t = 0.0   # cancel any decay in progress — a kill mid-ramp restarts the hold
	time_left = minf(RUSH_DURATION, time_left + RUSH_TIME_PER_KILL)
	# round(), not int() truncation — 0.15 has no exact binary representation,
	# so a "clean" multiplier like x1.15 can land a hair under it in float and
	# int() would silently shave a point off every score that hits this.
	return int(round(100.0 * float(max_hp) * multiplier()))

## The Rush cadence: advance the clock, step bodies (reusing the parent's
## corpse/revenge/pop handling — no wave_cleared here, an empty arena mid-run
## is a lull, not a clear), decay heat, and trickle-spawn to hold pressure.
func update_rush(delta: float, player_pos: Vector3) -> void:
	elapsed += delta
	time_left = maxf(0.0, time_left - delta)

	_step_bodies(delta)
	_update_heat(delta)
	_update_spawns(delta, player_pos)

## Splits `delta` across the window->decay boundary within ONE call rather than
## assuming a call never straddles both phases. A single small game frame never
## would, but this is also called directly with large steps in tests (and
## nothing rules out a stalled frame doing the same in play) — an earlier
## version silently "held" heat for an entire oversized step instead of
## decaying the correct partial amount, which is wrong regardless of how it
## gets triggered.
func _update_heat(delta: float) -> void:
	if _heat_timer > 0.0:
		var consumed := minf(delta, _heat_timer)
		_heat_timer -= consumed
		delta -= consumed
		if _heat_timer <= 0.0:
			_heat_decay_from = heat
			_heat_decay_t = RUSH_HEAT_DECAY
		if delta <= 0.0:
			return
	if _heat_decay_t > 0.0:
		_heat_decay_t = maxf(0.0, _heat_decay_t - delta)
		heat = _heat_decay_from * (_heat_decay_t / RUSH_HEAT_DECAY if RUSH_HEAT_DECAY > 0.0 else 0.0)
		if _heat_decay_t <= 0.0:
			heat = 0.0

func _update_spawns(delta: float, player_pos: Vector3) -> void:
	_since_last_spawn_start += delta

	# Resolve telegraphs whose wind-up has finished — this is the moment the
	# body actually starts existing, matching every other threat in the game.
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		p["t"] -= delta
		if p["t"] <= 0.0:
			_pending.remove_at(i)
			_complete_spawn(p["type"], p["pos"])

	if _since_last_spawn_start < RUSH_SPAWN_GAP:
		return

	var vw := virtual_wave_for(elapsed)
	var committed := live_pressure() + _pending_pressure()
	var target := target_pressure_for(elapsed)
	if committed >= target:
		return

	var body_room := body_cap_for(vw) - enemies.size() - _pending.size()
	if body_room <= 0:
		return
	var shooter_room := shooter_cap_for(vw) - _shooter_count(enemies) - _shooter_count(_pending)

	# body_cap pinned to 1 forces compose() to stop after its first successful
	# pick — reusing the ported affordability loop to hand back exactly one
	# type rather than a whole wave, without forking it.
	var picks := compose(vw, target - committed, maxi(shooter_room, 0), 1)
	if picks.is_empty():
		return

	var pos := _pick_edge_position(player_pos)
	_pending.append({"type": picks[0], "pos": pos, "t": RUSH_TELEGRAPH_TIME})
	_since_last_spawn_start = 0.0

func _complete_spawn(type_name: String, pos: Vector3) -> void:
	var e := _make(type_name)
	enemies_root.add_child(e)
	e.position = pos
	e.half_x = half_x
	e.half_z = half_z
	e.target = target
	e.bullets = bullets
	e.rng = rng
	e.type_name = type_name
	e.init()
	enemies.append(e)

## The full arena edge (not the 0.6x wave ellipse — RUSH_MODE.md §3.4: a body
## landing mid-play with no wave boundary to warn you is an unavoidable hit).
## Retries a handful of angles for one clear of RUSH_SPAWN_SAFE; if the player
## is cornered against every edge, places at the furthest angle actually found
## rather than looping — bounded cost beats a stuck director.
func _pick_edge_position(player_pos: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := -1.0
	for i in SPAWN_PLACEMENT_TRIES:
		var a := rng.randf() * TAU
		var pos := Vector3(cos(a) * half_x, 0.0, sin(a) * half_z)
		var d := pos.distance_to(player_pos)
		if d >= RUSH_SPAWN_SAFE:
			return pos
		if d > best_d:
			best_d = d
			best = pos
	return best
