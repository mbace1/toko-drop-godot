## main.gd
##
## Godot equivalent of toko-drop/js/main.js: builds the scene, owns the game
## states (menu/playing/paused/dead), runs the collision loop and updates the
## HUD. Everything is built in code rather than as hand-authored child scenes
## (mirrors main.js building the THREE.Scene programmatically), which keeps
## the single .tscn file trivial and avoids scene-file merge conflicts as the
## port grows.
extends Node3D

const HALF_X := 9.0
const HALF_Z := 9.0

enum State { MENU, PLAYING, PAUSED, DEAD }

var state := State.MENU
var score := 0

var player: Player
var bullets: BulletPool
var waves: WaveDirector
var input_mgr: InputManager
var camera: Camera3D

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
	env.background_color = Color(0.02, 0.02, 0.05)
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
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.07, 0.07, 0.11)
	fmat.roughness = 0.85
	floor_inst.material_override = fmat
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
	rail_mat.albedo_color = Color(0.10, 0.13, 0.20)
	rail_mat.emission_enabled = true
	rail_mat.emission = Color(0.20, 0.45, 0.65)
	rail_mat.emission_energy_multiplier = 0.9
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
	# Framing is computed from the arena rather than hand-tuned, so changing
	# HALF_X/HALF_Z cannot silently push the playfield off-screen again. The
	# first render had the arena as a trapezoid clipped at the bottom with the
	# void showing past its far edge.
	#
	# Godot's `fov` is VERTICAL (keep_aspect defaults to KEEP_HEIGHT), so the
	# binding constraint on a wide screen is the arena's depth. Pull back far
	# enough that the tilted 2*HALF_Z of floor plus a margin fits inside it.
	camera = Camera3D.new()
	camera.fov = 55.0
	var want := maxf(HALF_X, HALF_Z) * 2.0 * 1.12          # arena + a little headroom
	var dist := (want * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	var pitch := deg_to_rad(58.0)                          # steep enough to read the floor
	camera.position = Vector3(0.0, sin(pitch) * dist, cos(pitch) * dist)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
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

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	return l

func _process(delta: float) -> void:
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
			if input_mgr.dash_pressed() or Input.is_action_just_pressed("fire"):
				_start_game()

	_update_hud()

func _process_playing(delta: float) -> void:
	var move := input_mgr.get_move_dir()
	var aim := input_mgr.get_aim_dir(player.position)

	if input_mgr.dash_pressed():
		player.dash(aim)

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
					score += 100 * was_max   # tougher bodies are worth more

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
				break

	if not player.alive:
		_on_player_dead()

func _start_game() -> void:
	state = State.PLAYING
	score = 0
	player.reset()
	waves.clear()
	bullets.clear()
	waves.start_wave()
	_msg_label.hide()

func _on_wave_cleared(n: int) -> void:
	score += 50 * n
	waves.start_wave()

func _on_player_dead() -> void:
	state = State.DEAD
	_msg_label.text = "YOU DIED\n\nscore %d — wave %d\n\npress FIRE or DASH to retry" % [score, waves.wave]
	_msg_label.show()

func _show_menu() -> void:
	state = State.MENU
	_msg_label.text = "TOKO DROP\n\nWASD / left stick — move\nhold FIRE (LMB) + aim with mouse, or right stick — shoot\nSPACE / A — dash (i-frames)\nESC / Start — pause\n\npress FIRE or DASH to start"
	_msg_label.show()

func _update_hud() -> void:
	if player == null:
		return
	_hp_label.text = "HP " + "●".repeat(maxi(player.hp, 0)) + "○".repeat(maxi(player.max_hp - player.hp, 0))
	_wave_label.text = "WAVE %d" % waves.wave
	_score_label.text = "SCORE %d" % score
