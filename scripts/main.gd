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

## The front-page mode list, in the browser build's order: ROGUELIKE MODE
## first, RUSH MODE directly under it (owner direction, 2026-08-24).
##
## RUSH is designed in RUSH_MODE.md and NOT implemented yet — its §5 questions
## are open, and guessing at heat/boost rules before they are answered is how a
## mode ends up with a ruleset nobody chose. Selecting it today starts an
## ordinary run with `mode` set, so the plumbing is real and the rules land in
## one place when they are decided.
enum Mode { CLASSIC, ROGUELIKE, RUSH }

const MODE_ROWS := [
	{"mode": Mode.ROGUELIKE, "label": "ROGUELIKE MODE",
	 "note": "no upgrades — pure arcade survival", "ready": false},
	{"mode": Mode.RUSH, "label": "RUSH MODE",
	 "note": "boost to kill — shoot and you lose your shield", "ready": true},
]

var state := State.MENU
var score := 0
var mode := Mode.CLASSIC
var _menu_row := 0        # which mode row the selector is on; -1 = none

var player: Player
var bullets: BulletPool
var waves: WaveDirector
var input_mgr: InputManager
var camera: Camera3D
var audio: AudioKit
var save: SaveService
var sticks: TouchSticks

var rush: RushRules
var _rush_label: Label
var _floor_mat: ShaderMaterial
var hud: CanvasLayer
var _hp_label: Label
var _wave_label: Label
var _score_label: Label
var _msg_label: Label

func _ready() -> void:
	_setup_world()
	_setup_camera()

	player = Player.new()
	add_child(player)
	player.build()   # don't rely on _ready() timing — see BulletPool.build()

	bullets = BulletPool.new()
	add_child(bullets)
	bullets.build()

	var enemies_root := Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	waves = WaveDirector.new()
	add_child(waves)
	waves.half_x = HALF_X
	waves.half_z = HALF_Z
	waves.target = player
	waves.bullets = bullets
	waves.enemies_root = enemies_root
	waves.wave_cleared.connect(_on_wave_cleared)

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

	_rush_label = _make_label(20)
	_rush_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_rush_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rush_label.position.y = 44.0
	_rush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rush_label.hide()
	hud.add_child(_rush_label)

	sticks = TouchSticks.new()
	sticks.input_mgr = input_mgr
	hud.add_child(sticks)

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
				_start_game()

	_update_hud()

func _process_playing(delta: float) -> void:
	var move := input_mgr.get_move_dir()
	var aim := input_mgr.get_aim_dir(player.position)
	var firing: bool = aim["valid"]

	if mode == Mode.RUSH:
		_process_rush(delta, firing)
	elif input_mgr.dash_pressed():
		var was_ready := player.can_dash()
		player.dash(aim)
		if was_ready:
			audio.play("dash")

	player.update(delta, move, aim, bullets, HALF_X, HALF_Z)
	bullets.update(delta, maxf(HALF_X, HALF_Z))
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
					score += 100 * was_max   # tougher bodies are worth more
				else:
					audio.play_varied("hit")

	# Rush: boosting THROUGH a body kills it and chains the multiplier,
	# instead of costing a life. This one branch is the whole mode.
	if mode == Mode.RUSH and rush.boosting and player.alive:
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
					score += rush.award(100 * bmax)
					audio.play_varied("kill")

	# Enemy contact vs. player.
	if player.alive and not player.invincible:
		for e in waves.enemies:
			if not is_instance_valid(e) or not e.alive:
				continue
			var dx := e.position.x - player.position.x
			var dz := e.position.z - player.position.z
			var r := e.radius + Player.RADIUS
			if dx * dx + dz * dz < r * r:
				_damage_player()
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
				_damage_player()
				break

	if not player.alive:
		_on_player_dead()

## One damage path for both rulesets. Rush spends a LIFE and drops the
## chain; classic spends HP. Both take the mercy window, so a single frame
## can never cost two.
func _damage_player() -> void:
	if mode == Mode.RUSH:
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

	player.rush_shotgun = true
	player.rush_speed_mult = rush.speed_mult()
	player.rush_boosting = rush.boosting
	# Boosting is a shield you drop the moment you pull the trigger.
	player.rush_invuln = rush.invulnerable(firing)

	if input_mgr.ability_pressed():
		var r := rush.fire_ability()
		if r > 0.0:
			audio.play("dead")
			for e in waves.enemies:
				if not is_instance_valid(e) or not e.alive:
					continue
				var ax := e.position.x - player.position.x
				var az := e.position.z - player.position.z
				if ax * ax + az * az < r * r:
					var m := e.max_hp
					if e.take_hit(99):
						rush.add_boost_kill()
						score += rush.award(100 * m)

	if rush.note_score(score):
		audio.play("wave")

func _start_game() -> void:
	state = State.PLAYING
	score = 0
	input_mgr.reset()
	input_mgr.set_rush(mode == Mode.RUSH)
	sticks.show_hints = save.runs.is_empty()   # hints for a first-timer only
	rush.reset()
	player.rush_shotgun = mode == Mode.RUSH
	player.reset()
	waves.clear()
	bullets.clear()
	waves.start_wave()
	_msg_label.hide()

## Capture-only: fast-forward the director so tools/capture.gd can photograph
## later waves. Never called by the game itself.
func _capture_seek_wave(n: int) -> void:
	waves.clear()
	waves.wave = maxi(n - 1, 0)
	waves.start_wave()

func _on_wave_cleared(n: int) -> void:
	score += 50 * n
	audio.play("wave")
	waves.start_wave()

func _on_player_dead() -> void:
	state = State.DEAD
	audio.play("dead")
	input_mgr.reset()   # a finger still down must not steer the next run
	var best := save.record(score, waves.wave)
	var out := ["YOU DIED", "", "score %d — wave %d" % [score, waves.wave]]
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
	_msg_label.text = _menu_text()
	_msg_label.show()

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
		out.append("     %s" % row["note"])
	out.append("")
	out.append("touch \u2014 left thumb moves, right thumb aims, release to dash")
	out.append("keys \u2014 WASD move, hold LMB to aim and fire, SPACE dash")
	out.append("pad \u2014 sticks move and aim, A dash, Start pause")
	out.append("")
	if save.hi_score > 0:
		out.append("best %d" % save.hi_score)
		out.append("")
	out.append("tap, or press FIRE / DASH, to start")
	return "\n".join(out)

func _update_hud() -> void:
	if player == null:
		return
	# The stat row belongs to a RUN. On the title screen it was reporting
	# "WAVE 0" over the mode list, which reads as a game already in progress.
	var in_run := state == State.PLAYING or state == State.PAUSED or state == State.DEAD
	_hp_label.visible = in_run
	_wave_label.visible = in_run
	_score_label.visible = in_run
	_rush_label.visible = in_run and mode == Mode.RUSH
	if not in_run:
		return
	if mode == Mode.RUSH:
		_hp_label.text = "LIVES " + "●".repeat(maxi(rush.lives, 0))
		_wave_label.text = "LEVEL %d" % rush.level
		var pips := int(round(rush.heat * 10.0))
		# U+2591 rendered as a hatched slab in the default font and read as a
		# second FULL bar; a middle dot leaves the empty run obviously empty.
		var bar := "█".repeat(pips) + "·".repeat(10 - pips)
		var heat_txt := "OVERHEAT" if rush.overheated_now else "HEAT " + bar
		var ab := "   HEAT EXCHANGE READY" if rush.ability_ready() else ""
		_rush_label.text = "%s    x%d%s" % [heat_txt, rush.multiplier, ab]
	else:
		_hp_label.text = "HP " + "●".repeat(maxi(player.hp, 0)) + "○".repeat(maxi(player.max_hp - player.hp, 0))
		_wave_label.text = "WAVE %d" % waves.wave
	_score_label.text = ("SCORE %d" % score) if save.hi_score <= 0 \
		else ("SCORE %d   BEST %d" % [score, save.hi_score])
