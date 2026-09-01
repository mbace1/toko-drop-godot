# Rush mode — design

**Status:** the director's *structure* is implemented — `RushDirector` in
`scripts/rush_director.gd` (virtual-wave escalation §3.1, standing pressure
§3.2, gated/pipelined telegraph spawning §3.3–3.4, the pause-safe clock, the
earned-time cap, and heat/scoring §4) — with its own smoke coverage. It is
**not wired into `main.gd`**: no mode select, no HUD, no menu integration yet
(`Q-007`/`Q-008`). Numbers are a mix of `PROPOSED` (unverified against
`tuning.js` — mbace1/Suds-Jack could not be attached this session) and
`SPECIFIED` (settled directly by the project owner — the heat window and the
hit-does-not-break-the-chain rule, §4). Neither kind is a port. See
[Parity risk](#parity-risk-read-this-before-locking-any-number) before any
`PROPOSED` number is treated as final.

**Scope:** one alternative run structure — the mode itself, its scoring, its
HUD, its touch answer, its save shape, and the changes to `wave_director.gd` /
`main.gd` it forces. It does not add enemies, weapons or art; those stay on
`PORT_STATUS.md`'s ordered list.

---

## 1. The thesis

Normal mode is a **wave** game. `main.gd` starts a wave, the arena fills, you
clear it, `_on_wave_cleared()` fires and starts the next one. The gap between
"last enemy dies" and "next wave lands" is a real beat: you reposition, your
dash comes back (`DASH_CD 0.75`), your mercy i-frames expire safely, and you
read the new composition before it reaches you.

Rush mode deletes that beat. There is **no clear condition** — the arena is
held at a standing pressure by a director that refills as fast as you kill, and
the run ends on a clock or on your third hit, whichever comes first. Where
Normal asks *can you survive wave 14*, Rush asks *how much can you kill in three
minutes without ever getting a free second*.

That single change is the whole mode. Everything below follows from it, and
anything that does not follow from it does not belong in this doc.

Why it is worth building at all, before more enemy types land: the port has six
of ~40 species, and Rush is the mode that gets the most out of a *small*
roster — it re-uses every ported body at a higher rate rather than needing new
ones. It is also the cheapest way to exercise the pieces that are hardest to
feel in a wave game: the revenge volleys (corpses accumulate, so the graze game
compounds), the shooter cap (it becomes a *rate* limit, not a wave limit), and
the touch sticks under sustained load.

## 2. Run shape

Three candidates were considered; the recommendation is C.

| | shape | ends when | problem |
|---|---|---|---|
| A | **Endless pressure** — no clock, escalates forever | you die | it is Normal mode with the gaps removed; the run-length distribution is identical, so the leaderboard is the same leaderboard |
| B | **Fixed 180s time attack** | clock hits 0, or you die | clean, but a death at 0:20 costs the player nothing to retry and the mode has no comeback tension |
| C | **180s clock + earned time** ✅ | clock hits 0, or you die | needs one more rule (below), but that rule is the mode's hook |

**Recommended: C.** A base clock of `RUSH_DURATION 180.0` (PROPOSED), and every
kill adds `RUSH_TIME_PER_KILL 0.35s` (PROPOSED) back, capped at the base
duration so the bar can never grow past full. Aggression buys time; hiding in a
corner ends the run. That is the mode's whole economy in one line, and it is
readable on a bar without a tutorial.

The cap matters: without it a strong player extends indefinitely and C collapses
into A.

## 3. The director: pressure instead of waves

`WaveDirector.start_wave()` today spends a whole-wave budget in one burst, then
does nothing until the arena is empty. Rush needs the same *composition* logic
on a different *cadence*, and the composition logic is a ported table — it must
not be forked.

### 3.1 Virtual wave

Rush drives escalation from elapsed time rather than from clears:

```
virtual_wave = 1 + floor(elapsed / RUSH_WAVE_SECONDS)     # PROPOSED 12.0s
```

Everything downstream then calls the **existing** ported functions unchanged —
`budget_for(vw)`, `shooter_cap_for(vw)`, `body_cap_for(vw)`. No second tuning
table, no second curve to keep in sync with `tuning.js`. A 180s run reaches
virtual wave 16, which is past the budget knee at wave 10 and into the flat
`B_POST 0.8` ramp — the mode gets to show off the late curve inside three
minutes, which Normal takes far longer to reach.

### 3.2 Standing pressure

`budget_for()` returns a spend meant to be *cleared*; Rush holds it *standing*,
so it must be scaled down or the arena is instantly unplayable:

```
target_pressure = budget_for(virtual_wave) * RUSH_PRESSURE   # PROPOSED 0.55
live_pressure   = sum(POOL[type][1] for each living enemy)
```

Each tick, while `live_pressure < target_pressure` **and** the ported
`body_cap_for()` / `shooter_cap_for()` both allow it, spawn one affordable
type — reusing the exact affordability loop `start_wave()` already runs.

Worked example at virtual wave 5 (elapsed 60s): `budget_for(5)` ≈ 11.8, so
target ≈ 6.5 — three to six standing bodies against a body cap of 9. At virtual
wave 15 (elapsed 180s): `budget_for(15)` = 25.2 (`5 + 1.8×9`, then `+0.8×5`
past the knee), target ≈ 13.9, body cap 14.
The caps stay the real ceiling late, which is the behaviour we want: the shooter
cap is what keeps a screen readable, and it should not stop mattering just
because the mode changed.

### 3.3 Refill rate

Never refill instantly. `RUSH_SPAWN_GAP 0.35s` (PROPOSED) minimum between
spawns, so clearing four bodies with one good dash-and-sweep still *feels* like
it bought something — the arena visibly empties for about a second before it
closes again.

**The gap governs telegraph *starts*, and telegraphs may overlap.** If the
director instead waits for one body to finish spawning before beginning the
next tell, the cycle is `0.35 + 0.45 = 0.8s` — a hard supply ceiling of 1.25
bodies per second, which is below the rate an average player already kills at,
and an arena that takes six seconds to fill from empty. Several tells in flight
at once puts the ceiling at `1 / 0.35` ≈ 2.86 bodies/s after a 0.45s latency,
which is where it belongs. Worked through in
[`RUSH_TIERS_AND_LEVELS.md`](RUSH_TIERS_AND_LEVELS.md) §5.

### 3.4 Where they arrive, and the tell

`_spawn()` currently places a wave on an ellipse at `0.6 ×` the half-extents.
That is correct for a wave — it lands while you are looking at an empty arena.
It is **not** acceptable for a trickle: a body materialising at 0.6× extents
while you are mid-dash, with no wave boundary to warn you, is an unavoidable
hit, and this game's contract is that every threat telegraphs (SPITTOR's 0.45s
inflate, GLOBBO's crouch, ORANGE_CUBE's snap).

Rush spawns therefore change two things:

1. **On the edge ring** (full `half_x`/`half_z`, at the arena rail), never
   inside the play space, and never within `RUSH_SPAWN_SAFE 6.0` (PROPOSED) of
   the player.
2. **With a 0.45s floor telegraph** — a ring pulse on the grid at the spawn
   point before the body exists. 0.45s deliberately matches SPITTOR's wind-up:
   it is a tell duration the player has already been taught.

The telegraph is the one piece of new *visual* work the mode needs, and it is
small — the floor shader already pulses on a clock and can take a handful of
ping positions as uniforms.

### 3.5 What must not change

- Enemies stay driven by the explicit `update(delta)` from the director. No
  `_physics_process`, per `CLAUDE.md` — pause stays free.
- The Rush clock accumulates from that same `delta`, **never** from
  `Time.get_ticks_msec()`. The floor shader uses wall-clock deliberately (it
  pulses on the menu); a Rush clock that did the same would keep draining
  through a pause, which is a cheat and a bug.
- Corpses still finish their pop in `corpses` and still fire revenge volleys.
  Under Rush the corpse count runs much higher, so the existing
  `REV_POOL_GUARD 240` pool guard stops being a theoretical safety net and
  becomes load-bearing — verify it under sustained fire before shipping.

## 4. Scoring

Normal scores `100 × max_hp` per kill plus `50 × wave` per clear. Rush has no
clears, so the clear bonus has to be replaced by something that rewards the
behaviour the mode is about: never letting the pressure drop.

**Heat** (SPECIFIED — settled by the project owner, not derived; see below):

```
kill                → heat += 1, heat_timer = RUSH_HEAT_WINDOW (4.0s)
heat_timer expires  → heat decays to 0 over RUSH_HEAT_DECAY (1.0s)
multiplier          = 1.0 + min(heat * 0.15, 2.0)          # caps at x3.0
score per kill      = 100 * max_hp * multiplier
```

A chain of 14 kills inside the window reaches the ×3 cap. The decay ramp rather
than a hard reset matters: a player who dashes across the arena to reach the
next cluster should not be punished for the traversal, only for stalling.

**Only an idle timer breaks the chain — taking a hit never does.** Settled: the
window is 4.0s (not the original 2.5s guess), and a hit does not touch heat at
all. `RushDirector` in `scripts/rush_director.gd` has no method that reduces
heat in response to damage, so this is a structural guarantee, not a
convention — there is nothing to call. Losing an HP out of three is already the
harshest punishment the game has; stacking a score wipe on top would make the
mode punitive rather than fast.

## 5. HUD

Rush watches a different number, so the top row changes shape:

```
Normal:   HP ●●●            WAVE 7           SCORE 4200  BEST 9100
Rush:     HP ●●●     [=========-----] 1:12   SCORE 4200  x2.4
```

- The **clock replaces WAVE**, centred, with a drain bar behind it — the bar is
  how "a kill just bought you time" reads at a glance; the digits alone do not
  sell it.
- The **multiplier replaces BEST** at top-right, next to the score it is
  multiplying. Best belongs on the summary screen in this mode, not in the
  corner during a run where it competes with the live multiplier.
- A **SURGE** flash at each `RUSH_WAVE_SECONDS` boundary, on the existing
  `"wave"` audio voice. It is the only escalation signal Rush has — Normal gets
  one for free every time the arena empties and refills.

Both layouts are still one top row, so this does not resolve the open HUD
divergence recorded in `PORT_STATUS.md` (the browser build stacks WAVE + a
progress bar top-left with HP pips beneath). If that divergence is closed
later, Rush's clock takes the same slot the wave bar takes.

## 6. Touch, and mode selection

`TOKO_DROP_ROADMAP.md`'s constraint quoted in `PORT_STATUS.md` — *"Mobile touch
is first-class. Every feature ships with a touch answer"* — applies here, and
mode selection is where it bites: today **any** touch anywhere starts a run
(`main.gd::_process`, the `MENU`/`DEAD` branch), because on a phone there is no
FIRE key. Adding a second mode means the menu has to distinguish two intents
without breaking that.

Recommendation: two **mode chips** on the menu and the death screen, hit-tested
before the start-anywhere fallback, with the last-played mode persisted and
pre-selected. A tap on a chip selects *and* starts that mode; a tap anywhere
else starts the selected one. Keyboard gets `1`/`2` or left/right to move the
selection; gamepad gets d-pad left/right, with the existing A/Start to begin.

Rejected: left-half taps NORMAL, right-half taps RUSH. It reads as arbitrary,
it collides with the move/aim stick halves the player is about to use, and
there is nowhere to show which mode is which.

Under load, Rush is also the first thing in this port that will stress the
sticks (a finger that never lifts for three minutes, and an aim-stick release
that is both "dash" and "stop firing"). Budget a touch-device pass before
calling the mode done — that is a queue item, not an afterthought.

## 7. Save shape — and why it needs a migration

This is the part that will break something quietly if it is not designed first.

`save_service.gd` stores `{"hi_score": int, "runs": [...]}` — **mode-blind, and
unversioned.** If Rush writes into it, a 3-minute Rush score lands in the same
`hi_score` as the Normal best and the death screen starts comparing runs that
have nothing to do with each other. There is no version field to branch on, so
the migration has to key off the shape.

Proposed v2:

```json
{
  "v": 2,
  "modes": {
    "normal": { "hi_score": 9100, "runs": [ { "score": 9100, "wave": 14, "at": "..." } ] },
    "rush":   { "hi_score": 4200, "runs": [ { "score": 4200, "kills": 88, "heat_peak": 3.0, "at": "..." } ] }
  }
}
```

Migration rule: a parsed dictionary with **no `"v"` key** is v1 — move
`hi_score`/`runs` verbatim under `modes.normal`, stamp `"v": 2`, write once. The
existing "corrupt file starts clean rather than crashes" behaviour stays; a v1
file is not corrupt and must not be discarded.

Rush runs record `kills` and `heat_peak` instead of `wave`, because "wave" is a
virtual number in this mode and printing it on a summary would be a lie.
`recent_line()` needs a per-mode format, not one shared one.

Note the trap `save_service.gd` already documents: tests must point `path` at a
scratch file. A migration test that writes the real save is a test that eats the
player's Normal best — exactly the failure that doc comment exists to record.

## 8. Open questions

Decisions that change the work, in the order they block:

1. **Does the browser build already have a Rush/time-attack mode?** If it does,
   this document is wrong to invent numbers and should be replaced by a port of
   the source's — see below. **Blocks all tuning constants.**
2. ~~**Does taking a hit break the heat chain?**~~ **Settled: no** — see §4.
3. **180s, or shorter?** Still open. 180 is a guess at "one commute-length
   run"; 120 makes the mode a genuinely different session length from Normal;
   180 lets the virtual wave reach the post-knee curve. Kept as `RUSH_DURATION`
   in `scripts/rush_director.gd`, still `PROPOSED` — a one-constant change if
   this goes the other way.
4. **Do the modes share a leaderboard screen?** §7's shape supports either.
5. **Does Rush unlock, or is it available from the first launch?** Available
   immediately is the recommendation — a locked mode in a game with six enemy
   types is hiding content it does not have.
6. **Does Rush have to exist in `mbace1/Suds-Jack` too, not just here?**
   Directed by the project owner: yes — Rush should exist in **both** the
   browser build and this port, not merely be proposed upstream as optional.
   `QUEUE.md` `Q-010` is written to that mandate now rather than "propose or
   port, pick one". See the Parity risk section below.

## Parity risk (read this before locking any number)

`CLAUDE.md` is explicit: `mbace1/Suds-Jack` `toko-drop/` is the **source of
truth for behaviour and numbers**, and every ported constant carries a
`file:line` cross-reference. Every number in this document has **no such
reference** — the source repo could not be attached in the session that wrote
it, so nothing here was checked against `tuning.js`.

Two outcomes, and they need different work:

- **The browser build has a time-attack/rush mode.** Then this document is a
  design sketch that got there first, and the real task is a *port*: read its
  tuning table, replace §2–§4's constants with the source's, and keep only the
  Godot-specific parts (§5–§7) as this repo's own choices.
- **It does not.** Then Rush is a **deliberate divergence** — the first
  gameplay-level one in this port. Directed by the project owner: this is not
  optional. Rush is judged big and important enough that both codebases must
  end up with it, not just this one with an upstream proposal left to languish
  — the two builds drifting apart in *modes* is a much bigger split than
  drifting in materials, and it does not get treated as this repo's problem
  alone. `Q-010` in `QUEUE.md` now reads as a mandate to build it in
  `mbace1/Suds-Jack` if it is not already there, not merely to suggest it.

Resolving this is `Q-001` in [`../QUEUE.md`](../QUEUE.md) and it gates every
tuning constant behind it. It also gates the campaign
(`CAMPAIGN_LEVELS.md`) by direct instruction: hold that work until Rush has
reached parity between the two repos, so effort is not spent on the third
mode while the second is still unreconciled with its own source of truth.
