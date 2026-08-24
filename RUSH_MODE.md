# Rush Mode — design request

**Status: PROPOSAL. Nothing here is canon yet.** This document exists to be
argued with; the numbered questions in §5 are the parts I could not decide on
my own. Owner direction (2026-08-24): a new front-page mode sitting directly
under the ROGUELIKE MODE button, built to test ideas from **Blade Rush**.

Canon that already binds this work, and is not up for negotiation here:

- **`TOKO_DROP_ROADMAP.md` §Guiding constraints — "No Geometry Wars aesthetic
  drift."** Confirmed by the owner as still holding: Rush Mode borrows
  *structure*, never the look. Gel bodies, the neon grid arena and the satin
  material stay exactly as they are.
- **"Mobile touch is first-class. Every feature ships with a touch answer."**
  Every mechanic proposed below has to work under two thumbs.
- Rush Mode is **its own ruleset** (owner direction), not a toggle stacking on
  classic. ROGUELIKE and DAILY do not apply inside it.

---

## 1. What Blade Rush actually is

Researched 2026-08-24, since the design is meant to test *its* ideas rather
than my guesses about them.

- **Blade Rush**, by **Noba** (solo dev, [@novalocarus](https://twitter.com/novalocarus/)).
  Steam appid **3238790**, released **8 May 2025**. There is a free demo
  (appid 3297930).
- Store copy: *"a frantic top-down shooter where you pilot your Blade,
  shooting and boosting through waves of alien creatures. Pave your way
  through the endless swarm, and be careful not to overheat!"*
- Steam user tags: Shoot 'Em Up · Top-Down Shooter · Arcade · **Score Attack**
  · Psychedelic · Controller. Gamepad recommended, Steam leaderboards.
- Advertised content: **6 game modes**, **30 levels**, **3 boss battles**,
  ranks, and unlockable palettes/backgrounds/maps/modes.

**Where the mechanical detail below comes from:** the store page is thin, and
the game has one public review. The full achievement list (40 entries) is not
thin at all — achievements name mechanics precisely, because they have to be
checkable. Everything in §2 is quoted or directly inferred from it.

## 2. Its mechanical vocabulary

### Heat — the core tension
> *"Playing it Cool — Complete a round of any timed gamemode remaining below
> **66% heat**."*

Heat is a metered resource with a percentage, and staying low is hard enough
to be an achievement. The store line "be careful not to overheat" makes the
ceiling a fail state. **This is the single most interesting thing to steal:**
Toko Drop currently fires forever at a flat 0.09s cadence, so its gun has no
economy at all.

### Boost — the movement
> *"Threading the needle — Defeat **20 enemies in a single boost**."*
> *"Unrelenting — In Blaze, **boost for 15 seconds without stopping**."*
> *"Tower Defence — Defeat 30 enemies **without boosting** and without abilities."*

So boost is a **held, sustained state**, it **kills on contact**, and playing
without it is a deliberate handicap. That is a very different verb from Toko
Drop's dash (0.18s, 26 u/s, i-frames, 0.75s cooldown) — that is a dodge, this
is a way of attacking and travelling.

One review calls it *"an asteroids type game… snappy and kinetic"*, which
suggests momentum/inertia rather than Toko Drop's direct velocity control.

### Abilities — the synergy layer
Four are named, one achievement each:

| ability | what the achievement says it does |
|---|---|
| **Hyper Bomb** | defeat enemies with it — a screen-clear |
| **Overcharge** | score *"while under the effects of"* — a timed buff |
| **Heat Exchange** | *"**burn** 100 enemies"* — spends heat as a weapon |
| **Quantum Shielding** | *"**reflect** damage to 50 enemies"* |

**Heat Exchange is the synergy.** If heat is both your cost *and* your ammo,
every other decision routes through one meter: shoot more → hotter → closer to
overheat, but also more to spend. That is a real loop, and it is the thing
worth prototyping first.

### Levels — the structure
> *"Rush! — In Rush, **reach level 10 within 1:30**."*
> *"Endurance — In Crucible, reach level 10."* · *"Invincible — reach level 3
> without losing a life."*

"Levels" are **escalation tiers inside a run**, not a level select — you reach
them, you do not choose them. This is the Geometry Wars structure the owner
meant. Rush's own achievement implies roughly **9 seconds per level**, which
is very fast; Crucible reaches 10 with no time bound at all.

### The rest
- **Combo multiplier** up to **100x**.
- **Lives**, not a health bar (*"without losing a life"*).
- **Ranks** (S rank on bosses and challenges).
- **Freeplay** vs. challenge structure — most achievements say *"Freeplay
  only"*, so there are two shells around the same modes.
- **In-arena events**, completed *"perfectly"*: **Boost Pad**, **Boost Path**,
  **Bullet Vault**. These look like timed skill beats that interrupt the swarm.
- Enemies named: **Coolers** (heat-related?), **Snakes**, **Chompers**,
  **asteroids**. Bosses: **The Warden**, **The Scourge**, **The Leviathan**.
- Its six modes appear to be **Rush · Fury · Surge · Blaze · Blast ·
  Crucible**, each bending one variable (Blaze = boost, Blast = chain
  explosions, Surge = brutal, Crucible = endurance).

## 3. What Rush Mode should take

Ordered by how much each teaches us, and how cheap it is against what the port
already has:

1. **Heat.** Firing raises heat, heat falls when you stop. At 100% the gun
   locks until it cools. Turns Toko Drop's free gun into a managed one.
2. **Boost as a held state that kills.** Replaces the dash inside Rush Mode.
   Sustained, directional, damages on contact, and it is what heat is *for* if
   we route boost through the same meter.
3. **Level tiers on a fast clock.** Reuse the existing budget-based wave
   director but re-skin waves as levels with an aggressive cadence (~10s),
   plus a visible tier readout.
4. **Combo multiplier**, decaying — the port has no chain reward at all.
5. **One ability to prove the synergy: Heat Exchange.** Spend accumulated heat
   to burn everything near you. It makes running hot a *choice* instead of
   only a risk.

Deliberately **out** of a first pass: bosses, ranks, the challenge/Freeplay
split, arena events, unlocks, leaderboards.

## 4. How it fits this port

- **Own ruleset**, per owner direction. A `RushRules` object holds heat, boost,
  combo and tier; `main.gd` branches to it instead of the classic loop.
- **The look does not move.** Same gel shader, same grid, same bodies. Heat is
  HUD plus a rim-colour shift on the player (`gel.gdshader` already takes a
  per-instance `rim_color`, so heat can drive it for free).
- **Touch answer, day one.** Heat needs no new input (it is a consequence of
  firing). Boost is the one risk: the current touch dash fires on *release* of
  the aim stick, which cannot express a *held* boost — see question 3.
- **Enemy roster**: the port has 6 of ~40 types. Rush Mode should run on what
  exists rather than blocking on the roster.

## 5. Open questions

1. **Heat source** — does firing alone generate heat, or does boosting heat
   you too? (Boost-heats is what makes the two verbs fight each other.)
2. **Overheat consequence** — gun locked until fully cool (Blade Rush's
   "careful not to overheat" reads punitive), or a softer penalty like a
   fire-rate collapse?
3. **Boost on touch** — the dash currently fires on *release* of the aim
   stick, which cannot express a held boost. Options: a third touch zone, a
   double-tap-and-hold on the move stick, or boost = move stick pushed to the
   rim. Which?
4. **Boost vs. dash** — does boost fully replace the dash in Rush Mode
   (i-frames gone, contact damage instead), or do both exist?
5. **Level cadence** — Blade Rush's Rush implies ~9s per level. Do we match
   that, or tie a level to a cleared wave as the port does now?
6. **Lives or HP** — Blade Rush counts lives; the port has 3 HP with 1.2s
   mercy. Switch, or keep HP?
7. **Combo rules** — what breaks the chain? Time only, taking a hit, or both?
8. **Which ability first** — I propose Heat Exchange because it closes the
   loop with heat. Prefer Hyper Bomb (simpler, more legible) instead?
9. **Roguelike button** — the Godot port has no title-screen mode buttons at
   all yet; the browser build does. Should I build the front-page selector
   with a ROGUELIKE entry stubbed out, or Rush Mode only for now?
10. **Name** — "Rush Mode" is Blade Rush's own mode name. Keep it, or give it
    a Toko Drop name so the tribute is not literal?

## 6. Sources

- Steam store page + API, appid 3238790 (description, tags, release).
- Steam achievement list for 3238790 (40 entries) — the mechanical detail.
- Steam appreviews API for 3238790 (the "asteroids type" note).

Retrieved 2026-08-24. No Blade Rush code, art or text is used in this port;
this is a design reference only, in the same spirit as the repo's other
tributes (`hyperdagger/` to Devil Daggers, `dropcabal/` to Cabal).
