# Hazards — and where new enemies should come from

**Status:** proposal. Hazards are a genuine net-new system; the enemy half of
this document is mostly an argument for *not* inventing enemies yet.

## 1. Enemies: there are 34 already designed and waiting

`PORT_STATUS.md` records six of roughly forty species ported, and `tuning.js`
in the source repo **names all forty** with their `minWave` and budget cost.
`PARITY_RECON.md` Q5 exists to copy that table across.

So before any new species is invented, the honest accounting is:

- **34 enemies already exist**, already designed, already balanced against this
  exact wave director and budget curve, and already carrying the numbers this
  port is required to cross-reference.
- Inventing a new one means designing it, tuning it from nothing, and recording
  it as a divergence — while 34 sit unported.

`CLAUDE.md` is unambiguous that the browser build is the source of truth for
behaviour and numbers. An invented enemy is not a port, and it makes the two
builds diverge in *content*, which is a much larger split than the material and
HUD divergences already recorded.

**Recommendation: port before inventing.** The roster table (`PARITY_RECON.md`
Q5) turns "more enemy types" from an open-ended backlog line into a countable,
orderable set of tasks — and it is the single highest value-per-minute item
currently queued. If, after that table exists, a specific *role* is missing
from the roster, inventing one to fill it is a defensible decision made with
the full picture. Right now it would be a decision made with 6/40 of it.

This is not "no new enemies ever". It is "the cheapest 34 enemies in this
project are the ones already written down".

## 2. Hazards: a real gap

The arena is an empty box. A 38 × 22 plane, four emissive rails on the clamp
line, and nothing else — no cover, no geometry, no environmental threat of any
kind. Every threat in the game is a body or a bullet.

That is a genuine gap and worth filling on its own merits, independent of what
any other game does. It also has a specific payoff here: hazards are the only
thing that can make *arena position* matter. Today every square of the floor is
identical, so movement is purely about distance from bodies and bullets.

### What can be taken from elsewhere, honestly

Nothing specific, and that is fine. Game *mechanics* — area denial, timed
geysers, electrified boundaries — are common genre vocabulary, not anybody's
property, and this document uses them as such. What will not happen is lifting
a named commercial game's specific content, art or stat tables into this repo,
which would be both a legal question and a porting-discipline violation (there
would be no `file:line` to cross-reference).

Blade Rush specifically could not be verified: the Steam page and the
developer's site are both blocked by this environment's egress proxy, and two
searches returned contradictory descriptions — one describing a top-down
shooter with an overheat mechanic and floating platforms, the other saying that
is **Switchblade**, a different game by the same developer, and that Blade Rush
is a minimalist stealth-platformer. Designing against an unverified description
would produce exactly the silent drift this project's porting rules exist to
prevent.

## 3. What the codebase will and will not accept

Constraints, before any hazard is designed:

1. **Explicit `update(delta)`, never `_process`.** Same rule as `Enemy`
   (`CLAUDE.md`): `main.gd` pauses by not calling update, so a hazard on
   Godot's automatic callbacks keeps running while paused.
2. **Collision must fit the existing loop.** `main.gd` does flat circle-vs-
   circle distance checks in the XZ plane. A hazard that needs a physics body
   or a polygon test is a much bigger change than it looks.
3. **It must telegraph.** SPITTOR inflates for 0.45s, GLOBBO crouches,
   ORANGE_CUBE snaps to a compass direction. A hazard that damages without a
   tell breaks the contract every other threat in the game keeps.
4. **It must not hold up a wave clear.** `wave_cleared` fires when `enemies` is
   empty; hazards must live outside that list entirely.
5. **It must survive touch.** A hazard demanding precise positioning is a
   hazard that is unfair on a thumb stick.
6. **It must not shrink the arena.** The single biggest structural fix in this
   port was discovering the arena should be 38 × 22 rather than 18 × 18 —
   "a wide room you cross". Hazards that eat floor space undo that.

### The one that looks cheap and is not

**Static blockers — pillars, walls, cover.** Every enemy in this port steers
directly at the player: `_hold_at_range()` moves along the radial, chasers move
along the vector to the target, `_clamp_to_arena()` is the only obstacle logic
that exists. Introduce a pillar and every one of them walks into it forever.
Blockers mean pathfinding, or steering avoidance, retrofitted across six
species and every future one.

They also break bullets (line-of-sight tests in a loop that currently does
none) and spawning (`RUSH_SPAWN_SAFE` would need to test geometry too).

**Recommend against blockers in the first pass** — not because they are a bad
idea, but because they are a movement-system project wearing a level-design
costume, and they should be costed as one.

## 4. Proposed: area-denial hazards on the floor

Hazards that occupy floor without blocking it. They cost no pathing, they fit
the circle test exactly, they telegraph naturally by glowing, and — crucially —
**the floor is already a shader-driven neon grid that pulses on its own clock**,
so they are close to free visually.

Three, in the order they should be built:

### 4a. SLUDGE — a lingering pool that slows

A circular patch that slows the player while they stand in it. No damage: it
converts a positional mistake into *danger from something else*, which is more
interesting than chip damage and much fairer on touch.

Build this one first because **it is already required**. `PORT_STATUS.md`'s
next-up list names SLUDGE_CUBE as "slow MASS + poison trail" — that trail *is*
an area-denial hazard, so the hazard system is a prerequisite for a queued
enemy rather than a detour around it. Building it standalone first, then
hooking SLUDGE_CUBE's trail into it, gets one system serving two features.

### 4b. GRID SURGE — the floor fires along its own lines

A row or column of the existing floor grid lights, holds for a telegraph beat,
then discharges — damaging anything standing on that line.

This is the one that best fits what the game already is. The floor shader draws
the grid and pulses it; a surge is a brighter pulse travelling one line, which
the shader can take as a uniform. It telegraphs by construction (the line lights
before it fires), it reads at arena scale, it demands *movement* rather than
precision — you step off a line, and the lines are already drawn on the floor
in front of you — and it costs no new geometry at all.

It also creates the thing the empty arena lacks: a reason for one part of the
floor to be worse than another, changing every second.

### 4c. LIVE RAIL — the boundary bites

The four arena rails electrify on a cycle, damaging anything touching the clamp
line.

This one exists for a specific reason rather than for variety: **both modes
currently reward hugging the edge**. Bodies clamp to the same boundary the
player does, corners restrict the arc you can be attacked from, and Rush's
standing pressure makes a corner even more attractive. A periodically live rail
is a targeted answer to corner-camping, and it re-uses the emissive rail
material that is already there.

Sequence it last: it changes movement habits across the whole game, so it wants
the other two shipped and understood first.

## 5. Where hazards meet Rush

- **Spawn safety.** `RUSH_SPAWN_SAFE` keeps bodies from materialising on the
  player; it must also keep them from materialising *inside a live hazard*, or
  the mode kills its own spawns and the pressure accounting drifts.
- **Are enemies affected?** Recommendation: **no, in the first pass.** Hazards
  that damage enemies turn into a farming strategy — herd the swarm into the
  grid surge — which is a genuinely good mechanic and a much larger design
  (it interacts with heat, with revenge volleys, and with the pressure loop).
  Ship hazards as a player-side constraint first, then decide deliberately.
- **Rush leg III.** `RUSH_TIERS_AND_LEVELS.md` gives leg III the "arena stops
  being safe anywhere" character. Hazard density scaling with the virtual wave
  is the cheapest way to deliver that, and it is one number.

## 6. Explicitly considered and not recommended

**An overheat / vent system on the player's gun.** Common in the genre, and it
would add a real decision to a weapon that currently fires forever at
`FIRE_RATE 0.09`. Two reasons not to, for now:

1. It changes the **core loop**, which is ported. `player.js` has no heat, so
   this is a divergence at the most load-bearing point in the game — the thing
   the player does every single frame.
2. **The name is taken.** Rush already calls its score chain "heat"
   (`RUSH_TIERS_AND_LEVELS.md`). Two unrelated heat meters on one HUD is a
   readability problem before it is a design problem.

If it is wanted anyway, it needs its own document and a different name.

## 7. Open questions

1. **Does the browser build have hazards at all?** If it does, these should be
   ports rather than inventions — fold into `PARITY_RECON.md` as a sixth
   question, since the trip is already being made.
2. **Damage or denial?** §4a argues slow-not-damage for SLUDGE; GRID SURGE and
   LIVE RAIL are proposed as damage. A game where hazards never damage is
   gentler and arguably reads better with 3 HP.
3. **Do hazards persist across waves, or reset?** Persisting makes the arena
   accumulate character over a run; resetting keeps each wave readable.
4. **Density scaling** — by wave, by mode, or fixed? §5 suggests by virtual
   wave in Rush; Normal has no equivalent clock.
