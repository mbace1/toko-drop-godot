# Parity recon — one trip into the source repo

**Status:** an executable checklist, not a design. It exists so `Q-001` stops
being "someone should go look" and becomes a task with a defined output.

`CLAUDE.md` makes `mbace1/Suds-Jack` `toko-drop/` the source of truth for
behaviour and numbers, and every ported constant in this repo carries a
`file:line` cross-reference. Several queued items are blocked on facts that
only live over there. **Answer them in one trip** — the cost of the trip is
mostly getting the repo attached and paging in the tuning tables, and that cost
is the same whether you resolve one question or six.

## Getting in

The repo could not be attached in the session that wrote the Rush design, which
is the entire reason this file exists. Read access is enough — nothing here
writes to the source repo (that is `Q-010`, and it is a separate decision).

```
add_repo(owner="mbace1", repo="Suds-Jack", access="read")   # then clone as instructed
```

The interesting tree is `toko-drop/`: `js/tuning.js`, `js/main.js`,
`js/enemy.js`, `js/player.js`, plus the two canon docs `TOKO_DROP_ROADMAP.md`
and `TOKO_DROP_PORT_BRIEF.md`.

## Q1 — Does a Rush / time-attack mode already exist? (blocks Q-001)

The one that gates every tuning constant in `RUSH_MODE.md`.

Search for the mode by its many possible names, then by its *mechanics* — a
mode can exist without the word "rush" anywhere in it:

```
rush | RUSH | timeAttack | time_attack | blitz | frenzy | gauntlet | arcade
mode | MODE | gameMode | modes
countdown | timeLeft | timeRemaining | duration | deadline
```

Mechanical tells, which are more reliable than names: a spawn path that does
**not** wait for an empty arena, any timer that counts *down* rather than up,
and any second entry point beside the one `main.js` start path.

**Record, in `RUSH_MODE.md` § Parity risk:**

- exists / does not exist, with the `file:line` that proves it either way
- if it exists: its run length, its spawn cadence, its scoring, and whether it
  has its own saved best — each with a line reference
- if it does not: say so explicitly, so the next person does not re-search

**Then, per the outcome:**

| outcome | what happens to the queue |
|---|---|
| **exists** | `RUSH_MODE.md` §2–§4's constants are replaced wholesale by the source's; §5–§7 (HUD, touch, save) stay this repo's own choices. `Q-010` becomes "port it down", not "propose it up". Q-003/Q-005 unblock immediately. |
| **does not exist** | Rush is this port's first **gameplay-level** divergence. Record it in `PORT_STATUS.md`'s divergence list beside the emissive floor grid and the surface-mounted eyes. `Q-010` becomes "propose upstream". Constants stay PROPOSED and get tuned by playtest instead of by reference. |

## Q2 — The daily seed (feeds `DETERMINISM_AND_SEEDS.md`)

`save_service.gd`'s header records that Phase 4's "daily seed" shipped in the
browser build and is still open here. That means a *reference implementation
exists*, and this port should not invent its own scheme.

Find: how the day's seed is derived (date string? UTC midnight? which
timezone?), which RNG consumes it, and — the question that actually matters for
`Q-012` — **whether cosmetic randomness draws from the same stream as spawn
decisions**. Record the answer in `DETERMINISM_AND_SEEDS.md` §4.

## Q3 — The HUD layout divergence

`PORT_STATUS.md` records the browser build as stacking WAVE plus a wave-progress
bar top-left with HP pips beneath, score top-right, against this port's single
top row — listed as "still different, and still open".

Rush needs a clock in that same real estate (`RUSH_MODE.md` §5), so the layout
is about to get decided by default if nobody decides it deliberately. Grab the
actual HUD element list and positions, and record whether the wave-progress bar
has a natural Rush analogue (it is the same shape as a drain bar).

## Q4 — Kill particles: the numbers only

`PORT_STATUS.md` item 2 already names `TUNING.fx.killDroplets` 22 and
`killChunks` 5. Confirm those two, and pick up what is *not* recorded: droplet
lifetime, spread, gravity, and the splat decal's size/fade. Cheap while the
file is open; saves a second trip when that item comes up.

## Q5 — The roster names

`tuning.js` names all ~40 enemy types and this port has 6. Copy the full list
with each type's `minWave` and budget cost into a table in `PORT_STATUS.md`.

This is the highest value-per-minute item on the list: it turns "more enemy
types" from an open-ended backlog line into a countable, orderable set of
tasks, and it makes the wave-composition pool auditable against the source
without opening the source again.

## Definition of done

- every question above answered, or explicitly marked "not found, searched for
  X" — a searched-and-absent answer is a real result and must be written down
  so it is not re-searched
- each answer carries its `file:line`, per the porting discipline
- `Q-001` moved to Landed in `QUEUE.md` with the commit SHA
- any item the answers unblock has its `blocked-by:` line updated
