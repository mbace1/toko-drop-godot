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
	_main.call_deferred("_start_game")

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP:
		return false
	if (_frame - WARMUP) % _gap != 0:
		return false

	var img := get_root().get_texture().get_image()
	var path := "%s/shot_%02d.png" % [_out, _taken]
	img.save_png(path)
	print("wrote ", path)
	_taken += 1
	if _taken >= SHOTS:
		print("capture done -> ", _out)
		quit(0)
	return false
