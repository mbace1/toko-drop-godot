# Queue

The **work queue** for Toko Drop across both repos. High-level planning happens
here (see [`design/`](design/)); this file is the ordered, reviewable list of
what that planning turned into, and which repo each piece is destined for.

It is a *queue*, not a status report. `PORT_STATUS.md` remains the living
description of what the Godot port actually is today; this file describes what
is queued to change and who is holding it. When an item lands, `PORT_STATUS.md`
gets updated in the same commit — that rule does not change.

---

## How this file works with version control

The point of keeping the queue in git rather than in a tracker is that a
planning change and the code that satisfies it can arrive in the same commit,
reviewed together. That only holds if the file is built so two branches editing
it in parallel do not collide. Four rules make that true:

**1. Stable IDs, allocated high-water-mark.** Every item is `Q-NNN`, assigned
once and never reused, renumbered or recycled — not even after a `Dropped`.
Take the next number above the highest that has *ever* appeared in this file,
including in git history. IDs are how a commit message, a PR title and this
file refer to the same thing.

**2. One item per block, blocks are append-mostly.** Each item is a fenced
block under a status heading. Adding work appends a block; two branches adding
different items touch different lines and merge clean. Never reflow or re-sort
a whole section to make it look tidy — a cosmetic re-sort turns every other
open branch into a conflict.

**3. Status changes move exactly one line.** The `status:` line inside the
block, plus moving the block under the matching heading. Do not rewrite the
body while changing status; if the plan changed, that is a separate edit with
its own reasoning.

**4. Landing is recorded, not implied.** When an item lands, its status line
gains the commit SHA (and PR number, if there was one) that closed it. That is
what makes `git log -S "Q-014"` a complete history of one piece of work across
both repos.

Commit messages reference items as `Q-NNN` anywhere in the subject or body.
Branches carrying a single item are named `claude/<slug>-<qid>` or similar —
whatever the branch, the ID goes in the commit.

### Item template

Copy this block, take the next ID, fill it in:

```
### Q-000 — one-line title

- status: Queued
- repo: toko-drop-godot | Suds-Jack | both
- size: S | M | L
- blocked-by: —
- design: design/SOME_DOC.md §N
- gate: what has to be green before this is done

Two or three sentences of what and why. Enough that someone picking it up
cold does not have to re-derive the reasoning, and no more — the reasoning
itself lives in the design doc this points at.
```

Statuses: `Queued` → `In progress` → `Landed` (with SHA) — or `Blocked`
(with what on) or `Dropped` (with why, kept in place, never deleted).

`repo:` is what "submit to repos" means in practice: an item marked
`Suds-Jack` is planned here and *executed there*, and its landing SHA will be
from that repository. Design work happens in one place so the two builds do
not drift; the code lands wherever it belongs.

---

## Blocked

### Q-001 — Establish whether the browser build already has a Rush/time-attack mode

- status: Blocked — needs `mbace1/Suds-Jack` attached to a session
- repo: both
- size: S
- blocked-by: repo access
- design: design/PARITY_RECON.md (the executable checklist), design/RUSH_MODE.md § Parity risk
- gate: every question in PARITY_RECON.md answered or explicitly marked
  "searched for X, not found", each with a `file:line`

`CLAUDE.md` makes the browser build the source of truth for numbers, and every
constant in the Rush design currently has no cross-reference because the source
tree could not be read when it was written. If a rush mode exists upstream, the
design becomes a port and its constants get replaced wholesale. If it does not,
Rush is this port's first gameplay-level divergence and has to be recorded as
one — and probably proposed upstream. **Every item below inherits this block
for its tuning constants**; the structural work (Q-002, Q-006, Q-007, Q-011,
Q-012) does not depend on it and can start.

`PARITY_RECON.md` widens this into one trip that also answers the daily seed's
reference implementation (Q-013), the open HUD layout divergence (Q-015), the
kill-particle numbers (Q-016) and the full ~40-type roster table — the cost is
mostly in attaching the repo and paging in the tuning tables, and that is paid
once whether one question is answered or six.

---

## Queued

### Q-002 — Extract wave composition from `start_wave()` into a reusable picker

- status: Queued
- repo: toko-drop-godot
- size: S
- blocked-by: —
- design: design/RUSH_MODE.md §3.2
- gate: `tests/smoke.gd` green with the existing wave-budget checks unchanged

`WaveDirector.start_wave()` currently interleaves "decide what to spawn" with
"spend a whole wave at once". Rush needs the first half on a per-tick cadence.
Split out the affordability loop so both cadences call one picker — forking it
would mean two copies of a ported table drifting apart, which is the exact
failure `CLAUDE.md`'s porting discipline exists to prevent. Pure refactor: no
behaviour change, no new numbers, so it is safe to land ahead of Q-001.

### Q-003 — Rush director: virtual wave, standing pressure, gated refill

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-001 (constants), Q-002 (picker)
- design: design/RUSH_MODE.md §3
- gate: smoke checks for the virtual-wave mapping, the pressure ceiling, the
  refill gap, and that the clock does not advance while paused

Time-driven escalation reusing `budget_for()` / `shooter_cap_for()` /
`body_cap_for()` unchanged. The clock accumulates from the director's own
`delta`, never wall-clock — a Rush timer driven by `Time.get_ticks_msec()`
would keep draining through a pause, and that is both a cheat and the kind of
bug a headless test can actually catch.

### Q-004 — Edge-ring spawns with a floor telegraph

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-003
- design: design/RUSH_MODE.md §3.4
- gate: smoke check that no Rush spawn lands inside the safe radius, plus a
  `tools/capture.gd` run showing the telegraph — this one is visual, so the
  screenshot is half the gate

Trickle spawns cannot use the wave ellipse: a body appearing at 0.6× extents
mid-run with no wave boundary to warn you is an unavoidable hit. Edge ring, a
minimum distance from the player, and a 0.45s ring pulse on the floor grid
before the body exists — 0.45s because that is SPITTOR's wind-up, a tell the
player has already been taught.

### Q-005 — Heat multiplier and Rush scoring

- status: Queued
- repo: toko-drop-godot
- size: S
- blocked-by: Q-001 (constants), Q-003
- design: design/RUSH_MODE.md §4
- gate: smoke checks for the window, the decay ramp and the cap

Replaces Normal's per-clear bonus, which Rush cannot have. Open question 2 in
the design doc (does a hit break the chain?) is still unsettled and is cheap to
flip after the fact — do not let it hold the item.

### Q-006 — Save schema v2: per-mode bests, with a v1 migration

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: design/RUSH_MODE.md §7
- gate: smoke checks for the migration (v1 file in, v2 out, nothing lost) and
  for round-tripping v2 — both against a scratch `path`, never the real save

The stored shape is mode-blind and unversioned, so the first Rush run would
overwrite the Normal best with a number from a different game. Needs doing
before any Rush run can be recorded, and it is independent of Q-001, so it can
go early. `save_service.gd` already carries the warning that a test writing to
the real save eats the player's hi-score; honour it.

### Q-007 — Mode selection on the menu and death screen, touch-first

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-006 (last-played mode is persisted)
- design: design/RUSH_MODE.md §6
- gate: capture run on a touch-sized viewport; the start-anywhere fallback must
  still work for a first-time player who taps nothing in particular

Today any touch anywhere starts a run, because on a phone there is no FIRE key.
Two modes means selecting without breaking that: hit-tested mode chips ahead of
the fallback, last mode persisted and pre-selected, keyboard and gamepad
bindings alongside.

### Q-008 — Rush HUD: clock with drain bar, multiplier, SURGE flash

- status: Queued
- repo: toko-drop-godot
- size: S
- blocked-by: Q-003, Q-005
- design: design/RUSH_MODE.md §5
- gate: capture run — the HUD is the single thing in this port with a recorded
  history of passing every headless check while being visibly broken on screen

Clock replaces WAVE, multiplier replaces BEST, and the escalation beat that
Normal gets for free (an arena emptying and refilling) has to be announced
explicitly.

### Q-009 — Sustained-load pass: revenge pool guard, corpse count, touch endurance

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-003
- design: design/RUSH_MODE.md §1, §3.5
- gate: a full 180s Rush run captured end to end with no frame-time cliff and
  no starved player bullets

Rush drives corpse and bullet counts far past anything Normal produces, which
turns `REV_POOL_GUARD 240` from a theoretical safety net into load-bearing
code. Same for the touch sticks under a finger that never lifts for three
minutes. Neither is testable headless; both need the real game running.

### Q-010 — Propose Rush upstream, or port the upstream mode down

- status: Queued
- repo: Suds-Jack
- size: M
- blocked-by: Q-001 — and its answer decides which of the two this item *is*
- design: design/RUSH_MODE.md § Parity risk
- gate: either a landed upstream change, or a recorded decision not to

The two builds diverging in *modes* is a far bigger split than diverging in
materials, and the port has so far recorded every divergence deliberately. This
item exists so that record keeps holding.

### Q-011 — Move the bullet shimmer draw off the gameplay random stream

- status: Queued
- repo: toko-drop-godot
- size: S
- blocked-by: —
- design: design/DETERMINISM_AND_SEEDS.md §2, §5
- gate: `tests/smoke.gd` green; no behaviour change to assert yet, by design

`bullet_pool.gd:115` draws a bullet's cosmetic shimmer phase from the same
global RNG as `wave_director.gd`'s spawn picker. Nothing is broken today
because nothing is seeded — but the moment a seed exists, **firing one extra
shot shifts every subsequent wave composition**, and two players on the same
daily seed diverge from the trigger. Two lines now; a bug report about scores
that do not reproduce later. Do it early, independent of everything else.

### Q-012 — A gameplay RNG, and the cosmetic-vs-gameplay stream rule

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-011
- design: design/DETERMINISM_AND_SEEDS.md §4
- gate: a smoke check asserting the same seed yields the same wave composition
  twice; the rule written into `CLAUDE.md` alongside the existing architecture
  rules

One `RandomNumberGenerator` owned by `WaveDirector` and handed to enemies
through the same explicit `_spawn()` hand-off that already sets `target` /
`bullets` / `half_*`. The rule that keeps it working — draws that affect *what
happens* use the gameplay stream, draws that affect only *how it looks or
sounds* must not — has to be written down, or the first particle system
reintroduces Q-011's bug. `audio_kit.gd` already owns a private RNG and is the
pattern to copy. Worth landing even if the daily seed is never built: it also
lets the smoke gate assert on specific compositions instead of only on
aggregate budget properties.

### Q-013 — Daily seed: derivation and entry

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-012, Q-001 (PARITY_RECON.md Q2 — the browser build already
  shipped this, so match it rather than inventing a scheme)
- design: design/DETERMINISM_AND_SEEDS.md §4, §6
- gate: same seed ⇒ same swarm, asserted headless; the seed recorded with every
  run so a good run can be identified afterwards

The last open piece of `save_service.gd`'s Phase 4 note. Promises *the same
swarm*, not the same game — say so plainly in the UI, since full deterministic
replay is deliberately out of scope (§3 explains what it would cost).

### Q-014 — Split-on-death machinery, and SPLITTA

- status: Queued
- repo: toko-drop-godot
- size: L
- blocked-by: —
- design: design/SPLIT_ENEMIES.md
- gate: the six checks in §4 — above all, that a wave holding only a splitter
  does not emit `wave_cleared` when it dies

First item on `PORT_STATUS.md`'s backlog, and independent of Rush, so it can
run in parallel by different hands. Designed once because REDD_CUBE and
PURP_CUBE reuse it. The interesting part is not the spawn — it is that a death
here already pops for 0.28s, fires a revenge volley, awards score and can clear
a wave, and splitting has to answer for all four. Two notes land back on Rush:
recompute standing pressure rather than decrementing it, and decide
deliberately whether children may exceed the body cap.

### Q-015 — Settle the HUD layout divergence before Rush occupies it

- status: Queued
- repo: toko-drop-godot
- size: S
- blocked-by: Q-001 (PARITY_RECON.md Q3)
- design: design/RUSH_MODE.md §5
- gate: capture run at two viewport sizes

`PORT_STATUS.md` records the browser build stacking WAVE + a progress bar
top-left with HP pips beneath, against this port's single top row — "still
different, still open". Rush wants a clock in exactly that real estate, so the
divergence is about to be settled by default unless somebody settles it on
purpose. The browser's wave-progress bar is the same shape as Rush's drain bar,
which may make this cheaper than it looks.

### Q-016 — Kill particles

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-012 (must draw from the cosmetic stream, not the gameplay one)
- design: — (numbers from PARITY_RECON.md Q4)
- gate: capture run; `TUNING.fx.killDroplets` 22 / `killChunks` 5 confirmed
  against the source

`PORT_STATUS.md` item 2: the pop and the revenge volley are in, the debris is
not. Listed here mainly because it is the **next thing that would have
reintroduced Q-011's bug** — a particle system reaching for `randf()` is the
obvious way to pollute the gameplay stream, and now there is a rule that says
not to. Worth doing as `GPUParticles3D` directly, per `PORT_BRIEF.md` §3/§5.

---

## Landed

*(nothing yet — the first entry here will be a block moved up from Queued with
its SHA appended to the status line)*

---

## Dropped

*(nothing yet — dropped items stay here with the reason, so the same idea does
not get re-queued a month later without its history)*
