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
- Escalating wave director (cross-pattern spawn at 0.6×half-arena,
  count = 3+wave) — `scripts/wave_director.gd`.
- Game states (menu/playing/paused/dead), collision loop, HP/wave/score
  HUD — `scripts/main.gd`.

**Enemies** (2 of ~40 in the live roster — `js/tuning.js` names all 40)
- GLOBBO — chaser blob, lunging speed-pulse
  `speed × (max(0,sin(t·3+φ))² · 2.6 + 0.4)` — `scripts/globbo.gd`, math
  from `TOKO_DROP_PORT_BRIEF.md` Part 2. Stats `color:0x00ccaa, radius:0.55,
  speed:2.8, hp:1` from `enemy.js` line 487.
- YELA_CUBE — edge-pivot flop instead of a slide (arc 135°→45°, land flat,
  50% diagonal picks) — `scripts/yela_cube.gd`, math from
  `TOKO_DROP_PORT_BRIEF.md` Part 3. Stats `color:0xffdd00, radius:0.7,
  speed:2.2, hp:2` from `enemy.js` line 492.

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
- `tests/smoke.gd` — 16 checks, bare `SceneTree`, no GPU. Run before every
  commit touching `scripts/`.

## Not ported yet — in priority order

Gameplay breadth first (each item is small and mostly mechanical), then the
visual landmarks from `PORT_BRIEF.md` §2 onward (each is a real R&D task):

1. **More enemy types.** Next candidates by how little new machinery they
   need: SPITTOR (blob + inflate/recoil + a ranged aimed shot — first
   shooter, needs enemy-fired bullets through `BulletPool`), ORANGE_CUBE
   (cube + spread shot), TORO (wheel + telegraphed dash — `PORT_BRIEF.md`
   isn't the source for this one, `TOKO_DROP_PORT_BRIEF.md` Part 4 is).
   `enemy.gd`'s `setup()`/`update()` split already generalises to a shooter;
   it just hasn't been asked to yet.
2. **Enemy contact damage variety / player weapon modes.** `player.js`'s
   SPREAD/BURST/HOMING/RAPID weapon modes are stubbed out — only SINGLE
   exists here.
3. **Touch controls.** `input_manager.gd` has no touch path; the browser's
   dual virtual-stick scheme (`js/input.js`) is the reference.
4. **True SSS + thickness map** (`PORT_BRIEF.md` §2a) — replace
   `gel.gdshader`'s ALBEDO/ALPHA approximation with `StandardMaterial3D`'s
   `subsurf_scatter_*` + a thickness texture. This is the single biggest
   remaining visual gap: bodies currently look like tinted glass, not gel.
5. **Verlet tentacles** on one hero enemy (`PORT_BRIEF.md` §2b) — the
   landmark "alive" feature the whole brief is written around.
6. **GPU drip particles + dew normal map** (`PORT_BRIEF.md` §3).
7. **Trails** — `TubeTrail3D` / `Decal` (`PORT_BRIEF.md` §4).
8. **Death FX** — `SoftBody3D` split + `RigidBody3D` gel chunks
   (`PORT_BRIEF.md` §5).
9. **Compositor passes** — chromatic aberration, heat shimmer
   (`PORT_BRIEF.md` §6).
10. Screen-space refraction in `gel.gdshader` itself (currently approximated
    with plain alpha blending — see the shader's own header comment).

## Known gaps / deliberate simplifications

- Blob geometry is a plain `SphereMesh`, not the SDF gel-dome from
  `TOKO_DROP_PORT_BRIEF.md` Part 2 (flat-bottomed dome, origin at floor
  contact). Enemies currently rest with their mesh center offset up by
  `radius`, which is visually close enough for a first pass but not the
  real geometry.
- No death FX at all yet — a killed enemy just `queue_free()`s.
- No score/wave persistence (`localStorage` equivalent) — score resets to 0
  every run, nothing is saved between sessions.
- Camera is a fixed angled `Camera3D`, not a scene-relative rig; fine for a
  9×9 arena, will need revisiting if the arena grows.
