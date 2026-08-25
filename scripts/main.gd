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

## The LIVE arena size. Constants above are the default room; a challenge
## level may shrink it (CLOSE QUARTERS), and the floor, rails, grid, spawn
## ring and every clamp all read these rather than the constants.
var half_x := HALF_X
var half_z := HALF_Z

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
enum Mode { CLASSIC, ROGUELIKE, RUSH, CHALLENGE }

const MODE_ROWS := [
	{"mode": Mode.ROGUELIKE, "label": "ROGUELIKE MODE",
	 "note": "no upgrades — pure arcade survival", "ready": false},
	{"mode": Mode.RUSH, "label": "RUSH MODE",
	 "note": "boost to kill — shoot and you lose your shield", "ready": true},
	{"mode": Mode.CHALLENGE, "label": "CHALLENGES",
	 "note": "levels, each with its own rule — reach C to open the next",
	 "ready": true},
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
var _floor_mat: ShaderMaterial
var _floor_inst: MeshInstance3D
var _rails: Array[MeshInstance3D] = []
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

	trails = TrailPool.new()
	add_child(trails)
	trails.build()

	poison = PoisonField.new()
	add_child(poison)
	poison.build()

	debris = DebrisPool.new()
	add_child(debris)
	debris.build()

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
	_update_hud()

func _process_playing(delta: float) -> void:
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
	bullets.update(delta, maxf(half_x, half_z))
	trails.update(delta)
	poison.update(delta)
	debris.update(delta)
	# Standing in sludge costs you, long after the body that laid it died.
	if player.alive and not player.invincible \
			and poison.damages_at(player.position.x, player.position.z):
		_damage_player()
	waves.update(delta)

	_collide_player_bullets()
	_collide_enemy_bullets()
	_collide_contact()

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
			b.alive = false
			var was_max := e.max_hp
			if e.take_hit(1):
				var gain := 100 * was_max
				score += rush.award(gain) if _rush_verbs() else gain
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
func _collide_enemy_bullets() -> void:
	if not player.alive or player.invincible:
		return
	for b in bullets.active:
		if not b.alive or b.is_player:
			continue
		var dx := b.x - player.position.x
		var dz := b.z - player.position.z
		var r := Player.RADIUS + 0.15
		if dx * dx + dz * dz >= r * r:
			continue
		if _rush_verbs() and rush.reflecting():
			bullets.spawn_dir(b.x, b.z, -b.vx, -b.vz, true)
			b.alive = false
			continue
		b.alive = false
		_damage_player()
		return

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
					score += rush.award(100 * bmax)
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
			_damage_player()
			return

func _damage_player() -> void:
	add_shake(0.45)   # the one event you must never miss
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
				score += rush.award(100 * m)

func _start_game() -> void:
	state = State.PLAYING
	score = 0
	input_mgr.reset()
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
	waves.clear()
	bullets.clear()
	trails.clear()
	poison.clear()
	debris.clear()
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
	# walls are CLOSE, and that only reads if they fill the screen.
	var k := maxf(half_x / HALF_X, half_z / HALF_Z)
	_cam_rest = Vector3(0.0, 20.5 * k, 13.5 * k)
	camera.position = _cam_rest
	camera.look_at(Vector3(0.0, 0.0, 2.5 * k), Vector3.UP)

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

func _on_wave_cleared(n: int) -> void:
	_wave_peak = 0
	score += 50 * n
	audio.play("wave")
	waves.start_wave()

func _on_player_dead() -> void:
	if mode == Mode.CHALLENGE:
		_finish_challenge()   # a death ends the attempt; the score still grades
		return
	state = State.DEAD
	audio.play("dead")
	input_mgr.reset()   # a finger still down must not steer the next run
	var mkey := _cur_mode_key()
	var extra := {}
	if mode == Mode.RUSH:
		extra = {"kills": rush.kills, "heat_peak": rush.heat_peak}
	save.mode = mkey
	# record() stores `wave` only for the wave-based mode and drops it for
	# Rush, where a wave number would be a lie (design/RUSH_MODE.md 7).
	var best := save.record(score, waves.wave, extra)
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
	# Park the caret on the first PLAYABLE row rather than on a "SOON" one, so
	# pressing start does what the highlighted line says it will.
	for r in MODE_ROWS.size():
		if MODE_ROWS[r]["ready"]:
			_menu_row = r
			break
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

func _cur_mode_key() -> String:
	return SaveService.MODE_RUSH if mode == Mode.RUSH else SaveService.MODE_NORMAL

func _menu_mode_key() -> String:
	var r: Dictionary = MODE_ROWS[_menu_row]
	return SaveService.MODE_RUSH if r["mode"] == Mode.RUSH else SaveService.MODE_NORMAL

## main.js: trauma decays at ~2.8/s and the offset is trauma squared.
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
	return Vector3(0.0, 0.0, 2.5 * maxf(half_x / HALF_X, half_z / HALF_Z))

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
	_rush_label.visible = in_run and mode != Mode.CLASSIC
	_wave_bar.visible = in_run
	if not in_run:
		return
	var pips := "●".repeat(maxi(rush.lives if mode != Mode.CLASSIC else player.hp, 0))
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
		# The browser's bar is a wave TIMER; this port's waves are clear-based,
		# so it shows how much of the wave is dead. Same slot, same question.
		_wave_bar.value = _wave_progress()

	_score_label.text = ("SCORE %d" % score) if save.hi_score <= 0 \
		else ("SCORE %d   BEST %d" % [score, save.hi_score])
