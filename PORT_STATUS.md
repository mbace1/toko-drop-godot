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
- **`RushDirector` (`scripts/rush_director.gd`) — Rush mode's director,
  structurally.** `extends WaveDirector`, reusing `compose()` /
  `budget_for()` / `shooter_cap_for()` / `body_cap_for()` unchanged rather than
  forking a second table. Escalation runs off elapsed time through a *virtual
  wave*; spawning trickles through a pipeline of telegraphed pending bodies on
  the arena edge (never the 0.6× wave ellipse — a body appearing mid-dash with
  no wave boundary to warn you is an unavoidable hit); the clock only ever
  advances inside `update_rush(delta)`, so pausing (not calling it) is free,
  same as every other system in this port; a kill banks earned time capped at
  the run's base duration; and a heat multiplier (`register_kill()`) replaces
  the per-clear score bonus Rush cannot have — settled by the project owner to
  break only on an idle timer, never on taking a hit, which is a structural
  guarantee (`RushDirector` has no method that reduces heat from damage, so
  there is nothing to call). **Not wired into `main.gd`** — no mode select, no
  HUD, no menu integration. Landing this surfaced two real bugs, both caught by
  mutation-testing the new checks rather than by inspection: score used
  `int()` truncation on a multiplier like ×1.15, which float imprecision can
  land a hair under (dropping a point off the score); and the heat-decay math
  assumed a single call could never straddle the window→decay boundary, so an
  oversized step silently held heat instead of decaying the right partial
  amount. `design/RUSH_MODE.md` §3–§4, `QUEUE.md` Q-003/Q-004/Q-005.

**Enemies** (6 of ~40 in the live roster — `js/tuning.js` names all 40)
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
- `tests/smoke.gd` — 132 checks, bare `SceneTree`, no GPU. Run before every
  commit touching `scripts/`. The determinism checks are mutation-tested:
  reverting `compose()` to the global rng fails exactly two of them, including
  "shooting does not move the swarm". The RushDirector heat/scoring checks are
  the same discipline and are how the two bugs noted above were actually
  found, not just fixed. A gate that cannot fail is not a gate.
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

1. **More enemy types.** Wave 3 next: SLUDGE_CUBE (slow MASS + poison trail)
   and SPLITTA, which needs child-spawning-on-death machinery that
   REDD_CUBE and PURP_CUBE then reuse. TORO is the big one — wheel body +
   exact telegraph, `TOKO_DROP_PORT_BRIEF.md` Part 4 — and BAMBU needs the
   landing-ring lob (Part 5), the one genuinely new gameplay affordance in
   that document.
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
