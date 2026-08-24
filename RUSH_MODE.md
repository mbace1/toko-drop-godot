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

## 2b. What the patch notes settled

The store page and achievements gave the vocabulary; the **Steam patch notes**
gave the design intent, and they changed the plan. Two developer sentences
decide everything:

> *"Improved overall text to help clarify the intended playstyle of
> **prioritising boosting over shooting**."* — Tutorial Overhaul

> *"the sound effect that plays when your **boost invulnerability ends (either
> naturally or from disabling it by shooting)**"* — v1.6

So **boost grants invulnerability, and pulling the trigger cancels it.** Boost
is the good option; the gun is the fallback you take when you cannot afford to
boost. That is the "weapon synergy" in one rule, and it is far better than the
heat-only loop first proposed.

Three more things the notes revealed:

- The game shipped as **Switchblade** before it was Blade Rush.
- **Level is a DYNAMIC difficulty that moves both ways** — the UI has
  *"level up / level down text"*. It is not a one-way climb.
- The **multiplier runs on a timer**, and bonuses reset that timer
  (*"a bonus resetting the timer, then the timer running out"*).
- There are **mutators**, a **campaign** separate from gamemodes, **Boss Rush**
  and **Onslaught** modes, and abilities that **recharge**.

## 3. Decisions (owner, 2026-08-24)

| # | question | decision |
|---|---|---|
| 1 | dash | longer, **damages**, builds the multiplier; weapon is a **shotgun** |
| 2 | overheat | as Blade Rush — punitive lockout |
| 3 | touch boost | **build both schemes**, toggle in a corner |
| 4 | boost vs dash | boost replaces it: a longer dash you can **hold** |
| 5 | levels | **60s, 90s, then longer** |
| 6 | lives | as Blade Rush, and **you can gain more** |
| 7 | chain breaks | **both** — the timer lapsing *and* taking a hit |
| 8 | first ability | **Heat Exchange** |
| 9 | placement | RUSH under ROGUELIKE — done |

## 4. What shipped

`scripts/rush_rules.gd` owns the whole ruleset; `main.gd` branches into it.

- **Boost** — held, 17 u/s (walking is 6). Grants invulnerability, **kills on
  contact**, and each contact kill raises the chain. Heats you at 0.55/s, so
  roughly 1.8 seconds of continuous boost from cold.
- **Shooting drops the shield.** `invulnerable()` is `boosting and not firing`.
- **Heat** — the gun adds a little (0.02/shot), boost adds a lot. At 1.0 you
  **overheat**: boost locks out until you cool to 0.35. The hysteresis stops
  you fluttering on the edge of the meter.
- **Shotgun** — 5 pellets across 0.5 rad, firing 3.4x slower than the classic
  gun. Deliberately a close-range answer, so boosting stays better at range.
- **Multiplier** — +1 per boost kill, cap 100, 2.5s window. Breaks on the
  timer lapsing **and** on taking a hit.
- **Lives** — 3, +1 every 25,000 points. A hit costs a life and takes the
  mercy window, so one frame can never cost two.
- **Levels** — 60s, 90s, then +30s each. Losing a life **levels you down**,
  per the researched up/down behaviour.
- **Four abilities**, one chosen before the run (left/right on the RUSH row).
  Each bends the boost/shoot/heat triangle a different way, which is the whole
  point — picking one should change how you play, not just what you press:

  | ability | charge | what it does |
  |---|---|---|
  | **HEAT EXCHANGE** | 12s + heat | dumps stored heat as a burn scaled by it, and clears the overheat lock. Rewards running hot. |
  | **HYPER BOMB** | 18s | a wide clear (8.5u) that costs no heat at all. The panic button. |
  | **OVERCHARGE** | 20s | 6s where boosting and firing are FREE (no heat) and the chain climbs **double**. Rewards already being safe. |
  | **QUANTUM SHIELD** | 16s | 5s where enemy fire is **reflected back as yours**. The only one that pays you for standing and shooting. |

- **Levels drive composition, not just a clock.** `WaveDirector.level_override`
  makes the Rush level the number the budget, shooter cap and eligible-type
  tables are read from — so levelling *down* after losing a life genuinely
  makes the next wave easier, which is what makes a two-way difficulty mean
  anything.
- **Touch** — both schemes, live-switchable from a corner target:
  **RIM** (push the move stick past 86% of its travel) and **ZONE** (a pad in
  the left margin). Ability pad on the right, mirroring it.
- **The look does not move.** No new materials. Rush state rides on the gel
  shader's existing per-instance `rim_color`: cyan while shielded, orange
  while hot.

## 5. Still open

1. **Does the RIM scheme survive contact with a thumb?** It costs you the
   ability to walk at full speed without boosting; ZONE costs screen space.
   The toggle exists so this can be answered by playing, not by arguing.
2. **Heat balance is a first guess.** 1.8s of boost from cold, 2.4s to cool
   fully. Wants a play session, then tuning.
3. **Levels currently only change the wave director's clock**, not its
   composition. Should a Rush level also widen the spawn pool faster than
   classic does?
4. **Boost has no cost besides heat.** Blade Rush's boost may also be limited
   by a separate meter — the achievements do not say.
5. **Abilities are unlocked in Blade Rush**, not available from the start.
   Everything here is unlocked from the first run.
6. **Mutators, Boss Rush, Onslaught, events, ranks** — all seen in the
   research, none in scope yet.
7. **Name** — still "Rush Mode", which is Blade Rush's own mode name.

## 6. Sources

- Steam store page + API, appid 3238790 (description, tags, release).
- Steam achievement list for 3238790 (40 entries) — the mechanical vocabulary.
- **Steam news/patch-notes API for 3238790 (20 posts)** — the design intent,
  the boost/shoot rule, level up-and-down, the multiplier timer, and the
  game's former name (Switchblade).
- Steam appreviews API for 3238790 (the "asteroids type" note).

Retrieved 2026-08-24. No Blade Rush code, art or text is used in this port;
this is a design reference only, in the same spirit as the repo's other
tributes (`hyperdagger/` to Devil Daggers, `dropcabal/` to Cabal).
