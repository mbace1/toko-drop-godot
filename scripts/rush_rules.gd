## rush_rules.gd — the Rush Mode ruleset.
##
## Rush is its own ruleset (owner direction), not a toggle on classic. It owns
## heat, boost, the combo multiplier, lives and the difficulty level; main.gd
## branches into it and leaves the classic loop alone.
##
## See RUSH_MODE.md for the research this is built from. The two sentences that
## decide the whole design are the developer's own, from Blade Rush's patch
## notes:
##
##   "the intended playstyle of PRIORITISING BOOSTING OVER SHOOTING"
##   "boost invulnerability ends (either naturally or from DISABLING IT BY
##    SHOOTING)"
##
## So boost is the good option and the gun is the fallback, and the two cannot
## be used at once. The loop that falls out:
##
##   boost  -> safe (invulnerable), kills on contact, builds the multiplier,
##             but HEATS you fast
##   shoot  -> always available, but drops your invulnerability the moment you
##             pull the trigger
##   hot    -> boost locks out; you are left holding the gun until you cool
##   ability-> dump the heat back out as damage, so running hot is a CHOICE
class_name RushRules
extends Node

# ── Heat ────────────────────────────────────────────────────────────────────
const HEAT_MAX := 1.0
const HEAT_PER_BOOST_SEC := 0.55    # ~1.8s of continuous boost from cold
const HEAT_PER_SHOT := 0.020        # the gun heats too, just slowly
const COOL_PER_SEC := 0.42
## Hysteresis: once you overheat you must cool well past the line before boost
## comes back, so you cannot flutter on the edge of the meter.
const OVERHEAT_CLEAR := 0.35

# ── Boost ───────────────────────────────────────────────────────────────────
const BOOST_SPEED := 17.0           # vs 6.0 walking; the dash's 26 was a blink
const BOOST_KILL_COOLDOWN := 0.12   # per-enemy, so one pass is not 60 hits

# ── Multiplier ──────────────────────────────────────────────────────────────
const MULT_MAX := 100               # Blade Rush's "100x Combo" achievement
const MULT_WINDOW := 2.5            # the chain timer; bonuses reset it

# ── Lives ───────────────────────────────────────────────────────────────────
const LIVES_START := 3
const EXTRA_LIFE_EVERY := 25000     # "you can gain more" (owner direction)

# ── Levels ──────────────────────────────────────────────────────────────────
## Owner direction: "levels are 60, 90, and more seconds". Research adds that
## Blade Rush's level is a DYNAMIC difficulty that moves both ways — its UI
## shows "level up / level down" text. So levels advance on a lengthening
## clock and drop back when you lose a life.
const LEVEL_SECONDS := [60.0, 90.0]
const LEVEL_SECONDS_STEP := 30.0    # every level past the table adds this

# ── Heat Exchange ───────────────────────────────────────────────────────────
## The ability that closes the loop: spend the heat you built as damage. Radius
## scales with how hot you were, so the reward for running hot is real.
const ABILITY_CHARGE_SEC := 12.0
const ABILITY_MIN_HEAT := 0.25
const ABILITY_RADIUS_BASE := 2.6
const ABILITY_RADIUS_PER_HEAT := 5.0

signal level_changed(level: int, went_up: bool)
signal overheated()
signal life_lost(lives_left: int)
signal ability_fired(radius: float)

var heat := 0.0
var overheated_now := false
var boosting := false
var boost_blocked := false      # true while overheated

var multiplier := 1
var mult_t := 0.0

var lives := LIVES_START
var level := 1
var level_t := 0.0
var run_t := 0.0

var ability_charge := 0.0
var _next_extra_life := EXTRA_LIFE_EVERY

func reset() -> void:
	heat = 0.0
	overheated_now = false
	boosting = false
	boost_blocked = false
	multiplier = 1
	mult_t = 0.0
	lives = LIVES_START
	level = 1
	level_t = 0.0
	run_t = 0.0
	ability_charge = 0.0
	_next_extra_life = EXTRA_LIFE_EVERY

func level_duration(n: int) -> float:
	if n <= LEVEL_SECONDS.size():
		return LEVEL_SECONDS[n - 1]
	return LEVEL_SECONDS[LEVEL_SECONDS.size() - 1] \
		+ LEVEL_SECONDS_STEP * float(n - LEVEL_SECONDS.size())

## `want_boost` is the held input; `firing` is whether the trigger is down this
## frame. Returns nothing — read `boosting` / `invulnerable()` after calling.
func update(delta: float, want_boost: bool, firing: bool) -> void:
	run_t += delta

	# Boost is only available when not locked out by heat.
	boosting = want_boost and not boost_blocked
	if boosting:
		heat += HEAT_PER_BOOST_SEC * delta
	else:
		heat -= COOL_PER_SEC * delta
	if firing:
		heat += HEAT_PER_SHOT

	heat = clampf(heat, 0.0, HEAT_MAX)

	if not boost_blocked and heat >= HEAT_MAX:
		boost_blocked = true
		overheated_now = true
		boosting = false
		overheated.emit()
	elif boost_blocked and heat <= OVERHEAT_CLEAR:
		boost_blocked = false
		overheated_now = false

	# The chain runs on a timer; letting it lapse is one of the two ways to
	# lose it (the other is taking a hit — owner direction: "both").
	if multiplier > 1:
		mult_t -= delta
		if mult_t <= 0.0:
			multiplier = 1

	if ability_charge < ABILITY_CHARGE_SEC:
		ability_charge = minf(ABILITY_CHARGE_SEC, ability_charge + delta)

	level_t += delta
	if level_t >= level_duration(level):
		level_t = 0.0
		level += 1
		level_changed.emit(level, true)

## Shooting does not stop you boosting — it stops you being SAFE while you do.
func invulnerable(firing: bool) -> bool:
	return boosting and not firing

func speed_mult() -> float:
	return BOOST_SPEED / 6.0 if boosting else 1.0

## A kill made by boosting through a body. Ordinary gunfire does not chain.
func add_boost_kill() -> void:
	multiplier = mini(MULT_MAX, multiplier + 1)
	mult_t = MULT_WINDOW

## Any pickup/bonus refreshes the chain window without raising it.
func refresh_chain() -> void:
	if multiplier > 1:
		mult_t = MULT_WINDOW

## Returns true if the run is over.
func take_hit() -> bool:
	multiplier = 1
	mult_t = 0.0
	lives -= 1
	life_lost.emit(lives)
	# Difficulty moves BOTH ways — Blade Rush shows "level down" text too.
	if level > 1:
		level -= 1
		level_t = 0.0
		level_changed.emit(level, false)
	return lives <= 0

func ability_ready() -> bool:
	return ability_charge >= ABILITY_CHARGE_SEC and heat >= ABILITY_MIN_HEAT

## Dumps all stored heat outward. Returns the burn radius, or 0 if not ready.
func fire_ability() -> float:
	if not ability_ready():
		return 0.0
	var r := ABILITY_RADIUS_BASE + ABILITY_RADIUS_PER_HEAT * heat
	heat = 0.0
	boost_blocked = false
	overheated_now = false
	ability_charge = 0.0
	ability_fired.emit(r)
	return r

## Awards score at the current multiplier and hands out extra lives.
## Returns the points actually added.
func award(base: int) -> int:
	return base * multiplier

func note_score(total: int) -> bool:
	if total < _next_extra_life:
		return false
	_next_extra_life += EXTRA_LIFE_EVERY
	lives += 1
	return true
