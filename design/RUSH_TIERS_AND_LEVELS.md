# Rush — legs, goals, and S/A/B/C tiers

**Status:** proposal. Thresholds are `PROPOSED` and derived from a stated model
(§3) rather than picked by feel — **the model is the deliverable, not the
numbers.** First playtest replaces the numbers; it should not need to replace
the method.

Companion to [`RUSH_MODE.md`](RUSH_MODE.md). That doc gives the mode a clock and
a score; this one gives the clock **structure** and the score **meaning**.

## 1. Why a bare score needs both

Rush as designed produces one number after three minutes. That is enough to
rank a run and not enough to teach one. Two problems:

- **No mid-run feedback.** A player at 1:40 has no idea whether they are doing
  well. The score climbs monotonically, so it always looks like progress.
- **No second axis.** Score rewards exactly one behaviour — kill fast. A run
  that survived untouched and a run that was hit twice score the same if the
  kill counts match.

Legs fix the first (a checkpoint that says where you stand). Goals fix the
second (a separate axis that score cannot buy). Tiers turn the number into a
letter you can aim at.

## 2. The three legs

A 180s run splits into three 60s legs. They are **not** difficulty tiers set by
hand — they follow the virtual-wave curve `RUSH_MODE.md` §3.1 already defines
(`vw = 1 + floor(elapsed / 12)`), so each leg covers five surges and the arena
genuinely changes character across them.

| leg | window | virtual waves | standing bodies | character |
|---|---|---|---|---|
| **I — WARM** | 0:00–1:00 | 1–5 | ~1.3 → 3.6 | sparse; you go to the enemies |
| **II — PRESS** | 1:00–2:00 | 6–10 | ~4.2 → 6.4 | the arena stops being empty anywhere |
| **III — BOIL** | 2:00–3:00 | 11–16 | ~6.6 → 7.8 | past the budget knee; body/shooter caps bind |

(Standing bodies = `budget_for(vw) × RUSH_PRESSURE` ÷ average body cost 1.83,
from the species table in §3.)

Each leg ends at a **checkpoint** that stamps the tier you stood at, and those
stamps persist on the summary. A run that went S, S, B tells you exactly where
it fell apart — which a single final letter never does.

### Leg goals — the second axis

One goal per leg, each chosen to be *achievable in that leg and awkward in the
others*, so they cannot all be farmed with the same behaviour:

- **I — UNTOUCHED.** Finish leg I without taking a hit. Only realistic while
  the arena is sparse; attempting it in leg III is a different game.
- **II — UNBROKEN.** Never let heat reach 0 during leg II. Rewards chain
  continuity across the traversals that leg II's spread forces.
- **III — STILL STANDING.** Finish leg III with the clock above half. Ties the
  goal to the earned-time economy (`RUSH_MODE.md` §2): the only way to bank
  time is to keep killing while the arena is at its most dangerous.

All three completed awards a **★** beside the final grade. Deliberately **not**
a tier bump — score buys letters, goals buy the star, and keeping the two axes
separate is what stops "grind score" and "play well" collapsing into one thing.

## 3. Deriving the thresholds

The numbers come from the code, not from taste. Species values are exact
(`100 × max_hp`, `main.gd`; stats from each subclass's `setup()`):

| type | budget cost | hp | kill value | value per budget point |
|---|---|---|---|---|
| GLOBBO | 1 | 1 | 100 | 100 |
| YELA_CUBE | 1 | 2 | 200 | 200 |
| SPITTOR | 2 | 3 | 300 | 150 |
| FANNER | 2 | 3 | 300 | 150 |
| ORANGE_CUBE | 2 | 4 | 400 | 200 |
| WEEVA | 3 | 3 | 300 | 100 |

The director picks uniformly among affordable types, so for a full pool:
**average cost 1.83, average kill value 267.**

Score rate is then `kill_rate × 267 × multiplier`. Four reference players, with
the multiplier each sustains (chain continuity improves with rate):

| tier | kills/s | multiplier | pts/s |
|---|---|---|---|
| C | 0.5 | ×1.6 | 214 |
| B | 0.9 | ×2.2 | 529 |
| A | 1.4 | ×2.8 | 1047 |
| S | 2.0 | ×3.0 | 1602 |

Sanity check on S: 2.0 kills/s against average 2.67 hp is 5.3 damage/s, and the
player fires 11.1 shots/s (`FIRE_RATE 0.09`) — about 48% accuracy while moving.
Hard, not fictional. It also sits just under the supply ceiling (§5), which is
what "S" should mean.

Leg weights account for leg I being supply- and travel-limited (few bodies, a
38×22 arena to cross) and leg III being denser but far more dangerous:
**I ×0.75, II ×1.00, III ×1.15.**

### The table

Cumulative score at each checkpoint, rounded to legible numbers:

| tier | @ 1:00 | @ 2:00 | @ 3:00 |
|---|---|---|---|
| **S** | 72,000 | 168,000 | 280,000 |
| **A** | 47,000 | 110,000 | 182,000 |
| **B** | 24,000 | 55,000 | 92,000 |
| **C** | 10,000 | 22,000 | 37,000 |

Below C shows the score with **no letter** — not a D or an F. A punitive grade
on someone's first run teaches nothing they did not already know.

## 4. Grading rules

- **The live tier** is cumulative score against par linearly interpolated
  between checkpoints, so the letter moves during play. That is the mid-run
  feedback the mode currently lacks.
- **A stamp** is taken at each checkpoint and never revised.
- **The final grade** is the letter earned by final score at 3:00 — *not* an
  average of the stamps. One rule, one number, no compounding.
- **A grade requires finishing the clock.** Dying at 1:20 records the score and
  the stamps earned, but no grade: the grade means "completed a Rush", and
  prorating it would make an early death the cheapest way to a good letter.

## 5. Two things the throughput math exposed

Both are findings about `RUSH_MODE.md`, not about tiers — recorded here because
this is where they surfaced.

**Telegraphs must pipeline.** `RUSH_SPAWN_GAP` 0.35s plus a 0.45s telegraph is
a 0.8s cycle if the director waits for one body to exist before starting the
next telegraph — a hard supply ceiling of 1.25 kills/s, below even B tier, and
an arena that needs six seconds to fill from empty. The gap must govern
telegraph **starts**, with several in flight at once. Then the ceiling is
1/0.35 = 2.86 bodies/s after a 0.45s latency, and S at 2.0 sits sensibly under
it. This belongs in `Q-003`'s acceptance: *assert that overlapping telegraphs
are permitted*.

**The heat cap may not discriminate.** Heat needs only *continuity*, not rate —
one kill per 2.5s keeps the chain alive, so any competent player pins ×3 and
the multiplier stops separating A from S. Separation then comes entirely from
raw kill rate. If A and S prove indistinguishable in playtest, the lever is the
heat **window** (shorten it, so the chain demands rate), not the tier table.

## 6. Open questions

1. **Are the raw numbers unwieldy?** 280,000 for an S run is a big number next
   to Normal's scale. If it reads badly the fix is a per-mode score divisor
   applied consistently, **not** fudged tier thresholds — the thresholds are
   derived and should stay derived.
2. **Do tiers apply to Normal mode too?** The natural analogue is wave reached
   rather than time survived, which is a different table and a different doc.
   Not proposed here.
3. **Do the leg goals persist as achievements?** The save shape (`RUSH_MODE.md`
   §7) has room, but permanent achievements are a meta-progression feature and
   deserve their own decision.
4. **Should the live tier be visible, or only the stamps?** A visible live
   letter is better feedback and more pressure; some players find a letter
   sliding from A to B mid-run more discouraging than no letter at all.
5. **Is "levels" meant as legs inside one run, or a separate stage-select
   mode?** This doc assumes legs, which need no level select, no per-level
   saves and no new flow. A true stage-based mode is a larger separate design.
