# Campaign levels — rule-variant challenges

**Status:** proposal, **on hold.** Directed by the project owner: Rush is
large enough that it needs to exist correctly in both `mbace1/Suds-Jack` and
this port before campaign work starts — do not spend effort on a third mode
while the second is still unreconciled with its own source of truth. Nothing
in this document is queued to build until that parity is confirmed (`Q-001`
resolved, and `Q-010`'s cross-repo Rush work landed). It stays written now so
the design is ready the moment that gate opens, and so `Q-006`'s save shape
and `Q-007`'s mode-select scope already account for it (§4).

Answers `RUSH_TIERS_AND_LEVELS.md` §6 Q5, which asked whether "levels" meant
legs inside one run or a separate stage-select mode. **It is the separate
mode**, in the shape Geometry Wars uses: a list of short, hand-authored
levels, each with one rule twist and a graded score.

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

## 2. Level anatomy — every level is bespoke, not a template with parameters

Directed by the project owner: *"every level is different with a designed
challenge and an allocated time with goals."* That is a real pivot from an
earlier draft of this document, worth stating precisely — a campaign level is
**not** "pick an archetype, fill in its parameters." Each level is its own
hand-designed encounter:

> **name + a bespoke spawn script + its own time allocation + its own goals.**

That is the same anatomy Rush's legs already use (`RUSH_TIERS_AND_LEVELS.md`
§2 — a window, a tier stamped at the end of it, a goal that is achievable in
that window and awkward elsewhere), generalised from three uniform 60s legs
inside one run to N individually authored levels, each free to set its own
length and its own challenge rather than sharing a template.

**What stays reusable is the vocabulary of *twists*, not the levels
themselves.** The seven systems below are the modifiers a level's bespoke
script can draw on — a designer composing a level reaches for these the way a
level designer reaches for a tileset, not the way this document's earlier
draft used them (as a template instantiated with different numbers):

| twist | what it changes | where it already lives |
|---|---|---|
| arena size | `half_x` / `half_z`, already threaded through player, enemies, bullets, director | the biggest change for the least code |
| HP | `Player.MAX_HP` | a one-hit level |
| fire rate / dash | `FIRE_RATE`, `DASH_CD`, `DASH_DUR` in `player.gd` | weapon and mobility levels |
| composition | `WaveDirector` budget, `POOL`, shooter/body caps | melee-only, shooter-only, or a hand-fixed list |
| revenge | `REV_*` constants in `wave_director.gd` | corpse-density levels |
| dash-contact-kill | a genuinely new rule, not an existing parameter | Toko Drop's answer to a Pacifism-style level |
| hazards | once `Q-019`–`Q-021` land | timing-based levels |

A level's bespoke spawn script is authored the way `SEQUENCE` was described in
an earlier draft — fixed, learnable, no budget director running — which is now
the *default* shape for every level, not one option among several. That
default is also what makes grading tractable (§3): a fixed script has an
exactly knowable maximum. A level's designer can still choose to run the
budget director as *its* particular challenge (an "endless composition"
level), but that is now a deliberate, called-out exception per level, not a
generic archetype other levels share by default.

One twist is called out on its own merits, not just as a lever: **revenge
volleys amplified — every corpse blooms, at raised counts.** This is **ours,
not borrowed** — revenge volleys are Toko Drop's signature mechanic, and a
level built around them makes *kill order and spacing* the puzzle rather than
aim. Nothing in the games this document's structure borrows from has an
equivalent, and at least one level in any slice should be built around it.

## 3. Grading and progression

**Keep S/A/B/C.** Not stars. Rush already established that vocabulary
(`RUSH_TIERS_AND_LEVELS.md`), and one grading language across the whole game is
worth more than matching another game's icon. Below C shows the score with no
letter, same rule as Rush.

**Unlock currency = levels cleared at A or better.** Clearing a level opens the
next; a *count* of A-grades opens each new block of levels. That way a player
who is merely finishing levels keeps moving, while the gates ahead reward
playing them well — and it needs no second currency.

### Authoring thresholds: every level computes its own, from its own script

The Rush par table was **derived** by integrating a statistical model over 180s
of procedurally composed waves. That method does not transfer, and with every
campaign level now bespoke (§2) it does not need to — the situation is simpler
than the earlier draft's split:

- **Every level has an exactly knowable maximum**, because every level's spawn
  script is fixed by design. The total available score is the sum of its kill
  values, times the best achievable multiplier, over its own allocated time.
  Thresholds are a **percentage of that maximum**, computable per level and
  automatically correct when that level's script changes.
- **The rare level that deliberately runs open composition** as its challenge
  (§2's called-out exception) has no fixed maximum, so *that* level's
  thresholds are **measured from a reference run** and recorded as a
  measurement, not presented as a derived number.

Mixing the two silently — grading a bespoke level as if it were open, or vice
versa — is how a campaign ends up with some levels where A is routine and
others where it is impossible. With bespoke-by-default, this is now the
exception path rather than half the campaign.

## 4. What this costs — read before committing

This is a **third mode**, a **level-select screen**, N hand-authored levels, and
a **new save shape** — for a port at 6/40 enemies where Rush is now held on
cross-repo parity (Status, top). That is a real prioritisation question, not a
formality, and the hold above already answers *when*; this section is about
scope once that gate opens.

**Recommendation: vertical slice first.** Six levels, one per twist from §2's
table, shipped end to end — select screen, grading, unlocks, saves. That
proves the per-level threshold method against real play (§3), and six levels
of authored content is enough to know whether a thirty-level campaign is worth
the authoring time. Committing to thirty up front means authoring content
against a framework nothing has graded yet.

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
