## smoke.gd — bare-headless gate, in the spirit of the source repo's
## `node toko-drop/test/*.mjs` scripts: driven off game state, never the wall
## clock, runnable with no GPU. Exercises the pieces main.gd wires together,
## without needing real input events (which --headless cannot synthesize).
##
## Run: godot --headless --script tests/smoke.gd
extends SceneTree

var _ok := true

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	_test_player_move_and_fire(root)
	_test_globbo_pounces(root)
	_test_yela_cube_flops(root)
	_test_spittor_holds_range_and_spits(root)
	_test_fanner_fans(root)
	_test_wave_budget(root)
	_test_wave_clears_and_advances(root)

	print("SMOKE: %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)

func _check(cond: bool, label: String) -> void:
	print(("  ok  " if cond else "FAIL ") + label)
	_ok = _ok and cond

## Enemies need position/target/bullets/half_* set before init(), exactly as
## WaveDirector._spawn() does it.
func _place(root: Node3D, e: Enemy, at: Vector3, target: Node3D, bullets: BulletPool) -> Enemy:
	root.add_child(e)
	e.position = at
	e.target = target
	e.bullets = bullets
	e.half_x = 9.0
	e.half_z = 9.0
	e.init()
	return e

func _make_pool(root: Node3D) -> BulletPool:
	var bp := BulletPool.new()
	root.add_child(bp)
	bp.build()
	return bp

func _test_player_move_and_fire(root: Node3D) -> void:
	var player := Player.new()
	root.add_child(player)
	player.build()   # add_child() does not flush _ready() synchronously here
	player.reset()

	var bullets := _make_pool(root)

	var move := Vector2(1.0, 0.0)
	var aim := {"x": 1.0, "z": 0.0, "valid": true}
	player.update(0.5, move, aim, bullets, 9.0, 9.0)
	_check(player.position.x > 0.0, "player moves toward held direction")

	bullets.update(0.016, 9.0)
	_check(bullets.active.size() == 1, "holding fire+aim spawns exactly one bullet per fire tick")
	_check(bullets.active[0].is_player, "the spawned bullet is flagged as a player shot")

	player.hit()
	_check(player.hp == Player.MAX_HP - 1, "a contact hit costs one HP")
	_check(player.invincible, "a hit grants mercy invincibility")

	player.hit()
	_check(player.hp == Player.MAX_HP - 1, "a second hit during mercy i-frames is ignored")

	player.reset()
	_check(player.hp == Player.MAX_HP and not player.invincible, "reset() clears damage and mercy")

func _test_globbo_pounces(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)

	var e: Globbo = _place(root, Globbo.new(), Vector3(6.0, 0.0, 0.0), target, null)
	_check(e.hp == 1, "GLOBBO spawns at enemy.js's config hp:1")

	var start_x := e.position.x
	e.update(0.5)
	_check(e.position.x < start_x, "GLOBBO closes on its target while stalking")

	# Run past the stalk timer (1.6-3.0s) and confirm it reaches a leap, then
	# returns to stalking — the state machine must cycle, not stick.
	var saw_crouch := false
	var saw_leap := false
	for i in 400:
		e.update(1.0 / 60.0)
		if e._state == Globbo.Pounce.CROUCH:
			saw_crouch = true
		if e._state == Globbo.Pounce.LEAP:
			saw_leap = true
	_check(saw_crouch, "GLOBBO crouches — the leap is telegraphed")
	_check(saw_leap, "GLOBBO reaches its leap")

	_check(e.take_hit(1), "one hit kills a GLOBBO (hp:1)")
	_check(not e.alive, "a killed enemy reports not alive")

func _test_yela_cube_flops(root: Node3D) -> void:
	var c: YelaCube = _place(root, YelaCube.new(), Vector3.ZERO, null, null)
	_check(c.hp == 2, "YELA_CUBE spawns at enemy.js's config hp:2")

	var start := Vector2(c.position.x, c.position.z)
	for i in 90:
		c.update(1.0 / 60.0)
	var moved := Vector2(c.position.x, c.position.z).distance_to(start)
	_check(moved > 0.3, "YELA_CUBE has flopped away from its start after 1.5s (moved %.2f)" % moved)

	_check(not c.take_hit(1), "YELA_CUBE survives one hit (hp:2)")
	_check(c.take_hit(1), "YELA_CUBE dies to the second")

func _test_spittor_holds_range_and_spits(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var bullets := _make_pool(root)

	# Start it far too close: a HOLDER must BACK OFF, not close in.
	var e: Spittor = _place(root, Spittor.new(), Vector3(2.0, 0.0, 0.0), target, bullets)
	_check(e.hp == 3, "SPITTOR spawns at enemy.js's config hp:3")
	_check(e.fire_interval == 2.2, "SPITTOR uses enemy.js's fireInterval 2.2")

	var d0 := Vector2(e.position.x, e.position.z).length()
	for i in 60:
		e.update(1.0 / 60.0)
	var d1 := Vector2(e.position.x, e.position.z).length()
	_check(d1 > d0, "SPITTOR backs away when the player is inside its hold range")

	# It should inflate during the wind-up before anything is fired.
	var saw_inflate := false
	var fired_at := -1
	for i in 300:
		e.update(1.0 / 60.0)
		if e._is_telegraphing and e._inflate > 0.05:
			saw_inflate = true
		if fired_at < 0 and bullets.active.size() > 0:
			fired_at = i
	_check(saw_inflate, "SPITTOR swells through the wind-up (the tell)")
	_check(fired_at > 0, "SPITTOR eventually spits")
	_check(bullets.active.size() % Spittor.RING_COUNT == 0,
		"SPITTOR fires in rings of %d (got %d)" % [Spittor.RING_COUNT, bullets.active.size()])

	var enemy_shots := 0
	for b in bullets.active:
		if not b.is_player:
			enemy_shots += 1
	_check(enemy_shots == bullets.active.size(), "everything SPITTOR fires is flagged as an enemy shot")

func _test_fanner_fans(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var bullets := _make_pool(root)

	var e: Fanner = _place(root, Fanner.new(), Vector3(8.0, 0.0, 0.0), target, bullets)
	_check(e.hp == 3, "FANNER spawns at enemy.js's config hp:3")

	# Two volleys: the source alternates 6 shots, then every third is 9.
	var counts: Array[int] = []
	var last := 0
	for i in 600:
		e.update(1.0 / 60.0)
		var n := bullets.active.size()
		if n > last:
			counts.append(n - last)
		last = n
	_check(counts.size() >= 2, "FANNER fires repeatedly (%d volleys)" % counts.size())
	var only_expected := true
	for c in counts:
		if c != 6 and c != 9:
			only_expected = false
	_check(only_expected, "every FANNER volley is 6 or 9 shots (got %s)" % str(counts))
	_check(counts.has(9), "FANNER's every-third volley is the wide 9-shot one")

func _test_wave_budget(root: Node3D) -> void:
	var wd := WaveDirector.new()
	root.add_child(wd)

	# tuning.js: base 5, ramp 1.8 to the knee at 10, then 0.8 — with the early
	# ease shaving 15% at wave 1 and gone by wave 6.
	_check(is_equal_approx(wd.budget_for(1), 5.0 * 0.85), "wave 1 budget takes the -15% early ease")
	_check(wd.budget_for(6) > wd.budget_for(1), "the budget grows with the wave")
	_check(wd.budget_for(12) > wd.budget_for(10), "the budget still grows past the knee")
	var pre_knee := wd.budget_for(10) - wd.budget_for(9)
	var post_knee := wd.budget_for(12) - wd.budget_for(11)
	_check(post_knee < pre_knee, "growth flattens after the knee (%.2f -> %.2f)" % [pre_knee, post_knee])

	_check(wd.shooter_cap_for(1) == 1, "wave 1 allows a single shooter")
	_check(wd.shooter_cap_for(99) == WaveDirector.SHOOTER_CAP_MAX, "the shooter cap tops out")

func _test_wave_clears_and_advances(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var bullets := _make_pool(root)

	var enemies_root := Node3D.new()
	root.add_child(enemies_root)

	var wd := WaveDirector.new()
	root.add_child(wd)
	wd.half_x = 9.0
	wd.half_z = 9.0
	wd.target = target
	wd.bullets = bullets
	wd.enemies_root = enemies_root

	# GDScript lambdas capture outer locals BY VALUE, so a plain int wouldn't
	# see the mutation from inside the callback — use a 1-element Array
	# (captured by reference) to observe the signal firing.
	var cleared_at := [-1]
	wd.wave_cleared.connect(func(n): cleared_at[0] = n)

	wd.start_wave()
	_check(wd.wave == 1, "first start_wave() advances to wave 1")
	_check(wd.enemies.size() > 0, "wave 1 spawns bodies (%d)" % wd.enemies.size())

	var shooters := 0
	for e in wd.enemies:
		if e.fire_interval > 0.0:
			shooters += 1
	_check(shooters <= wd.shooter_cap_for(1), "wave 1 respects the shooter cap (%d)" % shooters)

	var spawn_r := 0.6 * 9.0
	var all_on_ring := true
	for e in wd.enemies:
		if absf(Vector2(e.position.x, e.position.z).length() - spawn_r) > 0.01:
			all_on_ring = false
	_check(all_on_ring, "every body spawns on the 0.6x half-arena ring, never on the player")

	for en in wd.enemies.duplicate():
		while en.alive:
			en.take_hit(en.hp)
	wd.update(0.016)
	_check(cleared_at[0] == 1, "wave_cleared fires once every enemy in the wave is dead")

	wd.start_wave()
	_check(wd.wave == 2, "the next wave starts")
	_check(wd.enemies.size() > 0, "wave 2 spawns bodies (%d)" % wd.enemies.size())
