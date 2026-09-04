## trace.gd — a seeded GAMEPLAY-STATE trace, headless. Q-035's gate.
##
## "Nothing changes" cannot be proved with pixels: cosmetic randomness is
## deliberately off the gameplay stream (CLAUDE.md), so two runs of the SAME
## code differ on screen. What must not move is the simulation. This drives
## the real main scene under one seed on a fixed timestep and prints every
## body's class and position (and the player's) at fixed frames, so a
## before/after pair can be diffed as text — the same shape as upstream's
## byte-for-byte schedule gate.
##
##   godot --headless --fixed-fps 60 --script tools/trace.gd -- seed:9D6875 [frames]
##
## Positions are float32 in the engine; nine decimals reproduce one exactly.
extends SceneTree

var _main: Node
var _frame := 0
var _last := 300
const EVERY := 15

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := 0x9D6875
	var level := ""
	for a in args:
		if a.begins_with("seed:"):
			seed_v = a.substr(5).hex_to_int()
		elif a.begins_with("level:"):
			level = a.substr(6)
		elif a.is_valid_int():
			_last = int(a)
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	# Q-032: `level:<id>` plays an authored level instead of the director's
	# roll. The seed still pins everything else; the SPAWN lines below are
	# what tools/level-parity.mjs compares against the browser build.
	if level != "":
		_main.set("level_id", level)
	_main.call_deferred("_start_game")
	(func() -> void:
		_main.waves.reseed(seed_v)
		if level == "":
			_main.waves.clear()
			_main.call("_capture_seek_wave", 3)
		else:
			_main.player.max_hp = 999   # nobody is holding the stick
			_main.player.hp = 999
	).call_deferred()

var _seen := 0

## The species name the browser uses — the class_name in SCREAMING_SNAKE.
func _type_name(e: Node) -> String:
	var n: String = e.get_script().get_global_name()
	var out := ""
	for i in n.length():
		var c := n[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower():
			out += "_"
		out += c.to_upper()
	return out

func _process(_delta: float) -> bool:
	_frame += 1
	# First sighting of every body, in the cross-build format — see
	# tools/level-parity.mjs. Printed for classic runs too; harmless.
	if _main.waves != null:
		var p = _main.player
		if _main.waves.level != null:
			p.max_hp = 999
			p.hp = 999
		for e in _main.waves.enemies:
			if e.get_meta("_traced", false):
				continue
			e.set_meta("_traced", true)
			print("SPAWN %d %s t=%.3f x=%.3f z=%.3f" % [_seen, _type_name(e), _main.waves.wave_timer, e.position.x, e.position.z])
			_seen += 1
	if _frame >= 5 and (_frame % EVERY == 0 or _frame == _last):
		var wd = _main.waves
		var parts := PackedStringArray()
		parts.append("f=%d wave=%d n=%d" % [_frame, wd.wave, wd.enemies.size()])
		var p = _main.player
		parts.append("player=%.9f,%.9f hp=%d" % [p.position.x, p.position.z, p.hp])
		for e in wd.enemies:
			parts.append("%s@%.9f,%.9f" % [e.get_script().get_global_name(), e.position.x, e.position.z])
		print("TRACE " + " ".join(parts))
	if _frame >= _last:
		print("TRACE done")
		quit(0)
	return false
