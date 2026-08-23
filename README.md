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

Playable vertical slice: twin-stick movement, dash with i-frames, shooting
both ways, four enemy types (GLOBBO pouncer, YELA_CUBE flopper, and the
ranged SPITTOR and FANNER), a budget-based wave director with a shooter cap,
death pops with **revenge volleys** (corpses bite back, in their own species'
attack language and their own palette), HP/wave/score HUD, one shared gel
shader. Full detail and the ordered list of
what's next: `PORT_STATUS.md`.

## Running it

Open `project.godot` in Godot **4.3+** (built against 4.7.2), or from the
command line:

```
godot --path . scenes/main.tscn
```

**Controls** — desktop: WASD move, hold left mouse + aim with the mouse to
shoot, Space to dash, Esc to pause. Gamepad: left stick move, right stick
aim/auto-fire, A to dash, Start to pause. Touch controls are not ported yet.

## Testing

```
godot --headless --script tests/smoke.gd
```

A bare-`SceneTree` gate (no GPU, no wall-clock dependence) exercising player
movement/firing/damage/i-frames, all four enemy types (including SPITTOR's
wind-up tell and FANNER's every-third-wide volley beat), the wave budget
curve, the death pop and every revenge dialect, and the spawn/clear cycle —
55 checks. Run it before every commit that
touches `scripts/`.

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
  wave_director.gd        budget-based wave composition, shooter cap,
                          corpse pops and revenge volleys
tests/smoke.gd         headless gate — see "Testing" above
PORT_BRIEF.md         inherited visual/material brief (Godot-side canon for shaders/lighting)
PORT_STATUS.md        living doc: what's ported, what's next, in priority order
```

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
