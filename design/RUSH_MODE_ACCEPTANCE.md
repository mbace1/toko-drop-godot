# Rush mode — acceptance spec

Companion to [`RUSH_MODE.md`](RUSH_MODE.md). That document argues *what Rush
is*; this one says **what "done" means** for each queued item, in terms
`tests/smoke.gd` can actually assert.

It exists because `CLAUDE.md` requires new mechanics to ship with their own
checks in the same commit, and because a check written after the fact tends to
assert what the code happens to do rather than what the design asked for.
Writing them here, before the code, keeps the gate honest.

## How the harness works (write checks in its idiom)

`tests/smoke.gd` is a bare `SceneTree` — no GPU, no wall clock, currently 78
checks. Conventions to follow rather than reinvent:

- `_check(cond, label)` is the only assertion. One behaviour per check, and the
  label reads as a sentence about the game, not about the code.
- `_place(root, enemy, at, target, bullets)` sets `position` / `target` /
  `bullets` / `half_*` and calls `init()` — exactly as `WaveDirector._spawn()`
  does. Use it; do not hand-roll setup.
- `_make_pool(root)` builds a `BulletPool` with its explicit `build()`.
- **Never sleep, never read the clock.** Advance state by calling `update(dt)`
  in a loop with a fixed `dt`. Every existing `_test_*` does this, and it is
  what makes the gate reproducible.
- Add each new `_test_*` to the list in `_init()`.
- Closures capture outer locals **by value** — to report out of a lambda,
  capture a 1-element `Array` or a `Dictionary` (`CLAUDE.md`, and the existing
  `wave_cleared` check).
- `Dictionary` uses bracket access, never dot access.

Two things headless **cannot** cover, both of which have already burned this
port once: HUD layout and anything visual. Those items name `tools/capture.gd`
as half their gate, and that half is not optional — the first render of this
port had the stat row printed across the middle of the screen after 55 green
checks.

---

## Q-002 — Composition picker extraction

Pure refactor, so the acceptance bar is *nothing observable changed*.

- The existing `_test_wave_budget` checks pass **unmodified**. If a check needs
  editing to stay green, the refactor changed behaviour and is not this item.
- New: the picker, called directly with a known budget and caps, never returns
  picks whose summed cost exceeds the budget.
- New: the picker never returns more shooters than the shooter cap allows, and
  never more bodies than the body cap allows.
- New: given a budget too small for the cheapest eligible type, it returns
  empty rather than looping — the `affordable.is_empty()` bail-out is what
  stops an unspendable remainder from hanging the game, and it deserves a check
  now that a second caller depends on it.

## Q-003 — Rush director

- Virtual wave maps as specified: at `elapsed` 0 it is 1, and it advances by 1
  every `RUSH_WAVE_SECONDS`, checked at a boundary and just either side of it.
- Standing pressure never exceeds the target: drive the director for a simulated
  minute and assert the summed cost of living enemies stays at or under
  `budget_for(virtual_wave) * RUSH_PRESSURE` on every tick.
- The ported caps still bind: at a late virtual wave, living bodies never exceed
  `body_cap_for()` and living shooters never exceed `shooter_cap_for()`. This is
  the check that catches "Rush quietly stopped respecting the shooter cap",
  which would be invisible in play until the screen became unreadable.
- Refill is gated: two spawns never occur closer together than
  `RUSH_SPAWN_GAP`, even when the arena is emptied in one frame.
- **The clock does not advance while paused.** `main.gd` pauses by not calling
  `waves.update()`, so assert the elapsed time is unchanged across a stretch of
  frames where `update()` is not called. This is the check that would catch a
  `Time.get_ticks_msec()` clock or a `Timer` node — both of which would keep
  draining through a pause, and neither of which any *playing* test would
  notice.
- Earned time: a kill adds `RUSH_TIME_PER_KILL`, and the remaining time is
  clamped so it never exceeds `RUSH_DURATION`. Assert the cap explicitly by
  killing repeatedly at full clock — without the cap the mode collapses into
  endless, so the cap *is* the design.

## Q-004 — Edge-ring spawns and the telegraph

- No Rush spawn lands within `RUSH_SPAWN_SAFE` of the player. Assert over many
  spawns with the player parked in several positions, including a corner —
  a corner is where a naive "push it to the edge" implementation fails.
- Spawns land on the arena edge, not the `0.6×` wave ellipse: assert each spawn
  position sits at the half-extents within a small epsilon.
- A body does not exist during its telegraph, and does exist after it — i.e.
  the telegraph is a real delay, not a cosmetic flourish drawn over an
  already-live enemy that can already hit you.
- **Capture gate:** the floor ring is visible, reads at arena scale, and is
  distinguishable from the grid pulse. A telegraph nobody notices is the same
  as no telegraph.

## Q-005 — Heat multiplier

- A kill raises heat; the multiplier follows `1.0 + min(heat * 0.15, 2.0)`.
- The cap holds at ×3.0 — kill far past the cap and assert it does not exceed.
- Heat decays to 0 over `RUSH_HEAT_DECAY` **after** `RUSH_HEAT_WINDOW` elapses,
  not immediately: assert an intermediate value mid-ramp, since a hard reset
  and a ramp are indistinguishable if you only check the endpoints.
- Score awarded per kill is `100 * max_hp * multiplier`, checked against a
  tougher body so the `max_hp` term cannot silently drop out.
- Whatever open question 2 resolves to (does a hit break the chain?), there is
  a check asserting it. The decision must be visible in the gate.

## Q-006 — Save v2 and migration

All checks point `path` at a scratch file. `save_service.gd` carries the recorded
history here: a test that wrote the real save invented a "BEST 900" that then
showed up in a capture run.

- A v1 file (`hi_score` + `runs`, no `"v"`) migrates: the score and every run
  land under `modes.normal`, nothing is lost, and `"v": 2` is stamped.
- Migration is idempotent — running it twice yields the same file.
- A v2 file round-trips unchanged.
- The two modes are independent: recording a Rush run leaves the Normal best
  untouched, and vice versa. This is the whole point of the item.
- A corrupt or non-dictionary file still starts clean rather than crashing, and
  **a v1 file is not treated as corrupt** — the failure mode this guards is
  silently discarding a real save because it lacks a field.
- Rush runs record `kills` and `heat_peak`; `recent_line()` formats per mode
  and never prints a `wave` for a Rush run.

## Q-007 — Mode selection

- Last-played mode persists and is pre-selected on the next launch.
- The start-anywhere fallback still works: a tap that hits no chip starts the
  selected mode. Breaking this makes the game unstartable on a phone.
- Chip hit-testing is checked ahead of the fallback, not after.
- **Capture gate** at touch viewport size: both chips reachable by thumb, the
  selected one legible as selected, neither sitting where a stick will be
  planted.

## Q-008 — Rush HUD

Almost entirely a capture gate; headless can check the numbers feeding it, not
the layout.

- Headless: clock text, bar fill fraction and multiplier text derive correctly
  from director state, including at 0:00 and at full.
- **Capture:** clock centred and legible at a glance, drain bar reading as
  drain, multiplier not colliding with the score at four digits, SURGE flash
  visible without obscuring the arena. Check a *late* wave too — the HUD has to
  survive a full arena behind it.

## Q-009 — Sustained load

Not headless-testable; this is a real 180s run with `tools/capture.gd`.

- No frame-time cliff across the run, including the worst moment (a large
  multi-kill at a late virtual wave, when corpses, revenge volleys and a refill
  land together).
- Player bullets are never starved: `REV_POOL_GUARD 240` is doing its job, and
  the moment it *starts* dropping revenge volleys is a difficulty cliff the
  player cannot see. Establish whether it is hit at all during a normal run —
  if it is, that is a design decision to make deliberately, not a limit to
  discover in play.
- Touch endurance: three minutes without lifting a thumb, with the aim-stick
  release still reading as a dash rather than drifting.

---

## Definition of done, for the mode as a whole

1. `godot --headless --script tests/smoke.gd` green, with every check above
   present — a passing suite that skips a listed check is not done.
2. A capture run looked at *by a person* for every item naming a capture gate.
3. `PORT_STATUS.md` updated in the same commit as the code, per `CLAUDE.md`.
4. Every constant either carries a `tuning.js` cross-reference or is recorded
   as a deliberate divergence (`PARITY_RECON.md` Q1 decides which).
5. Each landed item's `QUEUE.md` entry moved to Landed with its SHA.
