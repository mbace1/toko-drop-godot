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
const HALF_X := 19.0
const HALF_Z := 11.0

## main.js GRID_CELL — world units per floor-grid cell, chosen to keep the
## cells square on a non-square arena.
const GRID_CELL := 1.286

## main.js: scene.background 0x0d0d1a, fog 0x0d0d1a from 42 to 80.
const VOID_COLOR := Color(0.051, 0.051, 0.102)

const FLOOR_SHADER := preload("res://shaders/floor_grid.gdshader")

enum State { MENU, PLAYING, PAUSED, DEAD }
enum Mode { NORMAL, RUSH }

var state := State.MENU

## The mode selected on the menu, and of whatever run is in progress or just
## finished. Defaults NORMAL so tools/capture.gd's existing `_start_game()`
## call (no args) keeps booting a Normal run exactly as it always has.
## Deliberately kept as two distinct director CLASSES (_install_waves() below)
## rather than one director with mode branches sprinkled through it — Rush
## stays a genuinely separate mode, not a hybrid bolted onto Normal's.
var mode := Mode.NORMAL
var score := 0

var player: Player
var bullets: BulletPool
var waves: WaveDirector
var enemies_root: Node3D
var input_mgr: InputManager
var camera: Camera3D
var audio: AudioKit
var save: SaveService
var sticks: TouchSticks

var _floor_mat: ShaderMaterial
var hud: CanvasLayer
var _hp_label: Label
var _wave_label: Label
var _score_label: Label
var _msg_label: Label

## Rush's drain bar sits next to the clock in the top row rather than behind
## it — animating a Control's on-screen SIZE inside an HBoxContainer means
## driving its custom_minimum_size each frame, not its .size directly, which
## the container's own layout pass would just overwrite.
var _drain_bar: ColorRect
var _drain_bar_max_w := 120.0

var _mode_wrap: CenterContainer
var _mode_normal_btn: Button
var _mode_rush_btn: Button

var _surge_label: Label
var _surge_t := 0.0

func _ready() -> void:
	_setup_world()
	_setup_camera()

	player = Player.new()
	add_child(player)
	player.build()   # don't rely on _ready() timing — see BulletPool.build()

	bullets = BulletPool.new()
	add_child(bullets)
	bullets.build()

	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	_install_waves(WaveDirector.new())

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

	_setup_hud()
	_show_menu()

## Swaps the active director for a new instance of the right class — a plain
## WaveDirector for Normal, a RushDirector for Rush — rather than one director
## carrying a mode flag through every method. `waves` stays typed as the base
## class throughout, since everything Normal and Rush share (enemies, corpses,
## _step_bodies()) lives there; only the caller needs to know which subclass
## it is holding, and only where the two modes genuinely diverge.
func _install_waves(new_waves: WaveDirector) -> void:
	if waves != null and is_instance_valid(waves):
		waves.clear()
		waves.queue_free()
	waves = new_waves
	add_child(waves)
	waves.half_x = HALF_X
	waves.half_z = HALF_Z
	waves.target = player
	waves.bullets = bullets
	waves.enemies_root = enemies_root
	# RushDirector never clears in the Normal sense (main.gd drives it through
	# update_rush(), not update()), so it never emits wave_cleared — connecting
	# it there would just be dead wiring.
	if not (waves is RushDirector):
		waves.wave_cleared.connect(_on_wave_cleared)

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
	env.ssr_max_steps = 32
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
	add_child(back)

	var floor_inst := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_X * 2.0, HALF_Z * 2.0)
	floor_inst.mesh = pm
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = FLOOR_SHADER
	_floor_mat.set_shader_parameter("u_grid_x", (HALF_X * 2.0) / GRID_CELL)
	_floor_mat.set_shader_parameter("u_grid_z", (HALF_Z * 2.0) / GRID_CELL)
	floor_inst.material_override = _floor_mat
	add_child(floor_inst)

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
			bm.size = Vector3(HALF_X * 2.0 + t * 2.0, h, t)
		else:
			bm.size = Vector3(t, h, HALF_Z * 2.0 + t * 2.0)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = rail_mat
		match i:
			0: mi.position = Vector3(0.0, h * 0.5, -HALF_Z - t * 0.5)
			1: mi.position = Vector3(0.0, h * 0.5, HALF_Z + t * 0.5)
			2: mi.position = Vector3(-HALF_X - t * 0.5, h * 0.5, 0.0)
			3: mi.position = Vector3(HALF_X + t * 0.5, h * 0.5, 0.0)
		add_child(mi)

func _setup_camera() -> void:
	# The source's landscape camera, verbatim (main.js ARENA_PRESETS.landscape):
	# camRest [0, 20.5, 13.5], camLook [0, 0, 2.5], PerspectiveCamera fov 60.
	# Looking slightly PAST the centre (+2.5 z) is what tips the far half of
	# the arena up into the frame and gives the browser build its wide, shallow
	# read. The earlier derived framing was a reasonable guess and looked
	# nothing like the game.
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.position = Vector3(0.0, 20.5, 13.5)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 2.5), Vector3.UP)
	camera.current = true

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	hud.add_child(margin)

	# A MarginContainer stretches its child to fill, and an HBoxContainer then
	# centres its labels VERTICALLY — which put the whole stat row across the
	# middle of the screen, with WAVE printed on top of the player. The column
	# pins the row to the top and lets an empty Control eat the rest.
	var col := VBoxContainer.new()
	margin.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)

	_hp_label = _make_label(22)
	top.add_child(_hp_label)

	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer1)

	_drain_bar = ColorRect.new()
	_drain_bar.color = Color(0.3, 0.55, 1.0, 0.55)
	_drain_bar.custom_minimum_size = Vector2(0, 6)
	_drain_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_drain_bar.visible = false
	top.add_child(_drain_bar)

	_wave_label = _make_label(22)
	top.add_child(_wave_label)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer2)

	_score_label = _make_label(22)
	top.add_child(_score_label)

	var below := Control.new()
	below.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(below)

	_msg_label = _make_label(28)
	_msg_label.set_anchors_preset(Control.PRESET_CENTER)
	_msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(_msg_label)

	sticks = TouchSticks.new()
	sticks.input_mgr = input_mgr
	hud.add_child(sticks)

	# Mode-select chips — RUSH_MODE.md §6: hit-tested ahead of the "any touch
	# starts a run" fallback (via input_mgr.suppress_rects, kept live in
	# _process()), a CenterContainer so they stay centred regardless of their
	# own size rather than needing hand-computed offsets.
	_mode_wrap = CenterContainer.new()
	_mode_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_mode_wrap.position.y = 230.0
	_mode_wrap.custom_minimum_size.y = 60.0
	hud.add_child(_mode_wrap)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 16)
	_mode_wrap.add_child(mode_row)

	_mode_normal_btn = _make_mode_button("NORMAL")
	_mode_rush_btn = _make_mode_button("RUSH")
	_mode_normal_btn.pressed.connect(func(): _select_mode(Mode.NORMAL, true))
	_mode_rush_btn.pressed.connect(func(): _select_mode(Mode.RUSH, true))
	mode_row.add_child(_mode_normal_btn)
	mode_row.add_child(_mode_rush_btn)

	_surge_label = _make_label(26)
	_surge_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_surge_label.text = "SURGE"
	_surge_label.visible = false
	_surge_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_surge_label.position = Vector2(-40.0, 70.0)
	hud.add_child(_surge_label)

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	return l

func _make_mode_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120.0, 44.0)
	b.add_theme_font_size_override("font_size", 18)
	return b

## A tap on a chip both selects and starts that mode (RUSH_MODE.md §6); the
## keyboard/gamepad path (_process()'s ui_left/ui_right) only selects, so
## start_now is false there.
func _select_mode(m: Mode, start_now: bool) -> void:
	mode = m
	_refresh_mode_buttons()
	if start_now:
		_start_game()
	elif state == State.MENU:
		_show_menu()   # rebuild the best-score line for the newly selected mode

func _refresh_mode_buttons() -> void:
	_mode_normal_btn.modulate = Color(1, 1, 1, 1) if mode == Mode.NORMAL else Color(1, 1, 1, 0.55)
	_mode_rush_btn.modulate = Color(1, 1, 1, 1) if mode == Mode.RUSH else Color(1, 1, 1, 0.55)

## The best for whichever mode is currently SELECTED — read directly from the
## save's per-mode bucket rather than through save.hi_score, which tracks the
## mode of the run last STARTED, not the menu's current selection (those two
## can disagree for the few frames between toggling the chip and pressing go).
func _current_best() -> int:
	var key := SaveService.MODE_RUSH if mode == Mode.RUSH else SaveService.MODE_NORMAL
	return int(save._bucket(key).get("hi_score", 0))

func _process(delta: float) -> void:
	# The floor pulses on its own clock even on the menu — a still first screen
	# reads as a broken page.
	_floor_mat.set_shader_parameter("u_time", Time.get_ticks_msec() / 1000.0)

	var chips_visible := state == State.MENU or state == State.DEAD
	_mode_wrap.visible = chips_visible
	# Kept live rather than set once: chip layout isn't final until a frame
	# after _setup_hud(), and this only matters while the chips are shown.
	# (A ternary here infers a plain untyped Array, which GDScript refuses to
	# assign onto an Array[Rect2] property — hence the explicit typed local.)
	var suppress: Array[Rect2] = []
	if chips_visible:
		suppress = [_mode_normal_btn.get_global_rect(), _mode_rush_btn.get_global_rect()]
	input_mgr.suppress_rects = suppress

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
			# Only two modes, so either direction just toggles — RUSH_MODE.md §6's
			# "keyboard gets left/right to move the selection", satisfied minimally.
			if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
				_select_mode(Mode.RUSH if mode == Mode.NORMAL else Mode.NORMAL, false)

			# A touch anywhere starts a run: on a phone there is no FIRE key, and
			# the dash edge only fires on RELEASE of the aim stick. A chip's own
			# tap is excluded via input_mgr.suppress_rects above and starts the
			# game itself (_select_mode), so by the time this runs `state` has
			# already left MENU/DEAD on that frame — this fallback only ever
			# fires for a press that hit neither chip.
			if input_mgr.dash_pressed() or Input.is_action_just_pressed("fire") \
					or input_mgr.left.active or input_mgr.right.active:
				_start_game()

	_update_hud()

func _process_playing(delta: float) -> void:
	var move := input_mgr.get_move_dir()
	var aim := input_mgr.get_aim_dir(player.position)
	var rd: RushDirector = (waves as RushDirector) if mode == Mode.RUSH else null

	if input_mgr.dash_pressed():
		var was_ready := player.can_dash()
		player.dash(aim)
		if was_ready:
			audio.play("dash")

	player.update(delta, move, aim, bullets, HALF_X, HALF_Z)
	bullets.update(delta, maxf(HALF_X, HALF_Z))

	if rd != null:
		var vw_before := rd.virtual_wave_for(rd.elapsed)
		rd.update_rush(delta, player.position)
		if rd.virtual_wave_for(rd.elapsed) > vw_before:
			_surge_t = 0.6   # a SURGE flash is the escalation beat Normal gets
			audio.play("wave")   # for free every time the arena empties and refills
	else:
		waves.update(delta)

	# Player bullets vs. enemies.
	for e in waves.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		for b in bullets.active:
			if not b.alive or not b.is_player:
				continue
			var dx := b.x - e.position.x
			var dz := b.z - e.position.z
			var r := e.radius + 0.15
			if dx * dx + dz * dz < r * r:
				b.alive = false
				var was_max := e.max_hp
				if e.take_hit(1):
					audio.play_varied("kill")
					score += rd.register_kill(was_max) if rd != null else 100 * was_max   # tougher bodies are worth more
				else:
					audio.play_varied("hit")

	# Enemy contact vs. player.
	if player.alive and not player.invincible:
		for e in waves.enemies:
			if not is_instance_valid(e) or not e.alive:
				continue
			var dx := e.position.x - player.position.x
			var dz := e.position.z - player.position.z
			var r := e.radius + Player.RADIUS
			if dx * dx + dz * dz < r * r:
				player.hit()
				audio.play("player")
				break

	# Enemy bullets vs. player. Checked after contact so a single frame can
	# never cost two HP — player.hit() is a no-op while mercy i-frames run,
	# which the first hit of the frame has already started.
	if player.alive and not player.invincible:
		for b in bullets.active:
			if not b.alive or b.is_player:
				continue
			var dx := b.x - player.position.x
			var dz := b.z - player.position.z
			var r := Player.RADIUS + 0.15
			if dx * dx + dz * dz < r * r:
				b.alive = false
				player.hit()
				audio.play("player")
				break

	if not player.alive:
		_on_player_dead()
	elif rd != null and rd.is_over():
		_on_rush_timeout()

	_surge_t = maxf(0.0, _surge_t - delta)
	_surge_label.visible = _surge_t > 0.0

func _start_game() -> void:
	state = State.PLAYING
	score = 0
	input_mgr.reset()
	save.mode = SaveService.MODE_RUSH if mode == Mode.RUSH else SaveService.MODE_NORMAL
	sticks.show_hints = save.runs.is_empty()   # hints for a first-timer only, per mode

	player.reset()
	if mode == Mode.RUSH:
		var rd := RushDirector.new()
		_install_waves(rd)
		rd.start_rush()
	else:
		_install_waves(WaveDirector.new())
		waves.start_wave()

	bullets.clear()
	_surge_t = 0.0
	_surge_label.visible = false
	_msg_label.hide()

## Capture-only: fast-forward the director so tools/capture.gd can photograph
## later waves. Never called by the game itself. Normal mode only — `waves`
## must already be a plain WaveDirector, i.e. a Normal run is what's running.
func _capture_seek_wave(n: int) -> void:
	waves.clear()
	waves.wave = maxi(n - 1, 0)
	waves.start_wave()

## Capture-only, Rush's counterpart to _capture_seek_wave(): starts a Rush run
## and fast-forwards its clock so a later leg can be photographed. Never
## called by the game itself.
func _capture_seek_rush(elapsed_seconds: float) -> void:
	mode = Mode.RUSH
	_start_game()
	var rd := waves as RushDirector
	rd.elapsed = elapsed_seconds
	rd.time_left = maxf(0.0, RushDirector.RUSH_DURATION - elapsed_seconds)

func _on_wave_cleared(n: int) -> void:
	score += 50 * n
	audio.play("wave")
	waves.start_wave()

func _on_player_dead() -> void:
	_end_run("YOU DIED")

func _on_rush_timeout() -> void:
	_end_run("TIME'S UP")

## Shared by both ways a run ends — a third hit, or (Rush only) the clock
## running out. The state transition, sound and save write are the same
## either way; only what gets recorded and printed differs.
func _end_run(headline: String) -> void:
	state = State.DEAD
	audio.play("dead")
	input_mgr.reset()   # a finger still down must not steer the next run

	var out := [headline, ""]
	var best: bool
	if mode == Mode.RUSH:
		var rd := waves as RushDirector
		best = save.record(score, 0, {"kills": rd.kills, "heat_peak": rd.heat_peak})
		out.append("score %d — %d kills" % [score, rd.kills])
	else:
		best = save.record(score, waves.wave)
		out.append("score %d — wave %d" % [score, waves.wave])
	out.append("NEW BEST!" if best else "best %d" % save.hi_score)

	var recent := save.recent_line()
	if recent != "":
		out.append(recent)
	out.append("")
	out.append("tap, or press FIRE / DASH, to retry")
	_msg_label.text = "\n".join(out)
	_msg_label.show()

func _show_menu() -> void:
	state = State.MENU
	_msg_label.text = "TOKO DROP\n\ntwin-stick swarm survival\n\n" \
		+ "touch — left thumb moves, right thumb aims, release to dash\n" \
		+ "keys — WASD move, hold LMB to aim and fire, SPACE dash, ESC pause\n" \
		+ "pad — sticks move and aim, A dash, Start pause\n" \
		+ "choose a mode above — arrows / d-pad switch it too\n\n" \
		+ _menu_best_line() \
		+ "tap, or press FIRE / DASH, to start"
	_msg_label.show()
	_refresh_mode_buttons()

func _menu_best_line() -> String:
	var best := _current_best()
	return ("best %d\n\n" % best) if best > 0 else ""

func _update_hud() -> void:
	if player == null:
		return
	_hp_label.text = "HP " + "●".repeat(maxi(player.hp, 0)) + "○".repeat(maxi(player.max_hp - player.hp, 0))

	if mode == Mode.RUSH:
		var rd := waves as RushDirector
		var secs := int(ceil(rd.time_left))
		_wave_label.text = "%d:%02d" % [secs / 60, secs % 60]
		_drain_bar.custom_minimum_size.x = _drain_bar_max_w \
			* clampf(rd.time_left / RushDirector.RUSH_DURATION, 0.0, 1.0)
		_drain_bar.visible = true
		_score_label.text = "SCORE %d   x%.1f" % [score, rd.multiplier()]
	else:
		_wave_label.text = "WAVE %d" % waves.wave
		_drain_bar.visible = false
		var best := _current_best()
		_score_label.text = ("SCORE %d" % score) if best <= 0 \
			else ("SCORE %d   BEST %d" % [score, best])
