## smoke_main.gd — headless driver for main.gd's mode wiring (Rush vs Normal).
##
## tests/smoke.gd deliberately does not cover main.gd itself ("Exercises the
## pieces main.gd wires together, without needing real input events") because
## main.gd's own _ready() relies on deferred NOTIFICATION_READY the way every
## other script here is built to NOT need — see README's "Design note: no
## _ready()-timing surprises". So unlike everything in tests/smoke.gd, this
## can't run synchronously in _init(); it has to wait for a real frame.
##
## What this checks that nothing else does: that main.gd's actual collision
## loop calls RushDirector.register_kill() and adds its result to score (not
## a parallel, easier-to-get-wrong path), that Rush's clock reaching zero ends
## the run with a Rush-shaped recap (no wave number, which would be a lie),
## and that a Normal death and a Rush timeout land in separate save buckets
## through the real _start_game()/_end_run() wiring, not just through
## SaveService in isolation (already covered in tests/smoke.gd).
##
## Never touches the real save: save.path is redirected to a scratch file
## before _start_game() is ever called.
##
## Run: godot --headless --script tests/smoke_main.gd
extends SceneTree

# main.gd's State/Mode enums, mirrored here — main.gd has no class_name (it's
# the scene root, loaded by path, never instantiated by type elsewhere), so
# these can only be reached dynamically via .get()/.call(), and the enum
# values themselves have to be read off in the same order main.gd declares
# them. If main.gd's enum order ever changes, these need to change with it.
const MENU := 0
const PLAYING := 1
const DEAD := 3
const MODE_NORMAL := 0
const MODE_RUSH := 1

var _ok := true
var _main: Node
var _ran := false

func _check(cond: bool, label: String) -> void:
	print(("  ok  " if cond else "FAIL ") + label)
	_ok = _ok and cond

func _init() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)

func _process(_delta: float) -> bool:
	if _ran:
		return false
	# _ready() hasn't necessarily flushed yet on the frame add_child() runs in
	# a bare SceneTree — poll for it rather than assuming a fixed frame count.
	if _main.get("save") == null:
		return false
	_ran = true
	_run_all()
	print("SMOKE_MAIN: %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
	return false

func _run_all() -> void:
	var save = _main.get("save")
	var save_path := "user://_smoke_main_save.json"
	save.path = save_path
	save.modes = {}
	save.levels = {}

	_check(int(_main.get("state")) == MENU, "boots onto the menu")
	_check(int(_main.get("mode")) == MODE_NORMAL, "and defaults to Normal mode")

	# --- A Normal run, started and ended, exactly as tools/capture.gd's
	# existing no-args _start_game() call does today. ---
	_main.call("_start_game")
	var waves = _main.get("waves")
	_check(int(_main.get("state")) == PLAYING, "starting a Normal run enters PLAYING")
	_check(not (waves is RushDirector), "and installs a plain WaveDirector, not RushDirector")
	_check(int(_main.get("score")) == 0, "score resets to 0")

	# _on_player_dead() is the real call site's own handler — invoking it
	# directly is an honest stand-in for "the run just ended this way", the
	# same relationship _capture_seek_wave() already has to a real wave clear.
	_main.set("score", 240)
	_main.call("_on_player_dead")
	_check(int(_main.get("state")) == DEAD, "a Normal death ends the run")
	var normal_msg: String = _main.get("_msg_label").text
	_check(normal_msg.find("YOU DIED") != -1, "...with the Normal headline")
	_check(normal_msg.find("wave") != -1, "...and a wave number, which is real for Normal")
	_check(int(save._bucket(SaveService.MODE_NORMAL).get("hi_score", 0)) == 240,
		"the Normal run recorded into the normal bucket")

	# --- Mode selection, exactly as a chip press or ui_left/ui_right drives it. ---
	_main.call("_show_menu")
	_main.call("_select_mode", MODE_RUSH, false)
	_check(int(_main.get("mode")) == MODE_RUSH, "_select_mode(RUSH, false) changes the selection")
	_check(int(_main.get("state")) == MENU, "...without starting a run")

	# A chip press (or FIRE/DASH once selected) both selects and starts.
	_main.call("_select_mode", MODE_RUSH, true)
	waves = _main.get("waves")
	_check(int(_main.get("state")) == PLAYING, "selecting RUSH and starting enters PLAYING")
	_check(waves is RushDirector, "...and installs a RushDirector, not a plain WaveDirector")
	_check(save.mode == SaveService.MODE_RUSH, "...and save.mode follows the run, not the last one")

	# --- The scoring wiring itself: a real bullet, through the real collision
	# loop, must call RushDirector.register_kill() and add its result to
	# score. This is the check that would catch "forgot to branch main.gd's
	# scoring for Rush" or "added the score but not to the right variable". ---
	var spawned := false
	for i in 20:
		_main.call("_process_playing", 0.5)   # let a telegraphed body land
		if waves.enemies.size() > 0:
			spawned = true
			break
	_check(spawned, "Rush's director spawns a body once driven through main.gd's real loop")

	if spawned:
		var e = waves.enemies[0]
		e.hp = 1   # force this next hit to be lethal, whatever species it is
		var score_before := int(_main.get("score"))
		var kills_before := int(waves.kills)
		# A real bullet has real velocity, and the enemy moves on its own each
		# frame (a leaping GLOBBO especially) — one fixed spawn position is not
		# a reliable hit for every species. Re-glue the bullet to wherever the
		# enemy actually is at the start of each tiny-delta frame instead of
		# betting on a single coincidence; this is still the real collision
		# loop doing the detecting, just not a race against real movement.
		var bullets = _main.get("bullets")
		var b = null
		for i in 10:
			if waves.enemies.is_empty() or not is_instance_valid(waves.enemies[0]):
				break   # already killed by an earlier iteration
			var live = waves.enemies[0]
			if b == null:
				bullets.spawn_dir(live.position.x, live.position.z, 1.0, 0.0, true)
				b = bullets.active[-1]
			else:
				b.x = live.position.x
				b.z = live.position.z
			_main.call("_process_playing", 1.0 / 600.0)
			if int(waves.kills) > kills_before:
				break
		_check(int(_main.get("score")) > score_before,
			"a Rush kill through the real collision loop raises score")
		_check(int(waves.kills) > kills_before,
			"...and RushDirector's own kill count — the wiring, not a parallel score path")

	# --- The clock reaching zero ends the run, Rush-shaped. ---
	waves.time_left = 0.0
	_main.call("_process_playing", 1.0 / 60.0)
	_check(int(_main.get("state")) == DEAD, "Rush's clock reaching zero ends the run")
	var rush_msg: String = _main.get("_msg_label").text
	_check(rush_msg.find("TIME'S UP") != -1, "...with the Rush headline")
	_check(rush_msg.find("wave") == -1 and rush_msg.find("WAVE") == -1,
		"...and never prints a wave number, which would be a lie for a virtual-wave mode")
	_check(int(save._bucket(SaveService.MODE_RUSH).get("hi_score", 0)) > 0,
		"the Rush run recorded into the rush bucket")
	_check(int(save._bucket(SaveService.MODE_NORMAL).get("hi_score", 0)) == 240,
		"...and the earlier Normal run's best is still there, untouched")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
