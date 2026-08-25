## measure.gd — plays each challenge level headlessly and reports the score
## distribution, so its C/B/A/S thresholds can be MEASURED rather than guessed.
##
## Owner direction (2026-08-25): thresholds are measured per level. The reason
## is in design/CAMPAIGN_LEVELS.md and it is a real trap — a BOOST ONLY level
## and an ARTILLERY level have completely different kill rates, so one shared
## formula would be wrong on both, and "mixing the two silently is how a
## campaign ends up with some levels where A is routine and others where it is
## impossible".
##
##   godot --headless --script tools/measure.gd -- [runs_per_level] [seed]
##
## The bot is deliberately MEDIOCRE and consistent: it boosts toward the
## nearest body, fires when it cannot boost, and does not dodge. It is not a
## model of a good player — it is a fixed yardstick. Thresholds are set as
## multiples of its median, so they move only when the LEVEL changes.
extends SceneTree

const DEFAULT_RUNS := 12
const FIXED_DT := 1.0 / 60.0
const STEPS_PER_FRAME := 240   # 4 simulated seconds per real frame
## Percent of the bot's median score. The bot plays roughly like a competent
## first-timer: it is C that should sit near it, with the higher letters
## demanding play the bot cannot manage.
const TIER_OF_MEDIAN := [0.75, 1.35, 2.10, 3.10]   # C, B, A, S

var _main: Node
var _runs := DEFAULT_RUNS
var _level := 0
var _run := 0
var _scores: Array[int] = []
var _frames := 0
var _report: Array[String] = []

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_runs = maxi(1, int(args[0]))
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _level >= Challenges.count():
		_finish()
		return true
	if _main.state != _main.State.PLAYING:
		_begin_run()
		return false
	# Simulate far faster than real time: everything in the loop is delta-driven,
	# so a fixed step run many times per frame is the same game at 60x speed.
	# Measuring three 60-90s levels eight times each in real time would take
	# half an hour.
	for _i in STEPS_PER_FRAME:
		if _main.state != _main.State.PLAYING:
			break
		_drive(FIXED_DT)
	if _main.state != _main.State.PLAYING:
		_end_run()
	return false

func _begin_run() -> void:
	_main.mode = _main.Mode.CHALLENGE
	_main.challenge_i = _level
	# Every ability, so a locked campaign does not skew the measurement.
	_main.rush.ability = RushRules.Ability.HEAT_EXCHANGE
	_main._start_game()

## One frame of the yardstick bot. Deliberately simple and deterministic in
## shape: close on the nearest body, boost through it when boost is available,
## shoot at it when it is not.
func _drive(delta: float) -> void:
	var p = _main.player
	if not p.alive:
		return
	var nearest = null
	var best := INF
	for e in _main.waves.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: float = Vector2(e.position.x - p.position.x, e.position.z - p.position.z).length()
		if d < best:
			best = d
			nearest = e
	if nearest == null:
		return

	var to := Vector2(nearest.position.x - p.position.x, nearest.position.z - p.position.z)
	var dir := to.normalized()
	var can_boost: bool = not _main.rush.boost_blocked
	var firing: bool = not can_boost and _main._ch_rule != Challenges.Rule.BOOST_ONLY

	_main.rush.update(delta, can_boost, firing)
	_main.waves.level_override = _main.rush.level
	p.rush_shotgun = true
	p.rush_speed_mult = _main.rush.speed_mult()
	p.rush_boosting = _main.rush.boosting
	p.rush_invuln = _main.rush.invulnerable(firing)

	var aim := {"x": dir.x, "z": dir.y, "valid": firing}
	p.update(delta, dir, aim, _main.bullets, _main.half_x, _main.half_z)
	_main.bullets.update(delta, maxf(_main.half_x, _main.half_z))
	_main.waves.update(delta)
	_main._collide_player_bullets()
	_main._collide_enemy_bullets()
	_main._collide_contact()

	_main._ch_clock -= delta
	if _main._ch_clock <= 0.0 or not p.alive:
		_main._finish_challenge()

func _end_run() -> void:
	_scores.append(_main.score)
	_run += 1
	if _run >= _runs:
		_summarise()
		_level += 1
		_run = 0
		_scores.clear()

func _summarise() -> void:
	var s := _scores.duplicate()
	s.sort()
	var lv := Challenges.get_level(_level)
	var med: int = s[s.size() / 2]
	var tiers: Array[int] = []
	for f in TIER_OF_MEDIAN:
		tiers.append(int(round(float(med) * f / 50.0) * 50))

	_report.append('\t{')
	_report.append('\t\t"id": "%s", "name": "%s",' % [lv["id"], lv["name"]])
	_report.append('\t\t"rule": Challenges.Rule.%s, "duration": %.1f,'
		% [_rule_name(lv["rule"]), float(lv["duration"])])
	_report.append('\t\t"difficulty": %d,' % int(lv["difficulty"]))
	_report.append('\t\t"tiers": [%d, %d, %d, %d], "measured": true,'
		% [tiers[0], tiers[1], tiers[2], tiers[3]])
	_report.append('\t\t"unlocks_ability": %d,' % int(lv["unlocks_ability"]))
	_report.append('\t},')

	print("%s %-16s runs %d  min %d  med %d  max %d   -> C %d  B %d  A %d  S %d"
		% [lv["id"], lv["name"], s.size(), s[0], med, s[s.size() - 1],
		   tiers[0], tiers[1], tiers[2], tiers[3]])

func _rule_name(r: int) -> String:
	for k in Challenges.Rule.keys():
		if Challenges.Rule[k] == r:
			return k
	return "NONE"

func _finish() -> void:
	print("\n--- paste into scripts/challenges.gd LEVELS ---")
	for line in _report:
		print(line)
	quit(0)
