# Splitting enemies — child-spawn-on-death machinery

**Status:** proposal. Independent of Rush, so it can run in **parallel** with
it — different files, no shared blocker.

`PORT_STATUS.md`'s backlog opens with wave-3 types, and names the shape of the
problem: *"SPLITTA, which needs child-spawning-on-death machinery that
REDD_CUBE and PURP_CUBE then reuse."* Three species want one mechanism, so it
is worth designing once rather than growing it out of whichever lands first.

## 1. What splitting collides with

The mechanism itself is small — a body dies and puts smaller bodies where it
was. What makes it worth a document is that a death in this codebase already
does four things, and every one of them has to answer for splitting.

**Death is not instant.** `Enemy.die()` starts a 0.28s pop; `WaveDirector`
moves the body out of `enemies` into `corpses` and keeps calling
`update_death()`. So *when* do children appear — on death, or when the pop
ends? **Recommendation: on death, in the same frame.** The parent's pop then
plays *over* the children scattering out of it, which is the read you want; a
0.28s gap between "it died" and "the children exist" is long enough to look
like the game hiccuped.

**Death fires a revenge volley.** `_fire_revenge()` runs for every body that
dies. A splitter that both spawns children *and* blooms a revenge ring puts
children and bullets in the same place at the same moment, which is unreadable
and probably unfair. **Recommendation: splitting replaces the revenge volley** —
the children *are* the retaliation, and that keeps the "corpses bite back" rule
intact while giving the species its own dialect. This wants a fourth
`Revenge` value (`SPLIT`) rather than a special case in the director, so the
existing dialect dispatch keeps doing the work.

**Death is scored.** `main.gd` awards `100 * max_hp`. If a splitter's children
are each worth full price, splitting is a score fountain; if they are worth
nothing, killing them feels like chores. **Recommendation:** children score
normally by their own (lower) `max_hp`, and the parent's value is set knowing
it will be paid twice over — that is a tuning question, not a structural one.

**Death clears the wave.** `WaveDirector.update()` emits `wave_cleared` when
`enemies` is empty. Children must enter `enemies` **in the same frame the
parent leaves it**, or a wave with one splitter left alive can briefly read as
empty and advance. This is the sharpest bug in the feature and the one most
worth a check: the ordering inside the director's removal loop is what makes it
correct, and that loop already iterates backwards while mutating.

## 2. Proposed shape

Keep it in the base class, driven by data, so REDD_CUBE and PURP_CUBE are table
entries rather than new code:

```
# Enemy — set by subclasses in init(); 0 children means "does not split".
var split_count := 0            # how many children
var split_type := ""            # POOL name of the child (may be its own type)
var split_scale := 0.6          # child radius / hp relative to parent
var split_spread := 1.2         # how far out they scatter
```

`WaveDirector` handles it where it already handles death, next to
`_fire_revenge()` — it is the only object that can legally add to `enemies`,
owns `enemies_root`, and already knows how to build a type from a name
(`_make()`), place it and call `init()`. Putting it anywhere else means an
enemy reaching up into the director, which nothing in this codebase does.

Children are placed on a small ring around the parent, clamped into the arena —
a splitter dying against the rail must not push children out of bounds, and
`_clamp_to_arena()` already exists for exactly this.

**Recursion needs a hard stop.** A child that inherits `split_count` splits
forever. Either children are a non-splitting type, or they carry a decremented
depth. **Recommendation: an explicit `split_depth`, decremented on each
generation, with children of depth 0 unable to split** — this is the kind of
thing that is obvious in review and catastrophic in play.

## 3. Where it meets Rush

Splitting is unblocked and Rush is blocked, so these will probably be built by
different hands. Two places they touch, both of which are cheap to handle now
and annoying to discover later:

**Pressure accounting.** `RUSH_MODE.md` §3.2 holds standing pressure as the
summed `POOL` cost of living enemies. A splitter that becomes three bodies
makes the live cost *rise* after a kill — so a Rush director that recomputes
pressure from the live list handles it correctly and automatically, while one
that decrements a running total on each kill drifts. Design note for Q-003:
**recompute, do not decrement.**

**The body cap.** `body_cap_for()` limits what the director *spawns*. Children
are not spawned by the director's budget path, so a wave of splitters can
legitimately exceed the cap. That is probably correct — the cap exists to keep
a wave readable at spawn time, and a splitter's burst is a deliberate spike the
player caused. But it must be a decision, not an accident: assert it either
way, or the first time Rush meets splitters somebody will file it as a bug.

## 4. Checks this needs

Per `CLAUDE.md`, in the same commit:

- a splitter's death puts exactly `split_count` children into `enemies`
- **a wave with only a splitter left does not emit `wave_cleared` when it
  dies** — the ordering check above, and the important one
- children are smaller and weaker per `split_scale`, and are inside the arena
  even when the parent dies against the rail
- a splitter fires no revenge volley (the children replace it)
- depth terminates: a child of depth 0 dies without splitting
- score is awarded for parent and children independently

## 5. Open questions

1. **Do children inherit the parent's species, or a different one?** SPLITTA
   into smaller SPLITTAs is the classic read; REDD_CUBE/PURP_CUBE may want to
   split into a *different* type, which the `split_type` field already allows.
   Needs the source's table — fold into `PARITY_RECON.md` Q5.
2. **Do children arrive with i-frames?** Without a moment of grace, a player
   standing on the parent takes contact damage from a child that spawned inside
   them. Recommendation: a short spawn grace, matching the telegraph philosophy
   the rest of the game holds to.
3. **Does a split count as one kill or several for Rush heat?** §1's scoring
   recommendation implies several. That makes splitters the best heat engine in
   the game, which may be exactly right, or may need the parent to award no
   heat at all.
