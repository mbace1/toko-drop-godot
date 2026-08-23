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
## Only 4 of the roster's ~40 types are ported so far — see PORT_STATUS.md.
class_name WaveDirector
extends Node3D

signal wave_started(n: int)
signal wave_cleared(n: int)

# name -> [min_wave, cost, is_shooter]
const POOL := {
	"GLOBBO":    [1, 1, false],
	"YELA_CUBE": [1, 1, false],
	"SPITTOR":   [1, 2, true],
	"FANNER":    [1, 2, true],
}

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

var wave := 0
var half_x := 9.0
var half_z := 9.0
var target: Node3D
var bullets: BulletPool
var enemies_root: Node3D
var enemies: Array[Enemy] = []

## tuning.js waves.scale.budget — ramps to the knee, then flattens.
func budget_for(w: int) -> float:
	var b := B_BASE + B_RAMP * float(mini(w, B_KNEE) - 1)
	if w > B_KNEE:
		b += B_POST * float(w - B_KNEE)
	if w < EARLY_UNTIL:
		b *= EARLY_BASE + EARLY_STEP * float(w - 1)
	return b

func shooter_cap_for(w: int) -> int:
	return mini(SHOOTER_CAP_MAX, SHOOTER_CAP_BASE + int(float(w) / float(SHOOTER_CAP_PER_WAVES)))

func body_cap_for(w: int) -> int:
	return mini(BODY_CAP_MAX, BODY_CAP_BASE + BODY_CAP_PER * w)

func start_wave() -> void:
	wave += 1
	var budget := budget_for(wave)
	var shooters_left := shooter_cap_for(wave)
	var bodies_left := body_cap_for(wave)

	var picks: Array[String] = []
	var eligible := _eligible_for(wave)
	# Spend the budget. Bail out when nothing affordable is left rather than
	# looping forever on an unspendable remainder.
	while budget > 0.0 and bodies_left > 0:
		var affordable: Array[String] = []
		for name in eligible:
			var cost: float = POOL[name][1]
			var is_shooter: bool = POOL[name][2]
			if cost <= budget and (not is_shooter or shooters_left > 0):
				affordable.append(name)
		if affordable.is_empty():
			break
		var pick: String = affordable[randi() % affordable.size()]
		picks.append(pick)
		budget -= float(POOL[pick][1])
		bodies_left -= 1
		if POOL[pick][2]:
			shooters_left -= 1

	_spawn(picks)
	wave_started.emit(wave)

func _eligible_for(w: int) -> Array[String]:
	var out: Array[String] = []
	for name in POOL.keys():
		if POOL[name][0] <= w:
			out.append(name)
	return out

## Places the wave on a ring at 0.6× the arena half-size, evenly spaced with a
## little jitter, matching main.js's "spawns fresh enemies at 0.6 × HALF
## radius" — far enough out that nothing materialises on top of the player.
func _spawn(picks: Array[String]) -> void:
	var r := 0.6 * minf(half_x, half_z)
	var n := picks.size()
	for i in n:
		var a := (float(i) / float(maxi(n, 1))) * TAU + randf() * 0.4 - 0.2
		var e := _make(picks[i])
		enemies_root.add_child(e)
		e.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		e.half_x = half_x
		e.half_z = half_z
		e.target = target
		e.bullets = bullets
		e.init()
		enemies.append(e)

func _make(name: String) -> Enemy:
	match name:
		"GLOBBO":    return Globbo.new()
		"YELA_CUBE": return YelaCube.new()
		"SPITTOR":   return Spittor.new()
		"FANNER":    return Fanner.new()
	push_error("WaveDirector: unknown enemy '%s'" % name)
	return Globbo.new()

func update(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if not is_instance_valid(e) or not e.alive:
			enemies.remove_at(i)
			continue
		e.update(delta)
	if enemies.is_empty() and wave > 0:
		wave_cleared.emit(wave)

func clear() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	wave = 0
