## main.gd
##
## Godot equivalent of toko-drop/js/main.js: builds the scene, owns the game
## states (menu/playing/paused/dead), runs the collision loop and updates the
## HUD. Everything is built in code rather than as hand-authored child scenes
## (mirrors main.js building the THREE.Scene programmatically), which keeps
## the single .tscn file trivial and avoids scene-file merge conflicts as the
## port grows.
extends Node3D

## The arena is the source's LANDSCAPE preset, not a square
## (main.js ARENA_PRESETS.landscape: halfX 19, halfZ 11). Getting this wrong
## was the single biggest structural difference from the browser build: a
## square 18x18 made every body look huge, left no room to run, and framed
## nothing like the real game. 38 x 22 is a WIDE room you cross.
##
## main.js ALSO has a PORTRAIT preset (halfX 11, halfZ 18 — a TALL room) and
## picks between the two off the actual device's aspect (`landscapeMode =
## innerWidth > innerHeight`), re-deriving on resize/rotation. This port only
## ever had the landscape half — found 2026-08-26 by a real phone in portrait
## showing a landscape level, a landscape camera, and a landscape-sized HUD
## regardless of the actual (tall) screen. `HALF_X`/`HALF_Z` below are now
## the CURRENT preset's numbers, not a constant — `_apply_orientation()`
## picks one before anything gets built.
const HALF_X_LANDSCAPE := 19.0
const HALF_Z_LANDSCAPE := 11.0
const CAM_REST_LANDSCAPE := Vector3(0.0, 20.5, 13.5)
const CAM_LOOK_LANDSCAPE := Vector3(0.0, 0.0, 2.5)

const HALF_X_PORTRAIT := 11.0
const HALF_Z_PORTRAIT := 18.0
const CAM_REST_PORTRAIT := Vector3(0.0, 27.0, 21.0)
const CAM_LOOK_PORTRAIT := Vector3(0.0, 0.0, -3.0)

var HALF_X := HALF_X_LANDSCAPE
var HALF_Z := HALF_Z_LANDSCAPE
## main.js: `landscapeMode = innerWidth > innerHeight`.
var landscape_mode := true
var _cam_rest_base := CAM_REST_LANDSCAPE
var _cam_look_base := CAM_LOOK_LANDSCAPE

## The LIVE arena size. `HALF_X`/`HALF_Z` above are the current preset's
## default room; a challenge level may shrink it further (CLOSE QUARTERS),
## and the floor, rails, grid, spawn ring and every clamp all read these
## rather than the constants.
var half_x := HALF_X
var half_z := HALF_Z

## main.js GRID_CELL — world units per floor-grid cell, chosen to keep the
## Shown in the corner, the way the browser prints v221.
const VERSION := "2.1"

## cells square on a non-square arena.
const GRID_CELL := 1.286

## main.js drops a pod from roughly one kill in twelve.
const POD_CHANCE := 0.085

## main.js: scene.background 0x0d0d1a, fog 0x0d0d1a from 42 to 80.
const VOID_COLOR := Color(0.051, 0.051, 0.102)

const FLOOR_SHADER := preload("res://shaders/floor_grid.gdshader")

enum State { MENU, PLAYING, PAUSED, DEAD }

## The front-page mode list, in the browser build's order: ROGUELIKE MODE
## first, RUSH MODE directly under it (owner direction, 2026-08-24).
##
## RUSH is designed in RUSH_MODE.md and NOT implemented yet — its §5 questions
## are open, and guessing at heat/boost rules before they are answered is how a
## mode ends up with a ruleset nobody chose. Selecting it today starts an
## ordinary run with `mode` set, so the plumbing is real and the rules land in
## one place when they are decided.
enum Mode { CLASSIC, ROGUELIKE, RUSH, CHALLENGE, DAILY }

const MODE_ROWS := [
	{"mode": Mode.ROGUELIKE, "label": "ROGUELIKE MODE",
	 "note": "no upgrades — pure arcade survival", "ready": false},
	{"mode": Mode.RUSH, "label": "RUSH MODE",
	 "note": "boost to kill — shoot and you lose your shield", "ready": true},
	{"mode": Mode.CHALLENGE, "label": "CHALLENGES",
	 "note": "levels, each with its own rule — reach C to open the next",
	 "ready": true},
	{"mode": Mode.DAILY, "label": "DAILY RUN",
	 "note": "same seed as everyone today, worldwide — no upgrades", "ready": true},
]

var state := State.MENU
var score := 0
var mode := Mode.CLASSIC
var _menu_row := 0        # which mode row the selector is on; -1 = none
## Campaign state. `challenge_i` is which level is loaded; the rule it
## carries is read once at run start and then the loop just plays.
var challenge_i := 0
var _ch_clock := 0.0
var _ch_rule: int = Challenges.Rule.NONE

var player: Player
var bullets: BulletPool
var trails: TrailPool
var poison: PoisonField
var debris: DebrisPool
var pods: PowerupPool
var cargo: CargoCluster
## v175 "living-arena objectives" — one at a time, unresolved ones vanish at
## the next wave's setup rather than carrying over.
var vault: VaultCrate
var escort: EscortBot
## v175 gates: up to 2 alive at once, one new one added most waves — these
## persist ACROSS waves (unlike vault/escort), so they live in their own
## array rather than being cleared by `_clear_arena_objectives()`.
var gates: Array[Gate] = []
var gate_chain_t := 0.0
var gate_chain_n := 0
## CLEANSE FOAM: also persists across waves (its own 12s life or a cleanse
## ends it, never a new wave on its own) — same reason it is not swept by
## `_clear_arena_objectives()` either.
var foam_zones: Array[FoamZone] = []
## Seconds into the CURRENT wave the convoy fires (main.js clusterSpawnAt,
## "3-8s into the wave — always overlaps live enemies"); -1 once spent.
var _cargo_spawn_at := -1.0
var _cargo_wave_t := 0.0
## Normal mode has no chain of its own; the browser gives it a STREAK that
## climbs per kill and resets when you are hit.
var streak := 0
var _weapon_name := "SINGLE"
## main.js GRAZE (v125): bullets skimmed past while vulnerable, once each.
## Rewards weaving through fire without touching it; i-frames (dash, Rush
## boost) pay nothing, which is why this only runs where invincible already
## gates the loop below.
var graze_count := 0
## main.js scoreMultT: a 10s x2 SCORE MULTIPLIER, from the "scoremult"
## pickup (cargo convoy / VaultCrate loot). Applies uniformly via
## `_add_score()` rather than being threaded through every individual
## `score +=` site by hand.
var score_mult_t := 0.0
## DAILY RUN (main.js v130/v179). "" off-daily/Classic; else "glass" / "surge"
## / "rich" for today's twist, from a 4-day rotation everyone worldwide is on
## at once (Daily.mod_for, pure date math, no server). Kept here (not just on
## WaveDirector) because GLASS is a player stat, not a spawn one.
var daily_mod := ""
var _toast: Label
var _toast_t := 0.0
## Camera shake as main.js does it: a TRAUMA value events add to, decaying on
## its own, with the offset driven by trauma SQUARED. Squaring is what stops a
## stream of small hits reading as a constant judder while a kill still lands.
var _trauma := 0.0
var _cam_rest := Vector3.ZERO
var waves: WaveDirector
var input_mgr: InputManager
var camera: Camera3D
var audio: AudioKit
var save: SaveService
var sticks: TouchSticks

var rush: RushRules
var _rush_label: Label
var _wave_bar: ProgressBar
var _corner_l: Label
var _corner_r: Label
var _death_wash: ColorRect
## Wall-clock length of the current run. The browser treats time survived as
## a headline stat on the death screen; this port had no notion of it.
var _run_t := 0.0
var feedback: Feedback
## What landed the fatal blow. The death screen shows it and asks about it,
## so the question is about something you just lived through rather than a
## generic form every player sees forever (browser build, v212).
var _killed_by := ""
var _killed_how: int = Feedback.Cause.UNKNOWN
var _crowd_at_death := 0
var _fb_panel: PanelContainer
var _fb_prompt: Label
var _fb_answer: LineEdit
var _fb_status: Label
var _fb_id := ""
var _fb_liked: Array = []
var _fb_wrong: Array = []
var _floor_mat: ShaderMaterial
var _floor_inst: MeshInstance3D
var _rails: Array[MeshInstance3D] = []
var hud: CanvasLayer
var _hp_label: Label
var _wave_label: Label
var _score_label: Label
var _msg_label: Label

## main.js's own check, ported verbatim: the ACTUAL device/window aspect,
## not a stored preference — a game that opens portrait and gets rotated
## mid-title-screen should pick up the new shape (see the resize hook below).
func _detect_landscape() -> bool:
	var sz := get_viewport().get_visible_rect().size
	# >=, not >: a perfectly square viewport never happens on a real device
	# (headless test contexts report a dummy 100x100, though — see
	# tests/smoke.gd), and defaulting a tie to landscape is what the whole
	# existing test suite (half_x=19 assumed throughout) already expects.
	return sz.x >= sz.y

func _apply_orientation() -> void:
	_set_orientation(_detect_landscape())

## Split from _apply_orientation() so a test can drive the preset-selection
## logic directly, without needing to fake an actual window resize to
## exercise the portrait branch.
func _set_orientation(is_landscape: bool) -> void:
	landscape_mode = is_landscape
	HALF_X = HALF_X_LANDSCAPE if landscape_mode else HALF_X_PORTRAIT
	HALF_Z = HALF_Z_LANDSCAPE if landscape_mode else HALF_Z_PORTRAIT
	_cam_rest_base = CAM_REST_LANDSCAPE if landscape_mode else CAM_REST_PORTRAIT
	_cam_look_base = CAM_LOOK_LANDSCAPE if landscape_mode else CAM_LOOK_PORTRAIT

## main.js: "Re-derive orientation while on the title screen: rotating the
## device flips it... the next run picks up the new orientation instead" —
## a live rotation mid-run would teleport the arena under the player, so
## this only actually re-derives while at the menu.
func _on_viewport_resized() -> void:
	if camera == null or state != State.MENU:
		return   # a resize before setup finishes, or mid-run — ignore it
	if _detect_landscape() == landscape_mode:
		return
	_apply_orientation()
	half_x = HALF_X
	half_z = HALF_Z
	waves.half_x = half_x
	waves.half_z = half_z
	_resize_arena()

func _ready() -> void:
	_apply_orientation()
	half_x = HALF_X
	half_z = HALF_Z
	get_viewport().size_changed.connect(_on_viewport_resized)
	_setup_world()
	_setup_camera()

	player = Player.new()
	add_child(player)
	player.build()   # don't rely on _ready() timing — see BulletPool.build()

	bullets = BulletPool.new()
	add_child(bullets)
	bullets.build()

	trails = TrailPool.new()
	add_child(trails)
	trails.build()

	poison = PoisonField.new()
	add_child(poison)
	poison.build()

	debris = DebrisPool.new()
	add_child(debris)
	debris.build()

	pods = PowerupPool.new()
	add_child(pods)
	pods.build()
	pods.taken.connect(_on_pod_taken)
	pods.value_taken.connect(_on_value_taken)

	cargo = CargoCluster.new()
	add_child(cargo)
	vault = null
	escort = null

	var enemies_root := Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	waves = WaveDirector.new()
	add_child(waves)
	waves.half_x = half_x
	waves.half_z = half_z
	waves.target = player
	waves.bullets = bullets
	waves.trails = trails
	waves.poison = poison
	waves.enemies_root = enemies_root
	waves.wave_cleared.connect(_on_wave_cleared)
	waves.wave_started.connect(_on_wave_started)

	input_mgr = InputManager.new()
	input_mgr.camera = camera
	add_child(input_mgr)

	audio = AudioKit.new()
	add_child(audio)
	audio.build()
	player.on_shoot = func(): audio.play_varied("fire")

	save = SaveService.new()
	add_child(save)
	save.load_state()

	feedback = Feedback.new()
	add_child(feedback)

	rush = RushRules.new()
	add_child(rush)
	rush.overheated.connect(func(): audio.play("player"))
	rush.level_changed.connect(func(_n, up): audio.play("wave" if up else "hit"))

	_setup_hud()
	_show_menu()

func _setup_world() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()

	# The visible background stays the browser build's near-black void, but the
	# LIGHTING now comes off a sky. PORT_BRIEF.md §0 notes the source lights its
	# gel with IBL ("RoomEnvironment baked through PMREMGenerator (needed for
	# transmission + clearcoat)") — with a flat ambient colour there is nothing
	# for a clearcoat to reflect, which is most of why the first render came out
	# as matte plastic balls. background_mode and the light sources are separate
	# settings, so the void can stay black while the sky does the lighting.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.13, 0.24)
	sky_mat.sky_horizon_color = Color(0.22, 0.26, 0.36)
	sky_mat.ground_bottom_color = Color(0.04, 0.04, 0.07)
	sky_mat.ground_horizon_color = Color(0.14, 0.15, 0.22)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky

	env.background_mode = Environment.BG_COLOR
	env.background_color = VOID_COLOR
	# main.js: THREE.Fog(0x0d0d1a, 42, 80) — the far corners of a 38-unit-wide
	# arena sit in it, which is what stops the floor reading as a flat cut-out.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = VOID_COLOR
	env.fog_depth_begin = 42.0
	env.fog_depth_end = 80.0
	env.fog_density = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.05          # let the HDR threshold decide, not a floor
	env.glow_hdr_threshold = 0.9   # "only the hottest highlights bloom"
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssr_enabled = true
	# 16 rather than 32: SSR is a full-screen ray march, and the arena's floor
	# reflections do not need the extra steps to read — part of the 60fps pass.
	env.ssr_max_steps = 16
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env_node.environment = env
	add_child(env_node)

	# Key light — the source's single directional at intensity 1.3.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	# Back light. SSS TRANSMITTANCE is light passing THROUGH a body, so it can
	# only read when something is lit from behind relative to the camera — with
	# only a key light overhead the gel scatters into nothing and stays opaque.
	# The camera sits on +Z, so this fires from the far side of the arena back
	# toward it, and every body gets a translucent edge as it crosses.
	var back := DirectionalLight3D.new()
	back.light_energy = 1.5
	back.light_color = Color(0.72, 0.84, 1.0)
	back.rotation_degrees = Vector3(-18.0, 180.0, 0.0)
	# No shadow map: this light exists only to give SSS TRANSMITTANCE something
	# to carry (gel.gdshader's header), never to cast a visible shadow. A
	# second shadow-casting light doubles the shadow pass cost for a shadow
	# nobody was meant to see — part of the 60fps pass (owner direction).
	back.shadow_enabled = false
	add_child(back)

	_floor_inst = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half_x * 2.0, half_z * 2.0)
	_floor_inst.mesh = pm
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = FLOOR_SHADER
	_floor_mat.set_shader_parameter("u_grid_x", (half_x * 2.0) / GRID_CELL)
	_floor_mat.set_shader_parameter("u_grid_z", (half_z * 2.0) / GRID_CELL)
	_floor_inst.material_override = _floor_mat
	add_child(_floor_inst)

	_add_arena_edge()

## The playfield needs a BOUNDARY you can see. Without one the floor read as a
## grey trapezoid cut out of the void, and the wall you are actually clamped
## against (player.gd / enemy.gd clamp to half_x/half_z) was invisible — so the
## arena had an edge in the simulation and none on screen.
##
## Four thin emissive rails on the clamp line, dim enough not to compete with
## the bodies but bright enough to catch the glow pass.
func _add_arena_edge() -> void:
	var rail_mat := StandardMaterial3D.new()
	# main.js `border` is LineSegments in 0x5555cc — a cool violet-blue.
	rail_mat.albedo_color = Color(0.10, 0.11, 0.22)
	rail_mat.emission_enabled = true
	rail_mat.emission = Color(0.333, 0.333, 0.80)
	rail_mat.emission_energy_multiplier = 1.5
	rail_mat.roughness = 0.4

	var h := 0.16
	var t := 0.10
	for i in 4:
		var horizontal := i < 2
		var bm := BoxMesh.new()
		if horizontal:
			bm.size = Vector3(half_x * 2.0 + t * 2.0, h, t)
		else:
			bm.size = Vector3(t, h, half_z * 2.0 + t * 2.0)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = rail_mat
		match i:
			0: mi.position = Vector3(0.0, h * 0.5, -half_z - t * 0.5)
			1: mi.position = Vector3(0.0, h * 0.5, half_z + t * 0.5)
			2: mi.position = Vector3(-half_x - t * 0.5, h * 0.5, 0.0)
			3: mi.position = Vector3(half_x + t * 0.5, h * 0.5, 0.0)
		add_child(mi)
		_rails.append(mi)

func _setup_camera() -> void:
	# The source's camera, verbatim per orientation (main.js ARENA_PRESETS):
	# landscape camRest [0, 20.5, 13.5] / camLook [0, 0, 2.5]; portrait
	# camRest [0, 27, 21] / camLook [0, 0, -3]. PerspectiveCamera fov 60 in
	# both. Looking slightly PAST the centre is what tips the far half of the
	# arena up into the frame and gives the browser build its shallow read —
	# `_apply_orientation()` (called before this, in _ready()) already picked
	# which pair applies.
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.position = _cam_rest_base
	add_child(camera)
	camera.look_at(_cam_look_base, Vector3.UP)
	camera.current = true
	_cam_rest = camera.position

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	# Top-left stack: WAVE, the progress bar, then the HP pips — the browser
	# build's arrangement (js/main.js drawHud).
	var left := VBoxContainer.new()
	left.position = Vector2(16, 12)
	left.add_theme_constant_override("separation", 4)
	hud.add_child(left)

	_wave_label = _make_label(20)
	left.add_child(_wave_label)

	_wave_bar = ProgressBar.new()
	_wave_bar.custom_minimum_size = Vector2(140, 4)
	_wave_bar.show_percentage = false
	_wave_bar.max_value = 1.0
	_wave_bar.step = 0.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.667, 0.133)      # #ffaa22
	_wave_bar.add_theme_stylebox_override("background", track)
	_wave_bar.add_theme_stylebox_override("fill", fill)
	left.add_child(_wave_bar)

	_hp_label = _make_label(20)
	left.add_child(_hp_label)

	# Rush's clock and chain sit UNDER the stack rather than fighting the
	# centre for space (owner direction).
	_rush_label = _make_label(18)
	_rush_label.hide()
	left.add_child(_rush_label)

	_score_label = _make_label(22)
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_score_label.position = Vector2(-16, 12)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(_score_label)

	# Death wash. The browser floods the whole screen red on death and it is
	# most of why dying LANDS; a text swap alone reads as a menu appearing.
	_death_wash = ColorRect.new()
	_death_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_wash.color = Color(0.55, 0.02, 0.05, 0.0)
	_death_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_death_wash)

	_msg_label = _make_label(28)
	_msg_label.set_anchors_preset(Control.PRESET_CENTER)
	_msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(_msg_label)

	# The corners the browser build uses: version and frame rate bottom-left,
	# the run seed bottom-right.
	_corner_l = _make_label(13)
	_corner_l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35, 0.55))
	_corner_l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_corner_l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_corner_l.position = Vector2(16, -30)
	hud.add_child(_corner_l)

	_corner_r = _make_label(13)
	_corner_r.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0, 0.55))
	_corner_r.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_corner_r.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_corner_r.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_corner_r.position = Vector2(-16, -30)
	_corner_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(_corner_r)

	_toast = _make_label(24)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 90.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.hide()
	hud.add_child(_toast)

	_build_feedback_panel()

	sticks = TouchSticks.new()
	sticks.input_mgr = input_mgr
	hud.add_child(sticks)

## The death-screen question. Hidden until a run ends; never shown on the
## menu, because there is nothing to ask about yet.
func _build_feedback_panel() -> void:
	_fb_panel = PanelContainer.new()
	_fb_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_fb_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fb_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fb_panel.position = Vector2(0, -24)
	_fb_panel.custom_minimum_size = Vector2(720, 0)
	_fb_panel.hide()
	hud.add_child(_fb_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_fb_panel.add_child(col)

	_fb_prompt = _make_label(17)
	_fb_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fb_prompt.custom_minimum_size = Vector2(700, 0)
	col.add_child(_fb_prompt)

	_fb_answer = LineEdit.new()
	_fb_answer.placeholder_text = "anything else? (optional)"
	_fb_answer.custom_minimum_size = Vector2(700, 44)
	col.add_child(_fb_answer)

	col.add_child(_chip_row("what landed", Feedback.LIKED, _fb_liked))
	col.add_child(_chip_row("what went wrong", Feedback.WRONG, _fb_wrong))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)

	var send := Button.new()
	send.text = "SEND"
	send.custom_minimum_size = Vector2(150, 44)
	send.pressed.connect(_send_feedback)
	row.add_child(send)

	var skip := Button.new()
	skip.text = "SKIP"
	skip.custom_minimum_size = Vector2(150, 44)
	# SKIP sends nothing. Explicit consent by design.
	skip.pressed.connect(func():
		_fb_panel.hide()
		_msg_label.position.y = 0.0)
	row.add_child(skip)

	_fb_status = _make_label(14)
	_fb_status.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	row.add_child(_fb_status)

## A row of toggle chips. 44px minimum, because this has to work under a
## thumb like everything else.
func _chip_row(title: String, options: Array, into: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lab := _make_label(14)
	lab.text = title
	lab.custom_minimum_size = Vector2(140, 44)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lab)
	for opt in options:
		var b := Button.new()
		b.text = String(opt)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 44)
		b.toggled.connect(func(on: bool):
			if on and not into.has(opt):
				into.append(opt)
			elif not on:
				into.erase(opt))
		row.add_child(b)
	return row

## Opens the panel with a question about the run that just ended.
func _open_feedback() -> void:
	var pick := feedback.pick(_killed_how, _killed_by, _crowd_at_death)
	_fb_id = pick["id"]
	_fb_prompt.text = pick["question"]
	_fb_answer.text = ""
	_fb_liked.clear()
	_fb_wrong.clear()
	_fb_status.text = ""
	_fb_panel.show()
	# The panel owns the bottom of the screen while it is open, so lift the
	# summary clear of it — the retry line was being printed underneath it.
	_msg_label.position.y = -120.0

func _send_feedback() -> void:
	var run := {
		"mode": _cur_mode_key(), "score": score,
		"wave": waves.wave, "seed": waves.seed_text(),
		"killed_by": _killed_by,
	}
	var r := feedback.submit(_fb_id, _fb_answer.text, _fb_liked, _fb_wrong, run)
	# Saying nothing records nothing, and nothing claims a delivery that has
	# not happened — "saved" is the truthful word for a fire-and-forget POST.
	_fb_status.text = "" if r == "" else "saved — thank you"
	if r != "":
		_fb_panel.hide()
		_msg_label.position.y = 0.0

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	return l

func _process(delta: float) -> void:
	# The floor pulses on its own clock even on the menu — a still first screen
	# reads as a broken page.
	_floor_mat.set_shader_parameter("u_time", Time.get_ticks_msec() / 1000.0)

	if input_mgr.pause_pressed():
		if state == State.PLAYING:
			state = State.PAUSED
			_msg_label.text = "PAUSED\n\npress PAUSE to resume"
			_msg_label.show()
		elif state == State.PAUSED:
			state = State.PLAYING
			_msg_label.hide()

	match state:
		State.PLAYING:
			_process_playing(delta)
		State.MENU, State.DEAD:
			# Up/down walks the mode rows; anything else starts the run.
			# Left/right picks the Rush ability, so the choice is made before
			# the run rather than mid-fight.
			# Left/right walks the UNLOCKED challenge levels, skipping locked
			# ones rather than stopping on them.
			if MODE_ROWS[_menu_row]["mode"] == Mode.CHALLENGE \
					and (Input.is_action_just_pressed("move_left") \
					or Input.is_action_just_pressed("move_right")):
				var step := 1 if Input.is_action_just_pressed("move_right") else -1
				var n := Challenges.count()
				for _try in n:
					challenge_i = (challenge_i + step + n) % n
					if Challenges.unlocked(challenge_i, save):
						break
				_msg_label.text = _menu_text()
				return
			if MODE_ROWS[_menu_row]["mode"] == Mode.RUSH \
					and (Input.is_action_just_pressed("move_left") \
					or Input.is_action_just_pressed("move_right")):
				rush.cycle_ability(1 if Input.is_action_just_pressed("move_right") else -1)
				_msg_label.text = _menu_text()
				return
			if Input.is_action_just_pressed("move_down"):
				_menu_row = mini(_menu_row + 1, MODE_ROWS.size() - 1)
				_msg_label.text = _menu_text()
			elif Input.is_action_just_pressed("move_up"):
				_menu_row = maxi(_menu_row - 1, 0)
				_msg_label.text = _menu_text()
			elif input_mgr.dash_pressed() or Input.is_action_just_pressed("fire") \
					or input_mgr.left.active or input_mgr.right.active:
				var row: Dictionary = MODE_ROWS[_menu_row]
				mode = row["mode"] if row["ready"] else Mode.CLASSIC
				if mode == Mode.CHALLENGE and not Challenges.unlocked(challenge_i, save):
					challenge_i = 0
				_start_game()

	_update_shake(delta)
	_update_toast(delta)
	_update_adaptive_quality()
	_update_wash(delta)
	_update_hud()

func _process_playing(delta: float) -> void:
	_run_t += delta
	var move := input_mgr.get_move_dir()
	var aim := input_mgr.get_aim_dir(player.position)
	var firing: bool = aim["valid"]
	# BOOST ONLY disables the gun outright — the level's whole rule.
	if _ch_rule == Challenges.Rule.BOOST_ONLY:
		aim = {"x": 0.0, "z": 0.0, "valid": false}
		firing = false

	if mode == Mode.RUSH or mode == Mode.CHALLENGE:
		_process_rush(delta, firing)
		if mode == Mode.CHALLENGE:
			_ch_clock -= delta
			if _ch_clock <= 0.0:
				_finish_challenge()
				return
	elif input_mgr.dash_pressed():
		var was_ready := player.can_dash()
		player.dash(aim)
		if was_ready:
			audio.play("dash")

	player.update(delta, move, aim, bullets, half_x, half_z)
	bullets.update(delta, maxf(half_x, half_z), player.position)
	trails.update(delta)
	poison.update(delta)
	debris.update(delta)
	pods.update(delta, player.position, _run_t)
	if score_mult_t > 0.0:
		score_mult_t = maxf(0.0, score_mult_t - delta)
	if _base_mode():
		_update_cargo(delta)
		_update_arena_objectives(delta)
		_update_gates(delta)
		_update_foam_zones(delta)
	# Standing in sludge costs you, long after the body that laid it died.
	if player.alive and not player.invincible \
			and poison.damages_at(player.position.x, player.position.z):
		_note_killer("", Feedback.Cause.HAZARD)
		_damage_player()
	waves.update(delta)

	_collide_player_bullets()
	_collide_enemy_bullets()
	_collide_contact()
	_collide_bambu_lobs()
	_apply_magna_pull(delta)
	_collide_cargo_bullets()

	if not player.alive:
		_on_player_dead()

## One damage path for both rulesets. Rush spends a LIFE and drops the
## chain; classic spends HP. Both take the mercy window, so a single frame
## can never cost two.
## Player shots vs. enemy bodies. A method, not an inline loop, so the gate
## can drive it: these were only reachable through _process_playing() (which
## needs live input), and that is exactly how a bug that made player bullets
## damage the PLAYER shipped past a green suite.
func _collide_player_bullets() -> void:
	for e in waves.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		for b in bullets.active:
			if not b.alive or not b.is_player:
				continue
			var dx := b.x - e.position.x
			var dz := b.z - e.position.z
			var r := e.radius + 0.15
			if dx * dx + dz * dz >= r * r:
				continue
			# BULWARK shrugs off anything landing on its front plate, and a
			# WARDEN's umbrella protects everything under it. Both consume the
			# shot rather than passing it through, so a blocked hit still costs
			# you the bullet — and both are VISIBLE, because a shot that stops
			# working with no explanation reads as a bug.
			if e is Bulwark and (e as Bulwark).blocks(b.x, b.z):
				b.alive = false
				audio.play_varied("hit")
				continue
			if _shielded(e):
				b.alive = false
				audio.play_varied("hit")
				continue
			b.alive = false
			var was_max := e.max_hp
			if e.take_hit(1):
				if _rush_verbs():
					_add_score(rush.award(100 * was_max))
				else:
					# main.js onKill(): "streak++; score += 100 * streak * ..." —
					# a COMBO multiplier, not a per-body value keyed to the
					# thing's own toughness. Rush keeps its own chain
					# (`rush.multiplier`) and formula; this was a real
					# discrepancy in the base-mode path, found (not caused) by
					# porting Gates — the old `100 * max_hp` here never
					# actually matched the browser.
					streak += 1
					_add_kill_score(100 * streak)
				# main.js drops a weapon pod from a kill now and then. Bounded, so
				# a good wave does not carpet the floor with shopping.
				if not _rush_verbs() and waves.rng.randf() < POD_CHANCE:
					pods.drop(e.position.x, e.position.z, pods.roll(waves.wave, waves.rng))
				audio.play_varied("kill")
				# TUNING.fx: killDroplets 22 / killChunks 5.
				debris.burst(e.position.x, e.position.z, 22, e.color, e.radius * 0.26)
				debris.burst(e.position.x, e.position.z, 5, e.color, e.radius * 0.5, 4.0, 7.0)
				add_shake(0.12)
			else:
				audio.play_varied("hit")
				# TUNING.fx.hitDroplets 8 — a hit SPITS, a kill bursts.
				debris.burst(b.x, b.z, 8, e.color, e.radius * 0.15, 3.4, 3.0)
				break

## Enemy shots vs. the player. QUANTUM SHIELD belongs HERE — it turns
## incoming fire into outgoing fire, and is the one ability that pays you
## for standing and shooting.
## Is this body under a live WARDEN's umbrella? The warden never shields
## itself, which is what keeps the rule fair: there is always something you
## can shoot.
func _shielded(e: Enemy) -> bool:
	for w in waves.enemies:
		if not is_instance_valid(w) or not w.alive or not (w is Warden):
			continue
		if (w as Warden).shields(e):
			return true
	return false

func _collide_enemy_bullets() -> void:
	if not player.alive or player.invincible:
		return
	for b in bullets.active:
		if not b.alive or b.is_player:
			continue
		var dx := b.x - player.position.x
		var dz := b.z - player.position.z
		var d2 := dx * dx + dz * dz
		var br := BulletPool.FAT_BULLET_R if b.fat else BulletPool.BULLET_R
		var hit_r := br + Player.RADIUS
		if d2 < hit_r * hit_r:
			# main.js `break`s the loop the instant a bullet actually hits —
			# only the first colliding bullet in a frame counts, so a graze
			# never gets checked for one that just connected.
			if _rush_verbs() and rush.reflecting():
				bullets.spawn_dir(b.x, b.z, -b.vx, -b.vz, true)
				b.alive = false
				return
			b.alive = false
			_note_killer(_bullet_owner_name(b), Feedback.Cause.BULLET)
			_damage_player()
			return
		# GRAZE (main.js v125): a bullet skimming past pays score once. No
		# break here — the browser keeps checking every remaining bullet for
		# a graze each frame, and only a hit ends the loop early. Respects
		# scoreMultT via _add_score(); grazeMult (a separate "GRAZE" powerup
		# card, x3) isn't ported — no drop source rolls for it in this port.
		var graze_r := hit_r + 0.55
		if not b.grazed and d2 < graze_r * graze_r:
			b.grazed = true
			graze_count += 1
			_add_score(25)
			audio.play_varied("graze")
			debris.burst(b.x, b.z, 1, Color(1.0, 1.0, 1.0), 0.06, 3.0, 2.5)

## Bodies touching the player. In Rush a BOOSTING player kills instead of
## being hurt, which is the whole mode; that branch runs first.
func _collide_contact() -> void:
	if not player.alive:
		return
	if _rush_verbs() and rush.boosting:
		for e in waves.enemies:
			if not is_instance_valid(e) or not e.alive:
				continue
			var bdx := e.position.x - player.position.x
			var bdz := e.position.z - player.position.z
			var br := e.radius + Player.RADIUS
			if bdx * bdx + bdz * bdz < br * br:
				var bmax := e.max_hp
				if e.take_hit(99):
					rush.add_boost_kill()
					_add_score(rush.award(100 * bmax))
					audio.play_varied("kill")
					debris.burst(e.position.x, e.position.z, 22, e.color, e.radius * 0.30)
					add_shake(0.16)
		return
	if player.invincible:
		return
	for e in waves.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var dx := e.position.x - player.position.x
		var dz := e.position.z - player.position.z
		var r := e.radius + Player.RADIUS
		if dx * dx + dz * dz < r * r:
			_note_killer(e.display_name(), Feedback.Cause.MELEE)
			_damage_player()
			return

## BAMBU (main.js "Part 5"): a landed lob deals splash damage ONLY if the
## player is still standing in the landing ring when it lands — the ring
## flashed and the blob arced in visibly, so a hit here was avoidable. A
## method of its own for the usual reason: this is a hazard, not a bullet or
## a body touch, so neither of the two collision loops above would ever see
## it, and a system only reachable through input is a system the gate cannot
## see (see CLAUDE.md / PORT_STATUS.md's collision-bug postmortem).
func _collide_bambu_lobs() -> void:
	for e in waves.enemies:
		if not is_instance_valid(e) or not (e is Bambu):
			continue
		var landed = (e as Bambu).drain_landed()
		if landed == null:
			continue
		var lob: Vector2 = landed
		debris.burst(lob.x, lob.y, 10, Color(0.867, 0.733, 0.267), 0.11, 4.0, 4.0)
		add_shake(0.12)
		audio.play_varied("hit")
		if not player.alive or player.invincible:
			continue
		var dx := player.position.x - lob.x
		var dz := player.position.z - lob.y
		var rr := Bambu.RING_OUTER + Player.RADIUS
		if dx * dx + dz * dz < rr * rr:
			_note_killer("bambu lobber", Feedback.Cause.HAZARD)
			_damage_player()

## Gates persist across waves, so their own clock (chain window, pulse/
## risk-cycle/drift) runs every frame in base mode regardless of what the
## vault/escort/cargo clocks are doing.
func _update_gates(delta: float) -> void:
	if gate_chain_t > 0.0:
		gate_chain_t -= delta
		if gate_chain_t <= 0.0:
			gate_chain_n = 0
	for g in gates:
		g.update(delta, _run_t, half_x, half_z)
	_collide_gates()

## Two independent interactions per gate, per frame: the PLAYER dashing
## through pays out (or, on a red RISK gate, is a harmless dud); any ENEMY
## touching the beam takes damage on a 0.5s-per-gate cooldown, unconditional
## on risk/colour — the beam is armed for enemies whenever it's alive.
func _collide_gates() -> void:
	for g in gates:
		if not g.alive:
			continue
		if player.alive and g.hits_point(player.position.x, player.position.z, Player.RADIUS) 				and player.dashing:
			_use_gate(g)
			if not g.alive:
				continue   # deactivated by _use_gate(); no longer a hazard either
		if g.dmg_cooldown <= 0.0:
			for e in waves.enemies:
				if not is_instance_valid(e) or not e.alive:
					continue
				if not g.hits_point(e.position.x, e.position.z, e.radius * 0.5):
					continue
				# main.js: "gate lasers, vents, and suds walls vaporize
				# cleanly" — env kills skip the revenge volley there. This
				# port's revenge fire runs from WaveDirector's own corpse
				# sweep, not from the collision site, so it isn't suppressed
				# here — a documented divergence, not an oversight.
				if e.take_hit(1):
					streak += 1
					_add_kill_score(100 * streak)
					debris.burst(e.position.x, e.position.z, 22, e.color, e.radius * 0.26)
					audio.play_varied("kill")
				else:
					audio.play_varied("hit")
				g.dmg_cooldown = Gate.DMG_COOLDOWN
				break

## The player dashed through a live gate: RISK+red is a dud (deactivates,
## pays nothing); otherwise it drops one random buff (TWO, offset, on
## RISK+green — "GREEN RUSH! DOUBLE PRIZE") and, if another gate was banked
## within the last 6s, a climbing GATE CHAIN bonus.
func _use_gate(g: Gate) -> void:
	g.deactivate()
	if g.risk and not g.green:
		_show_toast("DUD! GREEN MEANS GO")
		audio.play_varied("hit")
		return
	debris.burst(g.position.x, g.position.z, 14, Color(0.267, 1.0, 0.533), 0.13, 5.5, 1.0)
	add_shake(0.14)
	audio.play_varied("kill")
	var gate_types := ["hp", "invincible", "firerate", "scoremult"]
	pods.drop(g.position.x, g.position.z, gate_types[waves.rng.randi() % gate_types.size()])
	if g.risk:
		pods.drop(g.position.x + 1.2, g.position.z, gate_types[waves.rng.randi() % gate_types.size()])
		_show_toast("GREEN RUSH! DOUBLE PRIZE")
	gate_chain_n = gate_chain_n + 1 if gate_chain_t > 0.0 else 1
	gate_chain_t = 6.0
	if gate_chain_n >= 2:
		var before := score
		_add_score(500 * gate_chain_n)
		_show_toast("GATE CHAIN x%d! +%d" % [gate_chain_n, score - before])
		audio.play("wave")

## CLEANSE FOAM: standing inside charges it, leaving decays it, full charge
## clears every enemy bullet on screen and pays per bullet cleared.
## Independent of the vault/escort/gate clocks — its own array, own
## per-instance life/burst timers.
func _update_foam_zones(delta: float) -> void:
	for i in range(foam_zones.size() - 1, -1, -1):
		var fz: FoamZone = foam_zones[i]
		var keep := fz.update(delta, player.position, player.alive, _run_t)
		if fz.is_charged():
			fz.begin_cleanse()
			_cleanse_foam(fz)
		if not keep:
			foam_zones.remove_at(i)
			fz.queue_free()

func _cleanse_foam(fz: FoamZone) -> void:
	var n := 0
	for b in bullets.active:
		if not b.alive or b.is_player:
			continue
		b.alive = false
		n += 1
	debris.burst(fz.position.x, fz.position.z, 10, Color(0.8, 0.965, 1.0), 0.1, 3.0, 2.5)
	_add_score(500 + n * 10)   # main.js: "pays per bullet cleared"
	add_shake(0.18)
	audio.play("wave")
	_show_toast("CLEANSED!")

func _clear_arena_objectives() -> void:
	if is_instance_valid(vault):
		vault.queue_free()
	vault = null
	if is_instance_valid(escort):
		escort.queue_free()
	escort = null

## v175 "living-arena objectives": the vault takes hits and pings the room;
## the escort bot crosses the arena and dies to stray fire or a melee touch,
## paying on delivery. Base/Classic mode only, same reason as the cargo
## convoy above.
func _update_arena_objectives(delta: float) -> void:
	if vault != null:
		vault.update(delta)
		_collide_vault()
	if escort != null:
		var arrived := escort.update(delta)
		var bot_dead := _collide_escort()
		if bot_dead:
			_escort_died()
		elif arrived:
			_escort_delivered()

## Player bullets vs the vault: every hit PINGS the room — every living
## enemy within SURGE_RADIUS surges toward the player (`Enemy.surge_t`, the
## same field SIREN's scream already drives) — so cracking it open costs
## something, not a free chest.
func _collide_vault() -> void:
	for b in bullets.active:
		if not b.alive or not b.is_player:
			continue
		var dx := b.x - vault.position.x
		var dz := b.z - vault.position.z
		if dx * dx + dz * dz >= VaultCrate.HIT_R * VaultCrate.HIT_R:
			continue
		b.alive = false
		vault.hit()
		audio.play_varied("hit")
		for e in waves.enemies:
			if not is_instance_valid(e) or not e.alive:
				continue
			var ex := e.position.x - vault.position.x
			var ez := e.position.z - vault.position.z
			if ex * ex + ez * ez < VaultCrate.SURGE_RADIUS * VaultCrate.SURGE_RADIUS:
				e.surge_t = maxf(e.surge_t, VaultCrate.SURGE_DUR)
		if vault.cracked():
			_crack_vault()
		break

func _crack_vault() -> void:
	var vx := vault.position.x
	var vz := vault.position.z
	debris.burst(vx, vz, 12, Color(1.0, 0.8, 0.2), 0.12, 5.0, 2.5)
	add_shake(0.4)
	audio.play("wave")
	pods.drop(vx, vz, pods.roll(waves.wave, waves.rng))
	# main.js's cash cache (800 + wave*60) plus a 40% chance of a second
	# scoremult bonus, at the same offsets from the crate it uses.
	pods.drop(vx + 1.1, vz, "score", 800 + waves.wave * 60)
	if waves.rng.randf() < 0.4:
		pods.drop(vx - 1.1, vz, "scoremult")
	_show_toast("VAULT CRACKED!")
	vault.queue_free()
	vault = null

## Enemy bullets (not the player's) cost the bot HP; any MELEE-attacking body
## touching it kills it outright (main.js's MELEE_TYPES — the ported subset
## of that set is this port's own touch-attacking roster). Returns true the
## instant it's dead, whatever the cause.
func _collide_escort() -> bool:
	for b in bullets.active:
		if not b.alive or b.is_player:
			continue
		var dx := b.x - escort.position.x
		var dz := b.z - escort.position.z
		if dx * dx + dz * dz >= EscortBot.HIT_R * EscortBot.HIT_R:
			continue
		b.alive = false
		escort.hit()
		break
	if escort.dead():
		return true
	for e in waves.enemies:
		if not is_instance_valid(e) or not e.alive or not _is_melee_type(e):
			continue
		var dx := e.position.x - escort.position.x
		var dz := e.position.z - escort.position.z
		var r := e.radius + 0.5
		if dx * dx + dz * dz < r * r:
			return true
	return false

## main.js's MELEE_TYPES, the ported subset: species that attack by TOUCH
## rather than gunfire. Not every non-shooter in this roster is on it —
## SHEPHERD/SIREN/WARDEN/MAGNA have their own non-contact mechanics and
## aren't a bump hazard to a passing bot the way a blob or a cube is.
func _is_melee_type(e: Enemy) -> bool:
	return e is Globbo or e is Splitta or e is Bulwark or e is YelaCube 		or e is SludgeCube or e is ReddCube or e is PurpCube 		or e is ReddMini or e is PurpMini or e is Toro

func _escort_died() -> void:
	debris.burst(escort.position.x, escort.position.z, 6,
		Color(0.267, 0.867, 1.0), 0.14, 3.0, 3.0)
	_show_toast("THE BOT IS DOWN…")
	escort.queue_free()
	escort = null

func _escort_delivered() -> void:
	pods.drop(escort.position.x, escort.position.z, pods.roll(waves.wave, waves.rng))
	_show_toast("ESCORT DELIVERED! ENJOY THE POD")
	escort.queue_free()
	escort = null

## The cargo convoy's per-wave clock. main.js schedules exactly one convoy
## per wave in classic mode (SMASH TV's extra convoys don't apply — this
## port has no room-graph mode); base/Classic mode only, same reason
## _on_wave_started's boss/banner branch is (owner direction 2026-08-25) —
## Rush/Challenge already suppress weapon-pod drops outright, and a convoy's
## whole point is dropping them.
func _update_cargo(delta: float) -> void:
	_cargo_wave_t += delta
	if not cargo.active and _cargo_spawn_at >= 0.0 and _cargo_wave_t >= _cargo_spawn_at:
		cargo.half_x = half_x
		cargo.half_z = half_z
		cargo.spawn(waves.rng)
		_cargo_spawn_at = -1.0   # one convoy per wave
	if cargo.active:
		cargo.update(delta, _run_t)

## Player bullets vs the convoy's moths (main.js ~line 8432). A method of its
## own for the usual reason — this is neither of the two existing collision
## loops' business (moths aren't in `waves.enemies`, and don't touch or shoot
## the player), so nothing else would ever call it.
func _collide_cargo_bullets() -> void:
	if not cargo.active:
		return
	for b in bullets.active:
		if not b.alive or not b.is_player:
			continue
		for i in cargo.drones.size():
			var d: CargoCluster.Drone = cargo.drones[i]
			if not d.alive:
				continue
			var dx := b.x - d.node.position.x
			var dz := b.z - d.node.position.z
			if dx * dx + dz * dz >= CargoCluster.HIT_R * CargoCluster.HIT_R:
				continue
			b.alive = false
			cargo.kill(i)
			add_shake(0.08)
			audio.play_varied("kill")
			debris.burst(d.node.position.x, d.node.position.z, 5,
				Color(1.0, 0.867, 0.333), 0.1, 3.5, 1.0)
			_drop_cargo_loot(d.node.position.x, d.node.position.z)
			break

## main.js: clearing every moth before any escape guarantees a weapon pod;
## otherwise a roll between a pod / an instant score nugget / a SCORE
## MULTIPLIER (classic split 55/25/20).
func _drop_cargo_loot(x: float, z: float) -> void:
	if cargo.all_killed():
		pods.drop(x, z, pods.roll(waves.wave, waves.rng))
		return
	var roll := waves.rng.randf()
	if roll < 0.55:
		pods.drop(x, z, pods.roll(waves.wave, waves.rng))
	elif roll < 0.80:
		pods.drop(x, z, "score", 250 + waves.wave * 25)
	else:
		pods.drop(x, z, "scoremult")

## MAGNA pull (main.js v144, MAGNA_REACH 11 / MAGNA_PULL 1.1 per magna,
## combined cap 2.0/s): every living Magna in reach drags the player toward
## it. Dashing grants ~1.2s of immunity (player.magna_immune_t) — momentum
## breaks the hold. This does not damage the player, so it is not gated on
## `player.invincible` the way _collide_contact()/_collide_bambu_lobs() are;
## a dashing player is IMMUNE to the pull specifically, not to everything.
const MAGNA_REACH := 11.0
const MAGNA_PULL := 1.1
const MAGNA_PULL_CAP := 2.0
const MAGNA_MIN_RANGE := 1.2

func _apply_magna_pull(delta: float) -> void:
	if not player.alive:
		return
	var pull := Vector2.ZERO
	var immune := player.magna_immune_t > 0.0
	for e in waves.enemies:
		if not is_instance_valid(e) or not e.alive or not (e is Magna):
			continue
		var m := e as Magna
		var mx := e.position.x - player.position.x
		var mz := e.position.z - player.position.z
		var md := sqrt(mx * mx + mz * mz)
		var held := not immune and md < MAGNA_REACH and md > MAGNA_MIN_RANGE
		m.pull_active = held
		if held:
			pull += Vector2(mx / md, mz / md) * MAGNA_PULL
	var pl := pull.length()
	if pl > MAGNA_PULL_CAP:
		pull *= MAGNA_PULL_CAP / pl
	if pull != Vector2.ZERO:
		player.position.x = clampf(player.position.x + pull.x * delta,
			-half_x + Player.RADIUS, half_x - Player.RADIUS)
		player.position.z = clampf(player.position.z + pull.y * delta,
			-half_z + Player.RADIUS, half_z - Player.RADIUS)

## Remembers the cause of the most recent hit. Whatever is stored when the
## last life goes is what the death screen asks about.
func _note_killer(who: String, how: int) -> void:
	_killed_by = who
	_killed_how = how
	_crowd_at_death = waves.enemies.size()

## Which species fired a given bullet. The pool carries no owner, so the
## nearest live shooter is the honest guess rather than a false record.
func _bullet_owner_name(b) -> String:
	var best := ""
	var best_d := INF
	for e in waves.enemies:
		if not is_instance_valid(e) or not e.alive or e.fire_interval <= 0.0:
			continue
		var d: float = Vector2(e.position.x - b.x, e.position.z - b.z).length()
		if d < best_d:
			best_d = d
			best = e.display_name()
	return best

func _damage_player() -> void:
	add_shake(0.45)   # the one event you must never miss
	streak = 0   # the browser resets the streak on a hit
	if mode == Mode.RUSH or mode == Mode.CHALLENGE:
		if player.invincible:
			return
		audio.play("player")
		player.start_mercy()
		if rush.take_hit():
			player.die()
		return
	player.hit()
	audio.play("player")

## Rush Mode's frame: heat, boost, the ability and the extra-life award.
func _process_rush(delta: float, firing: bool) -> void:
	input_mgr.poll_edges()
	rush.update(delta, input_mgr.boost_held(), firing)
	waves.level_override = rush.level

	player.rush_shotgun = true
	player.rush_speed_mult = rush.speed_mult()
	player.rush_boosting = rush.boosting
	# Boosting is a shield you drop the moment you pull the trigger.
	player.rush_invuln = rush.invulnerable(firing)

	if input_mgr.ability_pressed():
		_fire_ability()

	if rush.note_score(score):
		audio.play("wave")

## Fires the selected ability. "burst" kinds damage everything in a radius;
## "buff" kinds just start a window that other systems read (OVERCHARGE is
## read by RushRules itself, QUANTUM SHIELD by the bullet loop below).
func _fire_ability() -> void:
	var r := rush.fire_ability()
	if r < 0.0:
		return                     # not charged, or not hot enough
	if r == 0.0:
		audio.play("wave")         # a buff started
		return
	audio.play("dead")
	for e in waves.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var dx := e.position.x - player.position.x
		var dz := e.position.z - player.position.z
		if dx * dx + dz * dz < r * r:
			var m := e.max_hp
			if e.take_hit(99):
				rush.add_boost_kill()
				_add_score(rush.award(100 * m))

func _start_game() -> void:
	state = State.PLAYING
	score = 0
	input_mgr.reset()
	# DAILY RUN: every player on today's UTC date composes off the same seed
	# and gets the same modifier — main.js v130/v179, pure date math so there
	# is nothing to hand out or synchronise.
	waves.budget_mult = 1.0
	waves.rhythm_tight = false
	daily_mod = ""
	if mode == Mode.DAILY:
		var today := Daily.today()
		waves.reseed(Daily.seed_for(today))
		daily_mod = Daily.mod_for(today)
		match daily_mod:
			"rich":
				waves.budget_mult = 1.4    # tuning.js waves.budget.rich, direct port
			"surge":
				# main.js's SURGE DAY tightens HAZARD/curtain/drain cadence in
				# systems this port hasn't built yet (steam vents, drains, the
				# arena curtain). Divergence, not a guess at ONE of those: the
				# closest thing this port actually HAS is the wave rhythm
				# itself, so surge tightens THAT instead — spikes and swarms
				# arrive on a shorter clock. Documented in PORT_STATUS.md.
				waves.rhythm_tight = true
	else:
		waves.reseed()
	_run_t = 0.0
	_death_wash.color.a = 0.0
	_fb_panel.hide()
	input_mgr.set_rush(_rush_verbs())
	waves.level_override = 0
	save.mode = _cur_mode_key()   # every read below follows from this
	sticks.show_hints = save.runs.is_empty()   # hints for a first-timer only
	rush.reset()
	# GW3's drones arrive over its campaign; so do these. An ability that has
	# not been earned yet is simply not selectable.
	var owned := Challenges.unlocked_abilities(save)
	if not owned.has(rush.ability):
		rush.ability = owned[0]
	_start_challenge() if mode == Mode.CHALLENGE else _clear_challenge()
	_wave_peak = 0
	player.rush_shotgun = _rush_verbs()
	player.reset()
	if daily_mod == "glass":
		player.max_hp = 1
		player.hp = 1
	waves.clear()
	bullets.clear()
	trails.clear()
	poison.clear()
	debris.clear()
	pods.clear()
	cargo.clear()
	_cargo_spawn_at = -1.0
	_cargo_wave_t = 0.0
	_clear_arena_objectives()
	for g in gates:
		if is_instance_valid(g):
			g.queue_free()
	gates.clear()
	gate_chain_t = 0.0
	gate_chain_n = 0
	for fz in foam_zones:
		if is_instance_valid(fz):
			fz.queue_free()
	foam_zones.clear()
	score_mult_t = 0.0
	streak = 0
	graze_count = 0
	_weapon_name = "SINGLE"
	waves.start_wave()
	_msg_label.hide()

## Capture-only: fast-forward the director so tools/capture.gd can photograph
## later waves. Never called by the game itself.
func _capture_seek_wave(n: int) -> void:
	waves.clear()
	waves.wave = maxi(n - 1, 0)
	waves.start_wave()

## Applies the loaded level's rule. Everything here is a PARAMETER the game
## already had — that is what makes an archetype cheap and a level free.
func _start_challenge() -> void:
	var lv := Challenges.get_level(challenge_i)
	_ch_rule = lv["rule"]
	_ch_clock = float(lv["duration"])

	# A challenge runs on Rush's verbs — boost, heat, chain, the ability —
	# because that is the game the campaign is teaching.
	rush.reset()
	player.rush_shotgun = true

	half_x = HALF_X
	half_z = HALF_Z
	match _ch_rule:
		Challenges.Rule.CLOSE_QUARTERS:
			half_x = HALF_X * Challenges.CLOSE_QUARTERS_SCALE
			half_z = HALF_Z * Challenges.CLOSE_QUARTERS_SCALE
		Challenges.Rule.ONE_LIFE:
			rush.lives = 1

	waves.half_x = half_x
	waves.half_z = half_z
	waves.level_override = int(lv["difficulty"])
	waves.only_shooters = _ch_rule == Challenges.Rule.ARTILLERY
	waves.only_melee = _ch_rule == Challenges.Rule.SWARM
	waves.revenge_mult = 2 if _ch_rule == Challenges.Rule.GRAVEYARD else 1
	waves.force_support = _ch_rule == Challenges.Rule.FOCUS
	_resize_arena()

func _clear_challenge() -> void:
	_ch_rule = Challenges.Rule.NONE
	half_x = HALF_X
	half_z = HALF_Z
	waves.half_x = half_x
	waves.half_z = half_z
	waves.only_shooters = false
	waves.only_melee = false
	waves.revenge_mult = 1
	waves.force_support = false
	_resize_arena()

## The floor, rails and grid all follow half_x/half_z, so CLOSE QUARTERS is
## a real, visible change of room rather than an invisible clamp.
func _resize_arena() -> void:
	if _floor_inst != null:
		(_floor_inst.mesh as PlaneMesh).size = Vector2(half_x * 2.0, half_z * 2.0)
		_floor_mat.set_shader_parameter("u_grid_x", (half_x * 2.0) / GRID_CELL)
		_floor_mat.set_shader_parameter("u_grid_z", (half_z * 2.0) / GRID_CELL)
	for r in _rails:
		r.queue_free()
	_rails.clear()
	_add_arena_edge()

	# Pull the camera in with the room. A CLOSE QUARTERS level in the full-size
	# frame is a small board adrift in black — the point of the rule is that the
	# walls are CLOSE, and that only reads if they fill the screen. Scaled off
	# whichever orientation's own base camera is active, not a landscape
	# constant — `k` is 1 outside CLOSE QUARTERS, so this is a no-op then.
	if camera == null:
		return   # called by _on_viewport_resized() before _setup_camera() runs
	var k := maxf(half_x / HALF_X, half_z / HALF_Z)
	_cam_rest = _cam_rest_base * k
	camera.position = _cam_rest
	camera.look_at(_cam_look_base * k, Vector3.UP)

## The buzzer. Grades the score against the level's measured thresholds,
## records the attempt (best-only — a level's record is its high-water mark,
## not a history) and reports whether the next level just opened.
func _finish_challenge() -> void:
	state = State.DEAD
	var lv := Challenges.get_level(challenge_i)
	var grade := Challenges.grade_for(lv, score)
	var did := Challenges.cleared(lv, score)
	input_mgr.reset()
	audio.play("wave" if did else "dead")
	var improved := save.record_level(String(lv["id"]), score, grade)

	var out := ["%s — %s" % [lv["id"], lv["name"]], "", "score %d" % score]
	if grade != "":
		out.append("GRADE %s" % grade)
	else:
		out.append("no grade — reach %d for C" % int(lv["tiers"][0]))
	if improved and grade != "":
		out.append("new best")
	out.append("")
	if did and challenge_i + 1 < Challenges.count():
		out.append("%s UNLOCKED" % Challenges.get_level(challenge_i + 1)["name"])
		var ab: int = lv["unlocks_ability"]
		if ab >= 0:
			out.append("ability: %s" % RushRules.ABILITY_DEF[ab]["name"])
	elif not did:
		out.append("tier C or better opens the next level")
	out.append("")
	out.append("tap, or press FIRE / DASH, to try again")
	_msg_label.text = "
".join(out)
	_msg_label.show()
	_open_feedback()

## Boss waves and the wave-kind banner, both base-mode only (owner
## direction 2026-08-25) — Rush and Challenge already have their own
## escalation reads (heat, the clock) and do not need a second one.
func _on_wave_started(n: int) -> void:
	if not _base_mode():
		return
	# main.js: "3-8s into the wave — always overlaps live enemies". Drawn
	# from the gameplay stream, not global randf() — see cargo_cluster.gd's
	# header for why a convoy's timing has to be seed-reproducible too.
	_cargo_wave_t = 0.0
	_cargo_spawn_at = 3.0 + waves.rng.randf() * 5.0
	# v175 living-arena objectives: unresolved ones from the last wave vanish
	# here (main.js's clearArenaObjectives(), called from the same per-wave
	# setup that schedules the next one) rather than carrying over.
	_clear_arena_objectives()
	# Gates, unlike vault/escort, spawn every wave from 3 regardless of kind
	# (main.js has no boss-wave exclusion for these) and PERSIST — only the
	# 2-alive cap evicts one, never a new wave on its own.
	if n >= 3:
		if gates.size() >= 2:
			var oldest: Gate = gates.pop_front()
			if is_instance_valid(oldest):
				oldest.queue_free()
		var gx := (waves.rng.randf() - 0.5) * half_x * 1.5
		var gz := (waves.rng.randf() - 0.5) * half_z * 1.5
		var gangle := waves.rng.randf() * PI
		var g := Gate.new()
		add_child(g)
		g.build(gx, gz, gangle, n >= 5 and waves.rng.randf() < 0.35, n >= 10, waves.rng)
		gates.append(g)
	if waves.wave_kind != "boss":
		if n >= 5 and n % 4 == 3:
			vault = VaultCrate.new()
			add_child(vault)
			vault.build((waves.rng.randf() * 2.0 - 1.0) * (half_x - 5.0),
				(waves.rng.randf() * 2.0 - 1.0) * (half_z - 5.0))
		if n >= 6 and n % 4 == 1:
			escort = EscortBot.new()
			add_child(escort)
			escort.build(half_x, half_z, waves.rng)
		if n >= 6 and n % 4 == 2:
			var fz := FoamZone.new()
			add_child(fz)
			fz.build((waves.rng.randf() * 2.0 - 1.0) * (half_x - 4.0),
				(waves.rng.randf() * 2.0 - 1.0) * (half_z - 4.0))
			foam_zones.append(fz)
	match waves.wave_kind:
		"boss":
			# The BIGGEST-radius body in the wave is promoted, not the first one
			# spawned — a boss ring around the smallest thing on screen, with a
			# WARDEN aura the same size sitting next to it, read as the wrong body
			# being marked.
			var biggest: Enemy = null
			for e in waves.enemies:
				if biggest == null or e.radius > biggest.radius:
					biggest = e
			if biggest != null:
				biggest.apply_boss()
			_show_toast("WAVE %d — BOSS" % n)
			audio.play("wave")
		"spike":
			_show_toast("WAVE %d — SPIKE" % n)
		"swarm":
			_show_toast("WAVE %d — SWARM" % n)
		"breather":
			_show_toast("WAVE %d — BREATHER" % n)
	# Escort's toast runs last, so it wins the shared toast slot over a
	# same-wave kind banner — a fresh objective is the more useful thing to
	# tell the player about right now.
	if escort != null and n >= 6 and n % 4 == 1:
		_show_toast("ESCORT THE BOT!")

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.show()
	_toast_t = 1.8

## Fades the last 0.4s rather than cutting, so it reads as a beat, not a flicker.
func _update_toast(delta: float) -> void:
	if _toast_t <= 0.0:
		if _toast.visible:
			_toast.hide()
		return
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	if _toast_t <= 0.0:
		_toast.hide()

func _on_wave_cleared(n: int) -> void:
	_wave_peak = 0
	_add_score(50 * n)
	audio.play("wave")
	waves.start_wave()

func _on_player_dead() -> void:
	if mode == Mode.CHALLENGE:
		_finish_challenge()   # a death ends the attempt; the score still grades
		return
	state = State.DEAD
	audio.play("dead")
	input_mgr.reset()   # a finger still down must not steer the next run

	# The browser treats TIME SURVIVED as a headline stat ("WAVE 1 - 5s - 0
	# PTS") and keeps a best of it; this port had no notion of it at all.
	var t := int(_run_t)
	var mkey := _cur_mode_key()
	save.mode = mkey
	var prev_best_time := 0
	for r in save.runs:
		prev_best_time = maxi(prev_best_time, int(r.get("time", 0)))

	var extra := {"time": t}
	if mode == Mode.RUSH:
		extra["kills"] = rush.kills
		extra["heat_peak"] = rush.heat_peak
	# record() stores `wave` only for the wave-based mode and drops it for
	# Rush, where a wave number would be a lie (design/RUSH_MODE.md 7).
	var best := save.record(score, waves.wave, extra)

	var out := ["YOU DIED", "",
		"WAVE %d  ·  %ds  ·  %d PTS" % [waves.wave, t, score]]
	# Star each record actually beaten, the way the browser marks BEST TIME
	# and BEST WAVE separately — a run can be your longest without being your
	# highest, and one line saying "best" hides that.
	var stars: Array[String] = []
	if best:
		stars.append("★ BEST SCORE")
	if t > prev_best_time:
		stars.append("★ BEST TIME")
	if stars.is_empty():
		out.append("best %d" % save.hi_score)
	else:
		out.append("   ".join(stars))
	var recent := save.recent_line()
	if recent != "":
		out.append(recent)
	# main.js death screen: "N graze" only shows up when it happened.
	if graze_count > 0:
		out.append("%d graze" % graze_count)
	out.append("")
	out.append("SEED %s" % waves.seed_text())
	out.append("")
	out.append("tap, or press FIRE / DASH, to retry")
	_msg_label.text = "
".join(out)
	_msg_label.show()
	_open_feedback()

func _show_menu() -> void:
	state = State.MENU
	# Park the caret on the first PLAYABLE row rather than on a "SOON" one, so
	# pressing start does what the highlighted line says it will.
	for r in MODE_ROWS.size():
		if MODE_ROWS[r]["ready"]:
			_menu_row = r
			break
	_msg_label.text = _menu_text()
	_msg_label.show()
	_open_feedback()

## The title screen, built as text so it reflows on a phone without a layout
## pass. The selected mode row is marked with a caret, the same way the
## browser hub marks its selection.
func _menu_text() -> String:
	var out := ["TOKO DROP", "", "twin-stick swarm survival", ""]
	for i in MODE_ROWS.size():
		var row: Dictionary = MODE_ROWS[i]
		var caret := ">" if i == _menu_row else " "
		var state_txt := "ON" if mode == row["mode"] else "OFF"
		if not row["ready"]:
			state_txt = "SOON"
		out.append("%s  %s: %s" % [caret, row["label"], state_txt])
		# Detail lines belong to the SELECTED row only. Three modes each with a
		# note, an ability line and a level line overflowed the screen top and
		# bottom on the web build — the title was cut off.
		if i != _menu_row:
			continue
		out.append("     %s" % row["note"])
		if row["mode"] == Mode.CHALLENGE:
			var lv := Challenges.get_level(challenge_i)
			var rec = save.levels.get(String(lv["id"]), {})
			var g := ""
			var best := 0
			if typeof(rec) == TYPE_DICTIONARY:
				g = String(rec.get("grade", ""))
				best = int(rec.get("best_score", 0))
			var pick := "< %s >" if i == _menu_row else "  %s  "
			var rn: String = Challenges.RULE_NAME[lv["rule"]]
			var tag := ("%s   %s" % [lv["name"], rn]) if rn != "" else String(lv["name"])
			out.append("     " + (pick % tag))
			out.append("     %ds \u2014 %s" % [int(lv["duration"]), Challenges.RULE_BLURB[lv["rule"]]])
			if best > 0:
				out.append("     best %d%s" % [best, ("   GRADE " + g) if g != "" else ""])
		if row["mode"] == Mode.RUSH:
			# The < > only appear on the SELECTED row: arrows you cannot press
			# yet read as a control that is broken.
			var pick := "< %s >" if i == _menu_row else "  %s  "
			out.append("     " + (pick % rush.ability_name()) + "  " + rush.ability_blurb())
		if row["mode"] == Mode.DAILY:
			var dm := Daily.mod_for(Daily.today())
			out.append("     today: %s" % (dm.to_upper() if dm != "" else "no twist"))
	out.append("")
	out.append("touch — left thumb moves, right thumb aims and fires")
	out.append("rush — hold BOOST to kill on contact; firing drops your shield")
	out.append("keys \u2014 WASD move, hold LMB to aim and fire, SPACE dash")
	out.append("pad \u2014 sticks move and aim, A dash, Start pause")
	out.append("")
	save.mode = _menu_mode_key()
	if save.hi_score > 0:
		out.append("best %d" % save.hi_score)
		out.append("")
	out.append("tap, or press FIRE / DASH, to start")
	return "\n".join(out)

## Which save bucket the CURRENT run belongs to, and which the menu should
## quote a best from. Helpers rather than inline ternaries so that no call
## site can quietly forget the mode again.
## True when the RUSH VERB SET is live — boost, heat, chain, abilities. That
## is Rush AND every challenge level, because the campaign teaches Rush.
## Gating any of it on `mode == Mode.RUSH` alone silently disabled boost-kills
## inside challenges, which made the BOOST ONLY level literally unwinnable
## (tools/measure.gd scored it 0 on every run — that is how it was found).
func _rush_verbs() -> bool:
	return mode == Mode.RUSH or mode == Mode.CHALLENGE

## True for the classic open-arena wave loop — Classic itself, and DAILY,
## which is Classic with a shared seed and (on 3 days out of 4) one twist
## layered on top. Everything gated to "base mode" (bosses, the wave-kind
## banner, the streak/HP HUD) belongs to both.
func _base_mode() -> bool:
	return mode == Mode.CLASSIC or mode == Mode.DAILY

## A pod changes the gun for the rest of the run, or until the next pod.
func _on_pod_taken(mode_name: String, col: Color) -> void:
	player.weapon = mode_name
	_weapon_name = mode_name
	player.mat.set_shader_parameter("rim_color", col)
	audio.play("wave")

## main.js's non-weapon pickups: "score" pays an instant nugget, "scoremult"
## starts (or refreshes — main.js overwrites, not adds, so grabbing a second
## one is a top-up, not a stack) a 10s x2 window.
func _add_score(amount: int) -> void:
	score += amount * (2 if score_mult_t > 0.0 else 1)

## main.js's GLASS-day doubling ("GLASS pays double") lives ONLY in
## onKill()'s own formula — the wave-clear bonus and graze both stay at
## plain scoreMultT-only (checked directly against their own source lines,
## `1500 + wave*100` / `25 * grazeMult`, neither of which multiplies by
## dailyMod). So this is its own helper, not folded into _add_score()
## itself, or every score site would double on a GLASS day when only kills
## are supposed to.
func _add_kill_score(amount: int) -> void:
	_add_score(amount * (2 if daily_mod == "glass" else 1))

func _on_value_taken(kind: String, value: int, _col: Color) -> void:
	match kind:
		"score":
			_add_score(value)
			audio.play("wave")
		"scoremult":
			score_mult_t = 10.0
			audio.play("wave")
		"hp":
			player.hp = mini(player.max_hp, player.hp + 1)
			audio.play("wave")
		"invincible":
			player.grant_invincibility(3.0)
			audio.play("wave")
		"firerate":
			player.grant_fire_rate_boost(8.0)
			audio.play("wave")

func _cur_mode_key() -> String:
	return SaveService.MODE_RUSH if mode == Mode.RUSH else SaveService.MODE_NORMAL

func _menu_mode_key() -> String:
	var r: Dictionary = MODE_ROWS[_menu_row]
	return SaveService.MODE_RUSH if r["mode"] == Mode.RUSH else SaveService.MODE_NORMAL

## main.js: trauma decays at ~2.8/s and the offset is trauma squared.
## Fades the red flood up on death and back out when a run starts.
func _update_wash(delta: float) -> void:
	var want := 0.34 if state == State.DEAD else 0.0
	_death_wash.color.a = move_toward(_death_wash.color.a, want, delta * 1.6)

## The 60fps target (owner direction 2026-08-25): SSS is a per-pixel
## screen-space cost over every body's visible area, so the thing that
## actually threatens the frame rate is TOTAL ALIVE COUNT, not any one
## system. Above a soft threshold the quality scales down smoothly rather
## than the frame rate dropping off a cliff right at the body cap.
const SSS_FULL_BELOW := 10
const SSS_MIN_AT := 26

func _update_adaptive_quality() -> void:
	var n := waves.enemies.size() if waves != null else 0
	var q := 1.0
	if n > SSS_FULL_BELOW:
		q = clampf(1.0 - float(n - SSS_FULL_BELOW) / float(SSS_MIN_AT - SSS_FULL_BELOW), 0.35, 1.0)
	Enemy.quality = q

func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		if camera.position != _cam_rest:
			camera.position = _cam_rest
			camera.look_at(_cam_look(), Vector3.UP)
		return
	_trauma = maxf(0.0, _trauma - delta * 2.8)
	var mag := _trauma * _trauma
	var t := Time.get_ticks_msec() / 1000.0
	camera.position = _cam_rest + Vector3(
		sin(t * 41.0) * mag * 1.8,
		sin(t * 37.0) * mag * 1.2,
		sin(t * 43.0) * mag * 1.2)
	camera.look_at(_cam_look(), Vector3.UP)

## Where the camera aims, scaled with the room so a shrunken arena stays
## centred in frame.
func _cam_look() -> Vector3:
	return _cam_look_base * maxf(half_x / HALF_X, half_z / HALF_Z)

func add_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)

## How much of the current wave is dead, 0..1. Peak count is remembered because
## SPLITTA ADDS bodies mid-wave, and a bar that runs backwards reads as a bug.
var _wave_peak := 0

func _wave_progress() -> float:
	var live := waves.enemies.size()
	_wave_peak = maxi(_wave_peak, live)
	if _wave_peak <= 0:
		return 0.0
	return clampf(1.0 - float(live) / float(_wave_peak), 0.0, 1.0)

func _update_hud() -> void:
	if player == null:
		return
	# The stat row belongs to a RUN. On the title screen it was reporting
	# "WAVE 0" over the mode list, which reads as a game already in progress.
	var in_run := state == State.PLAYING or state == State.PAUSED or state == State.DEAD
	_hp_label.visible = in_run
	_wave_label.visible = in_run
	_score_label.visible = in_run
	_rush_label.visible = in_run
	_wave_bar.visible = in_run
	if not in_run:
		return
	var pips := "●".repeat(maxi(rush.lives if not _base_mode() else player.hp, 0))
	if mode == Mode.CHALLENGE:
		var clv := Challenges.get_level(challenge_i)
		_hp_label.text = "LIVES " + pips
		_wave_label.text = "%s  %d:%02d" % [clv["name"], int(_ch_clock) / 60, int(_ch_clock) % 60]
		_wave_bar.value = clampf(_ch_clock / float(clv["duration"]), 0.0, 1.0)
		var rn: String = Challenges.RULE_NAME[_ch_rule]
		_rush_label.text = ("x%d   %s" % [rush.multiplier, rn]) if rn != "" else "x%d" % rush.multiplier
	elif mode == Mode.RUSH:
		_hp_label.text = "LIVES " + pips
		_wave_label.text = "LEVEL %d" % rush.level
		_wave_bar.value = clampf(rush.level_t / rush.level_duration(rush.level), 0.0, 1.0)
		var heat_pips := int(round(rush.heat * 10.0))
		var bar := "█".repeat(heat_pips) + "·".repeat(10 - heat_pips)
		var heat_txt := "OVERHEAT" if rush.overheated_now else "HEAT " + bar
		var ab := "  " + rush.ability_name() if rush.ability_ready() else ""
		_rush_label.text = "%s   x%d%s" % [heat_txt, rush.multiplier, ab]
	else:
		_hp_label.text = "HP " + pips + "○".repeat(maxi(player.max_hp - player.hp, 0))
		_wave_label.text = "WAVE %d" % waves.wave
		# The browser shows the streak with visible HEAT TIERS (gold at 5,
		# orange at 10, red-hot at 20) so the scoring depth reads at a glance.
		var bits: Array[String] = []
		if _weapon_name != "SINGLE":
			bits.append(_weapon_name)
		if streak > 1:
			bits.append("x%d STREAK" % streak)
			_rush_label.add_theme_color_override("font_color",
				Color(1.0, 0.33, 0.4) if streak >= 20
				else Color(1.0, 0.667, 0.267) if streak >= 10
				else Color(1.0, 0.867, 0.267) if streak >= 5
				else Color(0.9, 0.95, 1.0))
		_rush_label.text = "   ".join(bits)
		# The browser's bar is a wave TIMER; this port's waves are clear-based,
		# so it shows how much of the wave is dead. Same slot, same question.
		_wave_bar.value = _wave_progress()

	_corner_l.text = "v%s   %d FPS" % [VERSION, int(Engine.get_frames_per_second())]
	# main.js's corner readout prefixes "DAILY · " onto the seed on a daily
	# run; this also names the day's modifier when there is one.
	var seed_line := "SEED %s" % waves.seed_text()
	if mode == Mode.DAILY:
		seed_line = "DAILY · " + seed_line
		if daily_mod != "":
			seed_line += "  ·  %s" % daily_mod.to_upper()
	_corner_r.text = seed_line
	_score_label.text = ("SCORE %d" % score) if save.hi_score <= 0 \
		else ("SCORE %d   BEST %d" % [score, save.hi_score])
