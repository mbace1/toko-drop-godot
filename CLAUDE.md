# CLAUDE.md

Guidance for Claude Code (or any agent) working in this repository.

## What this is

A Godot 4.7 port of **Toko Drop**, a twin-stick swarm-survival browser game
that lives in a different repository: **`mbace1/Suds-Jack`**, folder
`toko-drop/` (Three.js r167, deployed at
https://mbace1.github.io/Suds-Jack/toko-drop/). That repository is the
**source of truth for behaviour and numbers** — enemy stats, timings,
formulas. This one owns the Godot implementation and its own visual choices.

## Which build leads — owner direction, 2026-08-27

> "We should aim the push of graphics and physics here on Godot. Otherwise
> follow the lead of the JS version."

This is the same rule the owner's global notes now state for every project
with two builds, and it decides what belongs in this repo:

- **The JS/web build LEADS.** New gameplay, new modes, new mechanics, new
  content are designed, played and proved *there* first.
- **This build FOLLOWS on gameplay** — it ports what landed.
- **This build PUSHES on graphics and physics**, because that is the part
  the web build cannot do: real SSS, verlet tentacles, GPU-scale particle
  work, shaders, 3D presentation, controller feel, landscape framing.
- **A feature is never designed twice.** If it is new gameplay, it goes
  upstream first, even in a week when Godot is the build being worked on.

So the honest test for any change here is: *is this a look/feel/physics
push, or is it a new verb?* The first belongs here. The second belongs in
`mbace1/Suds-Jack` first, and is ported back afterwards.

**Known drift that predates this direction, and is the owner's to settle
(see `PORT_STATUS.md`'s "Modes that exist only here"):** RUSH MODE and the
CHALLENGE campaign were designed in THIS repo (`design/RUSH_MODE.md`,
`design/RUSH_TIERS_AND_LEVELS.md`, `design/CAMPAIGN_LEVELS.md`) and do not
exist in the browser build at all, while ROGUELIKE — which the browser has
shipped — is still a "SOON" row here. That is precisely the shape this rule
exists to prevent. Do not extend those modes further without asking; port
ROGUELIKE and keep new verbs upstream.

Read in this order before changing anything:

1. **`PORT_STATUS.md`** — what's ported, what's next, in priority order.
   Update it in the same commit as any `scripts/`/`shaders/` change.
2. **`PORT_BRIEF.md`** — the visual/material canon (inherited from the
   source repo's own Godot dispatch brief; do not edit its content, it's
   handed down). Material and lighting decisions should trace back to it.
3. **`README.md`** — layout, running, testing.

## Porting discipline

- **Cross-reference the source file and line/formula in a comment** when you
  port a number or a piece of math (every script here already does this —
  follow the pattern). A port that silently drifts from the browser build is
  a bug nobody can spot by reading Godot code alone.
- **The browser's own docs are canon for design intent**, even where this
  repo's `PORT_STATUS.md` describes the Godot state: `TOKO_DROP_PORT_BRIEF.md`
  (blob/cube geometry and movement math) and `GODOT_PORT.md` == this repo's
  `PORT_BRIEF.md` (material/shader/lighting) both live in `mbace1/Suds-Jack`,
  `toko-drop/`.
- **No build step.** Same rule as the source repo: this is a plain Godot
  project, nothing generated, nothing vendored beyond the engine itself.

## Architecture rules specific to this project

- **`scenes/main.tscn` stays a bare `Node3D` with `main.gd` attached.**
  Everything else — camera, lights, floor, HUD, player, enemies, bullets —
  is built in code inside `main.gd`/the individual scripts, the same way
  `toko-drop/js/main.js` builds its `THREE.Scene` in code rather than a
  hand-authored file. Do not start hand-editing a complex nested `.tscn`
  hierarchy for gameplay objects; add another `build()`-style method instead.
- **Never rely on `_ready()` timing for anything another script needs
  immediately after `add_child()`.** Use an idempotent `build()` method
  (see `player.gd`, `bullet_pool.gd`) or an explicit `init()` (see
  `enemy.gd` and its subclasses), called manually right after `add_child()`.
  This is not a style preference — `tests/smoke.gd` runs inside a bare
  `SceneTree._init()`, where `add_child()` genuinely does not flush
  `NOTIFICATION_READY` synchronously, and relying on it produced real null
  crashes during the first pass of this port (see git history / README's
  "Design note" section).
- **`Enemy` subclasses are driven by an explicit `update(delta)` called from
  `WaveDirector.update(delta)`, never by Godot's automatic
  `_process`/`_physics_process`.** That is what makes the pause state free —
  `main.gd` simply stops calling `waves.update()`/`bullets.update()`/
  `player.update()` while paused, and nothing moves. Do not add a
  `_physics_process` override to an enemy; it will keep running while the
  game is paused.
- **GDScript closures capture outer locals by value, not by reference.**
  If a lambda needs to report something back to its enclosing scope (see
  `tests/smoke.gd`'s `wave_cleared` check), capture a 1-element `Array` or a
  `Dictionary`, not a bare `int`/`bool`/`float`.
- **Gameplay randomness comes from `WaveDirector.rng`; cosmetic randomness must
  not.** Any draw that decides *what happens* — which type spawns, where it
  lands, which way a body flops, a revenge ring's start angle — uses the
  director's `RandomNumberGenerator` (bodies receive it in `_spawn()` before
  `init()`). Any draw that only affects *how something looks or sounds* uses
  the global `randf()`/`randi()` or a private generator, the way
  `audio_kit.gd` already does. This is not tidiness: a cosmetic draw sharing
  the gameplay stream makes wave composition depend on how much the player
  shot, so under a seed two players diverge from the trigger. `bullet_pool.gd`'s
  shimmer `phase` is the call site that got this wrong once and now carries a
  comment saying not to "fix" it. See `design/DETERMINISM_AND_SEEDS.md`.
- **Dictionaries use bracket access (`d["key"]`), never dot access
  (`d.key`)** — GDScript `Dictionary` has no dot-access sugar. `aim` results
  from `input_manager.gd` are plain Dictionaries for exactly this reason;
  don't refactor them into a class without checking every call site.

## Testing

`godot --headless --script tests/smoke.gd` — bare `SceneTree`, no GPU, no
wall-clock dependence (16 checks today). Run it before every commit that
touches `scripts/`. When you port a new enemy type or mechanic, add its own
checks to `tests/smoke.gd` in the same commit — the existing four
`_test_*` functions are the template.

Also sanity-check the real scene boots clean after any change:

```
godot --headless --path . scenes/main.tscn --quit-after 120
```

Zero output (no `SCRIPT ERROR:` lines) is a pass.

## Repo hygiene

- `.godot/` (the editor's local cache) and any exported `build/` output are
  gitignored — never commit them.
- This repo gets its own history because Godot ports accumulate binary art
  that doesn't diff well (`mbace1/piritori-eden` set the precedent, split
  out of `Suds-Jack` for the same reason — see that repo's `CLAUDE.md`).
  Keep it that way: don't vendor the browser build's assets in here without
  thinking about repo size first.
