## rush_rules.gd — the Rush Mode ruleset.
##
## Rush is its own ruleset (owner direction), not a toggle on classic. It owns
## heat, boost, the combo multiplier, lives, the difficulty level and the
## ability; main.gd branches into it and leaves the classic loop alone.
##
## See RUSH_MODE.md for the research. The two sentences that decide the whole
## design are the Blade Rush developer's own, from its patch notes:
##
##   "the intended playstyle of PRIORITISING BOOSTING OVER SHOOTING"
##   "boost invulnerability ends (either naturally or from DISABLING IT BY
##    SHOOTING)"
##
## So boost is the good option and the gun is the fallback, and the two cannot
## be used at once:
##
##   boost  -> safe (invulnerable), kills on contact, builds the multiplier,
##             but HEATS you fast
##   shoot  -> always available, but drops your shield the moment you fire
##   hot    -> boost locks out; you are left holding the gun until you cool
##   ability-> four of them, and each one bends that triangle differently
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
const LEVEL_SECONDS_STEP := 30.0

# ── Abilities ───────────────────────────────────────────────────────────────
## All four Blade Rush names an achievement for. Each one bends the
## boost/shoot/heat triangle in a different direction, which is the point:
## picking one should change how you play, not just what you press.
##
##   HEAT_EXCHANGE  — spend the heat you built as a burn. Rewards running hot.
##   HYPER_BOMB     — a big clear that costs no heat. The panic button.
##   OVERCHARGE     — a window where boosting is FREE (no heat) and the chain
##                    climbs double. Rewards already being safe.
##   QUANTUM_SHIELD — a window where enemy fire is REFLECTED back as yours.
##                    The only one that rewards standing still and shooting.
enum Ability { HEAT_EXCHANGE, HYPER_BOMB, OVERCHARGE, QUANTUM_SHIELD }

const ABILITY_DEF := {
	Ability.HEAT_EXCHANGE: {
		"name": "HEAT EXCHANGE", "charge": 12.0, "min_heat": 0.25,
		"kind": "burst", "radius": 2.6, "radius_per_heat": 5.0,
		"blurb": "dump your heat as a burn — bigger the hotter you are",
	},
	Ability.HYPER_BOMB: {
		"name": "HYPER BOMB", "charge": 18.0, "min_heat": 0.0,
		"kind": "burst", "radius": 8.5, "radius_per_heat": 0.0,
		"blurb": "a wide clear that costs no heat — the panic button",
	},
	Ability.OVERCHARGE: {
		"name": "OVERCHARGE", "charge": 20.0, "min_heat": 0.0,
		"kind": "buff", "duration": 6.0,
		"blurb": "6s of free boosting, and the chain climbs double",
	},
	Ability.QUANTUM_SHIELD: {
		"name": "QUANTUM SHIELD", "charge": 16.0, "min_heat": 0.0,
		"kind": "buff", "duration": 5.0,
		"blurb": "5s where enemy fire is reflected back as yours",
	},
}

signal level_changed(level: int, went_up: bool)
signal overheated()
signal life_lost(lives_left: int)
signal ability_fired(kind: String, radius: float)

var ability: int = Ability.HEAT_EXCHANGE

var heat := 0.0
var overheated_now := false
var boosting := false
var boost_blocked := false

var multiplier := 1
var mult_t := 0.0

var lives := LIVES_START
var level := 1
var level_t := 0.0
var run_t := 0.0

var ability_charge := 0.0
var buff_t := 0.0
var _next_extra_life := EXTRA_LIFE_EVERY

func def() -> Dictionary:
	return ABILITY_DEF[ability]

func ability_name() -> String:
	return def()["name"]

func ability_blurb() -> String:
	return def()["blurb"]

func charge_time() -> float:
	return def()["charge"]

## True while a timed ability is running.
func buff_active() -> bool:
	return buff_t > 0.0

func overcharged() -> bool:
	return buff_active() and ability == Ability.OVERCHARGE

func reflecting() -> bool:
	return buff_active() and ability == Ability.QUANTUM_SHIELD

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
	buff_t = 0.0
	_next_extra_life = EXTRA_LIFE_EVERY

func cycle_ability(step: int) -> void:
	var n := ABILITY_DEF.size()
	ability = (ability + step + n) % n

func level_duration(n: int) -> float:
	if n <= LEVEL_SECONDS.size():
		return LEVEL_SECONDS[n - 1]
	return LEVEL_SECONDS[LEVEL_SECONDS.size() - 1] \
		+ LEVEL_SECONDS_STEP * float(n - LEVEL_SECONDS.size())

## `want_boost` is the held input; `firing` is whether the trigger is down.
func update(delta: float, want_boost: bool, firing: bool) -> void:
	run_t += delta

	if buff_t > 0.0:
		buff_t = maxf(0.0, buff_t - delta)

	boosting = want_boost and not boost_blocked
	# OVERCHARGE's whole point: boosting stops costing anything for its window.
	var free_boost := overcharged()
	if boosting and not free_boost:
		heat += HEAT_PER_BOOST_SEC * delta
	elif not boosting:
		heat -= COOL_PER_SEC * delta
	if firing and not free_boost:
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

	if ability_charge < charge_time():
		ability_charge = minf(charge_time(), ability_charge + delta)

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
	var step := 2 if overcharged() else 1
	multiplier = mini(MULT_MAX, multiplier + step)
	mult_t = MULT_WINDOW

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
	return ability_charge >= charge_time() and heat >= float(def()["min_heat"])

## Fires the selected ability. Returns a radius for "burst" kinds (0 for
## buffs, which set buff_t instead), or -1.0 when it was not ready.
func fire_ability() -> float:
	if not ability_ready():
		return -1.0
	var d := def()
	ability_charge = 0.0
	if d["kind"] == "burst":
		var r: float = float(d["radius"]) + float(d["radius_per_heat"]) * heat
		# Spending the heat is what makes HEAT_EXCHANGE a choice rather than a
		# freebie; HYPER_BOMB has radius_per_heat 0 and keeps your heat.
		if float(d["radius_per_heat"]) > 0.0:
			heat = 0.0
			boost_blocked = false
			overheated_now = false
		ability_fired.emit("burst", r)
		return r
	buff_t = float(d["duration"])
	ability_fired.emit("buff", 0.0)
	return 0.0

func award(base: int) -> int:
	return base * multiplier

func note_score(total: int) -> bool:
	if total < _next_extra_life:
		return false
	_next_extra_life += EXTRA_LIFE_EVERY
	lives += 1
	return true
