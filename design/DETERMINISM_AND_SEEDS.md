# Determinism and seeds

**Status:** proposal. Decide this **before Rush ships**, not after — see §5.

## 1. Why this is on the critical path

`save_service.gd`'s own header records the daily seed as the one piece of Phase
4 still open. Rush mode makes it urgent rather than nice-to-have: Rush is a
score-attack mode, and a score-attack mode where two players get different
enemy compositions is comparing two different games. The moment Rush ships with
a leaderboard shape (`RUSH_MODE.md` §7 adds one), the pressure to add seeded
runs arrives with it.

Retrofitting determinism is expensive; the cheap version is nearly free **if
the call sites are fixed before more of them exist**. That asymmetry is the
whole argument for doing it now.

## 2. What the port does today

Every gameplay random draw goes through Godot's **global** RNG — `randf()` /
`randi()`, which Godot 4 seeds randomly at startup. Thirteen call sites across
seven scripts:

| file | draws | governs |
|---|---|---|
| `wave_director.gd` | `randi() % affordable.size()` | **which enemy type spawns** |
| `wave_director.gd` | `randf() * 0.4 - 0.2` | spawn angle jitter |
| `wave_director.gd` | `randf() * TAU` ×2 | revenge ring start angle |
| `globbo.gd` | `randf() * TAU`, `randf() * 1.4` ×2 | pounce phase and timing |
| `yela_cube.gd` | `randi() % angles.size()`, `randf() < 0.5` | flop direction, diagonal pick |
| `fanner.gd` | `randf()` ×2, `randf() < 0.5` | strafe flip timing and direction |
| `weeva.gd` | `randf() * TAU` | spiral start angle |
| `bullet_pool.gd` | `randf() * TAU` | **bullet shimmer phase — cosmetic** |
| `audio_kit.gd` | its own `RandomNumberGenerator` | pitch variation |

Two things stand out.

**`audio_kit.gd` already got it right.** It owns a private
`RandomNumberGenerator` rather than drawing from the global stream. That is the
pattern the rest should follow, and it means audio is already safely outside
any gameplay stream.

**`bullet_pool.gd:115` is the bug this document exists to prevent.** A bullet's
`phase` is pure shimmer — it changes nothing about where the bullet goes — but
it draws from the same global stream as `wave_director.gd`'s spawn picker. So
under a shared seed, **firing one extra shot shifts every subsequent wave
composition**. Two players on the same daily seed would diverge the moment one
of them held the trigger a fraction longer. Nothing is broken today only
because nothing is seeded today.

## 3. Two levels of determinism, and only one is worth building

| | what it promises | what it costs |
|---|---|---|
| **A. Seeded spawn stream** ✅ | same seed ⇒ same enemies, same types, same order, same spawn positions | one dedicated RNG, threaded to the director; discipline about which stream a draw comes from |
| **B. Full deterministic replay** | same seed + same inputs ⇒ identical run, frame for frame | fixed timestep throughout, every `delta`-driven float made reproducible, input recording, and a permanent tax on every future feature |

**Recommend A.** It delivers the thing a daily seed is actually for — a fair
comparison — and it stops at a boundary the codebase can hold. B is a different
project: `main.gd` drives everything from a variable frame `delta`, so identical
runs would require a fixed-step accumulator under the whole game loop, and every
future enemy would have to be written to respect it. That is a large permanent
constraint bought for a replay feature nobody has asked for.

Be honest in the UI about what A guarantees: *the same swarm*, not the same
game. Two players on one seed meet identical waves in identical places; what
they do about it is theirs.

## 4. Proposed design

**One gameplay RNG, owned by the director.** A `RandomNumberGenerator` created
in `WaveDirector`, seeded per run, exposed to enemies via the same explicit
hand-off that already sets `target` / `bullets` / `half_x` in `_spawn()`. This
fits the existing architecture exactly — enemies already receive their
dependencies explicitly rather than reaching for globals, per `CLAUDE.md`'s
no-`_ready()`-timing rule.

**The rule that keeps it working:** a draw that affects *what happens* uses the
gameplay RNG; a draw that affects only *what it looks or sounds like* uses the
global RNG or a private one. Cosmetic draws must never consume from the
gameplay stream — that is precisely the `bullet_pool.gd:115` failure above, and
it will be reintroduced by the first particle system that grabs `randf()`
unless the rule is written down. `PORT_STATUS.md` item 2 (kill particles, 22
droplets and 5 chunks per kill) is the next thing that would have done it.

**Seed derivation** — match the browser build rather than inventing one; that
is `PARITY_RECON.md` Q2. Absent an answer, the placeholder is a UTC date string
hashed to a 64-bit seed, so "today's seed" means the same thing everywhere.

**Modes:** an unseeded run randomises the seed and records it with the run, so
a good run can always be identified after the fact. A daily run takes the day's
seed. A seed can also be entered directly — that costs one text field and makes
the whole feature shareable.

## 5. Sequencing — the actual argument for doing this early

Ordered by cost of delay:

1. **Fix `bullet_pool.gd:115` to use a non-gameplay stream.** A two-line change
   today. After Rush + seeds ship it is a bug report about scores that do not
   reproduce, which is a far more expensive way to learn the same thing.
2. **Write the cosmetic-vs-gameplay stream rule into `CLAUDE.md`.** Enemies
   already follow a written architecture rule for their dependencies; this is
   the same kind of rule and the same kind of enforcement.
3. **Introduce the gameplay RNG** and thread it through `_spawn()`.
4. **Then** seed derivation and the daily-seed UI, which are ordinary features
   once the streams are separated.

Steps 1–3 are worth landing even if the daily seed is never built: they cost
little, they make `tests/smoke.gd` able to assert on *specific* wave
compositions rather than only on aggregate budget properties, and they remove a
class of bug that is genuinely hard to diagnose from a bug report.

## 6. Open questions

1. **Does Rush use the daily seed by default?** A shared daily Rush seed is the
   strongest version of the mode; it also means a bad daily draw sours the mode
   for a day. Recommendation: daily seed is opt-in, unseeded is the default.
2. **Does the seed cover spawn *positions* as well as types?** §3 assumes yes.
   The alternative is composition-only, which is weaker but survives an arena
   size change.
3. **Is a seed still comparable across versions?** No — a tuning change moves
   every composition. Store the game version alongside a seeded score, or the
   leaderboard silently mixes incomparable runs.
