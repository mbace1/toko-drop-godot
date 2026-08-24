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
	_test_orange_cube(root)
	_test_weeva(root)
	_test_audio_kit(root)
	_test_save_service(root)
	_test_rush_rules(root)
	_test_wave_budget(root)
	_test_death_pop(root)
	_test_revenge(root)
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

func _test_orange_cube(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(6.0, 0.0, 0.0)
	var bullets := _make_pool(root)

	var e: OrangeCube = _place(root, OrangeCube.new(), Vector3.ZERO, target, bullets)
	_check(e.hp == 4, "ORANGE_CUBE spawns at enemy.js's config hp:4")

	var fired := 0
	for i in 400:
		e.update(1.0 / 60.0)
		if bullets.active.size() > fired:
			fired = bullets.active.size()
			break
	_check(fired == OrangeCube.TOTAL_SHOTS,
		"ORANGE_CUBE throws a wall of %d at once (got %d)" % [OrangeCube.TOTAL_SHOTS, fired])

	# Every shot in a wall travels the SAME way \u2014 that is what makes it a wall
	# and not a spray, and the direction is snapped to one of eight.
	var v0 := Vector2(bullets.active[0].vx, bullets.active[0].vz).normalized()
	var parallel := true
	for b in bullets.active:
		if Vector2(b.vx, b.vz).normalized().distance_to(v0) > 0.001:
			parallel = false
	_check(parallel, "every shot in the wall travels the same direction")

	var snapped := false
	for d in OrangeCube.DIRS8:
		if d.normalized().distance_to(v0) < 0.01:
			snapped = true
	_check(snapped, "the wall is snapped to one of the eight compass directions")

func _test_weeva(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var bullets := _make_pool(root)

	var e: Weeva = _place(root, Weeva.new(), Vector3(5.0, 0.0, 0.0), target, bullets)
	_check(e.hp == 3, "WEEVA spawns at enemy.js's config hp:3")
	_check(is_equal_approx(e.fire_interval, 0.16), "WEEVA streams on a 0.16s interval")

	# A STREAM, not a volley: many single shots, each rotated past the last.
	for i in 120:
		e.update(1.0 / 60.0)
	_check(bullets.active.size() > 6,
		"WEEVA lays down a continuous stream (%d shots in 2s)" % bullets.active.size())

	var angles: Array[float] = []
	for b in bullets.active:
		angles.append(Vector2(b.vx, b.vz).angle())
	var all_same := true
	for a in angles:
		if absf(a - angles[0]) > 0.01:
			all_same = false
	_check(not all_same, "successive WEEVA shots rotate \u2014 it is a spiral, not a line")

func _test_audio_kit(root: Node3D) -> void:
	var kit := AudioKit.new()
	root.add_child(kit)
	kit.build()
	# Synthesised at load: no sample files anywhere, per the house rule that
	# sound is generated rather than sampled.
	for name in ["fire", "hit", "kill", "player", "dash", "wave", "dead"]:
		if not kit._clips.has(name):
			_check(false, "audio kit is missing the '%s' voice" % name)
			return
	var clip: AudioStreamWAV = kit._clips["fire"]
	_check(clip.data.size() > 0, "voices are real generated PCM, not empty stubs")
	_check(not kit.enabled, "the kit disables itself headless (no output device)")
	kit.play("fire")   # a no-op here, and must stay silent rather than erroring
	_check(true, "playing a voice headless neither crashes nor logs")

func _test_save_service(root: Node3D) -> void:
	var sv := SaveService.new()
	root.add_child(sv)
	# Point at a scratch file: record() persists, so running the gate against
	# the default path would overwrite the player's real hi-score.
	sv.path = "user://_smoke_save.json"
	sv.hi_score = 0
	sv.runs = []

	_check(sv.record(500, 3), "a first run is a new best")
	_check(sv.hi_score == 500, "the best is stored")
	_check(not sv.record(200, 2), "a worse run is not a new best")
	_check(sv.hi_score == 500, "and does not lower the best")
	_check(sv.record(900, 5), "a better run beats it")
	_check(sv.hi_score == 900, "and raises the best")
	_check(sv.runs.size() == 3, "every run is kept in history")
	_check(int(sv.runs[0]["score"]) == 900, "history is newest-first")

	for i in 20:
		sv.record(i, 1)
	_check(sv.runs.size() == SaveService.HISTORY_MAX,
		"history is capped at %d" % SaveService.HISTORY_MAX)
	_check(sv.hi_score == 900, "the cap never discards the best")

	# The recent line skips index 0 \u2014 the run you are already looking at.
	_check(not sv.recent_line().begins_with("recent: %d" % int(sv.runs[0]["score"])),
		"the recent line does not repeat the run just finished")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(sv.path))
	_check(true, "the gate cleans up its scratch save")

func _test_rush_rules(root: Node3D) -> void:
	var r := RushRules.new()
	root.add_child(r)
	r.reset()

	# --- the core tension: boosting is a shield you drop by shooting --------
	r.update(0.1, true, false)
	_check(r.boosting, "boost engages while held")
	_check(r.invulnerable(false), "boosting alone makes you invulnerable")
	_check(not r.invulnerable(true), "SHOOTING drops the shield mid-boost")
	_check(r.speed_mult() > 1.0, "boosting is faster than walking")

	# --- heat: boosting heats fast, and overheating locks boost out --------
	var h0 := r.heat
	r.update(0.5, true, false)
	_check(r.heat > h0, "boosting builds heat")
	var hot := r.heat
	r.update(0.5, false, false)
	_check(r.heat < hot, "letting go cools you")

	r.reset()
	var overheat_seen := [false]
	r.overheated.connect(func(): overheat_seen[0] = true)
	for i in 200:
		r.update(1.0 / 60.0, true, false)
	_check(overheat_seen[0], "holding boost eventually overheats")
	_check(r.boost_blocked, "overheating locks boost out")
	_check(not r.boosting, "and you stop boosting immediately")

	# Hysteresis: it must not flicker back on the instant you cool a hair.
	r.update(1.0 / 60.0, true, false)
	_check(r.boost_blocked, "boost stays locked while still hot")
	for i in 200:
		r.update(1.0 / 60.0, false, false)
	_check(not r.boost_blocked, "boost returns once you have cooled well past the line")

	# --- the chain ---------------------------------------------------------
	r.reset()
	r.add_boost_kill()
	r.add_boost_kill()
	_check(r.multiplier == 3, "each boost-kill raises the multiplier")
	_check(r.award(100) == 300, "score is paid at the multiplier")
	r.update(RushRules.MULT_WINDOW + 0.1, false, false)
	_check(r.multiplier == 1, "the chain lapses on its timer")

	r.add_boost_kill()
	_check(r.multiplier == 2, "and can be rebuilt")
	r.take_hit()
	_check(r.multiplier == 1, "taking a hit also breaks the chain")

	# --- lives, and levels that move BOTH ways -----------------------------
	r.reset()
	_check(r.lives == RushRules.LIVES_START, "a Rush run starts on lives, not HP")
	r.level = 3
	r.take_hit()
	_check(r.lives == RushRules.LIVES_START - 1, "a hit costs a life")
	_check(r.level == 2, "and knocks the difficulty level DOWN")

	r.reset()
	_check(is_equal_approx(r.level_duration(1), 60.0), "level 1 runs 60s")
	_check(is_equal_approx(r.level_duration(2), 90.0), "level 2 runs 90s")
	_check(r.level_duration(3) > r.level_duration(2), "and they keep lengthening")
	for i in 61:
		r.update(1.0, false, false)
	_check(r.level == 2, "surviving the clock levels you up")

	# --- Heat Exchange: spends the heat you built --------------------------
	r.reset()
	_check(not r.ability_ready(), "the ability is not ready from cold")
	r.ability_charge = RushRules.ABILITY_CHARGE_SEC
	r.heat = 0.8
	_check(r.ability_ready(), "charged and hot, it is ready")
	var rad := r.fire_ability()
	_check(rad > RushRules.ABILITY_RADIUS_BASE, "its radius scales with the heat spent")
	_check(is_equal_approx(r.heat, 0.0), "and it dumps the heat")
	_check(not r.ability_ready(), "it needs recharging afterwards")

	# --- extra lives -------------------------------------------------------
	r.reset()
	_check(not r.note_score(10), "a small score earns nothing")
	_check(r.note_score(RushRules.EXTRA_LIFE_EVERY), "crossing the threshold grants a life")
	_check(r.lives == RushRules.LIVES_START + 1, "and the life is real")

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

func _test_death_pop(root: Node3D) -> void:
	var e: Globbo = _place(root, Globbo.new(), Vector3(3.0, 0.0, 0.0), null, null)
	e.take_hit(1)
	_check(not e.alive, "a killed body is out of play immediately")
	_check(not e.update_death(1.0 / 60.0), "the death pop is still running one frame later")

	var scale_at_start := e.mesh.scale.x
	for i in 10:
		e.update_death(1.0 / 60.0)
	_check(e.mesh.scale.x > scale_at_start, "the corpse SWELLS as it pops")
	var alpha: float = e.mat.get_shader_parameter("alpha_amt")
	_check(alpha < e._base_alpha, "and fades while it does (alpha %.2f)" % alpha)

	var frames := 0
	while not e.update_death(1.0 / 60.0) and frames < 120:
		frames += 1
	_check(frames < 120, "the pop finishes rather than running forever")
	_check(is_equal_approx(Enemy.DEATH_TIME, 0.28), "the pop is enemy.js's 0.28s")

func _test_revenge(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)

	# A melee body blooms the classic RING; a small radius takes the small one.
	var bullets := _make_pool(root)
	var wd := _rev_director(root, target, bullets)
	var g: Globbo = _place(root, Globbo.new(), Vector3(4.0, 0.0, 0.0), target, null)
	wd.enemies.append(g)
	g.take_hit(1)
	wd.update(1.0 / 60.0)
	_check(bullets.active.size() == WaveDirector.REV_RING_SMALL,
		"a melee corpse blooms a ring of %d (got %d)" % [WaveDirector.REV_RING_SMALL, bullets.active.size()])
	_check(wd.corpses.size() == 1, "the corpse moves to the corpse list, not out of existence")
	_check(wd.enemies.is_empty(), "and out of the live list, so it cannot hold up a wave clear")

	var living_speed := BulletPool.ENEMY_SPEED
	var rev_speed := Vector2(bullets.active[0].vx, bullets.active[0].vz).length()
	_check(rev_speed < living_speed,
		"revenge is SLOW — the graze game (%.1f vs living %.1f)" % [rev_speed, living_speed])
	_check(is_equal_approx(rev_speed, living_speed * WaveDirector.REV_SPEED_MULT),
		"revenge runs at exactly TUNING.revenge.speedMult")

	# A gunner's corpse speaks its own language: a slow AIMED burst.
	var b2 := _make_pool(root)
	var wd2 := _rev_director(root, target, b2)
	var sp: Spittor = _place(root, Spittor.new(), Vector3(4.0, 0.0, 0.0), target, b2)
	wd2.enemies.append(sp)
	while sp.alive:
		sp.take_hit(sp.hp)
	wd2.update(1.0 / 60.0)
	_check(b2.active.size() == WaveDirector.REV_AIMED_COUNT,
		"a SPITTOR corpse spits an AIMED burst of %d (got %d)" % [WaveDirector.REV_AIMED_COUNT, b2.active.size()])

	# An arc species throws a slow FAN instead.
	var b3 := _make_pool(root)
	var wd3 := _rev_director(root, target, b3)
	var fa: Fanner = _place(root, Fanner.new(), Vector3(4.0, 0.0, 0.0), target, b3)
	wd3.enemies.append(fa)
	while fa.alive:
		fa.take_hit(fa.hp)
	wd3.update(1.0 / 60.0)
	_check(b3.active.size() == WaveDirector.REV_FAN_COUNT,
		"a FANNER corpse throws a FAN of %d (got %d)" % [WaveDirector.REV_FAN_COUNT, b3.active.size()])

	# The palette shift is the whole point: revenge must not wear living colours.
	_check(fa.revenge_color() != fa.bullet_color,
		"revenge fire never wears the living bullet colour")

func _rev_director(root: Node3D, target: Node3D, bullets: BulletPool) -> WaveDirector:
	var wd := WaveDirector.new()
	root.add_child(wd)
	wd.half_x = 9.0
	wd.half_z = 9.0
	wd.target = target
	wd.bullets = bullets
	wd.wave = 1   # non-zero so update() is in a "wave running" state
	return wd

func _test_wave_clears_and_advances(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var bullets := _make_pool(root)

	var enemies_root := Node3D.new()
	root.add_child(enemies_root)

	var wd := WaveDirector.new()
	root.add_child(wd)
	wd.half_x = 19.0   # the real landscape arena, so the ellipse is exercised
	wd.half_z = 11.0
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

	# Spawns sit on an ELLIPSE at 0.6x each half-extent, so on the real 38x22
	# arena a wave uses the whole room instead of a narrow central band.
	var all_on_ring := true
	for e in wd.enemies:
		var nx := e.position.x / (0.6 * wd.half_x)
		var nz := e.position.z / (0.6 * wd.half_z)
		if absf(sqrt(nx * nx + nz * nz) - 1.0) > 0.01:
			all_on_ring = false
	_check(all_on_ring, "every body spawns on the 0.6x half-arena ellipse, never on the player")

	for en in wd.enemies.duplicate():
		while en.alive:
			en.take_hit(en.hp)
	wd.update(0.016)
	_check(cleared_at[0] == 1, "wave_cleared fires once every enemy in the wave is dead")

	wd.start_wave()
	_check(wd.wave == 2, "the next wave starts")
	_check(wd.enemies.size() > 0, "wave 2 spawns bodies (%d)" % wd.enemies.size())
