## capture.gd — take screenshots of the REAL game, so the look can be judged
## by looking at it rather than inferred from state assertions.
##
## The source repo's own diagnosis (Suds-Jack CLAUDE.md, Toko Drop section) is
## that its games get stuck at prototype feel because "the smoke gates certify
## *works* and prototype-feel lives entirely in the part they cannot see". This
## is the other half of the gate: tests/smoke.gd proves it works, this proves
## it LOOKS like something.
##
##   godot --path . tools/capture.gd -- [out_dir] [frames_between_shots]
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
	_main.call_deferred("_start_game")
	# Jump the director forward so wave-2+ types appear in the shots.
	var w := int(OS.get_cmdline_user_args()[2]) if OS.get_cmdline_user_args().size() > 2 else 0
	if w > 0:
		_main.call_deferred("_capture_seek_wave", w)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP:
		return false
	if (_frame - WARMUP) % _gap != 0:
		return false

	if _force != "" and _taken == 0:
		var wd = _main.waves
		var e = wd._make(_force)
		wd.enemies_root.add_child(e)
		e.position = Vector3(0.0, 0.0, -4.0)
		e.half_x = _main.HALF_X
		e.half_z = _main.HALF_Z
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
