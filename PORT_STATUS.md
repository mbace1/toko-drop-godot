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

**Enemies** (4 of ~40 in the live roster — `js/tuning.js` names all 40)
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

**Ranged combat**
- Enemy-fired bullets through the same `BulletPool`, and enemy-bullet-vs-
  player collision in `main.gd`'s loop (ordered after contact damage so one
  frame can never cost two HP — mercy i-frames from the first hit absorb
  the second).
- `enemy.gd` carries the shared shooter scaffolding every ranged type needs:
  `_tick_fire()` (interval → telegraph → the one frame the volley fires),
  `_hold_at_range()` (the HOLDER archetype's hysteresis band, from
  `TUNING.movement.roles.HOLDER`), and `_ring()` / `_fan()` volley shapes.

**Material**
- One shared `shaders/gel.gdshader`: vertex ripple + hit shockwave, Fresnel
  rim glow, CPU-driven spring squash. Per-instance uniforms via
  `set_shader_parameter`, same "one shader drives every body" shape as the
  browser's `makeSatinMat`. This is **PORT_BRIEF.md §1's step 1** ("author
  one `shader_type spatial` gel shader… so a single material drives all
  enemies via per-instance uniforms").
- `WorldEnvironment`: glow, SSAO, SSR, ACES tonemap — **PORT_BRIEF.md §6**,
  "biggest single jump, near-free".

**Testing**
- `tests/smoke.gd` — 41 checks, bare `SceneTree`, no GPU. Run before every
  commit touching `scripts/`.

## Not ported yet — in priority order

Gameplay breadth first (each item is small and mostly mechanical), then the
visual landmarks from `PORT_BRIEF.md` §2 onward (each is a real R&D task):

1. **More enemy types.** The shooter scaffolding now exists, so the next ones
   are mostly table work: ORANGE_CUBE (cube + the 8-way-snapped "bullet wall"
   of `enemy.js` line 2046), WEEVA (drifting spiral turret, fireInterval 0.16
   — a stream, not a volley), SLUDGE_CUBE and SPLITTA (the latter needs
   child-spawning on death, which is new machinery). TORO is the big one —
   wheel body + exact telegraph, `TOKO_DROP_PORT_BRIEF.md` Part 4 — and
   BAMBU needs the landing-ring lob (Part 5), the one genuinely new
   gameplay affordance in that document.
2. **Death FX.** Killed enemies just `queue_free()`. The source pops them
   (`TUNING.fx.killDroplets/killChunks`) and, more importantly, has
   **revenge rings** — corpses bite back, per the roadmap's own tagline.
   `TUNING.revenge` (tuning.js line 230) is a complete spec: a per-species
   dialect (AIMED/FAN/RING) echoing how the thing attacked in life.
3. **Player weapon modes.** `player.js`'s SPREAD/BURST/HOMING/RAPID are
   stubbed out — only SINGLE exists here.
4. **Touch controls.** `input_manager.gd` has no touch path; the browser's
   dual virtual-stick scheme (`js/input.js`) is the reference.
5. **True SSS + thickness map** (`PORT_BRIEF.md` §2a) — replace
   `gel.gdshader`'s ALBEDO/ALPHA approximation with `StandardMaterial3D`'s
   `subsurf_scatter_*` + a thickness texture. This is the single biggest
   remaining visual gap: bodies currently look like tinted glass, not gel.
6. **Verlet tentacles** on one hero enemy (`PORT_BRIEF.md` §2b) — the
   landmark "alive" feature the whole brief is written around.
7. **GPU drip particles + dew normal map** (`PORT_BRIEF.md` §3).
8. **Trails** — `TubeTrail3D` / `Decal` (`PORT_BRIEF.md` §4).
9. **Death FX (visual half)** — `SoftBody3D` split + `RigidBody3D` gel chunks
   (`PORT_BRIEF.md` §5).
10. **Compositor passes** — chromatic aberration, heat shimmer
   (`PORT_BRIEF.md` §6).
11. Screen-space refraction in `gel.gdshader` itself (currently approximated
    with plain alpha blending — see the shader's own header comment).

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
