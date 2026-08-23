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
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.3)
	env.ambient_light_energy = 0.45
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.2
	env.glow_hdr_threshold = 0.9
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_inst := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_X * 2.0, HALF_Z * 2.0)
	floor_inst.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.07, 0.07, 0.11)
	fmat.roughness = 0.85
	floor_inst.material_override = fmat
	add_child(floor_inst)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 14.0, 9.0)
	camera.fov = 50.0
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

	var top := HBoxContainer.new()
	margin.add_child(top)

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
