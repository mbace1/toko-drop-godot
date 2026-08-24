# Campaign levels — rule-variant challenges

**Status:** proposal. Answers `RUSH_TIERS_AND_LEVELS.md` §6 Q5, which asked
whether "levels" meant legs inside one run or a separate stage-select mode.
**It is the separate mode**, in the shape Geometry Wars uses: a list of short,
hand-authored levels, each with one rule twist and a graded score.

## 1. Why this is the cheapest content in the project

Geometry Wars gets enormous variety out of a *small, fixed* enemy roster by
changing the **rules** rather than the content. Pacifism takes your gun away.
King restricts where you may fire. Sequence hand-authors a fixed run of setups.
Same arena, same handful of enemy behaviours, and each variant plays like a
different game.

That structure is unusually well suited to this port's actual situation. It has
**six of roughly forty species**, and `HAZARDS.md` argues at length that
inventing new ones is the wrong move while 34 already-designed species sit
unported. Rule-variant levels are the way out of that bind: they multiply what
the existing six can do, without inventing content *or* waiting on ports.

The design principle that keeps it cheap:

> **A level is a parameter set + a spawn script + a goal — not new code.**

Most of the parameters are already threaded through this codebase as arguments
rather than baked in, which is what makes this proposal small:

| lever | where it already lives | effect |
|---|---|---|
| arena size | `half_x` / `half_z`, passed to player, enemies, bullets, director | the biggest change available for the least code |
| HP | `Player.MAX_HP` | one-hit levels |
| fire rate / dash | `FIRE_RATE`, `DASH_CD`, `DASH_DUR` in `player.gd` | weapon and mobility twists |
| composition | `WaveDirector` budget, `POOL`, shooter/body caps | melee-only, shooter-only, fixed lists |
| revenge | `REV_*` constants in `wave_director.gd` | corpse-density levels |
| hazards | once `Q-019`–`Q-021` land | surge-timing levels |

## 2. Level archetypes

Seven, each twisting one system the game already has. A campaign reuses these
with different spawn scripts and parameters — the archetype is the *code*, the
level is the *data*.

**SEQUENCE** — a hand-authored fixed spawn list; the budget director is off
entirely. The same setup every attempt, so the level can be *learned*. This is
the backbone archetype and the one that most needs the director refactor
(`Q-002`) to already be done.

**CLOSE QUARTERS** — the arena clamped to a fraction of 38 × 22. Nearly free,
because `half_x`/`half_z` are already parameters everywhere, and it transforms
play completely: the dash stops being an escape and becomes a commitment.
Best value-per-line in the whole document.

**DASH ONLY** — the gun is disabled; contact during a dash kills. Toko Drop's
answer to Pacifism, and it makes the 0.18s dash window the entire game. The one
archetype needing a genuinely new rule (dash contact kills), and still small.

**GRAVEYARD** — revenge volleys amplified: every corpse blooms, at raised
counts. This one is **ours, not borrowed** — revenge volleys are Toko Drop's
signature mechanic, and a level built around them makes *kill order and
spacing* the puzzle rather than aim. Nothing in the games this borrows its
structure from has an equivalent.

**ARTILLERY** — shooters only, shooter cap lifted. Pure bullet-reading, and it
finally puts SPITTOR/FANNER/WEEVA/ORANGE_CUBE under a spotlight instead of
mixed three-deep into a swarm.

**SWARM** — melee only, body cap raised. Pure crowd control and space
management; the exact complement of ARTILLERY.

**ONE HP** — `MAX_HP` 1. Trivial to implement, brutal to play, and a natural
late-campaign gate.

An eighth, **MINEFIELD** (built around GRID SURGE timing), unlocks once the
hazard items land.

## 3. Grading and progression

**Keep S/A/B/C.** Not stars. Rush already established that vocabulary
(`RUSH_TIERS_AND_LEVELS.md`), and one grading language across the whole game is
worth more than matching another game's icon. Below C shows the score with no
letter, same rule as Rush.

**Unlock currency = levels cleared at A or better.** Clearing a level opens the
next; a *count* of A-grades opens each new archetype block. That way a player
who is merely finishing levels keeps moving, while the gates ahead reward
playing them well — and it needs no second currency.

### Authoring thresholds: measure, don't reuse the formula

The Rush par table was **derived** by integrating a statistical model over 180s
of procedurally composed waves. That method does not transfer, and someone will
try to reuse it — so, explicitly:

- **SEQUENCE-type levels have an exactly knowable maximum.** The spawn script
  is fixed, so the total available score is the sum of its kill values, times
  the best achievable multiplier. Thresholds should be a **percentage of that
  maximum** (with a time component), which is computable and stays correct when
  the script changes.
- **Open-composition levels** (CLOSE QUARTERS, SWARM at a budget) have no fixed
  maximum, so thresholds are **measured from a reference run** and recorded as
  measurements, not presented as derived numbers.

Mixing the two silently is how a campaign ends up with some levels where A is
routine and others where it is impossible.

## 4. What this costs — read before committing

This is a **third mode**, a **level-select screen**, N hand-authored levels, and
a **new save shape**, proposed for a port that is at 6/40 enemies with Rush
itself not yet built. That is a real prioritisation question, not a formality.

**Recommendation: vertical slice first.** Six levels, one per archetype, shipped
end to end — select screen, grading, unlocks, saves. That proves the archetype
system and the threshold method against real play, and six levels of data is
enough to know whether a thirty-level campaign is worth authoring. Committing to
thirty up front means authoring content against an ungraded, unvalidated
framework.

### Two items this changes, both still unlanded — act now, not later

**`Q-006` (save v2) should reserve the shape now.** Its `modes` map extends to a
third key cleanly, but per-level records are a *different shape* — a map of
level id → best score, best grade, goals met — not the `{score, wave}` run list
the other modes use. `Q-006` has not landed yet, so this costs nothing today
and costs a v3 migration later. Design it in now even if the campaign is never
built.

**`Q-007` (mode select) is bigger than it was scoped.** It was designed as two
chips on the menu. Three modes plus a level grid with per-level grades is a
different screen, with a touch answer of its own. Re-scope it before it is
built, or it will be built twice.

## 5. Open questions

1. **How many levels?** §4 recommends six as a slice. A full campaign in the
   thirty range is a content-authoring project measured in weeks, not an
   engineering one.
2. **Do levels use the daily seed?** SEQUENCE levels are hand-authored and so
   are deterministic already; open-composition ones would need `Q-012`'s
   gameplay RNG to be repeatable across attempts — and a level you cannot
   re-attempt identically is a level you cannot fairly grade.
3. **Do campaign levels feed the same leaderboard?** Recommendation: no. A
   per-level best is its own record, and mixing it with Rush and Normal scores
   repeats exactly the mode-blindness `Q-006` exists to fix.
4. **Does clearing levels unlock anything outside the campaign?** Weapon modes
   (`PORT_STATUS.md` item 3) are the obvious candidate, and equally the obvious
   way to make the other two modes feel gated behind homework. Recommend
   keeping campaign rewards inside the campaign.
5. **Is DASH ONLY's contact-kill rule campaign-only, or a global mechanic?**
   Campaign-only is cheaper and safer; global would change every mode's combat
   math.
