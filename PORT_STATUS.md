# Port status

Living doc — update this in the same commit as any change to `scripts/` or
`shaders/`. Source of truth for numbers/behaviour is the browser build at
`mbace1/Suds-Jack`, `toko-drop/js/*.js` (referenced per line below). Visual
target is `PORT_BRIEF.md`.

## Ported

**Core loop**
- Twin-stick movement + mouse/gamepad aim, dash with i-frames, fire-rate
  gated shooting — `scripts/player.gd`, numbers from `js/player.js`
  (SPEED 6, DASH_SPEED 26, DASH_DUR 0.18, DASH_CD 0.75, FIRE_RATE 0.09,
  MAX_HP 3, MERCY_DURATION 1.2, RADIUS 0.5).
- Pooled bullets rendered via `MultiMeshInstance3D` (halo/core/shadow),
  300-capacity — `scripts/bullet_pool.gd`, structure from `js/bullet.js`.
- Desktop keyboard+mouse and gamepad input, unified into the same
  `get_move_dir()` / `get_aim_dir()` shape as `js/input.js` —
  `scripts/input_manager.gd`.
- **Budget-based** wave director — `scripts/wave_director.gd`, porting three
  tables from tuning.js §waves (the v217 "Wave Director v1" that moved spawn
  tables out of main.js into data): the `[minWave, budgetCost]` composition
  pool (line 148), the budget curve (base 5, ramp 1.8 to a knee at wave 10,
  then 0.8, with the early ease that shaves 15% at wave 1 — line 184), and
  the shooter cap (1 at wave 1 growing to 5 by ~wave 12 — line 200). The cap
  matters: without it a budget spend fills the arena with artillery and the
  wave stops being readable. Bodies spawn on a ring at 0.6× the arena half-
  size, never on top of the player.
- Game states (menu/playing/paused/dead), collision loop, HP/wave/score
  HUD — `scripts/main.gd`.

**Input, sound and meta**
- **Touch — the browser's dual virtual sticks** (`scripts/input_manager.gd` +
  `touch_sticks.gd`). The screen splits down the middle; a finger on the left
  half plants a move stick where it landed, a finger on the right plants an aim
  stick that auto-fires, and RELEASING the aim stick is the dash. Nothing is a
  fixed button, so a stick is always under the thumb that reached for it.
  TOKO_DROP_ROADMAP.md §Guiding constraints: *"Mobile touch is first-class.
  Every feature ships with a touch answer."* — the port was breaking that rule
  outright until now.
- **Audio, synthesised at load** (`scripts/audio_kit.gd`). Eight voices, each
  an oscillator sweep under an exponential envelope baked into an
  `AudioStreamWAV` at startup. `js/audio.js` is all-synth WebAudio with no
  sample files, and the house rule across this codebase is that sound is
  generated, never sampled — so there is nothing to license and no binary in
  the repo. The gun sits at 0.10 gain deliberately: at ~11 shots a second it
  becomes the mix otherwise.
- **Hi-score and run history** (`scripts/save_service.gd`), the local-bests
  half of TOKO_DROP_ROADMAP.md Phase 4. `user://` stands in for localStorage;
  last 10 runs newest-first, and the death screen's "recent" line skips index 0
  because that is the run you are already reading the big number for. Nothing
  leaves the machine — no leaderboard, no network call. The daily seed is still
  open.
- **Save schema v2 — per-mode buckets.** v1 was flat and MODE-BLIND
  (`{hi_score, runs}`), so the first Rush run would have overwritten the Normal
  best with a number from a different game. It also had no version field, so
  the migration keys off the shape: a parsed dictionary with no `"v"` is v1 and
  is carried across into `modes.normal` rather than discarded (a v1 file is
  *old*, not corrupt). `levels` is reserved in the same pass — the campaign's
  per-level records are a high-water mark, a different shape from a run list,
  and adding them later would have cost a v3 migration for nothing.
  `design/RUSH_MODE.md` §7, `design/CAMPAIGN_LEVELS.md` §4.
- **One gameplay random stream** (`wave_director.gd`'s `rng`, handed to every
  body in `_spawn()`). Every draw that decides *what happens* — which type
  spawns, where it lands, which way a body flops, a revenge ring's start angle
  — comes from it; **cosmetic** draws deliberately stay on the global rng.
  That split is the whole point: a bullet's shimmer phase used to share the
  stream with the spawn picker, so under a seed, firing one extra shot would
  have shifted every later wave and two players on one daily seed would have
  diverged from the trigger. Nothing was broken only because nothing was seeded
  yet. The director is left unseeded by default, so an ordinary run is as
  random as it ever was. `design/DETERMINISM_AND_SEEDS.md`.
- **`WaveDirector.compose()`** — the affordability loop split out of
  `start_wave()` so a second *cadence* can spend the same ported table without
  forking it (Rush holds a standing pressure rather than spending a whole wave
  at once). Pure refactor; the existing wave checks pass unmodified.

**Enemies** (19 of ~40 in the live roster — `js/tuning.js` names all 40)
- GLOBBO — chaser blob. Two behaviours stack: the lunging speed-pulse
  `speed × (max(0,sin(t·3+φ))² · 2.6 + 0.4)` (`TOKO_DROP_PORT_BRIEF.md`
  Part 2 / tuning.js line 43) **and** the stalk→crouch→leap pounce state
  machine from `enemy.js` line 1397 — the crouch telegraphs, the leap
  commits to the direction captured at crouch time and cannot correct.
  `scripts/globbo.gd`. Stats from `enemy.js` line 486.
- YELA_CUBE — edge-pivot flop instead of a slide (arc 135°→45°, land flat,
  50% diagonal picks) — `scripts/yela_cube.gd`, math from
  `TOKO_DROP_PORT_BRIEF.md` Part 3. Stats from `enemy.js` line 492.
- SPITTOR — **the first ranged type.** HOLDER archetype: holds `want = 10`
  with a ±1 hysteresis band (`enemy.js` line 1932). Inflates +22% over a
  0.45s wind-up, recoils 0.18 backward on fire, and spits a ring of 8 aimed
  so one bullet leads straight at you (`enemy.js` line 2565,
  `TOKO_DROP_PORT_BRIEF.md` Part 2, tuning.js line 40).
  `scripts/spittor.gd`. Stats from `enemy.js` line 487.
- FANNER — HOLDER at `want = 8` (±1.5) while strafing perpendicular, flipping
  direction every 2.5–3.5s; rocks as it circles. Fires 6 shots across 0.6π,
  but **every third volley** is a wide 9 across 0.95π — "a heavier beat"
  (`enemy.js` line 2590). `scripts/fanner.gd`. Stats from `enemy.js` line 488.

- ORANGE_CUBE — flops toward you on the cube's eight-way grid, then throws a
  **wall**: six shots side by side, all travelling the same snapped compass
  direction, so you go around it rather than between the shots (`enemy.js`
  line 2046). Stats from `enemy.js` line 493.
- WEEVA — a drifting spiral turret, and the first ported enemy with **no
  wind-up**: `fireInterval` 0.16 is a STREAM, not a volley, each shot rotated
  `0.38` rad past the last. A telegraph on that cadence would be permanently
  lit and would say nothing. Weaves while slowly closing (`enemy.js` line
  1958). Stats from `enemy.js` line 489.

- SLUDGE_CUBE — slow MASS cube that lays a **poison patch every 0.5s**. The
  patch lives 8s (`TUNING.fx.poisonLife`), so a dead SLUDGE is still shaping
  where you can stand long after it is gone. Stats from `enemy.js` line 494.
- SPLITTA — dying is a SPAWN: three GLOBBOs, per `enemy.js`'s `_childType` /
  `_childCount` (*"always splits into 3 small blobs (v99)"*). It visibly
  **carries** two child domes before it dies (`TOKO_DROP_PORT_BRIEF.md`
  Part 2), so the rule is learnable by looking rather than by dying to it.
  Children join the LIVE list, so a wave is not clear until they are dealt
  with too. Stats from `enemy.js` line 490.

- REDD_CUBE / PURP_CUBE — the other two splitters, reusing the shared
  split-on-death contract (4 REDD_MINIs, 5 PURP_MINIs; counts from
  `enemy.js`'s `_childCount`). PURP's revenge speaks FAN, REDD's RING.
- REDD_MINI / PURP_MINI — one hit each, fast, straight at you. Spawned only by
  a parent's death, so deliberately absent from the wave POOL.
- **TORO** — the showpiece charger (`TOKO_DROP_PORT_BRIEF.md` Part 4). An
  upright wheel: idle creep → rev 1.6s → telegraph 0.5s → dash 22→14 →
  recover 0.8s, direction snapped to 45° and **locked at the telegraph** so it
  cannot re-aim after the tell. The indicator is raycast to the arena wall so
  the arrowhead **tip sits exactly on the impact point** — you are told where
  it will stop, not merely which way it is going. Spins about its axle at
  `v / radius` while dashing, so it visibly rolls.

- **SIREN / SHEPHERD — the "side quest" bodies.** Owner direction: not bosses,
  but enemies that pull focus off the primary goal. Neither touches you.
  SIREN inhales for 0.8s then SCREAMS, surging every body within 7u to 1.6x
  for three seconds (`tuning.js`: *"screamer — surges the pack, kill it
  first"*). SHEPHERD never closes; it holds 9u, circles, and drags its whole
  flock toward you (*"the threat is what it does to the OTHERS"*). Both are
  fragile and both are running away, so chasing one costs you what you were
  doing — and not chasing it costs more. `move_speed()` on the base class is
  what lets one scream lift the entire arena.

- **PYRA** — the one body that never moves. Spins in place and throws a
  7-shot fan every 2.5s, so it is entirely a positioning problem.
- **BOTFLY** — orbits at mid range and fires slow HOMING shots that steer a
  fraction of the way each frame rather than snapping. `bullet.js`'s own note
  on the speed: *"speedMult 0.62 keeps it outrunnable"* — a homing bullet you
  cannot outrun is a hit with extra steps.
- **BULWARK** — its FRONT is bulletproof; flank it. The facing turns at a
  limited rate on purpose (*"a quick side-step stays a real answer, the plate
  can't snap-track"*), because a shield that tracks instantly is not a puzzle,
  it is more HP.
- **WARDEN** — the third side-quest body and the most demanding. It never
  attacks; everything inside its aura shrugs off your shots. SIREN makes the
  swarm faster and SHEPHERD makes it closer, but a WARDEN makes it
  UNKILLABLE until you deal with the warden. It never shields itself, so
  there is always something you can shoot.

**Weapons and the streak**
- **Weapon pods** (`scripts/powerup_pool.gd`) — kills drop them, you walk over
  one and your gun changes for the rest of the run. Table mirrors main.js's
  `WEAPON_PODS`: S/S2 spread, B/B2 burst, L/L2 laser, R/R2 rapid, level-2 only
  from wave 4 and only 28% of the time even then. Two source rules kept:
  **HOMING never drops** (enemy.js v88 — *"homing is enemy-exclusive now"*;
  BOTFLY has it), and **pods expire**, so taking one is a decision you make
  now rather than deferred shopping.
- **Firing modes** on the player, from `js/player.js`: SPREAD 5 at π/9,
  SPREAD2 7 at π/10, BURST +2 queued, BURST2 +4, RAPID ×0.45, RAPID2 ×0.28.
  A burst's queued shots arrive even after you release the trigger, which is
  what makes it a COMMITMENT rather than just a slower gun.
- **Streak** — Normal mode had no chain at all. Climbs per kill, resets on a
  hit, and wears the browser's heat tiers (gold at 5, orange at 10, red at 20)
  so the scoring depth reads at a glance.

**Feedback**
- The browser's v212 CONTEXTUAL question, ported: every damage site records
  what hit you and how, and the deck asks about THAT, skipping anything asked
  recently. Explicit consent (SEND only), never claims an unmade delivery,
  and an empty submission records nothing. Files under `tokodropgodot`,
  its own catalogue id.

**HUD**
- **Parity with the browser build's layout** (`js/main.js` drawHud): `WAVE N`
  top-left, a progress bar beneath it, HP pips under that, score top-right.
  This port previously ran one centred row, which was the HUD divergence
  recorded here; it is closed, which also settles Q-015. Rush's clock and
  chain take a line UNDER that stack rather than fighting it for the centre.
- One honest divergence: the browser's bar is a wave TIMER (`waveTimer /
  ROUND_DUR`), because its waves escalate on a clock. This port's waves are
  clear-based, so the same bar shows how much of the wave is dead. Same slot,
  same question, different quantity.

**Run readouts — parity pass 3**
- **Seed.** `WaveDirector.reseed()` sets an explicit, showable run seed and
  `seed_text()` prints it as six hex digits, the way the browser prints
  `SEED ED1E2E`. A seeded run you cannot name is one you cannot ask anyone
  else to try.
- **Corner readouts**: version + FPS bottom-left, seed bottom-right.
- **Time survived** is now a first-class stat. The browser's death screen
  reads `WAVE 1 · 5s · 0 PTS` and keeps a best of the TIME as well as the
  score; this port had no notion of it. Records are starred separately
  (★ BEST SCORE / ★ BEST TIME) because a run can be your longest without
  being your highest, and one "best" line hides that.
- **The red death wash.** The browser floods the screen red on death, and it
  is most of why dying LANDS — a text swap alone reads as a menu appearing.

**Motion trails and ground**
- **Per-species motion trails** (`scripts/trail_pool.gd`) — pooled ghost
  spheres shrinking to nothing over 0.45s, one MultiMesh for the whole swarm.
  Cadence and size per species from `enemy.js`'s `TRAIL_CFG`; a species absent
  from that table leaves none. Ghosts spawn **one body-radius behind** the
  mover along its velocity (main.js v100) — at the body's own position they
  are hidden inside it. This is most of why the browser swarm reads as
  *flowing* rather than as independently teleporting dots.
- **Poison field** (`scripts/poison_field.gd`) — SLUDGE's patches as a
  MultiMesh of floor discs, with one shared damage tick so standing in three
  overlapping patches is a bad place to stand rather than instant death.

**Ranged combat**
- Enemy-fired bullets through the same `BulletPool`, and enemy-bullet-vs-
  player collision in `main.gd`'s loop (ordered after contact damage so one
  frame can never cost two HP — mercy i-frames from the first hit absorb
  the second).
- `enemy.gd` carries the shared shooter scaffolding every ranged type needs:
  `_tick_fire()` (interval → telegraph → the one frame the volley fires),
  `_hold_at_range()` (the HOLDER archetype's hysteresis band, from
  `TUNING.movement.roles.HOLDER`), and `_ring()` / `_fan()` volley shapes.

**Death, and the corpses biting back**
- Death pop — a killed body swells `1 + t·1.3` while fading on a SQUARED
  curve over 0.28s, so it is mostly transparent by the time it is large
  (`enemy.js` updateDeath()). Corpses leave the live list immediately (they
  cannot be shot again and never hold up a wave clear) and finish popping in
  `WaveDirector.corpses`.
- **Revenge volleys** — CLOSE COMBAT, the headline of the roadmap's own
  tagline (`main.js` onKill(), v187/v220). A corpse's retaliation *speaks the
  species' language*: SPITTOR spits a slow AIMED burst of 3, FANNER throws a
  slow FAN of 5, everything else blooms the classic RING (4, or 7 for a body
  over radius 0.75). All of it at `TUNING.revenge.speedMult` 0.6 — "the graze
  game, not a wall" — behind the same 240-bullet pool guard the source uses so
  a mass grave cannot starve the living of bullets.
- Revenge **palette shift** (`main.js` revengeColor()): warm goes dark blood,
  yellow goes poison green, cool goes deep venom. A corpse never wears living
  colours, so the two attack classes read apart at a glance.

**Rush Mode** (`scripts/rush_rules.gd`, designed in `RUSH_MODE.md`)
- A second, self-contained ruleset selectable from the front page under
  ROGUELIKE MODE. Boost is a held state that grants invulnerability, kills on
  contact and builds a chain — but **firing cancels the shield**, and boosting
  heats you until it locks out. The weapon is a shotgun. Lives, not HP.
  Difficulty levels run 60s/90s/longer and move DOWN when you lose a life.
  Four selectable abilities (Heat Exchange, Hyper Bomb, Overcharge, Quantum
  Shield), and levels drive the wave director's composition so levelling down
  really is easier.
- Built from research into Blade Rush (Noba, 2025) — its Steam patch notes
  state the intent outright: *"prioritising boosting over shooting"*, and
  *"boost invulnerability ends... from disabling it by shooting"*.
- The roadmap's "No Geometry Wars aesthetic drift" holds: structure only, no
  new materials. Rush state rides on the gel shader's existing per-instance
  rim colour.

**Game feel**
- **Debris** (`scripts/debris_pool.gd`) — ballistic gel lumps with a floor
  bounce, at `TUNING.fx` counts: 8 droplets on a hit, 22 droplets + 5 bigger
  chunks on a kill. Lit rather than unlit, because unlit spheres of a flat
  colour read as confetti instead of as bits of the same gel.
- **Camera shake** — main.js's trauma model: events add trauma, it decays at
  ~2.8/s, and the offset is trauma SQUARED. The squaring is what stops a
  stream of small hits reading as constant judder while a kill still lands.
  Taking damage shakes hardest — it is the one event you must not miss.

**Challenges — the campaign** (`scripts/challenges.gd`)
- A Geometry Wars 3-shaped Adventure: named levels played in order, each one a
  RULE rather than just a different spawn table. GW3's identity is Pacifism /
  Deflector / King; ours is BOOST ONLY / CLOSE QUARTERS / ONE LIFE /
  ARTILLERY / SWARM / GRAVEYARD, each bending a system the game already has,
  so a level is data and an archetype is a parameter.
- **Ten levels**, covering all seven rule archetypes, all measured.
- **Timed** — every level runs a fixed clock and the score at the buzzer is
  the grade. **Tier C or better opens the next level**, so a player merely
  finishing keeps moving and the higher letters are for those who want them.
- **Abilities unlock over the campaign** (GW3's drones do the same): only
  HEAT EXCHANGE at the start, the rest arrive with cleared levels.
- **Thresholds are MEASURED, never guessed** — `tools/measure.gd` plays each
  level headless with a fixed yardstick bot and sets C/B/A/S from its median.
  A BOOST ONLY level and an ARTILLERY level have completely different kill
  rates, so one shared formula would be wrong on both. Every level carries a
  `measured` flag; a guess is marked as a guess.
- The camera scales with the room, so CLOSE QUARTERS reads as walls that are
  actually close rather than a small board adrift in a full-size frame.

**Material**
- One shared `shaders/gel.gdshader`: vertex ripple + hit shockwave, Fresnel
  rim glow, clearcoat, CPU-driven spring squash. Per-instance uniforms via
  `set_shader_parameter`, same "one shader drives every body" shape as the
  browser's `makeSatinMat`. This is **PORT_BRIEF.md §1's step 1** ("author
  one `shader_type spatial` gel shader… so a single material drives all
  enemies via per-instance uniforms").
- **True subsurface scattering — PORT_BRIEF.md §2a**, the "gummy-bear read".
  `SSS_STRENGTH` + `SSS_TRANSMITTANCE_*` + `BACKLIGHT`, with thickness taken
  analytically from the silhouette (`1 - |N·V|`, so thin edges glow brightest)
  rather than from a shipped texture. Three things had to move together for it
  to read at all, and each is load-bearing:
  1. **The material is OPAQUE.** Godot's SSS is a screen-space pass over
     opaque geometry, so an alpha-blended body gets none of it. Fades now use
     `ALPHA_HASH_SCALE` (hashed alpha, still in the opaque pass).
  2. **Bodies sit at alpha 1.0 at rest.** Any lower and the hash dithers them
     into visible static. Alpha is only for bodies on their way out.
  3. **There is a back light.** Transmittance is light passing *through* a
     body — with only a key light overhead it scatters into nothing. The
     camera is on +Z, so a second directional fires from the far side.
- IBL from a `ProceduralSkyMaterial` (ambient + reflections), while the
  visible background stays the browser's near-black void. PORT_BRIEF.md §0
  notes the source needs IBL "for transmission + clearcoat"; with a flat
  ambient colour a clearcoat has nothing to reflect, which was most of why
  the first render came out as matte plastic.
- `WorldEnvironment`: glow (bloom floor dropped to 0.05 so the HDR threshold
  actually decides what blooms), SSAO, SSR, ACES tonemap — **PORT_BRIEF.md
  §6**, "biggest single jump, near-free".

**Testing**
- `tests/smoke.gd` — 127 checks, bare `SceneTree`, no GPU. Run before every
  commit touching `scripts/`.
- **`main.gd`'s collision resolution is now covered.** `_collide_player_bullets`
  / `_collide_enemy_bullets` / `_collide_contact` are methods the gate drives
  directly. They used to be inline loops reachable only through
  `_process_playing()`, which needs live input — which is exactly how a bug
  that made PLAYER BULLETS DAMAGE THE PLAYER shipped past a green 155-check
  suite. If a system is only reachable through input, the gate cannot see it.
- `tests/smoke.gd` — 106 checks, bare `SceneTree`, no GPU. Run before every
  commit touching `scripts/`. The determinism checks are mutation-tested:
  reverting `compose()` to the global rng fails exactly two of them, including
  "shooting does not move the swarm". A gate that cannot fail is not a gate.
- `tools/capture.gd` — screenshots the REAL game on a GPU. This is the other
  half of the gate and it is not optional: the source repo's own recorded
  diagnosis is that its games stall at prototype feel because "the smoke
  gates certify *works* and prototype-feel lives entirely in the part they
  cannot see". **Look at the output after any change to how the game looks.**

  The first time this port was ever rendered — after three commits, all green
  — it had the whole stat row printed across the middle of the screen with
  WAVE on top of the player, an arena clipped at the bottom with the void
  showing past its far edge, and no visible boundary at all on the line
  bodies are actually clamped against. Every one of those passed 55 checks.

## Not ported yet — in priority order

Work that is *designed but not started* — including anything that lands in the
browser repo rather than here — is tracked in `QUEUE.md` with its own IDs; the
first entries there are the Rush mode proposal in `design/RUSH_MODE.md`. This
list stays the port's own ordered backlog.

Gameplay breadth first (each item is small and mostly mechanical), then the
visual landmarks from `PORT_BRIEF.md` §2 onward (each is a real R&D task):

1. **More enemy types.** The child-spawning machinery SPLITTA needed is now
   shared, so REDD_CUBE and PURP_CUBE (wave 4/5, both splitters) are cheap.
   TORO is the big one — wheel body + exact telegraph,
   `TOKO_DROP_PORT_BRIEF.md` Part 4 — and BAMBU needs the landing-ring lob
   (Part 5), the one genuinely new gameplay affordance in that document.
2. **Kill particles.** The pop and the revenge volley are in; the *debris*
   is not — `TUNING.fx.killDroplets` 22 / `killChunks` 5, plus the splat
   decal they leave. Worth doing as `GPUParticles3D` straight away rather
   than as flat meshes, since `PORT_BRIEF.md` §3/§5 wants particles here
   anyway.
3. **Player weapon modes.** `player.js`'s SPREAD/BURST/HOMING/RAPID are
   stubbed out — only SINGLE exists here.
4. **Touch controls.** `input_manager.gd` has no touch path; the browser's
   dual virtual-stick scheme (`js/input.js`) is the reference.
5. **Verlet tentacles** on one hero enemy (`PORT_BRIEF.md` §2b) — the
   landmark "alive" feature the whole brief is written around.
6. **GPU drip particles + dew normal map** (`PORT_BRIEF.md` §3).
7. **Trails** — `TubeTrail3D` / `Decal` (`PORT_BRIEF.md` §4).
8. **Death FX (visual half)** — `SoftBody3D` split + `RigidBody3D` gel chunks
   (`PORT_BRIEF.md` §5).
9. **Compositor passes** — chromatic aberration, heat shimmer
   (`PORT_BRIEF.md` §6).
10. Screen-space refraction in `gel.gdshader` itself (currently approximated
    with plain alpha blending — see the shader's own header comment).

## Side-by-side against the shipped browser build (2026-08-24)

The browser game was captured running (Playwright + a local server over the
real `toko-drop/` tree, scratch harness kept outside both repos) and compared
frame to frame against `tools/capture.gd` output. What that found, and what
was fixed in the same pass:

| | browser build | this port, before | now |
|---|---|---|---|
| Arena | **38 × 22**, wide landscape room | 18 × 18 square | 38 × 22 |
| Camera | `[0, 20.5, 13.5]` → `[0, 0, 2.5]`, fov 60 | derived guess, fov 55 | the source's, verbatim |
| Floor | pulsing cyan/violet neon **grid** | featureless grey slab | ported shader, same math |
| Border | `0x5555cc` violet | ad-hoc blue | `0x5555cc` |
| Fog | `0x0d0d1a`, 42→80 | none | ported |
| Blobs | squat grounded **domes** | round balls | `TUNING.blob.shape` per species |
| Player | Kirby eyes tracking aim | featureless white ball | eyes, on the surface |

**The arena was the big one.** A square 18 × 18 made every body look huge,
left no room to run, and framed nothing like the real game — the browser build
is a *wide room you cross*. Almost every other "this feels off" symptom was
downstream of it: bullets looked oversized because the arena was half the size
it should be, and waves bunched into the middle because they spawned on a
circle of the smaller half-extent (they use an ellipse now, one radius per
axis, or the wide ends of the room stay empty).

Two deliberate DIVERGENCES from the source, both recorded because they are
choices rather than drift:

1. **The floor grid is emissive-on-lit, not `MeshBasicMaterial` unlit.** The
   lines glow and bloom identically, but the plane still receives the cast
   shadows this port has, and a body's contact shadow is most of how you read
   where it actually is on the plane.
2. **The eyes sit ON the body surface, not inside it.** The browser can embed
   them at 0.4 of a 0.5 radius because its player is transmissive gel; this
   port's gel is opaque, which is what buys it real SSS, so embedded eyes
   render as nothing at all (the first attempt was a blank white ball).

Still different, and still open: the browser's per-species **motion trails**
(the streak marks the swarm leaves on the floor — `TRAIL_CFG` in `enemy.js`,
and item 7 below), and its HUD layout (WAVE plus a wave-progress bar top-left
with HP pips beneath it, score top-right; this port runs HP / WAVE / SCORE
across one top row).

## What the first render showed (2026-08-24)

Fixed in the same pass: the HUD layout bug, camera framing (now derived from
`HALF_X`/`HALF_Z` so resizing the arena cannot silently push it off-screen
again), and an emissive rail on the clamp line so the arena has a visible
edge.

~~1. **The gel does not read as gel.**~~ **Done** — see Material above. Bodies
   now have a translucent interior, a wet highlight and real cast shadows.
   Two things only a render could have caught, both fixed in the same pass:
   the hashed alpha turned every body to TV static at the default 0.9 alpha,
   and the player's *smooth* mercy-flicker ramp through that hash read as
   broken graphics rather than i-frames (it is a square 12Hz mesh blink now,
   which is what the source does too).

Still open, in the order they hurt:

~~1. **The player has no identity.**~~ **Done** — eyes ported, see above.

~~2. **The floor is a featureless slab.**~~ **Done** — the browser's neon grid
   is ported, which was `PORT_BRIEF.md` §6's arena pass in its shipped form.

## Known gaps / deliberate simplifications

- Blob geometry is a plain `SphereMesh`, not the SDF gel-dome from
  `TOKO_DROP_PORT_BRIEF.md` Part 2 (flat-bottomed dome, origin at floor
  contact). Enemies currently rest with their mesh center offset up by
  `radius`, which is visually close enough for a first pass but not the
  real geometry.
- No score/wave persistence (`localStorage` equivalent) — score resets to 0
  every run, nothing is saved between sessions.
- Camera is a fixed angled `Camera3D`, not a scene-relative rig; fine for a
  9×9 arena, will need revisiting if the arena grows.
