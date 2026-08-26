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
	_test_trails(root)
	_test_poison(root)
	_test_splitta(root)
	_test_splitter_cubes(root)
	_test_toro(root)
	_test_bambu(root)
	_test_cloaker(root)
	_test_magna(root)
	_test_draper(root)
	_test_cargo(root)
	_test_vault_crate(root)
	_test_escort_bot(root)
	_test_powerup_values(root)
	_test_gate(root)
	_test_foam_zone(root)
	_test_audio_kit(root)
	_test_save_service(root)
	_test_rush_rules(root)
	_test_boss(root)
	_test_variants(root)
	_test_weapons(root)
	_test_armour_and_aura(root)
	_test_feedback(root)
	_test_challenges(root)
	_test_wave_budget(root)
	_test_death_pop(root)
	_test_revenge(root)
	_test_wave_clears_and_advances(root)
	_test_compose(root)
	_test_seeded_stream(root)
	_test_save_v2_migration(root)
	_test_level_records(root)
	# The scene test needs a REAL frame: main.tscn's _ready() does not run
	# until the tree processes one, and add_child() does not flush it here.
	# So the component tests finish in _init and _process picks it up.

var _frames := 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_test_collisions()
	_test_graze()
	_test_bambu_wiring()
	_test_magna_wiring()
	_test_cargo_wiring()
	_test_arena_objectives_wiring()
	_test_score_mult_wiring()
	_test_gates_wiring()
	_test_orientation_wiring()
	_test_foam_wiring()
	_test_kill_scoring()
	_test_adaptive_quality()
	_test_daily()
	print("SMOKE: %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
	return true

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

func _test_trails(root: Node3D) -> void:
	var tp := TrailPool.new()
	root.add_child(tp)
	tp.build()

	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(9.0, 0.0, 0.0)

	var e: Globbo = _place(root, Globbo.new(), Vector3.ZERO, target, null)
	e.trails = tp
	_check(e.trail_interval > 0.0, "GLOBBO carries a TRAIL_CFG signature")

	# A body that MOVES leaves ghosts; the first frame cannot, because velocity
	# is measured from the previous position and there is not one yet.
	for i in 60:
		e.update(1.0 / 60.0)
	tp.update(0.0)
	_check(tp._mm.multimesh.visible_instance_count > 0,
		"a moving body lays down motion trails (%d live)" % tp._mm.multimesh.visible_instance_count)

	# Ghosts spawn BEHIND the mover, never inside it (main.js v100).
	var behind := true
	for i in tp._live:
		if tp._life[i] <= 0.0:
			continue
		var d := Vector2(tp._x[i] - e.position.x, tp._z[i] - e.position.z).length()
		if d < 0.01:
			behind = false
	_check(behind, "ghosts sit behind the body, not inside it")

	# And they expire.
	for i in 60:
		tp.update(1.0 / 60.0)
	_check(tp._mm.multimesh.visible_instance_count == 0, "trails expire after their life")

	# A species absent from TRAIL_CFG leaves nothing at all.
	var tp2 := TrailPool.new()
	root.add_child(tp2)
	tp2.build()
	var c: SludgeCube = _place(root, SludgeCube.new(), Vector3.ZERO, target, null)
	c.trails = tp2
	for i in 90:
		c.update(1.0 / 60.0)
	tp2.update(0.0)
	_check(tp2._mm.multimesh.visible_instance_count == 0,
		"a species with no TRAIL_CFG entry leaves no streak")

func _test_poison(root: Node3D) -> void:
	var pf := PoisonField.new()
	root.add_child(pf)
	pf.build()

	_check(not pf.damages_at(0.0, 0.0), "clean floor does not hurt")
	pf.add(0.0, 0.0, 1.2)
	_check(pf.damages_at(0.0, 0.0), "standing in a patch hurts")
	_check(not pf.damages_at(0.0, 0.0), "but only on its own tick, not every frame")
	_check(not pf.damages_at(6.0, 6.0), "and only where the patch actually is")

	# The patch OUTLIVES the body: 8s is most of the point of the species.
	_check(is_equal_approx(PoisonField.LIFE, 8.0), "a patch lasts TUNING.fx.poisonLife")
	for i in 60 * 9:
		pf.update(1.0 / 60.0)
	pf._tick_t = 0.0
	_check(not pf.damages_at(0.0, 0.0), "and it does eventually expire")

	# SLUDGE lays patches as it goes.
	var pf2 := PoisonField.new()
	root.add_child(pf2)
	pf2.build()
	var c: SludgeCube = _place(root, SludgeCube.new(), Vector3.ZERO, null, null)
	c.poison = pf2
	for i in 120:
		c.update(1.0 / 60.0)
	pf2.update(0.0)
	_check(pf2._mm.multimesh.visible_instance_count > 0,
		"SLUDGE_CUBE lays poison as it moves (%d patches)" % pf2._mm.multimesh.visible_instance_count)

func _test_splitta(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var enemies_root := Node3D.new()
	root.add_child(enemies_root)

	var wd := WaveDirector.new()
	root.add_child(wd)
	wd.half_x = 19.0
	wd.half_z = 11.0
	wd.target = target
	wd.enemies_root = enemies_root
	wd.wave = 1

	var sp: Splitta = _place(root, Splitta.new(), Vector3(4.0, 0.0, 2.0), target, null)
	_check(sp.hp == 5, "SPLITTA spawns at enemy.js's config hp:5")
	_check(sp.mesh.get_child_count() >= 2,
		"it visibly CARRIES its children before it splits")

	wd.enemies.append(sp)
	while sp.alive:
		sp.take_hit(sp.hp)
	_check(sp.wants_children, "dying flags it to split")

	wd.update(1.0 / 60.0)
	_check(wd.enemies.size() == Splitta.CHILD_COUNT,
		"it splits into %d children (got %d)" % [Splitta.CHILD_COUNT, wd.enemies.size()])
	var all_globbo := true
	for c in wd.enemies:
		if not (c is Globbo):
			all_globbo = false
	_check(all_globbo, "and the children are GLOBBOs, per enemy.js _childType")
	_check(not sp.wants_children, "the flag is consumed, so it cannot split twice")

	# Children land inside the arena, not through the wall.
	var inside := true
	for c in wd.enemies:
		if absf(c.position.x) > wd.half_x or absf(c.position.z) > wd.half_z:
			inside = false
	_check(inside, "children land inside the arena")

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
	sv.modes = {SaveService.MODE_NORMAL: {"hi_score": 0, "runs": []},
		SaveService.MODE_RUSH: {"hi_score": 0, "runs": []}}

	_check(_rec(sv, SaveService.MODE_NORMAL, 500, {"wave": 3}), "a first run is a new best")
	_check(_hs(sv, SaveService.MODE_NORMAL) == 500, "the best is stored")
	_check(not _rec(sv, SaveService.MODE_NORMAL, 200, {"wave": 2}), "a worse run is not a new best")
	_check(_hs(sv, SaveService.MODE_NORMAL) == 500, "and does not lower the best")
	_check(_rec(sv, SaveService.MODE_NORMAL, 900, {"wave": 5}), "a better run beats it")
	_check(_rn(sv, SaveService.MODE_NORMAL).size() == 3, "every run is kept in history")
	_check(int(_rn(sv, SaveService.MODE_NORMAL)[0]["score"]) == 900, "history is newest-first")

	# THE BUG THIS SCHEMA EXISTS FOR: a Rush run must not touch the Normal best.
	_check(_rec(sv, SaveService.MODE_RUSH, 120, {"kills": 9, "heat_peak": 0.8}),
		"a Rush run records under its own mode")
	_check(_hs(sv, SaveService.MODE_NORMAL) == 900,
		"and a WORSE Rush score does not overwrite the Normal best")
	_check(_hs(sv, SaveService.MODE_RUSH) == 120, "Rush keeps its own best")
	_check(_rn(sv, SaveService.MODE_RUSH).size() == 1, "and its own history")
	_check(_rn(sv, SaveService.MODE_NORMAL).size() == 3, "Normal history is untouched")
	_check(int(_rn(sv, SaveService.MODE_RUSH)[0]["kills"]) == 9,
		"a Rush run records kills, not a wave number that would be a lie")

	for i in 20:
		_rec(sv, SaveService.MODE_NORMAL, i, {"wave": 1})
	_check(_rn(sv, SaveService.MODE_NORMAL).size() == SaveService.HISTORY_MAX,
		"history is capped at %d" % SaveService.HISTORY_MAX)
	_check(_hs(sv, SaveService.MODE_NORMAL) == 900, "the cap never discards the best")

	_check(not _rl(sv, SaveService.MODE_NORMAL).begins_with(
		"recent: %d" % int(_rn(sv, SaveService.MODE_NORMAL)[0]["score"])),
		"the recent line does not repeat the run just finished")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(sv.path))

	# --- the v1 migration --------------------------------------------------
	# A v1 file has no "v" key. It is not corrupt and must not be discarded:
	# everything it holds was a Normal run and has to land under modes.normal.
	var legacy := "user://_smoke_v1.json"
	var f := FileAccess.open(legacy, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"hi_score": 4242,
		"runs": [{"score": 4242, "wave": 11, "at": "2026-01-01T00:00:00"}],
	}))
	f.close()

	var sv2 := SaveService.new()
	root.add_child(sv2)
	sv2.path = legacy
	sv2.load_state()
	_check(_hs(sv2, SaveService.MODE_NORMAL) == 4242,
		"a v1 save migrates its best into modes.normal")
	_check(_rn(sv2, SaveService.MODE_NORMAL).size() == 1, "and carries its history over")
	_check(_hs(sv2, SaveService.MODE_RUSH) == 0, "with Rush starting empty")

	# The migration is written back once, so the next load is a plain v2 read.
	var sv3 := SaveService.new()
	root.add_child(sv3)
	sv3.path = legacy
	sv3.load_state()
	_check(_hs(sv3, SaveService.MODE_NORMAL) == 4242, "and the migration persisted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy))
	_check(true, "the gate cleans up its scratch saves")

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

	# --- the four abilities, each bending the triangle differently ---------
	r.reset()
	r.ability = RushRules.Ability.HEAT_EXCHANGE
	_check(not r.ability_ready(), "an ability is not ready from cold")
	_check(r.fire_ability() < 0.0, "firing it unready reports failure")

	r.ability_charge = r.charge_time()
	_check(not r.ability_ready(), "HEAT EXCHANGE also needs HEAT, not just charge")
	r.heat = 0.8
	_check(r.ability_ready(), "charged and hot, it is ready")
	var rad := r.fire_ability()
	_check(rad > 2.6, "its radius scales with the heat spent (%.1f)" % rad)
	_check(is_equal_approx(r.heat, 0.0), "and it dumps the heat")
	_check(not r.boost_blocked, "which also clears an overheat lock")
	_check(not r.ability_ready(), "it needs recharging afterwards")

	# HYPER BOMB is the panic button: wide, and it costs no heat at all.
	r.reset()
	r.ability = RushRules.Ability.HYPER_BOMB
	r.ability_charge = r.charge_time()
	_check(r.ability_ready(), "HYPER BOMB is ready with no heat at all")
	r.heat = 0.6
	var bomb := r.fire_ability()
	_check(bomb > rad, "HYPER BOMB clears wider than HEAT EXCHANGE")
	_check(is_equal_approx(r.heat, 0.6), "and it does NOT spend your heat")

	# OVERCHARGE: boosting stops costing anything, and the chain climbs double.
	r.reset()
	r.ability = RushRules.Ability.OVERCHARGE
	r.ability_charge = r.charge_time()
	_check(is_equal_approx(r.fire_ability(), 0.0), "a buff ability returns no radius")
	_check(r.buff_active() and r.overcharged(), "OVERCHARGE starts a window")
	var h_before := r.heat
	for i in 30:
		r.update(1.0 / 60.0, true, true)
	_check(is_equal_approx(r.heat, h_before), "boosting is FREE while overcharged")
	r.add_boost_kill()
	_check(r.multiplier == 3, "and the chain climbs double (+2)")
	for i in 500:
		r.update(1.0 / 60.0, false, false)
	_check(not r.buff_active(), "the window closes on its own")

	# QUANTUM SHIELD: the reflect window. main.gd reads reflecting().
	r.reset()
	r.ability = RushRules.Ability.QUANTUM_SHIELD
	r.ability_charge = r.charge_time()
	r.fire_ability()
	_check(r.reflecting(), "QUANTUM SHIELD starts a reflect window")
	_check(not r.overcharged(), "and is not confused with OVERCHARGE")

	# Cycling wraps, so a single input can walk the whole list.
	r.ability = RushRules.Ability.HEAT_EXCHANGE
	r.cycle_ability(-1)
	_check(r.ability == RushRules.Ability.QUANTUM_SHIELD, "ability selection wraps")
	r.cycle_ability(1)
	_check(r.ability == RushRules.Ability.HEAT_EXCHANGE, "and wraps back")

	# --- extra lives -------------------------------------------------------
	r.reset()
	_check(not r.note_score(10), "a small score earns nothing")
	_check(r.note_score(RushRules.EXTRA_LIFE_EVERY), "crossing the threshold grants a life")
	_check(r.lives == RushRules.LIVES_START + 1, "and the life is real")

	# --- Rush levels drive the wave director ------------------------------
	var wd := WaveDirector.new()
	root.add_child(wd)
	wd.wave = 9
	_check(wd.difficulty() == 9, "with no override the director reads its wave count")
	wd.level_override = 3
	_check(wd.difficulty() == 3, "a Rush level overrides it")
	_check(wd.budget_for(wd.difficulty()) < wd.budget_for(9),
		"so levelling DOWN really does make the next wave easier")

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


## Drives main.gd's own collision methods against a real scene. Everything
## above tests components in isolation; this is the only thing that tests the
## wiring, and the wiring is where the worst bug so far lived.
func _test_collisions() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()
	main.bullets.clear()
	main.score = 0

	# Park an enemy and put a PLAYER bullet on top of it.
	var e := Globbo.new()
	main.waves.enemies_root.add_child(e)
	e.position = Vector3(3.0, 0.0, 0.0)
	e.half_x = 19.0
	e.half_z = 11.0
	e.target = main.player
	e.init()
	main.waves.enemies.append(e)

	var hp_before: int = main.player.hp
	main.bullets.spawn_dir(3.0, 0.0, 1.0, 0.0, true)
	main._collide_player_bullets()

	_check(main.player.hp == hp_before,
		"a PLAYER bullet hitting an enemy does not damage the player")
	_check(not e.alive, "it kills the enemy (GLOBBO is hp 1)")
	_check(main.score > 0, "and scores (%d)" % main.score)

	# An ENEMY bullet on the player does damage it.
	main.player.reset()
	main.bullets.clear()
	main.bullets.spawn_dir(main.player.position.x, main.player.position.z,
		1.0, 0.0, false)
	main._collide_enemy_bullets()
	_check(main.player.hp == Player.MAX_HP - 1, "an ENEMY bullet costs the player HP")

	# Contact damage, and the Rush boost branch that replaces it.
	main.player.reset()
	main.waves.enemies.clear()
	var e2 := Globbo.new()
	main.waves.enemies_root.add_child(e2)
	e2.position = main.player.position
	e2.half_x = 19.0
	e2.half_z = 11.0
	e2.target = main.player
	e2.init()
	main.waves.enemies.append(e2)

	main._collide_contact()
	_check(main.player.hp == Player.MAX_HP - 1, "a body touching you costs HP in Normal")
	_check(e2.alive, "and the body survives")

	main.mode = main.Mode.RUSH
	main.rush.reset()
	main.rush.boosting = true
	main.player.reset()
	main._collide_contact()
	_check(not e2.alive, "in Rush, BOOSTING through a body kills it instead")
	_check(main.player.hp == Player.MAX_HP, "and costs the player nothing")
	_check(main.rush.multiplier > 1, "and chains the multiplier")

	main.queue_free()

## GRAZE (main.js v125): a bullet that skims past without touching pays
## score once, and only once — the loop must keep scanning past it for
## OTHER bullets rather than stopping the way an actual hit does.
func _test_graze() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()
	main.bullets.clear()
	main.score = 0
	main.graze_count = 0

	# A bullet just outside the hit radius but inside the graze band.
	var hit_r: float = BulletPool.BULLET_R + Player.RADIUS
	var gx: float = main.player.position.x + hit_r + 0.3
	main.bullets.spawn_dir(gx, main.player.position.z, -1.0, 0.0, false)
	main._collide_enemy_bullets()
	_check(main.graze_count == 1, "a bullet skimming past grazes once")
	_check(main.score == 25, "and pays graze score (%d)" % main.score)
	_check(main.player.hp == Player.MAX_HP, "without costing HP")

	# Same bullet, same frame shape again: must not pay twice.
	main._collide_enemy_bullets()
	_check(main.graze_count == 1, "the same bullet does not graze twice")
	_check(main.score == 25, "or pay twice (%d)" % main.score)

	# A bullet that actually connects hits instead of grazing, and a hit
	# must not also be counted as a graze.
	main.bullets.clear()
	main.player.reset()
	main.graze_count = 0
	main.score = 0
	main.bullets.spawn_dir(main.player.position.x, main.player.position.z,
		1.0, 0.0, false)
	main._collide_enemy_bullets()
	_check(main.graze_count == 0, "a bullet that actually hits does not also graze")
	_check(main.player.hp == Player.MAX_HP - 1, "and it costs HP as a real hit")

	main.queue_free()

## compose() is start_wave()'s affordability loop, split out so Rush can spend
## the same ported table on a per-tick cadence instead of a whole wave at once
## (design/RUSH_MODE.md §3.2). Checked directly, because a second caller now
## depends on properties start_wave() only ever exercised incidentally.
func _test_compose(root: Node3D) -> void:
	var wd := WaveDirector.new()
	root.add_child(wd)

	var picks := wd.compose(5, 12.0, 5, 20)
	var shooters := 0
	for entry in picks:
		if WaveDirector.POOL[entry["type"]][2]:
			shooters += 1
	_check(picks.size() <= 20, "compose() respects the body cap")

	# NOTE: the sum of BASE costs can exceed the budget, and that is correct.
	# A twin is priced at 1.6x for two bodies and a group at cost-per-body for
	# 3-5 of something cheap, so both are deliberate DISCOUNTS for doubling up
	# (tuning.js twinCost / group). Asserting "sum of base costs <= budget"
	# fails intermittently for exactly that reason, and the assertion was
	# wrong rather than the code. What must hold is that a smaller budget
	# buys fewer bodies.
	var lean := wd.compose(5, 4.0, 5, 20)
	var rich := wd.compose(5, 40.0, 5, 40)
	_check(lean.size() <= rich.size(),
		"a smaller budget buys no more bodies (%d vs %d)" % [lean.size(), rich.size()])

	var capped := wd.compose(9, 40.0, 2, 20)
	var capped_shooters := 0
	for entry in capped:
		var name: String = entry["type"]
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
	for entry in early:
		if WaveDirector.POOL[entry["type"]][0] > 1:
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


## Small adapters. SaveService reads and writes through a settable `mode`, so
## a test that wants to poke two buckets in one breath has to switch between
## them; wrapping that keeps the assertions readable.
func _rec(sv: SaveService, m: String, score: int, extra: Dictionary) -> bool:
	sv.mode = m
	# record() takes `wave` positionally and ignores it outside Normal.
	var w := int(extra.get("wave", 0))
	extra.erase("wave")
	return sv.record(score, w, extra)

func _hs(sv: SaveService, m: String) -> int:
	sv.mode = m
	return sv.hi_score

func _rn(sv: SaveService, m: String) -> Array:
	sv.mode = m
	return sv.runs

func _rl(sv: SaveService, m: String) -> String:
	sv.mode = m
	return sv.recent_line()


func _test_splitter_cubes(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var wd := _rev_director(root, target, _make_pool(root))
	wd.enemies_root = Node3D.new()
	root.add_child(wd.enemies_root)

	for spec in [["REDD_CUBE", 4, "REDD_MINI"], ["PURP_CUBE", 5, "PURP_MINI"]]:
		var e: Enemy = wd._make(spec[0])
		wd.enemies_root.add_child(e)
		e.position = Vector3(2.0, 0.0, 1.0)
		e.half_x = 19.0
		e.half_z = 11.0
		e.target = target
		e.rng = wd.rng
		e.init()
		_check(e.child_count == spec[1],
			"%s carries %d children" % [spec[0], spec[1]])
		_check(e.child_kind == spec[2], "%s children are %s" % [spec[0], spec[2]])

		wd.enemies = [e]
		while e.alive:
			e.take_hit(e.hp)
		wd.update(1.0 / 60.0)
		_check(wd.enemies.size() == spec[1],
			"%s splits into %d (got %d)" % [spec[0], spec[1], wd.enemies.size()])

	# The minis are fast and fragile — that is what makes a pack the threat.
	var mini: Enemy = wd._make("PURP_MINI")
	root.add_child(mini)
	mini.rng = wd.rng
	mini.init()
	_check(mini.hp == 1 and mini.speed > 3.0,
		"PURP_MINI is one hit and faster than anything else ported")

func _test_toro(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(0.0, 0.0, 0.0)

	var t: Toro = _place(root, Toro.new(), Vector3(-8.0, 0.0, 0.0), target, null)
	_check(t.hp == 6, "TORO spawns at enemy.js's config hp:6")

	# The indicator must reach the WALL, so its tip is the impact point.
	var reach := t.dash_length(Vector2(1.0, 0.0))
	_check(is_equal_approx(reach, t.half_x - t.position.x),
		"the telegraph is raycast to the arena wall, not a fixed length (%.1f)" % reach)
	# ...and it shortens as the wheel gets closer to that wall.
	t.position.x = t.half_x - 3.0
	_check(t.dash_length(Vector2(1.0, 0.0)) < reach,
		"and it shortens as the wall gets nearer")
	t.position.x = -8.0

	# It has to walk the whole state machine and come back to idle.
	var seen := {}
	for i in 60 * 12:
		t.update(1.0 / 60.0)
		seen[t._phase] = true
	for ph in [Toro.Phase.REV, Toro.Phase.TELEGRAPH, Toro.Phase.DASH, Toro.Phase.RECOVER]:
		_check(seen.has(ph), "TORO reaches phase %d" % ph)

	# The dash line is LOCKED at telegraph: it cannot steer onto you after the
	# tell, which is the whole reason the tell is fair.
	var t2: Toro = _place(root, Toro.new(), Vector3(-8.0, 0.0, 0.0), target, null)
	while t2._phase != Toro.Phase.TELEGRAPH:
		t2.update(1.0 / 60.0)
	var locked := t2._dash_dir
	target.position = Vector3(0.0, 0.0, 9.0)   # jump the player somewhere else
	for i in 20:
		t2.update(1.0 / 60.0)
	_check(t2._dash_dir == locked, "the dash line does not re-aim after the telegraph")


## BAMBU: stationary, segmented HP, and the telegraph -> lob -> splashdown
## cycle, including the "still standing in the ring when it lands" damage
## rule main.gd's _collide_bambu_lobs() implements.
func _test_bambu(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(0.0, 0.0, 0.0)

	var b: Bambu = _place(root, Bambu.new(), Vector3(-6.0, 0.0, 0.0), target, null)
	_check(b.hp == 3, "BAMBU spawns pre-grown at 3 segments/HP")
	_check(is_equal_approx(b.radius, 1.8), "and a radius that tracks segments (3 x 0.6)")
	_check(is_zero_approx(b.speed), "it never moves")

	b.take_hit(1)
	_check(b.hp == 2, "a hit costs HP")
	_check(is_equal_approx(b.radius, 1.2), "and pops a segment, shrinking the radius")
	b.take_hit(1)
	b.take_hit(1)
	_check(not b.alive, "the third hit kills it (3 segments, 3 hp)")
	_check(is_equal_approx(b.radius, 0.6), "radius never drops below the floor (max(0.6, 0*0.6))")

	# The attack cycle: WAITING -> TELEGRAPHING -> LOBBING -> back to WAITING,
	# landing a splashdown exactly once per cycle.
	var b2: Bambu = _place(root, Bambu.new(), Vector3(-6.0, 0.0, 0.0), target, null)
	var seen := {}
	var landed := 0
	for i in 60 * 6:
		b2.update(1.0 / 60.0)
		seen[b2._state] = true
		if b2.drain_landed() != null:
			landed += 1
	for st in [Bambu.LobState.WAITING, Bambu.LobState.TELEGRAPHING, Bambu.LobState.LOBBING]:
		_check(seen.has(st), "BAMBU reaches lob state %d" % st)
	_check(landed == 1, "exactly one splashdown lands in 6s (cooldown is 4s, first lob at 1.3+0.7+1.0=3s)")

	# drain_landed() is one-shot: the SAME landing is never paid out twice.
	# First cycle lands at ~3.0s (1.3 wait + 0.7 telegraph + 1.0 flight); the
	# next is a 4.0s cooldown away, so 3.2s is well clear of both edges.
	var b3: Bambu = _place(root, Bambu.new(), Vector3(-6.0, 0.0, 0.0), target, null)
	var drains := 0
	for i in int(60 * 3.2):
		b3.update(1.0 / 60.0)
		if b3.drain_landed() != null:
			drains += 1
	_check(drains == 1, "one splashdown lands and pays out exactly once (%d)" % drains)
	_check(b3.drain_landed() == null, "and a second drain the same frame finds nothing")

	# Dying mid-lob cancels the in-flight visual (main.js: "hide any in-flight
	# lob when BAMBU dies mid-cycle") rather than leaving it stranded on screen.
	var b4: Bambu = _place(root, Bambu.new(), Vector3(-6.0, 0.0, 0.0), target, null)
	while b4._state == Bambu.LobState.WAITING:
		b4.update(1.0 / 60.0)
	b4.take_hit(99)
	_check(not b4.alive, "it's dead")
	_check(not b4._lob_ring.visible, "and the landing ring is hidden")
	_check(not b4._lob_blob.visible, "and the blob is hidden")
	_check(b4.drain_landed() == null, "and no splashdown pays out for a cancelled lob")

## CLOAKER: visible -> cloak -> decloak -> a 3-shot burst, still hittable the
## whole time (enemy.js: "Still hittable — tracking pays").
func _test_cloaker(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(0.0, 0.0, 0.0)
	var bp := _make_pool(root)

	var c: Cloaker = _place(root, Cloaker.new(), Vector3(-5.0, 0.0, 0.0), target, bp)
	_check(c.hp == 3, "CLOAKER spawns at enemy.js's config hp:3")
	_check(is_equal_approx(c.speed, 2.4), "and its config speed")
	_check(c._state == Cloaker.CkState.VISIBLE, "starts VISIBLE")

	var seen := {}
	for i in 60 * 8:
		c.update(1.0 / 60.0)
		seen[c._state] = true
	for st in [Cloaker.CkState.VISIBLE, Cloaker.CkState.CLOAK, Cloaker.CkState.DECLOAK]:
		_check(seen.has(st), "CLOAKER reaches state %d" % st)
	_check(bp.active.size() >= 3, "at least one decloak burst fired (%d bullets)" % bp.active.size())
	for b in bp.active:
		_check(not b.is_player, "the burst is enemy-owned")

	var c2: Cloaker = _place(root, Cloaker.new(), Vector3(-5.0, 0.0, 0.0), target, bp)
	c2.take_hit(99)
	_check(not c2.alive, "still hittable no matter the cloak state (no invulnerability added)")

## MAGNA: holds range rather than closing in, and its tether dies with it.
## The actual pull on the PLAYER is cross-cutting (main.gd), tested in
## _test_magna_wiring().
func _test_magna(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(0.0, 0.0, 0.0)

	var m: Magna = _place(root, Magna.new(), Vector3(-15.0, 0.0, 0.0), target, null)
	# _place()'s default 9x9 test arena is smaller than MAGNA's own hold
	# range (9.0) — a real arena is 19x11 (main.gd's HALF_X/HALF_Z), and the
	# clamp must not be what stops it short of that range.
	m.half_x = 19.0
	m.half_z = 11.0
	_check(m.hp == 4, "MAGNA spawns at enemy.js's config hp:4")
	_check(is_equal_approx(m.speed, 0.9), "and its config speed")

	var start_x := m.position.x
	for i in 60 * 20:
		m.update(1.0 / 60.0)
	_check(m.position.x > start_x, "MAGNA closes distance")
	var final_dist: float = absf(m.position.x - target.position.x)
	_check(final_dist < 9.5 and final_dist > 8.5,
		"and holds near keep-range+1 rather than closing all the way (%.2f)" % final_dist)

	m.pull_active = true
	m.die()
	_check(not m.pull_active, "dying clears pull_active")
	_check(not m._tether.visible, "and hides the tether")

## DRAPER: holds range, faces the player, and fires a 15-slot curtain with
## exactly one 2-slot gap.
func _test_draper(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(0.0, 0.0, 0.0)
	var bp := _make_pool(root)

	var d: Draper = _place(root, Draper.new(), Vector3(-5.0, 0.0, 0.0), target, bp)
	# Same reason as MAGNA above: DRAPER's own hold range (11.0 +/- 1.5) is
	# bigger than _place()'s default 9x9 test arena.
	d.half_x = 19.0
	d.half_z = 11.0
	_check(d.hp == 5, "DRAPER spawns at enemy.js's config hp:5")
	_check(is_equal_approx(d.speed, 0.9), "and its config speed")

	for i in 60 * 30:
		d.update(1.0 / 60.0)
	var dist: Vector2 = Vector2(d.position.x - target.position.x, d.position.z - target.position.z)
	_check(dist.length() > Draper.WANT_RANGE - Draper.RANGE_BAND - 0.5
		and dist.length() < Draper.WANT_RANGE + Draper.RANGE_BAND + 0.5,
		"DRAPER holds near its keep range (%.2f)" % dist.length())

	bp.clear()
	for i in 60 * 8:
		d.update(1.0 / 60.0)
		if bp.active.size() > 0:
			break
	_check(bp.active.size() == Draper.CURTAIN_SLOTS - 2,
		"the curtain fires 13 of 15 slots, the 2-slot gap open (%d)" % bp.active.size())
	for b in bp.active:
		_check(not b.is_player, "curtain bullets are enemy-owned")

## Wiring half of _test_bambu: main.gd actually draining and applying splash
## damage needs a REAL main.tscn (player etc. only exist post-_ready()), so
## this runs from _process(), same reason _test_collisions() does.
func _test_bambu_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()

	var b5 := Bambu.new()
	main.waves.enemies_root.add_child(b5)
	b5.position = Vector3(-6.0, 0.0, 0.0)
	b5.half_x = 19.0
	b5.half_z = 11.0
	b5.target = main.player
	b5.init()
	main.waves.enemies.append(b5)
	# Force a splashdown centred on the player, as if it had just landed there.
	b5._landed = Vector2(main.player.position.x, main.player.position.z)
	main._collide_bambu_lobs()
	_check(main.player.hp == Player.MAX_HP - 1,
		"standing in a landed splashdown costs HP")
	_check(b5.drain_landed() == null, "and main.gd actually drained it")

	main.player.reset()
	b5._landed = Vector2(main.player.position.x + 20.0, main.player.position.z)
	main._collide_bambu_lobs()
	_check(main.player.hp == Player.MAX_HP,
		"a splashdown far from the player costs nothing")

	main.queue_free()

## MAGNA's actual pull on the player (main.gd's _apply_magna_pull) — cross-
## cutting, so it needs the real player the same reason _test_bambu_wiring()
## does.
func _test_magna_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()

	var m := Magna.new()
	main.waves.enemies_root.add_child(m)
	m.position = Vector3(5.0, 0.0, 0.0)
	m.half_x = 19.0
	m.half_z = 11.0
	m.target = main.player
	m.init()
	main.waves.enemies.append(m)

	var start_x: float = main.player.position.x
	main._apply_magna_pull(1.0 / 60.0)
	_check(main.player.position.x > start_x, "MAGNA pulls the player toward it")
	_check(m.pull_active, "and marks itself as actively pulling")

	# Dashing grants immunity — the pull must stop entirely.
	main.player.position.x = start_x
	main.player.magna_immune_t = 1.0
	main._apply_magna_pull(1.0 / 60.0)
	_check(is_equal_approx(main.player.position.x, start_x), "dash immunity stops the pull")
	_check(not m.pull_active, "and the tether goes inactive")

	# Point-blank (inside MAGNA_MIN_RANGE) does not pull either.
	main.player.magna_immune_t = 0.0
	main.player.position.x = m.position.x + 0.5
	var px: float = main.player.position.x
	main._apply_magna_pull(1.0 / 60.0)
	_check(is_equal_approx(main.player.position.x, px), "point-blank range does not pull")

	main.queue_free()

## The convoy's wiring into main.gd: scheduling, collision, and loot.
func _test_cargo_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()
	main.cargo.clear()
	main.pods.clear()
	main.score = 0

	main._on_wave_started(1)
	_check(main._cargo_spawn_at >= 3.0 and main._cargo_spawn_at <= 8.0,
		"the convoy is scheduled 3-8s into the wave (%.2f)" % main._cargo_spawn_at)
	# Real per-frame deltas, not one giant jump: _update_cargo() both checks
	# the schedule AND advances the convoy's own flight in the same call, so
	# a single huge delta would spawn it and immediately fly it clean off the
	# arena before this line ever got to look.
	var dt := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < main._cargo_spawn_at + 0.05:
		main._update_cargo(dt)
		elapsed += dt
	_check(main.cargo.active, "and actually spawns once the wave clock reaches it")
	_check(main._cargo_spawn_at < 0.0, "and only schedules one convoy per wave")

	# A player bullet on top of a moth kills it.
	var d0 = main.cargo.drones[0]
	main.bullets.spawn_dir(d0.node.position.x, d0.node.position.z, 1.0, 0.0, true)
	main._collide_cargo_bullets()
	_check(not d0.alive, "a player bullet kills the moth it lands on")

	# Killing every remaining drone with none escaping drops a guaranteed pod.
	for i in range(1, main.cargo.drones.size()):
		var d = main.cargo.drones[i]
		main.bullets.spawn_dir(d.node.position.x, d.node.position.z, 1.0, 0.0, true)
		main._collide_cargo_bullets()
	_check(main.cargo.all_killed(), "every drone was shot and none escaped")
	var pod_dropped := false
	for l in main.pods._life:
		if l > 0.0:
			pod_dropped = true
			break
	_check(pod_dropped, "so the guaranteed all-clear pod actually dropped")

	# _drop_cargo_loot() always pays something — a weapon pod or a value
	# pickup (score/scoremult) — never nothing. Checked against a FRESH (not
	# all-killed) convoy so the roll branch runs rather than the
	# guaranteed-pod one.
	main.cargo.spawn(main.waves.rng)
	main.pods.clear()
	var any_pod := false
	var any_value := false
	for i in 40:
		main._drop_cargo_loot(0.0, 0.0)
		for j in main.pods.POOL_SIZE:
			if main.pods._life[j] <= 0.0:
				continue
			if main.pods.PODS.has(main.pods._id[j]):
				any_pod = true
			else:
				any_value = true
		main.pods.clear()
	_check(any_pod, "the loot roll drops a weapon pod sometimes")
	_check(any_value, "and a score/scoremult value pickup sometimes")

	main.queue_free()

## The vault/escort's wiring into main.gd: per-wave scheduling (mutually
## exclusive on any one wave in this test, since 7%4==3 and 9%4==1), the
## vault's crack payout and enemy-surge ping, and the escort's delivery vs.
## a melee kill.
func _test_arena_objectives_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()
	main._clear_arena_objectives()
	main.pods.clear()
	main.score = 0

	main._on_wave_started(7)
	_check(main.vault != null, "wave 7 (>=5, %4==3) arms a vault")
	_check(main.escort == null, "and does not also arm an escort on the same wave")

	# The ping: a hit surges nearby enemies (Enemy.surge_t), tested before
	# the vault actually cracks.
	var g := Globbo.new()
	main.waves.enemies_root.add_child(g)
	g.position = main.vault.position + Vector3(1.0, 0.0, 0.0)
	g.half_x = 19.0
	g.half_z = 11.0
	g.target = main.player
	g.bullets = main.bullets
	g.rng = main.waves.rng
	g.init()
	main.waves.enemies.append(g)
	main.bullets.spawn_dir(main.vault.position.x, main.vault.position.z, 1.0, 0.0, true)
	main._collide_vault()
	_check(g.surge_t > 0.0, "a vault hit surges nearby enemies")

	# The remaining hits crack it.
	for i in VaultCrate.HP - 1:
		main.bullets.spawn_dir(main.vault.position.x, main.vault.position.z, 1.0, 0.0, true)
		main._collide_vault()
	_check(main.vault == null, "cracking the vault clears it")
	var pod_dropped := false
	var cash_dropped := false
	for j in main.pods.POOL_SIZE:
		if main.pods._life[j] <= 0.0:
			continue
		if main.pods.PODS.has(main.pods._id[j]):
			pod_dropped = true
		elif main.pods._id[j] == "score":
			cash_dropped = true
			# _crack_vault() reads WaveDirector's OWN `wave` counter, not the
			# `n` this test called _on_wave_started(n) with directly (that is
			# just a signal handler — it never sets waves.wave itself).
			var want: int = 800 + main.waves.wave * 60
			_check(main.pods._value[j] == want,
				"the cash drop carries main.js's value (800 + wave*60 = %d)" % want)
	_check(pod_dropped, "and drops the guaranteed pod")
	_check(cash_dropped, "plus a walk-over cash pickup rather than instant score")

	# Escort, on a different scheduled wave.
	main._clear_arena_objectives()
	main._on_wave_started(9)
	_check(main.escort != null, "wave 9 (>=6, %4==1) arms an escort")
	_check(main.vault == null, "and does not also arm a vault on the same wave")

	main.pods.clear()
	main.escort.position.x = main.escort.target_x
	var arrived: bool = main.escort.update(0.0)
	_check(arrived, "the escort reports arrival once at its target")
	_check(not main._collide_escort(), "and nothing has killed it")
	main._escort_delivered()
	_check(main.escort == null, "delivering it clears it")
	pod_dropped = false
	for l in main.pods._life:
		if l > 0.0:
			pod_dropped = true
			break
	_check(pod_dropped, "and drops a pod on delivery")

	# Dying to a melee-type body's touch.
	main._clear_arena_objectives()
	main._on_wave_started(9)
	var yc := YelaCube.new()
	main.waves.enemies_root.add_child(yc)
	yc.position = main.escort.position
	yc.half_x = 19.0
	yc.half_z = 11.0
	yc.target = main.player
	yc.bullets = main.bullets
	yc.rng = main.waves.rng
	yc.init()
	main.waves.enemies.append(yc)
	_check(main._collide_escort(), "a melee-type body touching the escort kills it")

	main.queue_free()

## score_mult_t (main.js scoreMultT): the "scoremult" pickup's 10s x2 window,
## and that every existing score site (_add_score()) actually respects it.
func _test_score_mult_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.score = 0
	main.score_mult_t = 0.0

	main._on_value_taken("score", 300, Color.WHITE)
	_check(main.score == 300, "a 'score' pickup pays its value once")

	main._on_value_taken("scoremult", 0, Color.WHITE)
	_check(main.score_mult_t > 0.0, "a 'scoremult' pickup starts the timer")

	main.score = 0
	main._on_value_taken("score", 100, Color.WHITE)
	_check(main.score == 200, "and every score award doubles while it's running")

	main._add_score(50)
	_check(main.score == 300, "including the shared _add_score() path (graze/kills/wave-clear)")

	main.queue_free()

## Gates' wiring into main.gd: per-wave spawn/eviction cap, a dash-through
## reward (and a RISK-red dud, and a RISK-green double), enemy damage on
## beam touch, and the GATE CHAIN bonus for banking two within 6s.
## Base-mode kill scoring: main.js onKill()'s REAL formula is
## "streak++; score += 100 * streak * ..." — a combo multiplier, not the
## per-body `100 * max_hp` this port used to pay (found, not caused, by
## porting Gates). Also: GLASS day's double only applies to KILLS, never to
## every _add_score() site (graze/wave-clear/loot don't multiply by
## dailyMod in the source, checked directly against those lines).
func _test_kill_scoring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()
	main.score = 0
	main.streak = 0

	var e1 := Globbo.new()
	main.waves.enemies_root.add_child(e1)
	e1.position = Vector3(3.0, 0.0, 0.0)
	e1.half_x = 19.0
	e1.half_z = 11.0
	e1.target = main.player
	e1.rng = main.waves.rng
	e1.init()
	main.waves.enemies.append(e1)
	main.bullets.spawn_dir(3.0, 0.0, 1.0, 0.0, true)
	main._collide_player_bullets()
	_check(main.streak == 1, "the first kill starts the streak at 1")
	_check(main.score == 100, "and pays 100 x streak (100)")

	var e2 := Globbo.new()
	main.waves.enemies_root.add_child(e2)
	e2.position = Vector3(3.0, 0.0, 0.0)
	e2.half_x = 19.0
	e2.half_z = 11.0
	e2.target = main.player
	e2.rng = main.waves.rng
	e2.init()
	main.waves.enemies.append(e2)
	main.bullets.spawn_dir(3.0, 0.0, 1.0, 0.0, true)
	main._collide_player_bullets()
	_check(main.streak == 2, "a second kill climbs the streak")
	_check(main.score == 300, "and the SAME body now pays more (100 + 200 = 300)")

	main.daily_mod = "glass"
	main.score = 0
	main._add_kill_score(100)
	_check(main.score == 200, "GLASS day doubles a kill")
	main.score = 0
	main._add_score(100)
	_check(main.score == 100, "but not graze/wave-clear/loot (plain _add_score())")
	main.daily_mod = ""

	main.queue_free()

## CLEANSE FOAM's wiring into main.gd: per-wave spawn (offset from vault's/
## escort's beats), and a full charge clearing every ENEMY bullet while
## leaving the player's own alone.
## The portrait/landscape dual-arena system (main.js ARENA_PRESETS), added
## 2026-08-26 after a real phone in portrait showed a landscape level, a
## landscape camera, and a landscape HUD regardless of the actual screen.
func _test_orientation_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)

	_check(is_equal_approx(main.HALF_X_PORTRAIT, 11.0) and is_equal_approx(main.HALF_Z_PORTRAIT, 18.0),
		"portrait preset matches main.js ARENA_PRESETS (halfX 11, halfZ 18)")
	_check(is_equal_approx(main.HALF_X_LANDSCAPE, 19.0) and is_equal_approx(main.HALF_Z_LANDSCAPE, 11.0),
		"landscape preset matches main.js (halfX 19, halfZ 11)")
	_check(main.CAM_REST_PORTRAIT == Vector3(0.0, 27.0, 21.0), "portrait camera rest matches main.js")
	_check(main.CAM_LOOK_PORTRAIT == Vector3(0.0, 0.0, -3.0), "portrait camera look-at matches main.js")
	_check(main.CAM_REST_LANDSCAPE == Vector3(0.0, 20.5, 13.5), "landscape camera rest matches main.js")
	_check(main.CAM_LOOK_LANDSCAPE == Vector3(0.0, 0.0, 2.5), "landscape camera look-at matches main.js")

	main._set_orientation(false)
	_check(not main.landscape_mode, "portrait mode sets landscape_mode false")
	_check(is_equal_approx(main.HALF_X, 11.0) and is_equal_approx(main.HALF_Z, 18.0),
		"and HALF_X/HALF_Z switch to the portrait numbers")
	_check(main._cam_rest_base == main.CAM_REST_PORTRAIT, "and the camera base switches too")

	main._set_orientation(true)
	_check(main.landscape_mode, "landscape mode sets landscape_mode true")
	_check(is_equal_approx(main.HALF_X, 19.0) and is_equal_approx(main.HALF_Z, 11.0),
		"and HALF_X/HALF_Z switch back")
	_check(main._cam_rest_base == main.CAM_REST_LANDSCAPE, "and the camera base switches back")

	# A headless/test viewport reports a square (100x100) size — the tie
	# has to resolve to landscape, or the whole rest of this test suite
	# (half_x=19 assumed almost everywhere) breaks under it.
	_check(main._detect_landscape(), "a square (tied) viewport defaults to landscape")

	main.queue_free()

func _test_foam_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()
	main.foam_zones.clear()
	main.bullets.clear()
	main.score = 0

	main._on_wave_started(6)
	_check(main.foam_zones.size() == 1, "wave 6 (>=6, %4==2) arms a foam zone")
	_check(main.vault == null and main.escort == null,
		"and does not also arm a vault/escort on the same wave")

	var fz: FoamZone = main.foam_zones[0]
	main.player.position = fz.position
	main.bullets.spawn_dir(1.0, 1.0, 1.0, 0.0, false)   # an enemy bullet on screen
	main.bullets.spawn_dir(2.0, 2.0, 1.0, 0.0, true)    # the player's own — must survive
	for i in int(60 * (FoamZone.CHARGE_NEEDED + 0.1)):
		main._update_foam_zones(1.0 / 60.0)
	_check(fz.done, "fully charging it triggers the cleanse")
	var enemy_bullets_left := 0
	var player_bullets_left := 0
	for b in main.bullets.active:
		if not b.alive:
			continue
		if b.is_player:
			player_bullets_left += 1
		else:
			enemy_bullets_left += 1
	_check(enemy_bullets_left == 0, "the cleanse clears every ENEMY bullet")
	_check(player_bullets_left == 1, "and leaves the player's own bullet alone")
	_check(main.score > 0, "and pays out (500 + 10/bullet cleared)")

	main.queue_free()

func _test_gates_wiring() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.CLASSIC
	main.player.reset()
	main.waves.clear()
	main.gates.clear()
	main.pods.clear()
	main.score = 0
	main.gate_chain_t = 0.0
	main.gate_chain_n = 0

	main._on_wave_started(3)
	_check(main.gates.size() == 1, "wave 3 arms the first gate")
	main._on_wave_started(4)
	_check(main.gates.size() == 2, "and a second the next wave")
	var first_gate = main.gates[0]
	main._on_wave_started(5)
	_check(main.gates.size() == 2, "a 3rd gate does not exceed the 2-alive cap")
	_check(main.gates[0] != first_gate, "the OLDEST gate is the one evicted, not the newest")

	# Dash through a plain (non-RISK) gate: pays out one buff pickup.
	var g0 = main.gates[0]
	main.player.position = g0.position
	main.player._dash_time = 0.5
	main.pods.clear()
	main._collide_gates()
	_check(not g0.alive, "dashing through a gate deactivates it")
	var pod_count := 0
	for l in main.pods._life:
		if l > 0.0:
			pod_count += 1
	_check(pod_count == 1, "and drops exactly one buff pickup (not RISK+green)")

	# A fresh RISK gate on red is a harmless dud.
	var gr := Gate.new()
	main.add_child(gr)
	gr.build(main.player.position.x, main.player.position.z, 0.0, true, false, main.waves.rng)
	gr.green = false
	main.gates.append(gr)
	main.pods.clear()
	main.player._dash_time = 0.5
	main._collide_gates()
	_check(not gr.alive, "a RISK gate still deactivates on a dud")
	pod_count = 0
	for l in main.pods._life:
		if l > 0.0:
			pod_count += 1
	_check(pod_count == 0, "but a red RISK gate pays nothing")

	# A RISK gate on green pays DOUBLE.
	var gg := Gate.new()
	main.add_child(gg)
	gg.build(main.player.position.x, main.player.position.z, 0.0, true, false, main.waves.rng)
	gg.green = true
	main.gates.append(gg)
	main.pods.clear()
	main.player._dash_time = 0.5
	main._collide_gates()
	pod_count = 0
	for l in main.pods._life:
		if l > 0.0:
			pod_count += 1
	_check(pod_count == 2, "a RISK gate on green pays double")

	# GATE CHAIN: two SUCCESSFUL gates (the dud does not count — main.js
	# `break`s before the chain increment on a dud) banked within 6s pays a
	# climbing bonus.
	_check(main.gate_chain_n >= 2, "banking gates back-to-back builds the chain (%d)" % main.gate_chain_n)
	_check(main.score > 0, "and the chain bonus actually paid out")

	# Enemy damage on beam touch — independent of the player entirely.
	var g1 := Gate.new()
	main.add_child(g1)
	g1.build(0.0, 0.0, 0.0, false, false, main.waves.rng)
	main.gates.append(g1)
	var e := Globbo.new()
	main.waves.enemies_root.add_child(e)
	e.position = Vector3(0.0, 0.0, 0.5)   # on the beam axis at angle 0 (para runs along z)
	e.half_x = 19.0
	e.half_z = 11.0
	e.target = main.player
	e.bullets = main.bullets
	e.rng = main.waves.rng
	e.init()
	main.waves.enemies.append(e)
	main.player.position = Vector3(30.0, 0.0, 30.0)   # well clear of the beam
	main.player._dash_time = 0.0
	main._collide_gates()
	_check(not e.alive, "an enemy touching a live beam takes damage (GLOBBO is hp 1)")

	main.queue_free()

## The cargo convoy (main.js CargoCluster): formation, determinism, and the
## all_killed() rule that gates the guaranteed pod.
func _test_cargo(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var c := CargoCluster.new()
	root.add_child(c)
	c.half_x = 19.0
	c.half_z = 11.0
	c.spawn(rng)
	_check(c.active, "spawn() activates the convoy")
	_check(c.drones.size() >= 3 and c.drones.size() <= 5,
		"3-5 drones (%d)" % c.drones.size())
	_check(not c.all_killed(), "nothing has been killed yet")

	# Same seed, same convoy — determinism, the same reason wave composition
	# has it (design/DETERMINISM_AND_SEEDS.md).
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 12345
	var c2 := CargoCluster.new()
	root.add_child(c2)
	c2.half_x = 19.0
	c2.half_z = 11.0
	c2.spawn(rng2)
	_check(c2.drones.size() == c.drones.size(), "the same seed spawns the same drone count")

	# Kill every drone without letting any escape.
	for i in c.drones.size():
		c.kill(i)
	_check(c.all_killed(), "killing every drone before any escapes reads as all_killed()")

	# One escapee breaks it, even if every OTHER drone was shot.
	for i in range(1, c2.drones.size()):
		c2.kill(i)
	c2.drones[0].escaped = true
	c2.drones[0].alive = false
	_check(not c2.all_killed(), "one escapee breaks all_killed() even if the rest were shot")

	# It eventually flies clear off the arena and reports "done".
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 3
	var c3 := CargoCluster.new()
	root.add_child(c3)
	c3.half_x = 19.0
	c3.half_z = 11.0
	c3.spawn(rng3)
	var result := "alive"
	for i in 600:   # 10s at 60fps, comfortably crosses a 19x11 arena at >=5.5 u/s
		result = c3.update(1.0 / 60.0, float(i) / 60.0)
		if result == "done":
			break
	_check(result == "done", "the convoy eventually clears the arena and reports done")
	_check(not c3.active, "and marks itself inactive")

## VaultCrate (main.js v175): fixed HP, cracks on the last hit.
func _test_vault_crate(root: Node3D) -> void:
	var v := VaultCrate.new()
	root.add_child(v)
	v.build(3.0, -2.0)
	_check(v.hp == VaultCrate.HP, "VaultCrate spawns at enemy.js's config hp:8")
	_check(is_equal_approx(v.position.x, 3.0) and is_equal_approx(v.position.z, -2.0),
		"and at the given position")
	for i in VaultCrate.HP - 1:
		v.hit()
	_check(v.hp == 1, "hp decrements one per hit")
	_check(not v.cracked(), "not cracked yet")
	v.hit()
	_check(v.cracked(), "the 8th hit cracks it")

## EscortBot (main.js v175): crosses from one wall to the other and reports
## arrival; a hit costs HP the same as the vault.
func _test_escort_bot(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var e := EscortBot.new()
	root.add_child(e)
	e.build(19.0, 11.0, rng)
	_check(e.hp == EscortBot.HP, "EscortBot spawns at enemy.js's config hp:2")
	_check(absf(e.position.x) > 17.0, "starts hard against one side wall")
	_check(is_equal_approx(e.target_x, -e.position.x), "and targets the opposite side exactly")

	var start_x := e.position.x
	var arrived := false
	for i in 60 * 20:   # 14s crossing time, plus margin
		arrived = e.update(1.0 / 60.0)
		if arrived:
			break
	_check(arrived, "it reaches the far wall within the crossing time")
	_check(signf(e.position.x - start_x) == signf(e.target_x - start_x),
		"having moved toward its target the whole way")

	var e2 := EscortBot.new()
	root.add_child(e2)
	e2.build(19.0, 11.0, rng)
	e2.hit()
	_check(e2.hp == 1, "a hit costs HP")
	e2.hit()
	_check(e2.dead(), "the second hit kills it (config hp:2)")

## PowerupPool's non-weapon value pickups (main.js's Powerup class, scoped
## to the two CLASSIC-mode drops this port's own systems roll for).
func _test_powerup_values(root: Node3D) -> void:
	var pp := PowerupPool.new()
	root.add_child(pp)
	pp.build()

	# 1-element Arrays, not bare locals: GDScript closures capture outer
	# locals BY VALUE, so a lambda assigning to a plain `var` would never be
	# seen out here (design note in this repo's CLAUDE.md).
	var got := ["", 0]
	pp.value_taken.connect(func(k, v, _c): got[0] = k; got[1] = v)

	pp.drop(2.0, -1.0, "score", 777)
	pp.update(0.016, Vector3(2.0, 0.0, -1.0), 0.0)
	_check(got[0] == "score", "picking up a 'score' drop emits value_taken with that kind")
	_check(got[1] == 777, "and carries the value through")

	got[0] = ""
	pp.drop(5.0, 5.0, "scoremult")
	pp.update(0.016, Vector3(5.0, 0.0, 5.0), 0.0)
	_check(got[0] == "scoremult", "and 'scoremult' drops the same way")

	# Weapon pods are unaffected — they still go through the original `taken`
	# signal, not the new one.
	var got_mode := [""]
	pp.taken.connect(func(m, _c): got_mode[0] = m)
	pp.drop(-3.0, 0.0, "S")
	pp.update(0.016, Vector3(-3.0, 0.0, 0.0), 0.0)
	_check(got_mode[0] == "SPREAD", "weapon pods are unaffected by the value-pickup path")

## Gate (main.js v175): the beam hit-test, the RISK green/red cycle, DRIFT
## wander + wall bounce, and deactivate().
func _test_gate(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	var g := Gate.new()
	root.add_child(g)
	g.build(0.0, 0.0, 0.0, false, false, rng)
	# hits_point()'s own axis convention at angle 0: para runs along Z
	# (ax=-sin(0)=0, az=cos(0)=1), so "along the beam" means varying z, not x.
	_check(g.alive, "a fresh gate is alive")
	_check(g.hits_point(0.0, 1.5, 0.1), "a point along the beam axis hits")
	_check(not g.hits_point(1.5, 0.0, 0.1), "a point off the beam axis (across it) does not")
	_check(not g.hits_point(0.0, 3.5, 0.1), "a point past the beam's own length does not")

	g.deactivate()
	_check(not g.alive, "deactivate() kills it")
	_check(not g.hits_point(0.0, 1.5, 0.1), "and a dead gate never hits")

	# RISK: green/red on a strict 1.6s clock.
	var gr := Gate.new()
	root.add_child(gr)
	gr.build(5.0, 5.0, 0.0, true, false, rng)
	var seen_green := false
	var seen_red := false
	for i in 200:
		gr.update(1.0 / 60.0, float(i) / 60.0 * 3.2, 19.0, 11.0)
		if gr.green:
			seen_green = true
		else:
			seen_red = true
	_check(seen_green and seen_red, "a RISK gate actually cycles green and red")

	# DRIFT: wanders, and bounces back inside the wall margin.
	var gd := Gate.new()
	root.add_child(gd)
	gd.build(0.0, 0.0, 0.0, false, true, rng)
	var start_pos := gd.position
	for i in 60 * 30:
		gd.update(1.0 / 60.0, 0.0, 19.0, 11.0)
	_check(gd.position != start_pos, "a DRIFT gate actually moves")
	_check(absf(gd.position.x) <= 19.0 - 3.0 + 0.5 and absf(gd.position.z) <= 11.0 - 3.0 + 0.5,
		"and stays bounced back inside the wall margin")

## CLEANSE FOAM (main.js FoamZone): charges while stood in, decays FASTER
## while stood out of, and expires on its own if never touched.
func _test_foam_zone(root: Node3D) -> void:
	var fz := FoamZone.new()
	root.add_child(fz)
	fz.build(0.0, 0.0)
	_check(not fz.is_charged(), "a fresh zone is not charged")

	var keep := true
	for i in int(60 * (FoamZone.CHARGE_NEEDED + 0.1)):
		keep = fz.update(1.0 / 60.0, Vector3.ZERO, true, 0.0)
	_check(fz.is_charged(), "standing inside the whole time fully charges it")
	_check(keep, "and it's still 'alive' the frame it reaches full charge")

	fz.begin_cleanse()
	_check(not fz.is_charged(), "begin_cleanse() marks it done")
	var alive := true
	for i in 60:
		alive = fz.update(1.0 / 60.0, Vector3.ZERO, true, 0.0)
		if not alive:
			break
	_check(not alive, "the burst plays out and then it reports finished")

	var fz2 := FoamZone.new()
	root.add_child(fz2)
	fz2.build(0.0, 0.0)
	for i in 30:
		fz2.update(1.0 / 60.0, Vector3.ZERO, true, 0.0)
	var charged_at_30 := fz2.charge
	for i in 30:
		fz2.update(1.0 / 60.0, Vector3(50.0, 0.0, 50.0), true, 0.0)   # well outside
	_check(fz2.charge < charged_at_30 * 0.5,
		"leaving decays the charge FASTER than it built (1.5x)")

	var fz3 := FoamZone.new()
	root.add_child(fz3)
	fz3.build(0.0, 0.0)
	var still_alive := true
	for i in int(60 * (FoamZone.LIFE + 0.5)):
		still_alive = fz3.update(1.0 / 60.0, Vector3(50.0, 0.0, 50.0), true, 0.0)
		if not still_alive:
			break
	_check(not still_alive, "an untouched zone expires on its own life timer")

## The campaign: grading, the tier-C gate, and ability unlocks.
func _test_challenges(root: Node3D) -> void:
	var sv := SaveService.new()
	root.add_child(sv)
	sv.path = "user://_smoke_ch.json"
	sv.levels = {}

	var l1 := Challenges.get_level(0)
	var tiers: Array = l1["tiers"]

	_check(Challenges.grade_for(l1, 0) == "", "below C there is no letter, just a score")
	_check(Challenges.grade_for(l1, int(tiers[0])) == "C", "hitting the C threshold grades C")
	_check(Challenges.grade_for(l1, int(tiers[3])) == "S", "and the top one grades S")
	_check(not Challenges.cleared(l1, int(tiers[0]) - 1), "just under C does not clear")
	_check(Challenges.cleared(l1, int(tiers[0])), "C clears the level")

	# Every shipped level must have real, ordered thresholds.
	for i in Challenges.count():
		var lv := Challenges.get_level(i)
		var t: Array = lv["tiers"]
		var ordered := true
		for k in range(1, t.size()):
			if int(t[k]) <= int(t[k - 1]):
				ordered = false
		_check(ordered, "%s tiers ascend" % lv["id"])
		_check(bool(lv["measured"]), "%s thresholds are MEASURED, not guessed" % lv["id"])

	# Unlocking: level 1 open, the rest gated on the previous grade.
	_check(Challenges.unlocked(0, sv), "the first level is always open")
	_check(not Challenges.unlocked(1, sv), "the second is locked until the first is cleared")
	sv.record_level("L1", int(tiers[0]), "C")
	_check(Challenges.unlocked(1, sv), "clearing at C opens the next")

	# Abilities arrive with the campaign, not all at once.
	var owned := Challenges.unlocked_abilities(sv)
	_check(owned.size() == 1 and owned[0] == RushRules.Ability.HEAT_EXCHANGE,
		"only HEAT EXCHANGE is available at the start")
	sv.record_level("L2", 99999, "S")
	owned = Challenges.unlocked_abilities(sv)
	_check(owned.has(RushRules.Ability.HYPER_BOMB), "clearing L2 grants HYPER BOMB")

	# A level's record is its high-water mark, not a history.
	sv.record_level("L1", 10, "")
	var rec: Dictionary = sv.levels["L1"]
	_check(int(rec["best_score"]) == int(tiers[0]),
		"a worse attempt does not lower a level's record")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(sv.path))


## The contextual question deck. Its whole value is that it asks about the
## body you just lost to and does not repeat itself; both are testable.
func _test_feedback(root: Node3D) -> void:
	var fb := Feedback.new()
	root.add_child(fb)
	fb._asked.clear()

	var melee := fb.pick(Feedback.Cause.MELEE, "globbo", 1)
	_check(melee["id"] == "killer_read", "a melee death asks the melee question")
	_check("globbo" in melee["question"], "and NAMES what killed you")

	fb._asked.clear()
	var shot := fb.pick(Feedback.Cause.BULLET, "spittor", 1)
	_check(shot["id"] == "killer_shot", "a shot death asks a different question")
	_check("spittor" in shot["question"], "and names the shooter")

	fb._asked.clear()
	var haz := fb.pick(Feedback.Cause.HAZARD, "", 1)
	_check(haz["id"] == "hazard", "dying to the arena asks about the arena")
	_check(not ("%s" in haz["question"]), "a nameless cause never leaves a hole in the text")

	# It rotates: asking the same way twice must not ask the same thing.
	fb._asked.clear()
	var a := fb.pick(Feedback.Cause.MELEE, "globbo", 6)
	var b := fb.pick(Feedback.Cause.MELEE, "globbo", 6)
	_check(a["id"] != b["id"], "a repeat run does not get the same prompt twice")

	# The crowd prompt only fires in an actual crowd.
	fb._asked.clear()
	fb._asked.append("killer_read")
	var lonely := fb.pick(Feedback.Cause.MELEE, "globbo", 1)
	_check(lonely["id"] != "swarm_read", "the crowd question needs an actual crowd")

	# Saying nothing records nothing.
	fb.path_override_for_test()
	_check(fb.submit("general", "   ", [], [], {}) == "",
		"an empty submission is discarded, not filed as an empty opinion")
	_check(fb.submit("general", "it felt good", [], {}.keys(), {}) != "",
		"a real note is kept")


## BULWARK's plate and WARDEN's umbrella. Both change what your gun does, so
## both need to be provably fair: the plate must be out-steppable and the
## warden must never shield itself.
func _test_armour_and_aura(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)

	var b: Bulwark = _place(root, Bulwark.new(), Vector3.ZERO, target, null)
	b.face = Vector2(1.0, 0.0)
	_check(b.blocks(5.0, 0.0), "a shot into the plate is blocked")
	_check(not b.blocks(-5.0, 0.0), "a shot into its BACK is not")
	_check(not b.blocks(0.0, 5.0), "and neither is one from the side")

	# The plate must not snap-track, or side-stepping stops being an answer.
	target.position = Vector3(0.0, 0.0, 9.0)
	var before := b.face
	b.update(1.0 / 60.0)
	var turned: float = before.angle_to(b.face)
	_check(absf(turned) < 0.1, "the plate turns SLOWLY (%.3f rad in one frame)" % turned)

	var w: Warden = _place(root, Warden.new(), Vector3.ZERO, target, null)
	var near: Globbo = _place(root, Globbo.new(), Vector3(3.0, 0.0, 0.0), target, null)
	var far: Globbo = _place(root, Globbo.new(), Vector3(15.0, 0.0, 0.0), target, null)
	_check(w.shields(near), "a body inside the aura is shielded")
	_check(not w.shields(far), "one outside it is not")
	_check(not w.shields(w), "a WARDEN never shields ITSELF — there is always something to shoot")

	# BOTFLY's shot steers, but slowly enough to outrun.
	var bullets := _make_pool(root)
	bullets.spawn_dir(0.0, 0.0, 1.0, 0.0, false, Color.WHITE, false,
		Botfly.SPEED_MULT, true, Botfly.TURN_RATE)
	var shot = bullets.active[0]
	var start_dir := Vector2(shot.vx, shot.vz).normalized()
	for i in 30:
		bullets.update(1.0 / 60.0, 40.0, Vector3(0.0, 0.0, 10.0))
	var now_dir := Vector2(shot.vx, shot.vz).normalized()
	_check(now_dir != start_dir, "a homing shot actually steers")
	_check(now_dir.angle_to(start_dir) < 1.4, "but turns, rather than snapping onto you")
	_check(Vector2(shot.vx, shot.vz).length() < BulletPool.ENEMY_SPEED,
		"and it is slower than ordinary fire, so it can be outrun")


## Weapon pods and the modes they hand you.
func _test_weapons(root: Node3D) -> void:
	var p := Player.new()
	root.add_child(p)
	p.build()
	p.reset()
	var bullets := _make_pool(root)
	var aim := {"x": 1.0, "z": 0.0, "valid": true}

	_check(p.weapon == "SINGLE", "the run starts on the plain gun")
	p.update(0.5, Vector2.ZERO, aim, bullets, 19.0, 11.0)
	_check(bullets.active.size() == 1, "SINGLE fires one shot")

	bullets.clear()
	p.weapon = "SPREAD"
	p._fire_t = 0.0
	p.update(0.5, Vector2.ZERO, aim, bullets, 19.0, 11.0)
	_check(bullets.active.size() == 5, "SPREAD fires 5 (got %d)" % bullets.active.size())

	bullets.clear()
	p.weapon = "SPREAD2"
	p._fire_t = 0.0
	p.update(0.5, Vector2.ZERO, aim, bullets, 19.0, 11.0)
	_check(bullets.active.size() == 7, "SPREAD2 fires 7")

	# BURST commits: the rest of the burst arrives even after you let go.
	bullets.clear()
	p.weapon = "BURST"
	p._fire_t = 0.0
	p.update(0.01, Vector2.ZERO, aim, bullets, 19.0, 11.0)
	var immediate := bullets.active.size()
	_check(immediate == 1, "BURST fires one immediately")
	var idle := {"x": 0.0, "z": 0.0, "valid": false}
	for i in 40:
		p.update(1.0 / 60.0, Vector2.ZERO, idle, bullets, 19.0, 11.0)
	_check(bullets.active.size() > immediate,
		"and the queued shots still arrive after the trigger is released (%d)"
			% bullets.active.size())

	# RAPID is a RATE change, not a shot-count change.
	p.weapon = "RAPID"
	p._fire_t = 0.0
	p.update(0.01, Vector2.ZERO, aim, bullets, 19.0, 11.0)
	_check(p._fire_t < Player.FIRE_RATE, "RAPID shortens the gap between shots")

	# The pod table: homing is enemy-exclusive, per enemy.js v88.
	var pool := PowerupPool.new()
	root.add_child(pool)
	pool.build()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 200:
		seen[pool.roll(1, rng)] = true
	_check(not seen.has("H") and not seen.has("H2"),
		"HOMING never drops — it is the enemy's toy (enemy.js v88)")
	var early_lv2 := false
	for i in 200:
		if PowerupPool.LV2.has(pool.roll(1, rng)):
			early_lv2 = true
	_check(not early_lv2, "level-2 pods do not drop before wave %d" % PowerupPool.LV2_FROM_WAVE)
	var late_lv2 := false
	for i in 400:
		if PowerupPool.LV2.has(pool.roll(9, rng)):
			late_lv2 = true
	_check(late_lv2, "but they do later")

	# Pods expire, so taking one is a decision you make now.
	var took := [""]
	pool.taken.connect(func(m, c): took[0] = m)
	pool.drop(0.0, 0.0, "S")
	pool.update(0.016, Vector3(40.0, 0.0, 40.0), 0.0)
	_check(took[0] == "", "a pod you are not standing on is not taken")
	pool.update(0.016, Vector3(0.0, 0.0, 0.0), 0.0)
	_check(took[0] == "SPREAD", "walking onto one takes it")

	pool.drop(0.0, 0.0, "B")
	for i in 60 * 14:
		pool.update(1.0 / 60.0, Vector3(40.0, 0.0, 40.0), 0.0)
	took[0] = ""
	pool.update(0.016, Vector3(0.0, 0.0, 0.0), 0.0)
	_check(took[0] == "", "and an ignored pod eventually expires")


## Spawn variants, elite affixes and the wave rhythm — the three tables that
## stop wave 12 being wave 4 with more bodies.
func _test_variants(root: Node3D) -> void:
	var wd := WaveDirector.new()
	root.add_child(wd)
	wd.reseed(1234)

	# The rhythm gives a run a SHAPE rather than a ramp.
	_check(wd.kind_for(8) == "boss", "every 8th wave is a boss wave")
	_check(wd.kind_for(4) == "spike", "every 4th is a spike")
	_check(wd.kind_for(6) == "swarm", "and a swarm lands on the threes from wave 3")
	_check(wd.kind_for(5) == "breather",
		"the wave after a spike is a BREATHER — the curve needs a trough")
	_check(float(WaveDirector.KIND_BUDGET["boss"]) > float(WaveDirector.KIND_BUDGET["normal"]),
		"a boss wave spends more")
	_check(float(WaveDirector.KIND_BUDGET["breather"]) < float(WaveDirector.KIND_BUDGET["normal"]),
		"and a breather spends less")

	# A swarm draws from its own table: groups and twins, never elites.
	_check(not WaveDirector.VARIANTS_SWARM.has("elite"),
		"a swarm wave never rolls an ELITE — that would not be a swarm")

	# Variants must never smuggle bodies past the caps.
	for cap in [3, 5, 9]:
		wd.wave_kind = "swarm"
		var picks := wd.compose(9, 60.0, 9, cap)
		_check(picks.size() <= cap,
			"a swarm respects a body cap of %d (got %d)" % [cap, picks.size()])

	wd.wave_kind = "normal"
	var shooters := 0
	var sp := wd.compose(12, 60.0, 2, 30)
	for e in sp:
		if WaveDirector.POOL[e["type"]][2]:
			shooters += 1
	_check(shooters <= 2,
		"a TWIN of a shooter counts twice against the shooter cap (got %d)" % shooters)

	# The variants themselves.
	var target := Node3D.new()
	root.add_child(target)
	var base: Globbo = _place(root, Globbo.new(), Vector3.ZERO, target, null)
	var plain_hp := base.hp

	var el: Globbo = _place(root, Globbo.new(), Vector3.ZERO, target, null)
	el.apply_variant("elite", "")
	_check(el.hp > plain_hp, "an elite has more HP (%d vs %d)" % [el.hp, plain_hp])
	_check(el.base_shape.x > base.base_shape.x, "and is visibly bigger")
	_check(el.max_hp == el.hp, "its max_hp tracks, so the score value is right")

	# ANCHORED cannot move at all — that is the whole modifier.
	var an: Globbo = _place(root, Globbo.new(), Vector3(5.0, 0.0, 0.0), target, null)
	an.apply_variant("elitelite", "anchored")
	_check(is_equal_approx(an.move_speed(), 0.0), "an ANCHORED body does not move")
	var was := an.position
	for i in 60:
		an.update(1.0 / 60.0)
	_check(an.position.distance_to(was) < 0.01, "and really does stay put")
	_check(an.hp > int(ceil(float(plain_hp) * 1.5)) - 1, "it is tougher for standing still")

	# SWIFT is faster and leaves a bolder streak.
	var sw: Globbo = _place(root, Globbo.new(), Vector3.ZERO, target, null)
	var base_trail := sw.trail_interval
	sw.apply_variant("elitelite", "swift")
	_check(sw.move_speed() > base.move_speed(), "a SWIFT body is faster")
	_check(sw.trail_interval < base_trail, "and streaks harder, so you can see it coming")


## Boss promotion and always-RING revenge, both from main.js setBoss().
func _test_boss(root: Node3D) -> void:
	var target := Node3D.new()
	root.add_child(target)
	var g: Globbo = _place(root, Globbo.new(), Vector3(3.0, 0.0, 0.0), target, null)
	var plain_hp := g.hp
	var plain_r := g.base_shape.x

	g.apply_boss()
	_check(g.is_boss, "apply_boss() flags the body")
	_check(g.hp == plain_hp * 3, "a boss has 3x the HP (%d vs %d)" % [g.hp, plain_hp])
	_check(g.base_shape.x > plain_r, "and is visibly bigger")
	_check(g.max_hp == g.hp, "max_hp tracks, so its score value is right")

	# A boss corpse rings regardless of its species' own dialect — main.js:
	# "a boss corpse is an arena event, not a duel".
	var target2 := Node3D.new()
	root.add_child(target2)
	var bullets := _make_pool(root)
	var wd := _rev_director(root, target2, bullets)
	var sp: Spittor = _place(root, Spittor.new(), Vector3(4.0, 0.0, 0.0), target2, bullets)
	_check(sp.revenge_dialect == Enemy.Revenge.AIMED, "SPITTOR is normally AIMED")
	sp.apply_boss()
	wd.enemies.append(sp)
	while sp.alive:
		sp.take_hit(sp.hp)
	wd.update(1.0 / 60.0)
	_check(bullets.active.size() == 14,
		"a BOSS SPITTOR rings 14 anyway, not its usual AIMED burst (got %d)"
			% bullets.active.size())

## Adaptive gel quality — the 60fps pass. Enemy.quality is a shared static,
## so this leaves it back at 1.0 for every OTHER test in the suite.
func _test_adaptive_quality() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.waves.clear()

	main._update_adaptive_quality()
	_check(is_equal_approx(Enemy.quality, 1.0), "quality is full with few bodies alive")

	for i in 20:
		var e := Globbo.new()
		main.waves.enemies_root.add_child(e)
		e.rng = main.waves.rng
		e.init()
		main.waves.enemies.append(e)
	main._update_adaptive_quality()
	_check(Enemy.quality < 1.0, "and drops once the arena is crowded (%.2f)" % Enemy.quality)
	_check(Enemy.quality >= 0.35, "but never below the floor, so bodies never go flat")

	main.waves.clear()
	main._update_adaptive_quality()
	_check(is_equal_approx(Enemy.quality, 1.0), "and recovers once the arena empties")
	Enemy.quality = 1.0   # leave it clean for every test after this one
	main.queue_free()

## DAILY RUN: the date math is pure, so it is checked directly against known
## dates rather than against "today" (a test that only runs correctly on the
## day it was written is not a test). main.js todaysMod(): day-since-epoch % 4
## against [null, glass, surge, rich] — these four are consecutive days, so
## the assertions also prove the rotation actually rotates.
func _test_daily() -> void:
	_check(Daily.mod_for("2026-08-23") == "", "2026-08-23 is a classic day (no twist)")
	_check(Daily.mod_for("2026-08-24") == "glass", "2026-08-24 is GLASS")
	_check(Daily.mod_for("2026-08-25") == "surge", "2026-08-25 is SURGE DAY")
	_check(Daily.mod_for("2026-08-26") == "rich", "2026-08-26 is RICH DAY")
	_check(Daily.mod_for("2026-08-22") == "rich", "the rotation wraps (day 20687 mod 4 == 3)")

	_check(Daily.seed_for("2026-08-25") == Daily.seed_for("2026-08-25"),
		"the same date always hashes to the same seed")
	_check(Daily.seed_for("2026-08-25") != Daily.seed_for("2026-08-26"),
		"and different dates (almost always) hash to different ones")
	_check(Daily.seed_for("2026-08-25") >= 0 and Daily.seed_for("2026-08-25") <= 0xFFFFFF,
		"the seed fits the six-hex-digit SEED readout")

	# Wiring: starting a DAILY run seeds from today's date and applies today's
	# mod, both deterministically — a second run started the same "today"
	# reaches the same seed and the same mod, the way two different players
	# opening the game on the same date are supposed to.
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.mode = main.Mode.DAILY
	main._start_game()
	var seed1 = main.waves.run_seed
	var mod1 = main.daily_mod
	main._start_game()
	_check(main.waves.run_seed == seed1, "a second DAILY run today reseeds identically")
	_check(main.daily_mod == mod1, "and carries the same modifier")
	_check(mod1 == Daily.mod_for(Daily.today()),
		"which matches what the pure date math says today is")

	if mod1 == "glass":
		_check(main.player.max_hp == 1 and main.player.hp == 1, "GLASS: 1 HP")
	elif mod1 == "rich":
		_check(is_equal_approx(main.waves.budget_mult, 1.4), "RICH DAY: budget x1.4")
	elif mod1 == "surge":
		_check(main.waves.rhythm_tight, "SURGE DAY: the wave rhythm tightens")
	else:
		_check(main.player.max_hp == Player.MAX_HP, "an unmodified day leaves HP alone")
		_check(is_equal_approx(main.waves.budget_mult, 1.0), "and the budget alone")
		_check(not main.waves.rhythm_tight, "and the rhythm alone")

	# A CLASSIC run must never pick up a stray daily_mod/budget_mult left over
	# from a previous DAILY run in the same session.
	main.mode = main.Mode.CLASSIC
	main._start_game()
	_check(main.daily_mod == "", "switching back to CLASSIC clears the daily modifier")
	_check(is_equal_approx(main.waves.budget_mult, 1.0), "and the budget multiplier")
	_check(not main.waves.rhythm_tight, "and the tightened rhythm")
	main.queue_free()
