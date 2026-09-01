# Toko Drop — Godot 4 port

A Godot 4.7 port of **Toko Drop**, the twin-stick swarm-survival browser game
at [mbace1.github.io/Suds-Jack/toko-drop](https://mbace1.github.io/Suds-Jack/toko-drop/)
(source: [mbace1/Suds-Jack](https://github.com/mbace1/Suds-Jack), `toko-drop/`,
Three.js r167, no build step).

The browser build is large — 40 enemy types, a wave director, weapon
upgrades, cabinets, a full pause-menu tuner. This port is a **fresh start**,
not a straight recompile: it re-implements the core loop from scratch against
the browser code as the numeric/behavioural reference, and grows outward from
there. See `PORT_STATUS.md` for exactly what exists today and `PORT_BRIEF.md`
for the visual target (that document is inherited unmodified from the source
repo's own Godot dispatch brief and stays canon for material/shader work).

## Status

Playable vertical slice: twin-stick movement on **touch, keyboard+mouse or
gamepad**, dash with i-frames, shooting both ways, six enemy types (GLOBBO
pouncer, YELA_CUBE flopper, and the ranged SPITTOR, FANNER, ORANGE_CUBE and
WEEVA), a budget-based wave director with a shooter cap, death pops with
**revenge volleys** (corpses bite back, in their own species' attack language
and their own palette), a synthesised sound kit, saved hi-score and run
history, and one shared gel shader doing real subsurface scattering. Full detail and the ordered list of
what's next: `PORT_STATUS.md`.

## Running it

Open `project.godot` in Godot **4.3+** (built against 4.7.2), or from the
command line:

```
godot --path . scenes/main.tscn
```

**Controls**

- **Touch** — left thumb anywhere on the left half moves; right thumb anywhere
  on the right half aims and auto-fires; **releasing the aim stick dashes**. A
  tap on the top-centre strip pauses.
- **Keyboard + mouse** — WASD move, hold LMB to aim and fire, Space dash, Esc
  pause.
- **Gamepad** — left stick move, right stick aim/auto-fire, A dash, Start
  pause.

## Looking at it

```
godot --path . tools/capture.gd -- <out_dir> [frames_between_shots]
```

Screenshots the real game on a GPU. **This is half the gate, not a nicety.**
The source repo's own recorded diagnosis is that its games stall at prototype
feel because "the smoke gates certify *works* and prototype-feel lives
entirely in the part they cannot see" — and the first time this port was ever
rendered, after three commits and 55 green checks, the HUD was printed across
the middle of the screen, the arena was clipped, and the boundary bodies are
clamped against was invisible. Run it after anything that changes how the
game looks, and *look at the output*.

## Testing

```
godot --headless --script tests/smoke.gd
```

A bare-`SceneTree` gate (no GPU, no wall-clock dependence) exercising player
movement/firing/damage/i-frames, all four enemy types (including SPITTOR's
wind-up tell and FANNER's every-third-wide volley beat), the wave budget
curve, the death pop and every revenge dialect, the spawn/clear cycle, the
synthesised audio kit, the save service and its v1→v2 migration, the wave
composer, the seeded gameplay random stream, and the Rush director's
escalation/spawn/heat mechanics — 132 checks. Run it before every commit that
touches `scripts/`.

```
godot --headless --script tests/smoke_main.gd
```

A second, separate headless gate — `main.gd` itself, which the first
deliberately stays out of (`main.gd` relies on deferred `_ready()`, unlike
everything the first gate exercises, which is built specifically not to need
it — see "Design note" below). Drives real runs through `main.gd`'s own
`_start_game()` / `_process_playing()` / `_end_run()` for both Normal and
Rush — including a bullet through the *real* collision loop, confirming Rush
scoring actually reaches `RushDirector.register_kill()` rather than a
parallel, easier-to-break path — 22 checks. State only: it proves the wiring
is correct, not that the HUD it drives looks right on screen. Run it whenever
`main.gd` changes.

## Layout

```
project.godot        Godot 4 project config (Forward+ renderer)
scenes/main.tscn      the only hand-authored scene — a bare Node3D with main.gd.
                       Everything else (camera, lights, floor, HUD, player,
                       enemies, bullets) is built in code, mirroring how
                       toko-drop/js/main.js builds its THREE.Scene in code.
shaders/gel.gdshader   the one material every gel body shares (PORT_BRIEF.md §0/§1)
scripts/
  main.gd              scene setup, game states, the collision loop, HUD
  input_manager.gd      keyboard+mouse / gamepad → move/aim/dash/pause
  player.gd             port of js/player.js
  bullet_pool.gd         port of js/bullet.js (MultiMesh instead of InstancedMesh)
  enemy.gd               shared enemy base: gel material, hit-wobble, spring
                          squash, and the telegraph->fire + hold-at-range
                          scaffolding every ranged type shares
  globbo.gd               GLOBBO — chaser blob, lunge pulse + stalk/crouch/leap
  yela_cube.gd            YELA_CUBE — edge-pivot flop instead of sliding
  spittor.gd              SPITTOR — holds range, swells, spits a ring of 8
  fanner.gd               FANNER — circles and fans, every 3rd volley wider
  orange_cube.gd          ORANGE_CUBE — flops with intent, throws bullet walls
  weeva.gd                WEEVA — drifting spiral turret, a stream not a volley
  audio_kit.gd            eight voices, synthesised at load (no sample files)
  save_service.gd         hi-score + last 10 runs, in user://
  touch_sticks.gd         draws the two virtual sticks
  wave_director.gd        budget-based wave composition, shooter cap,
                          corpse pops and revenge volleys
  rush_director.gd         RushDirector — Rush mode's director (extends
                          WaveDirector), wired into main.gd (mode select,
                          collision-loop scoring, run-ending) but not yet
                          capture-verified — see PORT_STATUS.md
tests/smoke.gd         headless gate — see "Testing" above
tests/smoke_main.gd    a second headless gate, for main.gd itself — see "Testing" above
tools/capture.gd      screenshots the real game — see "Looking at it" above
PORT_BRIEF.md         inherited visual/material brief (Godot-side canon for shaders/lighting)
PORT_STATUS.md        living doc: what's ported, what's next, in priority order
QUEUE.md              the cross-repo work queue — see "Planning" below
design/               high-level design docs, ahead of implementation
  RUSH_MODE.md              Rush mode (proposal, nothing implemented)
  RUSH_TIERS_AND_LEVELS.md   legs, per-leg goals, S/A/B/C thresholds
  CAMPAIGN_LEVELS.md         rule-variant challenge levels and progression
  RUSH_MODE_ACCEPTANCE.md    what "done" means per Rush item, as smoke checks
  PARITY_RECON.md            one trip into the source repo, as a checklist
  DETERMINISM_AND_SEEDS.md   seeded runs — decide before Rush ships
  SPLIT_ENEMIES.md           child-spawn-on-death (SPLITTA, REDD/PURP_CUBE)
  HAZARDS.md                 floor hazards, and why enemies should be ported
                              from the roster rather than invented
```

## Planning

Design that spans both repos is written here first, then queued:
`design/` holds the high-level docs, and `QUEUE.md` is the ordered list of what
those docs turned into, with a `repo:` field per item saying where each piece
actually lands. `QUEUE.md`'s own header explains the conventions that keep it
merge-friendly (stable `Q-NNN` IDs, one block per item, status changes touching
a single line, landings recorded with their SHA).

`PORT_STATUS.md` is unaffected by this and stays what it has always been: the
description of what the port *is* today, updated in the same commit as any
`scripts/`/`shaders/` change.

## Design note: no `_ready()`-timing surprises

`Player` and `BulletPool` build their meshes/materials in an idempotent
`build()` method, not directly in `_ready()`. `_ready()` just calls `build()`.
This exists because `add_child()` does **not** synchronously flush
`NOTIFICATION_READY` in every context (confirmed the hard way: it doesn't in
a bare `SceneTree` script's `_init()`, which is exactly where `tests/smoke.gd`
needs it to). `main.gd` and the tests both call `.build()` explicitly right
after `add_child()` so behaviour never depends on exactly when the engine
gets around to `_ready()`. `Enemy` sidesteps the question entirely — it has
no `_ready()` at all; `WaveDirector` calls `.init()` explicitly instead.
