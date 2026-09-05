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

- status: **Landed** in `2b76cbd` — answered, no code needed
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



**Answered 2026-08-24.** With `mbace1/Suds-Jack` attached: the browser build
has **no** time-attack / Rush mode. Its mode flags in `toko-drop/js/main.js`
are `roguelikeMode`, `smashMode`, `meleeOnlyMode`, `dailyMode`, `testMode`,
the six cabinet flags, plus `landscape`/`perf`/`pixel` display toggles.
So Rush is a genuine DIVERGENCE, the `PROPOSED` constants are free, and
**Q-010 is "propose upstream", not "port down"**. One upstream detail worth
having: `main.js` carries `const ROUND_DUR = 20; // seconds per wave`, so it
has a per-wave clock without having a time-attack mode.

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


### Q-007 — Mode selection on the menu and death screen, touch-first

- status: Queued
- repo: toko-drop-godot
- size: M — **re-scope before building** if the campaign (Q-022) is wanted:
  two chips becomes three modes plus a level grid with per-level grades, which
  is a different screen with its own touch answer
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

- status: **Landed, 2026-08-28** — it turned out to be *both*, in that order
- repo: Suds-Jack, then here
- size: M
- blocked-by: ~~Q-001~~ — answered
- design: design/RUSH_MODE.md § Parity risk
- gate: either a landed upstream change, or a recorded decision not to — **met
  by a landed upstream change**

Resolved the way the item hoped. The design went UP: the browser's **v224**
("RUSH MODE — boost is the answer, the gun is the fallback") credits its own
ruleset to this repo's `design/RUSH_MODE.md`, and shipped it. Its numbers and
this port's then matched line for line without either being edited to suit the
other — checked 2026-08-27, see `PORT_STATUS.md`.

Then the port came DOWN: **v225** ("RUSH gets its own arena and its own
roster") is upstream work this repo did not have, and is ported here as of
v3.2 — the bare arena, the four-body roster, the COOLER's heat vent, and no
boss set pieces.

So Rush is now a normal follow-the-lead mode: upstream leads it, this repo
ports it. The remaining Rush divergence is the four **abilities**, which exist
only here — raised upstream in `Suds-Jack` PR #311 for a decision, not acted
on unilaterally.


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

- status: **Landed** in `db7158d`
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


**Landed.** `Splitta.wants_children` + `child_positions()` with the director
owning `_split()`. Children join the LIVE list, so a wave is not clear until
they are dealt with. The parent visibly CARRIES two child domes beforehand
(`TOKO_DROP_PORT_BRIEF.md` Part 2). Scatter draws from `rng` as of `2b76cbd`.
REDD_CUBE and PURP_CUBE reuse this path.

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

- status: **Landed** in `2097f5c`
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


**Landed.** `scripts/debris_pool.gd` — ballistic gel lumps with a floor
bounce at `TUNING.fx` counts (8 droplets on a hit, 22 + 5 chunks on a kill),
one MultiMesh. Lit rather than unlit: unlit spheres of a flat colour read as
confetti rather than as bits of the same gel. Camera shake landed alongside
it on main.js's trauma-squared model.

### Q-019 — Hazard scaffolding, and SLUDGE pools

- status: **Partly landed** in `db7158d` — SLUDGE pools done, hazards open
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: design/HAZARDS.md §3, §4a
- gate: smoke checks that a hazard updates only when called (so pause freezes
  it), that it never enters `enemies` and so cannot hold up a wave clear, and
  that the slow applies and lifts on the arena's flat circle test

The arena is an empty box — no cover, no geometry, no environmental threat, so
every square of floor is identical and position means nothing beyond distance
from bodies. Area-denial on the floor is the cheapest fix that fits: no
pathing, no new geometry, and it uses the circle test `main.gd` already runs.
Do SLUDGE first because it is **already required** — `PORT_STATUS.md`'s
next-up SLUDGE_CUBE is "slow MASS + poison trail", and that trail is this
system. One system, two features.


**Partly landed.** `scripts/poison_field.gd` is the pooled floor-hazard
scaffolding (MultiMesh discs, per-patch life, one shared damage tick so
overlapping patches are a bad place to stand rather than instant death), and
SLUDGE_CUBE lays one every 0.5s with an 8s life. The GENERAL hazard types in
`design/HAZARDS.md` are still open and can build on this node.

### Q-020 — GRID SURGE

- status: Queued
- repo: toko-drop-godot
- size: M
- blocked-by: Q-019
- design: design/HAZARDS.md §4b
- gate: capture run — the line must read as armed before it fires, at arena
  scale, without competing with the bodies

A row or column of the existing floor grid lights, holds a beat, then
discharges. The best fit for what the game already is: the floor shader draws
and pulses that grid already, so a surge is a uniform rather than an object. It
telegraphs by construction, demands movement rather than precision (which is
what keeps it fair on a thumb stick), and gives the arena the thing it lacks —
a reason for one part of the floor to be worse than another, changing every
few seconds.

### Q-021 — LIVE RAIL

- status: Queued
- repo: toko-drop-godot
- size: S
- blocked-by: Q-019, Q-020
- design: design/HAZARDS.md §4c
- gate: capture run; plus a deliberate check that the arena still plays as "a
  wide room you cross" rather than a shrinking one

Exists for a specific reason, not for variety: both modes currently reward
hugging the edge, since bodies clamp to the same boundary the player does and a
corner restricts the arc you can be attacked from. A periodically live rail is
the targeted answer, and it reuses the emissive rail material already built.
Last of the three because it changes movement habits game-wide.

### Q-031 — `arena.gd`: port `js/arena.js` (SDF arena) with its check suite

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-031"`);
  the module and its gate. Wiring the rectangle call sites is Q-035.
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: `Suds-Jack` `toko-drop/LEVEL_EDITOR_DESIGN.md` §2, §8 (P0 as
  built, v236)
- gate: a port of `scripts/arena-check.mjs` — the same comparisons
  (`sdf`/`contains`/`clamp`/`ringPoint`/`insetPoint`/`rayEdge`/
  `randomPoint`) against the literal expressions, at every shipped arena
  size, exact rather than tolerant

Owner decision 2026-09-04: a body left outside a moving shape is PUSHED
along the SDF gradient — which is exactly `arena.js`'s `clamp()` ("march
down the gradient"), so no new rule is needed. Keep §8's two determinism
rules verbatim: `randomPoint` draws exactly twice, and nothing in the
module reads a clock. Only the rectangle is wired up upstream; port that
first and stop, same as they did.

### Q-035 — Wire the rectangle sites to `Arena`

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-035"`).
  The gate turned out to be a seeded state TRACE (`tools/trace.gd`), not a
  pixel pair — see PORT_STATUS.md "Q-031 — the arena as an SDF", "Wired".
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: PORT_STATUS.md "Q-031 — the arena as an SDF"; upstream
  LEVEL_EDITOR_DESIGN.md §8 for the site split and the three deliberate
  non-migrations
- gate: `tests/smoke.gd` unchanged in count and content; a seeded
  gameplay-state trace (`tools/trace.gd`, same `seed:HEX`) before and
  after is byte-identical — pixels cannot be, by design (cosmetic
  randomness is off the gameplay stream)

`main.gd` owns one `Arena`, `set_rect(half_x, half_z)` on every arena
resize, and threads it to `player.update()`, `WaveDirector._spawn()`
(`ring_point`), every enemy's `_clamp_to_arena()`, TORO's slab test
(`ray_edge`) and the random placements (`random_point`, two draws). Only
BOUNDARY questions move; `half_x`/`half_z` as a SIZE stay where they are.
Nothing changes — which is what the seeded pair proves.

### Q-032 — Level format loader: read upstream's JSON directly, no exporter

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-032"`).
  Both shipped levels play identically in both builds: `tools/level-parity.mjs`
  46/46 and 34/34. The floor drawing the region here is Q-037.
- repo: both (format lands upstream first; the loader lands here)
- size: M
- blocked-by: Q-035; upstream P1 (the format, a loader, one authored level)
- design: `Suds-Jack` `toko-drop/LEVEL_EDITOR_DESIGN.md` §4 (format 1)
- gate: the same authored level plays end to end in both builds; every
  field the format declares round-trips through the Godot loader (a field
  the loader does not know is a FAILURE, not a skip)

Owner decision 2026-09-04: the editor is built upstream in JS; this build
loads the levels. The loader must parse the shared JSON as-is — Eeri's
`export-levels.mjs` carries an allow-list that silently dropped two new
part types for two versions, and a translation step is the only thing that
can do that. Godot parses JSON natively; do not build the thing that can
drop a field.

### Q-033 — Compat tier: the floor hue

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-033"`).
  Neither suspect; the compat ACES tonemapper zeroed dark red. AgX on
  that tier. The 8-bit residual is Q-036.
- repo: toko-drop-godot
- size: S
- blocked-by: —
- design: PORT_STATUS.md "Q-030 — the two gel tiers", "still different"
- gate: same-seed floor sample within a stated tolerance of Forward+ on
  both tiers (capture recipe in `tools/capture.gd`)

Forward+ open floor `rgb(11.5, 19.2, 56.6)`; Compatibility
`rgb(0, 13.7, 87.3)`. Same luma, zero red, +54% blue. Suspects in order:
SSR of the warm-grey sky (absent on compat), the sky ambient term. Measure
before changing anything.

### Q-036 — Compat tier: the 8-bit dark crush (`use_hdr_2d`, re-tuned)

- status: **Landed as a NEGATIVE RESULT, 2026-09-04** — this commit
  (`git log -S "Q-036"`). No code changed. The premise was false (a grey
  card shows the renderers agree on lit albedo), `use_hdr_2d` was
  measured and rejected, and the real cause of the floor shift is
  ENABLING GLOW on the Compatibility renderer — which also falsifies
  Q-033's recorded diagnosis. Full numbers in PORT_STATUS.md. The choice
  that remains is Q-038.
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: PORT_STATUS.md "Q-030 — the two gel tiers", the Q-033 and
  Q-036 bullets
- gate: same-seed floor AND void AND rail samples within a stated
  tolerance of Forward+ on the compat tier; the seeded sheet for the eye

After Q-033, the compat floor still carries half of Forward+'s red and
runs 37% bright, because dark linear values are quantised to zero in an
8-bit scene buffer before any tonemapper sees them. `use_hdr_2d` gives
that tier an HDR buffer and puts the void exactly on Forward+'s, but
triples the floor's brightness — so the exposure, threshold (Q-034) and
tonemapper must be re-tuned together with it, on one seed, against the
Forward+ frame. Change all of them in one item or none.

### Q-034 — Compat tier: bloom

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-034"`).
  The glow pass works on Compatibility; the 0.9 HDR threshold was the
  whole problem on an LDR buffer. `COMPAT_GLOW_THRESHOLD = 0.4`.
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: PORT_STATUS.md "Q-030 — the two gel tiers", "still different"
- gate: a halo on the emissive rail in a Compatibility capture

Nothing blooms on Compatibility — not the rail, not the pulse bullets —
and Godot prints no warning about it. Establish whether 4.7's Compatibility
glow needs an HDR buffer or different thresholds, or is simply faint here.
Until this lands, every compat look must be built as tint and shape, never
as light (Q-030's transmittance was cut that way for this reason).

### Q-037 — Godot floor draws the level's region (both tiers)

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-037"`).
  Photographed on both tiers beside upstream's picture; parity unchanged.
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: upstream v238 (`FLOOR_FRAG`'s shape term: world-space SDF from a
  fixed slot array, union=min, intersect=max, neutral for an unused slot,
  dim outside, boundary glow); PORT_STATUS.md "Q-032", the last paragraph
- gate: `three-rings` photographed on Forward+ AND Compatibility with the
  region visible on both (Q-030's rule), against upstream's own
  `scripts/level-shot.sh` pictures; smoke unchanged; the parity gate
  unchanged (drawing must not touch the simulation)

The mechanics already honour the shape (Q-031/Q-032); the floor still
paints the bounding rectangle, so a circle level is invisible. Port the
term into `floor_grid.gdshader` with the shape slots as uniforms written
from `_apply_level()`. The compat tier's bloom threshold (Q-034) and
tonemapper (Q-033) will both act on the glowing boundary — judge it on the
phone's tier, not the desktop's.

### Q-038 — OWNER CALL: on the phone, bloom or floor colour?

- status: Blocked — needs the owner
- repo: toko-drop-godot
- size: S (the change is two lines; the decision is the item)
- blocked-by: an owner decision
- design: PORT_STATUS.md, the Q-036 bullet
- gate: whichever is chosen, photographed on both tiers on one seed

On the Compatibility renderer the two cannot both be had, and no exposed
setting splits the difference (threshold, intensity, strength and blend
mode were all measured and none modulate the side effect):

- **bloom on** (what ships today): the gel and the rails glow; the floor
  runs `(6.2, 29.0, 81.1)` against the desktop's `(11.4, 19.6, 57.0)` —
  about 35% bright and distinctly bluer, with AgX compensating.
- **glow off on compat only**: the floor lands on `(10.0, 19.8, 63.6)`,
  a near match for the desktop, and nothing on the phone blooms.

Not a bug in either direction, so it is not mine to settle. If bloom wins,
the AgX split stays and the reason in the docs is now correct. If colour
wins, disable glow on the compat tier and revert to ACES there (with glow
off, AgX's compensation is no longer wanted — re-measure).

## Landed

### Q-030 — Two gel tiers: Compatibility gets an analytic transmittance

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-030"`)
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: PORT_BRIEF.md §2a (what the look is for); PORT_STATUS.md
  "Q-030 — the two gel tiers" (what was found and what shipped)
- gate: `_test_render_tier` in `tests/smoke.gd`, plus the three-panel
  same-seed sheet described in PORT_STATUS.md

Godot's GLES3 compiler warns that SSS, transmittance and SSR are Forward+
only; the cabinet is a Compatibility build, so the gel's headline read was
absent on the web. Owner decision: both tiers get the look. `RenderTier`
detects the renderer once, publishes it to the shader as a global, and
`gel.gdshader` deepens lit-from-behind faces toward the gel colour on that
tier (tint, not glow — bloom does not run there, see Q-034). Forward+ is
untouched by construction. Also fixes `tools/capture.gd`, which was never
running at all (`--script` is not optional).

### Q-029 — Rush lives settled: 3, the counter stays, v226 not ported

- status: **Landed, 2026-09-04** — this commit (`git log -S "Q-029"`)
- repo: toko-drop-godot
- size: S
- blocked-by: —
- design: PORT_STATUS.md "Catching up with the browser: v226-v231", the v226
  bullet; `Suds-Jack` `toko-drop/PARITY_WITH_GODOT.md`, PR #311
- gate: `tests/smoke.gd` — "Rush starts on exactly 3 lives (Q-029, owner
  decision)"

Owner direction 2026-09-04: "rush lives is 3". This build's `rush.lives` is a
real, spent resource (`take_hit()` decrements it, the run ends at zero); the
browser's v226 removed its own counter as dead code and runs Rush on HP. The
two builds disagree on purpose from here: keep `LIVES_START := 3`, pin the
number in the gate so a drift to the HP model cannot hide behind a rename,
and do not port v226. Nothing else changes — the value was already 3.

### Q-017 — Par curve, live tier, and the final grade

- status: **Landed, 2026-08-28, v3.4** — in the SIMPLER shape that shipped
  upstream, not this item's own proposal
- repo: toko-drop-godot
- size: M
- blocked-by: ~~Q-005~~ — landed in the browser's own shape instead of this
  repo's, so the blocker never applied
- design: design/RUSH_TIERS_AND_LEVELS.md §3, §4 (superseded — see the note at
  that doc's own top) / `Suds-Jack`'s v227, `RUSH_DESIGN.md` §3
- gate: `_test_rush_tiers` in `tests/smoke.gd`

Landed by porting `Suds-Jack`'s v227 rather than building this item's own
par-curve-with-interpolated-checkpoints design: `tier_for(kills, seconds)` is a
flat rate x seconds comparison per LEVEL (Rush's existing 60/90/+30s
escalation), not the leg-checkpoint interpolation this item specified. Same
four reference rates (S 2.0 / A 1.4 / B 0.9 / C 0.5), same "derived, not
hand-edited" rule, same "below C shows no letter". Closed by the simpler
version landing rather than reopening the elaborate one.


### Q-018 — Legs, checkpoints, goals and the star

- status: **Landed, 2026-08-28, v3.4** — with TWO goals, not three; the third
  turned out to be impossible as specified
- repo: toko-drop-godot
- size: M
- blocked-by: ~~Q-017~~
- design: design/RUSH_TIERS_AND_LEVELS.md §2 (superseded) /
  `Suds-Jack`'s `RUSH_DESIGN.md` §3.4
- gate: `_test_rush_tiers` (7 checks on the goals and the ladder)

Porting `Suds-Jack`'s v227 found — independently of that repo's own identical
finding — that this item's UNTOUCHED goal cannot exist separately: a hit
already resets the level clock to 0 (`take_hit()`), so reaching ANY level-up
stamp already proves the attempt was hit-free. `chain_unbroken` and
`never_locked` are the two goals that survived; a level keeping both clean
earns a `★` in `rush.ladder`. Also landed per LEVEL rather than per 60s LEG —
Rush's existing escalation, not a new structure. Recorded in both repos'
parity notes (`Suds-Jack`'s `toko-drop/PARITY_WITH_GODOT.md`,
[PR #311](https://github.com/mbace1/Suds-Jack/pull/311)) as the case where a
design flaw was caught the same way on both sides of the port.


### Q-002 — Extract wave composition from `start_wave()` into a reusable picker

- status: **Landed** in `e6bf70a`
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

### Q-006 — Save schema v2: per-mode bests, with a v1 migration

- status: **Landed** in `e6bf70a`
- repo: toko-drop-godot
- size: M
- blocked-by: —
- design: design/RUSH_MODE.md §7, design/CAMPAIGN_LEVELS.md §4 (reserve the
  per-level record shape now — it is a map of level id → best score/grade, not
  the `{score, wave}` run list, and adding it later means a v3 migration)
- gate: smoke checks for the migration (v1 file in, v2 out, nothing lost) and
  for round-tripping v2 — both against a scratch `path`, never the real save

The stored shape is mode-blind and unversioned, so the first Rush run would
overwrite the Normal best with a number from a different game. Needs doing
before any Rush run can be recorded, and it is independent of Q-001, so it can
go early. `save_service.gd` already carries the warning that a test writing to
the real save eats the player's hi-score; honour it.

### Q-011 — Move the bullet shimmer draw off the gameplay random stream

- status: **Landed** in `e6bf70a`
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

**Landed differently than specified**, recorded here rather than by rewriting
the block above. The fix was not to move the shimmer draw — it was to move
*gameplay* off the global stream (Q-012), which left the shimmer's global draw
correct by construction. So the only change at this call site is a comment
recording why it must stay where it is. The bug this item describes is real and
is now closed; the remedy was the inverse of the one written down.

### Q-012 — A gameplay RNG, and the cosmetic-vs-gameplay stream rule

- status: **Landed** in `e6bf70a`
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


---

## Dropped

*(nothing yet — dropped items stay here with the reason, so the same idea does
not get re-queued a month later without its history)*

### Q-022 — Level archetype scaffolding: a level as data

- status: **Dropped, 2026-08-28** — see Q-024's note; CHALLENGES itself was
  dropped by the owner (`Suds-Jack` `QUEUE.md` Q-028)
- repo: toko-drop-godot
- size: L
- blocked-by: Q-002 (SEQUENCE needs the composition picker split out first)
- design: design/CAMPAIGN_LEVELS.md §1, §2
- gate: smoke checks that a level spec drives arena extents, HP, composition
  and revenge parameters without touching the scripts that consume them; one
  SEQUENCE level reproducible identically across attempts

A level is a parameter set + a spawn script + a goal, **not new code** — the
archetype is the code, the level is the data. Most levers already exist as
parameters (`half_x`/`half_z` threaded through player, enemies, bullets and
the director; `MAX_HP`; `FIRE_RATE`; the `POOL` and the caps; the `REV_*`
constants), which is what keeps this proposal small. Start with SEQUENCE and
CLOSE QUARTERS: the first is the backbone, the second is the best
value-per-line in the project because the arena is already a parameter.


### Q-023 — Per-level grading and unlocks

- status: **Dropped, 2026-08-28** — see Q-024's note
- repo: toko-drop-godot
- size: M
- blocked-by: Q-022, Q-017 (shares the S/A/B/C vocabulary)
- design: design/CAMPAIGN_LEVELS.md §3
- gate: for a SEQUENCE level, the theoretical maximum computed from the spawn
  script matches what a scripted perfect run actually scores — if those two
  disagree, the thresholds are fiction

Keeps one grading language across the whole game rather than adding stars.
**Do not reuse Rush's threshold formula**: it integrates a statistical curve
over procedurally composed waves, and a hand-authored level has no such curve.
Fixed spawn list ⇒ exact maximum ⇒ percentage thresholds; open composition ⇒
measured from a reference run and recorded as a measurement.


### Q-024 — Campaign vertical slice: six levels, one per archetype

- status: **Dropped, 2026-08-28, owner's call.** CHALLENGES was the one mode
  designed on the port side instead of proposed upstream first — exactly the
  shape `CLAUDE.md`'s "a feature is never designed twice" rule exists to
  prevent. Rather than migrate it upstream after the fact or leave it an open
  question, the owner shelved it on both sides: no build here, no build
  upstream (`Suds-Jack` `QUEUE.md` Q-028). `design/CAMPAIGN_LEVELS.md` and
  `design/RUSH_TIERS_AND_LEVELS.md` stay as a record, same shape as
  `sudsjack/`'s "SET DOWN" in the browser repo. Do not resume Q-022/023/024
  without the owner asking in their own words.
- repo: toko-drop-godot
- size: L
- blocked-by: Q-022, Q-023, Q-007 (re-scoped)
- design: design/CAMPAIGN_LEVELS.md §4
- gate: six levels playable end to end — select, grade, unlock, save — and
  looked at on a touch viewport

Deliberately a slice, not a campaign. Six levels of real play is enough to
learn whether the archetype system and the threshold method hold up; committing
to thirty up front means authoring content against a framework nothing has
graded yet. This is a third mode on a port that is at 6/40 enemies with Rush
itself unbuilt — sequence it against that honestly.

---

