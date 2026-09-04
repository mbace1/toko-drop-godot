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

**When auditing this port against the browser, grep the DEPLOYED tree.**
The game ships from `mbace1/Suds-Jack`'s **`gh-pages`** branch, not `main`,
and a local clone sitting on `main` can be many commits behind. An audit
here got this wrong once and reported a mode as missing upstream that had
shipped there the same day — see `PORT_STATUS.md`'s "Modes that exist only
here" for the corrected table.

**RUSH is settled.** It went upstream and shipped as v224/v225/v227; this
repo's job with Rush now is to port each landing, reconciled against that
version rather than assumed to match. `PORT_STATUS.md` tracks the versions
ported so far.

**ROGUELIKE is settled too — ported, v3.1.** Was the one clear
follow-the-lead gap (shipped in the browser, still "SOON" here); it no
longer is.

**CHALLENGES is settled — dropped, 2026-08-28, owner's call
(`Suds-Jack` `QUEUE.md` Q-028).** It had existed only in this repo
(`design/CAMPAIGN_LEVELS.md`, `design/RUSH_TIERS_AND_LEVELS.md`), which was
exactly the shape this rule exists to prevent — designed on the port side
instead of proposed upstream first. Shelved on both sides: no build here, no
further Godot build-out. The design docs stay as a record, same shape as
`sudsjack/`'s "SET DOWN" — do not resume without the owner asking in their
own words.

**Both of the once-open Rush divergences are now settled.** The four
selectable abilities went upstream as v232 and their numbers lead. **RUSH
lives: owner decision 2026-09-04, "rush lives is 3" (Q-029).** Upstream v226
removed the browser's `rush.lives` as dead code (it was never spent there;
extra lives already worked through player HP), while this repo's `rush.lives`
is a live, spent resource. That divergence is KEPT on purpose: this build
runs Rush on 3 lives, `tests/smoke.gd` pins the number, and v226 is not to
be ported. Recorded in `mbace1/Suds-Jack`'s `toko-drop/PARITY_WITH_GODOT.md`
and [PR #311](https://github.com/mbace1/Suds-Jack/pull/311); whether the
browser converges back to lives is upstream's call, not a port task.

## Two renderers, two gel tiers — Q-030, 2026-09-04

The cabinet runs **Compatibility** (WebGL2); the desktop runs **Forward+**.
Godot's GLES3 compiler warns at every Compatibility launch that SSS,
transmittance and SSR are Forward+ only (SSAO goes silently). Owner
decision: the look ships on BOTH tiers. `scripts/render_tier.gd` is the
one place the tier is detected; `gel.gdshader` multiplies its compat-only
terms by the `gel_compat` global. Rules that follow:

- **Any look change is photographed on both tiers, same seed.**
  `tools/capture.gd` — `--script` is mandatory, `seed:HEX` pins the run,
  `TOKO_TIER=compat` forces the tier on a desktop. Judge the compat
  picture on its own; do not infer it from the Forward+ one.
- **Compat blooms, at its own threshold.** The scene buffer there is LDR,
  so `glow_hdr_threshold` must live in the tonemapped range —
  `main.gd`'s `COMPAT_GLOW_THRESHOLD` (0.4), Forward+ keeps 0.9. Emission
  above that blooms on both tiers (Q-034). Anything judged "too dim to
  bloom" on compat is a threshold question, not a renderer limit.
- A feature that only exists in Forward+ is not a bug on compat, but it
  must be NAMED in PORT_STATUS.md's "still different" list.

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

`godot --headless --path . --script tests/arena_check.gd` — 8,396 exact
checks that `scripts/arena.gd` still reproduces the rectangle's literal
expressions (Q-031). Run it on every edit to that file. It is a port of
upstream's `scripts/arena-check.mjs`, check for check, and it has been
falsified: a 1e-12 nudge on one coordinate fails 1,536 of them.

`godot --headless --fixed-fps 60 --script tools/trace.gd -- seed:9D6875 300`
— a seeded GAMEPLAY-STATE trace: every body's class and exact float32
position at fixed frames. Diff it before and after any change to movement,
spawning or the arena; zero lines is the pass (Q-035). Do not try to prove
"nothing changed" with screenshots — cosmetic randomness is deliberately off
the gameplay stream, so two runs of identical code differ on screen.

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
