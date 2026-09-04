## capture.gd — take screenshots of the REAL game, so the look can be judged
## by looking at it rather than inferred from state assertions.
##
## The source repo's own diagnosis (Suds-Jack CLAUDE.md, Toko Drop section) is
## that its games get stuck at prototype feel because "the smoke gates certify
## *works* and prototype-feel lives entirely in the part they cannot see". This
## is the other half of the gate: tests/smoke.gd proves it works, this proves
## it LOOKS like something.
##
##   godot --path . --script tools/capture.gd -- [out_dir] [frames_between_shots] [wave] [menu|rush|spawn:TYPE|pods|ch:N]
##
## Add `seed:HEX` (any position) to pin the run seed for a like-for-like pair.
## Add `level:<id>` (any position) to play an authored level from levels/.
## `--script` is NOT optional: passed positionally, Godot 4 ignores this file
## and simply launches the main scene, which never quits and never writes a
## shot. That is what "capture.gd doesn't work here" was (found 2026-09-04).
## On a machine where the window cannot present frames, add
##   --fixed-fps 60 --write-movie <dir>/f.png --quit-after 150
## and Godot writes every frame itself on a fixed timestep.
## TOKO_TIER=compat|forward_plus in the environment forces the gel tier
## (scripts/render_tier.gd), for photographing one tier on the other renderer.
##
## Writes shot_00.png … to out_dir (default: user:// — printed on exit).
extends SceneTree

const SHOTS := 6
const WARMUP := 30          # let the first wave spawn and the gel settle

var _main: Node
var _frame := 0
var _taken := 0
var _out := ""
var _force := ""
var _gap := 45

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		_gap = int(args[1])
	DirAccess.make_dir_recursive_absolute(_out)

	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	# Drop straight into a run rather than sitting on the menu — the menu is
	# not the thing being judged.
	# arg[3] == "menu" photographs the title screen instead of a run.
	if OS.get_cmdline_user_args().size() > 3 and OS.get_cmdline_user_args()[3] == "menu":
		return
	# arg[3] == "spawn:TYPE" forces one body of that type into the arena, so a
	# bespoke mesh can be looked at without waiting for the budget to buy one.
	if OS.get_cmdline_user_args().size() > 3 			and OS.get_cmdline_user_args()[3].begins_with("spawn:"):
		_force = OS.get_cmdline_user_args()[3].substr(6)
	if OS.get_cmdline_user_args().size() > 3 and OS.get_cmdline_user_args()[3] == "rush":
		_main.set("mode", 2)   # Mode.RUSH
	# "ch:N" plays challenge level N.
	if OS.get_cmdline_user_args().size() > 3 			and OS.get_cmdline_user_args()[3].begins_with("ch:"):
		_main.set("mode", 3)   # Mode.CHALLENGE
		_main.set("challenge_i", int(OS.get_cmdline_user_args()[3].substr(3)))
	# "level:<id>" anywhere in the args plays an authored level (Q-032/Q-037):
	# the file's arena and timeline instead of the director's roll. The seek
	# and the seeded clear below are skipped for it — clear() would empty the
	# level's queue.
	var level := ""
	for a in args:
		if a.begins_with("level:"):
			level = a.substr(6)
	if level != "":
		_main.set("level_id", level)
	_main.call_deferred("_start_game")
	# "seed:HEX" anywhere in the args pins the run's seed (the HUD's SEED
	# line), so two captures on different renderers show the SAME bodies in
	# the SAME places and the only difference left is the renderer. Deferred
	# after _start_game, which would otherwise draw a fresh random seed.
	for a in args:
		if a.begins_with("seed:"):
			var v: int = a.substr(5).hex_to_int()
			# `_main.waves` does not exist until main's _ready() has run, so
			# this must be a deferred CALLABLE, not a deferred call on it.
			(func() -> void:
				_main.waves.reseed(v)
				if level == "":
					_main.waves.clear()   # a level's queue must NOT be cleared
			).call_deferred()
	# Jump the director forward so wave-2+ types appear in the shots.
	var w := int(OS.get_cmdline_user_args()[2]) if OS.get_cmdline_user_args().size() > 2 else 0
	if w > 0 and level == "":
		_main.call_deferred("_capture_seek_wave", w)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP:
		return false
	if (_frame - WARMUP) % _gap != 0:
		return false

	# "pods" scatters one of each weapon pod, so the pickup art can be looked
	# at without waiting for a lucky drop.
	if _force == "pods" and _taken == 0:
		var k := 0
		for id in PowerupPool.PODS.keys():
			_main.pods.drop(-7.0 + float(k) * 2.0, -2.0, id)
			k += 1
		_force = ""
	if _force != "" and _taken == 0:
		var wd = _main.waves
		var e = wd._make(_force)
		wd.enemies_root.add_child(e)
		e.position = Vector3(0.0, 0.0, -4.0)
		e.arena = _main.arena   # Q-035
		e.target = _main.player
		e.bullets = _main.bullets
		e.trails = _main.trails
		e.rng = wd.rng
		e.init()
		wd.enemies.append(e)
		_force = ""

	var img := get_root().get_texture().get_image()
	var path := "%s/shot_%02d.png" % [_out, _taken]
	img.save_png(path)
	print("wrote ", path)
	_taken += 1
	if _taken >= SHOTS:
		print("capture done -> ", _out)
		quit(0)
	return false
