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
	_test_wave_budget(root)
	_test_death_pop(root)
	_test_revenge(root)
	_test_wave_clears_and_advances(root)
	_test_compose(root)
	_test_seeded_stream(root)
	_test_save_v2_migration(root)
	_test_level_records(root)
	_test_rush_escalation_and_caps(root)
	_test_rush_spawn_placement_and_telegraph(root)
	_test_rush_heat_and_scoring(root)

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

## compose() is start_wave()'s affordability loop, split out so Rush can spend
## the same ported table on a per-tick cadence instead of a whole wave at once
## (design/RUSH_MODE.md §3.2). Checked directly, because a second caller now
## depends on properties start_wave() only ever exercised incidentally.
func _test_compose(root: Node3D) -> void:
	var wd := WaveDirector.new()
	root.add_child(wd)

	var picks := wd.compose(5, 12.0, 5, 20)
	var cost := 0.0
	var shooters := 0
	for name in picks:
		cost += float(WaveDirector.POOL[name][1])
		if WaveDirector.POOL[name][2]:
			shooters += 1
	_check(cost <= 12.0, "compose() never overspends its budget (%.1f of 12)" % cost)
	_check(picks.size() <= 20, "compose() respects the body cap")

	var capped := wd.compose(9, 40.0, 2, 20)
	var capped_shooters := 0
	for name in capped:
		if WaveDirector.POOL[name][2]:
			capped_shooters += 1
	_check(capped_shooters <= 2, "compose() respects the shooter cap (%d of 2)" % capped_shooters)

	_check(wd.compose(9, 40.0, 0, 3).size() <= 3, "compose() respects a tight body cap")

	# The bail-out that stops an unspendable remainder looping forever. Every
	# type costs at least 1, so a budget of 0.5 can afford nothing.
	_check(wd.compose(9, 0.5, 5, 20).is_empty(),
		"compose() returns empty rather than looping on an unspendable remainder")

	# Nothing is eligible before its minWave.
	var early := wd.compose(1, 30.0, 9, 30)
	var all_wave_1 := true
	for name in early:
		if WaveDirector.POOL[name][0] > 1:
			all_wave_1 = false
	_check(all_wave_1, "compose() never picks a type before its minWave")

## The gameplay random stream. One seed must reproduce one swarm, and COSMETIC
## draws must not be able to shift it — design/DETERMINISM_AND_SEEDS.md §2,
## where a bullet's shimmer phase shared the global stream with the spawn
## picker, so firing one extra shot would have moved every later wave.
func _test_seeded_stream(root: Node3D) -> void:
	var a := WaveDirector.new()
	root.add_child(a)
	var b := WaveDirector.new()
	root.add_child(b)

	a.rng.seed = 12345
	b.rng.seed = 12345
	var first := a.compose(7, 18.0, 5, 20)
	var second := b.compose(7, 18.0, 5, 20)
	_check(first == second, "the same seed composes the same wave")

	# The regression that matters: burn the GLOBAL rng the way firing a lot of
	# bullets does, and the seeded composition must not move an inch.
	var bullets := _make_pool(root)
	for i in 50:
		bullets.spawn_dir(0.0, 0.0, 1.0, 0.0, true)
	var c := WaveDirector.new()
	root.add_child(c)
	c.rng.seed = 12345
	_check(c.compose(7, 18.0, 5, 20) == first,
		"cosmetic draws cannot shift a seeded wave (shooting does not move the swarm)")

	# Two different seeds should not agree — otherwise the seed is not being used.
	var d := WaveDirector.new()
	root.add_child(d)
	d.rng.seed = 999
	var many_differ := false
	for w in range(3, 12):
		var e := WaveDirector.new()
		root.add_child(e)
		e.rng.seed = 12345
		if d.compose(w, 24.0, 5, 20) != e.compose(w, 24.0, 5, 20):
			many_differ = true
	_check(many_differ, "different seeds compose different waves")

## Save schema v2. v1 was flat and mode-blind, so a Rush run would have
## overwritten the Normal best; and v1 has no version field, so the migration
## has to key off the shape (design/RUSH_MODE.md §7).
func _test_save_v2_migration(root: Node3D) -> void:
	var p := "user://_smoke_v1.json"
	var abs_p := ProjectSettings.globalize_path(p)

	# Hand-write a v1 payload: flat, no "v".
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"hi_score": 4200,
		"runs": [{"score": 4200, "wave": 11, "at": "2026-01-01T00:00:00"}],
	}))
	f.close()

	var sv := SaveService.new()
	root.add_child(sv)
	sv.path = p
	sv.load_state()
	_check(sv.hi_score == 4200, "a v1 save migrates its best across")
	_check(sv.runs.size() == 1 and int(sv.runs[0]["wave"]) == 11,
		"a v1 save migrates its run history across")

	# The migration must have stamped v2 on disk, and must not run twice.
	var raw = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
	_check(typeof(raw) == TYPE_DICTIONARY and int(raw.get("v", 0)) == SaveService.VERSION,
		"the migration stamps the new version on disk")

	var again := SaveService.new()
	root.add_child(again)
	again.path = p
	again.load_state()
	_check(again.hi_score == 4200 and again.runs.size() == 1,
		"re-loading a migrated save is idempotent")

	# The whole point: the modes are independent.
	again.mode = SaveService.MODE_RUSH
	_check(again.hi_score == 0, "a fresh mode starts with no best of its own")
	again.record(90000, 0, {"kills": 210, "heat_peak": 3.0})
	_check(again.hi_score == 90000, "a rush run records against the rush bucket")
	again.mode = SaveService.MODE_NORMAL
	_check(again.hi_score == 4200, "and leaves the normal best untouched")

	# A rush run has no wave, and the recap must not invent one.
	again.mode = SaveService.MODE_RUSH
	again.record(50000, 0, {"kills": 120})
	_check(not again.runs[0].has("wave"), "a rush run records no wave number")
	_check(again.recent_line().find("w0") == -1, "the rush recap never prints a wave")
	_check(again.recent_line().find("kills") != -1, "the rush recap prints kills instead")

	# A corrupt file still starts clean rather than crashing.
	var bad := FileAccess.open(p, FileAccess.WRITE)
	bad.store_string("not json at all {{{")
	bad.close()
	var broken := SaveService.new()
	root.add_child(broken)
	broken.path = p
	broken.load_state()
	_check(broken.hi_score == 0, "a corrupt save starts clean instead of crashing")

	DirAccess.remove_absolute(abs_p)

## Campaign levels keep a high-water mark per level, not a run list — a
## different shape from a mode bucket, reserved in v2 so adding the campaign
## later cannot cost a v3 migration (design/CAMPAIGN_LEVELS.md §4).
func _test_level_records(root: Node3D) -> void:
	var p := "user://_smoke_levels.json"
	var sv := SaveService.new()
	root.add_child(sv)
	sv.path = p

	_check(sv.level_best("l01").is_empty(), "an unplayed level has no record")
	_check(sv.record_level("l01", 1200, "B"), "a first attempt sets the level record")
	_check(not sv.record_level("l01", 900, "C"), "a worse attempt does not replace it")
	_check(int(sv.level_best("l01")["best_score"]) == 1200, "the better score is kept")
	_check(sv.record_level("l01", 3000, "S", ["untouched"]), "a better attempt improves it")
	_check(sv.level_best("l01")["grade"] == "S", "the grade travels with the score")
	_check(sv.level_best("l02").is_empty(), "levels are recorded independently")

	# Levels persist alongside the mode buckets rather than replacing them.
	sv.record(700, 4)
	var reloaded := SaveService.new()
	root.add_child(reloaded)
	reloaded.path = p
	reloaded.load_state()
	_check(int(reloaded.level_best("l01")["best_score"]) == 3000,
		"level records survive a reload alongside run history")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _rush_director(root: Node3D, target: Node3D, bullets: BulletPool) -> RushDirector:
	var rd := RushDirector.new()
	root.add_child(rd)
	rd.half_x = 19.0
	rd.half_z = 11.0
	rd.target = target
	rd.bullets = bullets
	var enemies_root := Node3D.new()
	root.add_child(enemies_root)
	rd.enemies_root = enemies_root
	rd.start_rush()
	return rd

## RushDirector escalates off ELAPSED TIME through a virtual wave rather than
## clears, and holds a STANDING pressure instead of spending a whole budget at
## once — reusing budget_for()/shooter_cap_for()/body_cap_for() unchanged
## (design/RUSH_MODE.md §3). The caps binding under a completely different
## cadence is the check that would have caught "Rush quietly ignores the
## shooter cap", which would be invisible in play until the screen became
## unreadable — and the pause check is the one that would catch a clock built
## on Time.get_ticks_msec() or a Timer, either of which drains through a pause.
func _test_rush_escalation_and_caps(root: Node3D) -> void:
	_check(RushDirector.new().virtual_wave_for(0.0) == 1, "elapsed 0 is virtual wave 1")
	var boundary := RushDirector.RUSH_WAVE_SECONDS * 5.0
	_check(RushDirector.new().virtual_wave_for(boundary - 0.01) == 5,
		"just before a wave boundary is still the earlier virtual wave")
	_check(RushDirector.new().virtual_wave_for(boundary) == 6,
		"a wave boundary advances the virtual wave")

	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(1000.0, 0.0, 1000.0)   # out of the way
	var bullets := _make_pool(root)
	var rd := _rush_director(root, target, bullets)

	var dt := 1.0 / 30.0
	var last_start_elapsed := -999.0
	var min_gap_seen := 999.0
	var pressure_ok := true
	var caps_ok := true
	var player_pos := Vector3.ZERO

	for i in range(int(150.0 / dt)):
		rd.update_rush(dt, player_pos)

		if rd._since_last_spawn_start < dt * 0.5:
			if last_start_elapsed > -900.0:
				min_gap_seen = minf(min_gap_seen, rd.elapsed - last_start_elapsed)
			last_start_elapsed = rd.elapsed

		var vw := rd.virtual_wave_for(rd.elapsed)
		if rd.live_pressure() > rd.target_pressure_for(rd.elapsed) + 0.001:
			pressure_ok = false
		if rd.enemies.size() > rd.body_cap_for(vw):
			caps_ok = false
		var shooters := 0
		for e in rd.enemies:
			if WaveDirector.is_shooter_type(e.type_name):
				shooters += 1
		if shooters > rd.shooter_cap_for(vw):
			caps_ok = false

	_check(pressure_ok, "standing pressure never exceeds its target over a full simulated run")
	_check(caps_ok, "the ported body and shooter caps still bind under Rush's cadence")
	_check(min_gap_seen >= RushDirector.RUSH_SPAWN_GAP - 0.001,
		"telegraph starts never land closer together than the spawn gap (min seen %.3f)" % min_gap_seen)

	var rd2 := _rush_director(root, target, bullets)
	rd2.update_rush(1.0, player_pos)
	var elapsed_snapshot := rd2.elapsed
	var time_left_snapshot := rd2.time_left
	# main.gd pauses by simply not calling waves.update() — nothing here should
	# move the clock without update_rush() being called.
	_check(rd2.elapsed == elapsed_snapshot and rd2.time_left == time_left_snapshot,
		"the rush clock only ever advances inside update_rush() — pause is free")

	var rd3 := _rush_director(root, target, bullets)
	rd3.time_left = RushDirector.RUSH_DURATION - 0.1
	for i in 10:
		rd3.register_kill(1)
	_check(rd3.time_left <= RushDirector.RUSH_DURATION + 0.0001,
		"earned time never exceeds the run's base duration")
	_check(is_equal_approx(rd3.time_left, RushDirector.RUSH_DURATION),
		"and caps exactly at it once kills keep coming — without this the mode is plain endless")

## Trickle spawns cannot use the wave ellipse (design/RUSH_MODE.md §3.4): a body
## materialising at 0.6x extents mid-dash with no wave boundary to warn you is
## an unavoidable hit. Rush spawns on the full edge, clear of the player, and
## behind a real telegraph delay rather than a cosmetic flourish over an
## already-live body.
func _test_rush_spawn_placement_and_telegraph(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var bullets := _make_pool(root)
	var rd := _rush_director(root, target, bullets)

	var corners := [Vector3.ZERO, Vector3(17.0, 0.0, 9.0), Vector3(-17.0, 0.0, -9.0)]
	var all_safe := true
	var all_on_edge := true
	for c in corners:
		for i in 40:
			var pos := rd._pick_edge_position(c)
			if pos.distance_to(c) < RushDirector.RUSH_SPAWN_SAFE - 0.001:
				all_safe = false
			var nx := pos.x / rd.half_x
			var nz := pos.z / rd.half_z
			if absf(sqrt(nx * nx + nz * nz) - 1.0) > 0.01:
				all_on_edge = false
	_check(all_safe, "no Rush spawn lands inside the safe radius, even with the player in a corner")
	_check(all_on_edge, "Rush spawns land on the full arena edge, not the 0.6x wave ellipse")

	target.position = Vector3.ZERO
	var player_far := Vector3(1000.0, 0.0, 1000.0)
	var dt := 1.0 / 60.0
	var first_pending: Dictionary = {}
	var enemies_at_pending_start := 0
	var precocious := false
	var completed := false
	var steps := 0
	while steps < int(6.0 / dt) and not completed:
		var had_none := first_pending.is_empty()
		rd.update_rush(dt, player_far)
		if had_none and not rd._pending.is_empty():
			first_pending = rd._pending[0]
			enemies_at_pending_start = rd.enemies.size()
		if not first_pending.is_empty():
			if float(first_pending.get("t", -1.0)) > 0.0:
				if rd.enemies.size() > enemies_at_pending_start:
					precocious = true
			else:
				completed = rd.enemies.size() > enemies_at_pending_start
		steps += 1

	_check(not first_pending.is_empty(), "a Rush spawn enters a telegraph before it exists")
	_check(not precocious, "the telegraphed body does not exist while its wind-up is still running")
	_check(completed, "the telegraphed body exists once its wind-up ends")

## Heat replaces Normal's per-clear bonus (design/RUSH_MODE.md §4). Per the
## project owner: the chain breaks only on an IDLE timer, never on taking a
## hit — accordingly RushDirector has no method that reduces heat in response
## to damage, so a hit cannot break the chain by construction. Not a runtime
## check for that reason: there is nothing to call.
func _test_rush_heat_and_scoring(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var bullets := _make_pool(root)
	var rd := _rush_director(root, target, bullets)

	_check(is_equal_approx(rd.multiplier(), 1.0), "heat starts at zero, the multiplier at x1.0")

	var s1 := rd.register_kill(1)
	_check(is_equal_approx(rd.multiplier(), 1.0 + RushDirector.RUSH_HEAT_MULT_PER),
		"the multiplier follows 1.0 + heat * 0.15")
	_check(s1 == 115, "the first kill scores 100 * max_hp * the multiplier it just earned (%d)" % s1)

	for i in 20:
		rd.register_kill(1)
	_check(is_equal_approx(rd.multiplier(), 3.0), "the multiplier caps at x3.0 however long the chain runs")
	_check(rd.heat_peak >= 13.0, "heat_peak tracks the run's high-water mark")

	var s_tough := rd.register_kill(4)
	_check(s_tough == int(100 * 4 * 3.0), "score scales with the body's max_hp too (%d)" % s_tough)

	var rd2 := _rush_director(root, target, bullets)
	rd2.register_kill(1)
	rd2.register_kill(1)
	var heat_at_kill := rd2.heat
	# Exactly the window, not window+epsilon: a real decay has now started (the
	# next call proves that), but nothing of it has landed inside THIS call yet.
	rd2._update_heat(RushDirector.RUSH_HEAT_WINDOW)
	_check(is_equal_approx(rd2.heat, heat_at_kill),
		"heat holds for the full window before it starts decaying")

	rd2._update_heat(RushDirector.RUSH_HEAT_DECAY * 0.5)
	_check(rd2.heat < heat_at_kill and rd2.heat > 0.0,
		"heat ramps down partway through the decay window, not instantly")

	rd2._update_heat(RushDirector.RUSH_HEAT_DECAY * 0.5 + 0.01)
	_check(is_equal_approx(rd2.heat, 0.0), "heat reaches zero once the decay window fully elapses")

	var rd3 := _rush_director(root, target, bullets)
	rd3.register_kill(1)
	rd3.register_kill(1)
	var h_before := rd3.heat
	rd3._update_heat(RushDirector.RUSH_HEAT_WINDOW + RushDirector.RUSH_HEAT_DECAY * 0.5)
	_check(rd3.heat < h_before, "heat has started decaying mid-ramp")
	rd3.register_kill(1)
	var h_after_kill := rd3.heat
	_check(h_after_kill > 0.0, "a kill mid-decay adds to whatever heat remained rather than resetting to zero first")
	rd3._update_heat(0.5)
	_check(is_equal_approx(rd3.heat, h_after_kill),
		"a kill mid-decay restarts the hold — heat does not keep dropping right after")
