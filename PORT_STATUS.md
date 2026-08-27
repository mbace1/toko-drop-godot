# Port status

Living doc — update this in the same commit as any change to `scripts/` or
`shaders/`. Source of truth for numbers/behaviour is the browser build at
`mbace1/Suds-Jack`, `toko-drop/js/*.js` (referenced per line below). Visual
target is `PORT_BRIEF.md`.

## Ported

**Portrait/landscape dual arena** (`scripts/main.gd`, main.js
`ARENA_PRESETS`) — found 2026-08-26 by a real phone, not a capture: this
port had ONLY ever ported the browser's LANDSCAPE preset (halfX 19, halfZ
11) and treated it as THE arena. main.js actually swaps between that and a
PORTRAIT preset (halfX 11, halfZ 18 — a tall room, not the wide one
scaled down) off the real device aspect (`landscapeMode = innerWidth >
innerHeight`), each with its own camera rest position and look-at target,
and re-derives on resize/rotation while at the title screen. Opening this
port on an actual portrait phone got the landscape room, the landscape
camera, and a landscape-sized HUD regardless — a sideways level on a
vertical screen, everything undersized, menus reading wrong. `main.gd` now
carries both presets (`HALF_X_LANDSCAPE`/`HALF_X_PORTRAIT` etc.,
`CAM_REST_LANDSCAPE`/`CAM_REST_PORTRAIT`), picks one at `_ready()` via
`_detect_landscape()` (viewport width vs height), and re-picks on resize
while `state == State.MENU` (never mid-run, which would teleport the arena
under the player — same reason main.js gates it the same way). The
project's `window/handheld/orientation` was forcing `"landscape"` via the
Screen Orientation API — a lock that only actually works in fullscreen
mobile browsers, so in a normal tab it was likely a silent no-op fighting
nothing, while the game underneath had no portrait math to fall back on
regardless. Changed to `"sensor"` so the real orientation reaches the game,
which now knows what to do with either one.

**The HUD/touch layer, found and fixed the same day** — this port gained a
working visual-verification path mid-session (Playwright + a portrait phone
device profile, driven against a local export server; `tools/capture.gd`
still doesn't work here) and used it to actually chase the remaining report
(small HUD, sticks not appearing, dash not firing) rather than guess at it.
Root cause, confirmed empirically by toggling `window/stretch/aspect`
between `"expand"` and `"keep"` and comparing screenshots: `canvas_items` +
`"expand"` stretch (right for the 3D scene — it's what lets the portrait
arena above fill the whole screen) turns the 2D UI's own logical coordinate
space into something like 1280 x 2600 in portrait, not the 1280x720 every
HUD element is tuned against. A `position.y = -120` nudge that reads as
"just above centre" in a 720-tall reference is imperceptible in one 2600
tall, so content ended up bunched wherever its anchor happened to sit —
menu text cut off at the very top edge, HUD readouts unreadable, hint text
computed against the wrong reference and clipped by the top of the screen.
Fixed with three separate, verified pieces:
- `main.gd`'s `_update_hud_transform()` gives the (now correctly-labelled)
  `hud` CanvasLayer its OWN `Transform2D` mapping a fixed 1280x720 design
  space onto a centred, aspect-correct rectangle of whatever the real
  screen is — the same trade `"keep"` makes for the whole game, applied to
  the UI only, so the 3D scene keeps filling the real screen. Recomputed on
  every resize (cosmetic, safe mid-run, unlike the arena orientation).
- **TouchSticks got its OWN separate, untransformed CanvasLayer**
  (`touch_layer`) — its stick RINGS have to track real finger positions
  1:1 (`InputManager.Stick.origin`/`.delta` are real viewport pixels), so
  routing them through the same fixed-1280x720 remap as the labels would
  have drawn a ring somewhere the finger wasn't.
- **`TouchSticks.size` wasn't reliable** for a top-level Control parented
  directly under a bare CanvasLayer (no Control/SubViewportContainer
  ancestor for `PRESET_FULL_RECT` to inherit a rect from) — confirmed with
  a debug print showing the idle hint text computed against the right
  numbers yet still rendering top-left; fixed by driving `size` explicitly
  every frame (`_sync_size()`) instead of trusting anchoring to do it.
- Two more real, independent bugs found by the SAME phone report and fixed
  in the same pass: **`●`/`○`/`█`** (HP/lives pips, the heat bar) rendered
  as tofu boxes — Godot's bundled default font doesn't include those
  Unicode blocks and this port has no custom font loaded to fall back on;
  swapped for plain ASCII (`@`/`o`/`#`) guaranteed to exist in any font.
  **The feedback panel was opening on the very first title screen**, before
  a single run had ever happened — `_show_menu()` called `_open_feedback()`
  unconditionally; that call only belongs on an actual death/level-end
  recap (the other two call sites), so it's removed from the menu path.

**Menu launched RUSH by default, and the title screen had no visual
hierarchy** — a real phone re-check after the HUD/touch fixes above still
called menus "hard to read", and separately asked whether tapping to start
was landing in Rush Mode (it explained getting a shotgun on what should have
been a first CLASSIC run). Both true, both in `main.gd`, both fixed
2026-08-27:
- `MODE_ROWS` (the menu's row table) never had a `Mode.CLASSIC` entry — it
  started at ROGUELIKE (`"ready": false`) then RUSH. `_show_menu()` parks the
  caret on the first `"ready": true` row, which was RUSH, so a tap/dash
  before ever touching the d-pad launched Rush (shotgun ability, boost/heat
  HUD) instead of the plain original run. Added an explicit, always-ready
  `Mode.CLASSIC` row first, matching main.js's own default mode.
- The title screen was one `Label` at one font size/colour throughout — no
  equivalent of main.js's huge glowing `logo.png` wordmark over small plain
  copy (`showTitle()`, `js/main.js`). Added a second, big (56px), warm-gold
  `_title_label` ("TOKO DROP") shown only on the menu (hidden on
  pause/death/challenge-finish, which never carried it). Getting it to sit
  where it should have taken a second pass: anchoring it to a fixed pixel
  offset from the top put it in a completely different part of the screen
  from the (vertically-centred) menu body on a portrait phone, because the
  message `Label` centres against the CanvasLayer's real (very tall, post-
  `"expand"`-stretch) viewport while a fixed offset does not track that.
  main.js's own `#overlay` is ONE div, `top:50%; transform:translate(-50%,
  -50%)` — title and body move together as a single centred block. Ported
  that behaviour with two independent Controls by anchoring both to the same
  centre point and adding `_position_title()`, which reads
  `_msg_label.get_minimum_size().y` (recomputed on every menu redraw — row
  selection changes how many lines are showing) to place the title directly
  above the body with a fixed gap, rather than a screen-space guess.
  `_menu_text()` also dropped its own now-redundant `"TOKO DROP", ""` header
  line and moved "tap, or press FIRE / DASH, to start" up to right after the
  subtitle, ahead of the mode-row list — main.js's own order (logo, subtitle,
  best score, tap-to-start, mode toggles, controls).

**Typography and menu hierarchy** (2026-08-27) — found by serving BOTH
builds locally and capturing them at the same Pixel-7 profile, rather
than by reading either one's source. Two things were making the port
read as a different game in a side-by-side:
- **No font.** The browser sets `font-family: monospace` on its whole
  overlay (`index.html` `#overlay`) and every screen is that face. This
  port had no font resource at all, so it rendered in Godot's default
  proportional sans. JetBrains Mono Regular (SIL OFL 1.1) is now bundled
  at `assets/fonts/`, with `OFL.txt` beside it because that license
  requires the license to travel with the font.
  **`SystemFont` is a trap here** and was tried first: it resolves fine
  on desktop and silently resolves to NOTHING in a Web export, because
  the browser sandbox gives Godot no OS font access — so the one platform
  this ships on was the one platform where it did nothing. Only exporting
  and screenshotting showed that; a headless test cannot see it.
- **No glow.** `#overlay` carries `text-shadow: 0 0 24px #ff4422, 0 0
  60px #aa00ff`, which is most of why the browser's menus read as lit
  signage. Ported as a soft zero-offset shadow.

`scripts/theme_kit.gd` (ThemeKit) owns both so `main.gd` and
`touch_sticks.gd` cannot drift into two typefaces. It deliberately has
TWO looks because the browser does: overlay text glows, the in-game HUD
does not — the HUD is painted on a separate `#canvas-ui` 2D context
(`main.js` ~4136) in flat `rgba(255,255,255,0.55)` and never sees the
overlay's CSS. Glowing the HUD made it read as hot orange signage over
the arena; a screenshot of a real run is what caught it.

**The menu is a container now.** The browser builds its title hierarchy
out of SIZE and OPACITY (subtitle 13px/0.5, call-to-action 16px/0.85,
mode chips 14px bold, hints 11px/0.45, controls 9.5px/0.32 — see
`showTitle()`); this port had all of it in one Label at one size, which
is what "still hard to read" was pointing at. It is now five Labels in a
`VBoxContainer` — title, subtitle, CTA, the mode list, controls. Using a
container rather than hand-placed offsets is the point: the previous
pass positioned the title by reading the message body's height on every
redraw, and every new line of menu text was another chance for that
arithmetic to be wrong. Pause/death/recap screens hide the other four
labels, leaving the box holding only `_msg_label`, so they centre
exactly as before and needed no layout of their own (verified by
screenshotting a real pause).

**The HUD reference now fits on WIDTH, not on `min(width, height)`** —
and this was the reason everything looked small. Fitting on the smaller
axis letterboxed the entire UI into a 1280x720 band across the MIDDLE
28% of a portrait phone: the menu could never be bigger than that band,
and the two bottom corner readouts sat at 63% of screen height rather
than at the bottom, because that is where the band ended. Measured, not
guessed — a debug print in the running Web build gave viewport
1280x2607 against a 720-tall reference. Fitting on width keeps 1280
design units == the full screen width on any device (so every size in
`main.gd` stays in one honest unit) and lets the height be however many
of those units the screen is tall. Every font size was then re-derived
from the browser's own: at this scale a design unit is ~0.32 CSS px on a
412px-wide phone, so the browser's 13-16px overlay text is ~40-50 units,
roughly double what this port had been using.

**The mode rows are the browser's chips.** Each row is a PanelContainer
with its own StyleBoxFlat (2px border, translucent black fill, 8px
radius) built once and re-tinted per redraw, with the selected row's
detail block moved to sit directly beneath it. Chips override the
overlay's inherited neon glow exactly as the browser's do
(`text-shadow: ${on ? '0 0 12px <accent>' : 'none'}`) — without that the
one orange halo sat on every chip and swamped the state colours.

Fixed in the same pass, and it predates the chips: **the ON/OFF badge
was lying.** It followed `mode` (the run that happened last) while
pressing start plays the row the CARET is on, so walking down to DAILY
RUN left it reading OFF while start would have launched exactly that.
ON now means "this is what start will play".

**The wordmark is the real `logo.png`**, carried across from the browser
build rather than set in the body font — it is the one part of the title
screen typography cannot reproduce, and it is this game's own art from
the same project. The text headline is kept as a fallback so a failed
load is a plain title rather than a title screen with no title.

**The wash behind the logo is in too** — `radial-gradient(ellipse 52%
48% at 50% 50%, rgba(255,68,34,0.50), rgba(170,0,255,0.30) 55%,
rgba(170,0,255,0) 74%)` at `inset: -34% -22%`, as a `GradientTexture2D`
in `FILL_RADIAL` behind the wordmark. It is a RADIAL gradient rather
than a drop shadow for the reason `showTitle()`'s own comment gives: the
rectangular shadow it replaced "read as a pink box". A VBox stacks its
children, so the logo sits in a small wrapper Control with the wash
anchored behind it.

**A third tofu bug, and a permanent guard against a fourth.** The death
recap printed `U+2605` (a star) before "BEST TIME" and JetBrains Mono has
no such glyph, so it drew as a box — found in a capture of a real death,
on a screen no test covered and nobody had looked at. This port has now
shipped tofu twice before (the HP pips and heat bar against Godot's
default font, found on a real phone). `_test_font_glyphs` turns it from a
rendering fact into a logic one via `Font.has_char()`: every non-ASCII
codepoint the UI prints is asserted against the BUNDLED font, and the
test also asserts that `U+2605` really is absent, so it can fail rather
than passing on everything.

**The four screens are covered by a test now** (`_test_screen_states`
in `tests/smoke.gd`, 17 checks). The title, pause, death and level-recap
screens share one CenterContainer, and the menu-only chrome is hidden on
the others so the box collapses to just the message label. That had been
restructured three times — hand-positioned labels, then a VBox, then a
CenterContainer — and each time the only check was a screenshot of ONE
of the four. The test asserts all of them plus the chip invariants
(one chip per row, exactly one reads ON, and it is the row the caret is
on), so the next restructure cannot quietly leave the death recap with a
title over it.

**Core loop**
- Twin-stick movement + mouse/gamepad aim, dash with i-frames, fire-rate
  gated shooting — `scripts/player.gd`, numbers from `js/player.js`
  (SPEED 6, DASH_SPEED 26, DASH_DUR 0.18, DASH_CD 0.75, FIRE_RATE 0.09,
  MAX_HP 3, MERCY_DURATION 1.2, RADIUS 0.5).
- Pooled bullets rendered via `MultiMeshInstance3D` (halo/core/shadow),
  300-capacity — `scripts/bullet_pool.gd`, structure from `js/bullet.js`.
- Desktop keyboard+mouse and gamepad input, unified into the same
  `get_move_dir()` / `get_aim_dir()` shape as `js/input.js` —
  `scripts/input_manager.gd`.
- **Budget-based** wave director — `scripts/wave_director.gd`, porting three
  tables from tuning.js §waves (the v217 "Wave Director v1" that moved spawn
  tables out of main.js into data): the `[minWave, budgetCost]` composition
  pool (line 148), the budget curve (base 5, ramp 1.8 to a knee at wave 10,
  then 0.8, with the early ease that shaves 15% at wave 1 — line 184), and
  the shooter cap (1 at wave 1 growing to 5 by ~wave 12 — line 200). The cap
  matters: without it a budget spend fills the arena with artillery and the
  wave stops being readable. Bodies spawn on a ring at 0.6× the arena half-
  size, never on top of the player.
- Game states (menu/playing/paused/dead), collision loop, HP/wave/score
  HUD — `scripts/main.gd`.

**Input, sound and meta**
- **Touch — the browser's dual virtual sticks** (`scripts/input_manager.gd` +
  `touch_sticks.gd`). The screen splits down the middle; a finger on the left
  half plants a move stick where it landed, a finger on the right plants an aim
  stick that auto-fires, and RELEASING the aim stick is the dash. Nothing is a
  fixed button, so a stick is always under the thumb that reached for it.
  TOKO_DROP_ROADMAP.md §Guiding constraints: *"Mobile touch is first-class.
  Every feature ships with a touch answer."* — the port was breaking that rule
  outright until now.
- **Audio, synthesised at load** (`scripts/audio_kit.gd`). Eight voices, each
  an oscillator sweep under an exponential envelope baked into an
  `AudioStreamWAV` at startup. `js/audio.js` is all-synth WebAudio with no
  sample files, and the house rule across this codebase is that sound is
  generated, never sampled — so there is nothing to license and no binary in
  the repo. The gun sits at 0.10 gain deliberately: at ~11 shots a second it
  becomes the mix otherwise.
- **Hi-score and run history** (`scripts/save_service.gd`), the local-bests
  half of TOKO_DROP_ROADMAP.md Phase 4. `user://` stands in for localStorage;
  last 10 runs newest-first, and the death screen's "recent" line skips index 0
  because that is the run you are already reading the big number for. Nothing
  leaves the machine — no leaderboard, no network call. Daily Run (below)
  ports the seed/modifier half of this; the browser's separate per-day
  leaderboard is not.
- **Save schema v2 — per-mode buckets.** v1 was flat and MODE-BLIND
  (`{hi_score, runs}`), so the first Rush run would have overwritten the Normal
  best with a number from a different game. It also had no version field, so
  the migration keys off the shape: a parsed dictionary with no `"v"` is v1 and
  is carried across into `modes.normal` rather than discarded (a v1 file is
  *old*, not corrupt). `levels` is reserved in the same pass — the campaign's
  per-level records are a high-water mark, a different shape from a run list,
  and adding them later would have cost a v3 migration for nothing.
  `design/RUSH_MODE.md` §7, `design/CAMPAIGN_LEVELS.md` §4.
- **One gameplay random stream** (`wave_director.gd`'s `rng`, handed to every
  body in `_spawn()`). Every draw that decides *what happens* — which type
  spawns, where it lands, which way a body flops, a revenge ring's start angle
  — comes from it; **cosmetic** draws deliberately stay on the global rng.
  That split is the whole point: a bullet's shimmer phase used to share the
  stream with the spawn picker, so under a seed, firing one extra shot would
  have shifted every later wave and two players on one daily seed would have
  diverged from the trigger. Nothing was broken only because nothing was seeded
  yet. The director is left unseeded by default, so an ordinary run is as
  random as it ever was. `design/DETERMINISM_AND_SEEDS.md`.
- **`WaveDirector.compose()`** — the affordability loop split out of
  `start_wave()` so a second *cadence* can spend the same ported table without
  forking it (Rush holds a standing pressure rather than spending a whole wave
  at once). Pure refactor; the existing wave checks pass unmodified.

**Enemies** (19 of ~40 in the live roster — `js/tuning.js` names all 40)
- GLOBBO — chaser blob. Two behaviours stack: the lunging speed-pulse
  `speed × (max(0,sin(t·3+φ))² · 2.6 + 0.4)` (`TOKO_DROP_PORT_BRIEF.md`
  Part 2 / tuning.js line 43) **and** the stalk→crouch→leap pounce state
  machine from `enemy.js` line 1397 — the crouch telegraphs, the leap
  commits to the direction captured at crouch time and cannot correct.
  `scripts/globbo.gd`. Stats from `enemy.js` line 486.
- YELA_CUBE — edge-pivot flop instead of a slide (arc 135°→45°, land flat,
  50% diagonal picks) — `scripts/yela_cube.gd`, math from
  `TOKO_DROP_PORT_BRIEF.md` Part 3. Stats from `enemy.js` line 492.
- SPITTOR — **the first ranged type.** HOLDER archetype: holds `want = 10`
  with a ±1 hysteresis band (`enemy.js` line 1932). Inflates +22% over a
  0.45s wind-up, recoils 0.18 backward on fire, and spits a ring of 8 aimed
  so one bullet leads straight at you (`enemy.js` line 2565,
  `TOKO_DROP_PORT_BRIEF.md` Part 2, tuning.js line 40).
  `scripts/spittor.gd`. Stats from `enemy.js` line 487.
- FANNER — HOLDER at `want = 8` (±1.5) while strafing perpendicular, flipping
  direction every 2.5–3.5s; rocks as it circles. Fires 6 shots across 0.6π,
  but **every third volley** is a wide 9 across 0.95π — "a heavier beat"
  (`enemy.js` line 2590). `scripts/fanner.gd`. Stats from `enemy.js` line 488.

- ORANGE_CUBE — flops toward you on the cube's eight-way grid, then throws a
  **wall**: six shots side by side, all travelling the same snapped compass
  direction, so you go around it rather than between the shots (`enemy.js`
  line 2046). Stats from `enemy.js` line 493.
- WEEVA — a drifting spiral turret, and the first ported enemy with **no
  wind-up**: `fireInterval` 0.16 is a STREAM, not a volley, each shot rotated
  `0.38` rad past the last. A telegraph on that cadence would be permanently
  lit and would say nothing. Weaves while slowly closing (`enemy.js` line
  1958). Stats from `enemy.js` line 489.

- SLUDGE_CUBE — slow MASS cube that lays a **poison patch every 0.5s**. The
  patch lives 8s (`TUNING.fx.poisonLife`), so a dead SLUDGE is still shaping
  where you can stand long after it is gone. Stats from `enemy.js` line 494.
- SPLITTA — dying is a SPAWN: three GLOBBOs, per `enemy.js`'s `_childType` /
  `_childCount` (*"always splits into 3 small blobs (v99)"*). It visibly
  **carries** two child domes before it dies (`TOKO_DROP_PORT_BRIEF.md`
  Part 2), so the rule is learnable by looking rather than by dying to it.
  Children join the LIVE list, so a wave is not clear until they are dealt
  with too. Stats from `enemy.js` line 490.

- REDD_CUBE / PURP_CUBE — the other two splitters, reusing the shared
  split-on-death contract (4 REDD_MINIs, 5 PURP_MINIs; counts from
  `enemy.js`'s `_childCount`). PURP's revenge speaks FAN, REDD's RING.
- REDD_MINI / PURP_MINI — one hit each, fast, straight at you. Spawned only by
  a parent's death, so deliberately absent from the wave POOL.
- **TORO** — the showpiece charger (`TOKO_DROP_PORT_BRIEF.md` Part 4). An
  upright wheel: idle creep → rev 1.6s → telegraph 0.5s → dash 22→14 →
  recover 0.8s, direction snapped to 45° and **locked at the telegraph** so it
  cannot re-aim after the tell. The indicator is raycast to the arena wall so
  the arrowhead **tip sits exactly on the impact point** — you are told where
  it will stop, not merely which way it is going. Spins about its axle at
  `v / radius` while dashing, so it visibly rolls.

- **SIREN / SHEPHERD — the "side quest" bodies.** Owner direction: not bosses,
  but enemies that pull focus off the primary goal. Neither touches you.
  SIREN inhales for 0.8s then SCREAMS, surging every body within 7u to 1.6x
  for three seconds (`tuning.js`: *"screamer — surges the pack, kill it
  first"*). SHEPHERD never closes; it holds 9u, circles, and drags its whole
  flock toward you (*"the threat is what it does to the OTHERS"*). Both are
  fragile and both are running away, so chasing one costs you what you were
  doing — and not chasing it costs more. `move_speed()` on the base class is
  what lets one scream lift the entire arena.

- **PYRA** — the one body that never moves. Spins in place and throws a
  7-shot fan every 2.5s, so it is entirely a positioning problem.
- **BOTFLY** — orbits at mid range and fires slow HOMING shots that steer a
  fraction of the way each frame rather than snapping. `bullet.js`'s own note
  on the speed: *"speedMult 0.62 keeps it outrunnable"* — a homing bullet you
  cannot outrun is a hit with extra steps.
- **BULWARK** — its FRONT is bulletproof; flank it. The facing turns at a
  limited rate on purpose (*"a quick side-step stays a real answer, the plate
  can't snap-track"*), because a shield that tracks instantly is not a puzzle,
  it is more HP.
- **WARDEN** — the third side-quest body and the most demanding. It never
  attacks; everything inside its aura shrugs off your shots. SIREN makes the
  swarm faster and SHEPHERD makes it closer, but a WARDEN makes it
  UNKILLABLE until you deal with the warden. It never shields itself, so
  there is always something you can shoot.

**Wave shape — variants, affixes and rhythm**
- **Wave kinds** from `tuning.js` waves.rhythm: boss every 8, spike every 4,
  swarm every 3 from wave 3, and a breather after each spike — each with its
  own budget multiplier. Without this, wave 12 is wave 4 with more bodies; the
  rhythm is what gives a run a SHAPE, including a trough to climb out of.
- **Spawn variants** per body, drawn from the source's tables (repetition is
  the weighting): elite (×2 HP, ×1.2 size, always an affix), elitelite
  (×1.5 HP, half the time an affix), twin (two of it), group (3–5 of
  something CHEAP). Swarm waves draw from their own table — groups and twins,
  never elites, because a swarm of elites is not a swarm.
- **Elite affixes**, each with a visible tell (main.js v145): **volatile**
  strobes orange and its corpse blooms an extra ring; **swift** is 1.35× and
  streaks harder so you see it coming; **anchored** cannot move at all and is
  tougher for it.
- Two accounting bugs the tests caught: a TWIN of a shooter counted once
  against the shooter cap that exists to keep a screen readable, and a GROUP
  could push past the body cap entirely.

**Weapons and the streak**
- **Weapon pods** (`scripts/powerup_pool.gd`) — kills drop them, you walk over
  one and your gun changes for the rest of the run. Table mirrors main.js's
  `WEAPON_PODS`: S/S2 spread, B/B2 burst, L/L2 laser, R/R2 rapid, level-2 only
  from wave 4 and only 28% of the time even then. Two source rules kept:
  **HOMING never drops** (enemy.js v88 — *"homing is enemy-exclusive now"*;
  BOTFLY has it), and **pods expire**, so taking one is a decision you make
  now rather than deferred shopping.
- **Firing modes** on the player, from `js/player.js`: SPREAD 5 at π/9,
  SPREAD2 7 at π/10, BURST +2 queued, BURST2 +4, RAPID ×0.45, RAPID2 ×0.28.
  A burst's queued shots arrive even after you release the trigger, which is
  what makes it a COMMITMENT rather than just a slower gun.
- **Streak** — Normal mode had no chain at all. Climbs per kill, resets on a
  hit, and wears the browser's heat tiers (gold at 5, orange at 10, red at 20)
  so the scoring depth reads at a glance.
- **Kill scoring, corrected 2026-08-26**: found while porting Gates, not
  caused by it. main.js's `onKill()` pays `100 * streak * multipliers` —
  the SAME body costs more to kill the deeper into a streak you already
  are — and this port had instead been paying `100 * max_hp` (a per-body
  value keyed to the enemy's own toughness, never what the browser does).
  Fixed at both base-mode kill sites (`_collide_player_bullets()`, the
  gate's own enemy-kill path) via a new `_add_kill_score()` helper, which
  also folds in GLASS day's kill-only double (main.js: *"GLASS pays
  double"* — checked directly against the source line, this does NOT
  apply to graze/wave-clear/loot, which stay on plain `_add_score()`).
  Rush/Challenge keep their own unrelated `rush.multiplier` chain and
  formula — there is no browser mode to match there, so nothing changed
  for them beyond routing through `_add_score()` for the shared
  `score_mult_t` handling.
- **Graze** (main.js v125, `_collide_enemy_bullets()`) — an enemy bullet that
  skims within `bulletRadius + PLAYER_RADIUS + 0.55` without actually hitting
  pays +25 score, once per bullet, and only while the loop is even reachable
  — i.e. only while vulnerable, since the whole function returns early on
  `player.invincible`. So dashing or Rush-boosting through fire pays nothing;
  weaving through it does. A white puff + a short "graze" chirp mark it, and
  the death recap prints the run's total the way the browser's death screen
  does. **Divergence, documented rather than guessed**: the browser's
  `grazeMult`/`scoreMultT` are both powerup-card effects that are not ported
  yet, so this pays the base rate only (×1, not the card's ×3/×2).

**BAMBU** (`scripts/bambu.gd`, enemy.js "Part 5" + TUNING.bambu) — a
stationary segmented lobber, the last of the source's own "one genuinely new
gameplay affordance" call-outs. Never moves; the whole threat is a
telegraphed lob you dodge after it lands, not a bullet you weave: a flashing
landing ring appears at the target point, a charge climbs the 3-segment
stalk, a visible blob arcs in on a parabola, and splashdown only costs HP if
you're still standing in the ring when it lands (`main.gd`'s
`_collide_bambu_lobs()` — its own method for the usual reason, since this is
a hazard neither of the two bullet/contact collision loops would ever see).
Every hit pops the top segment, so HP and the visible stalk height are the
same number. Divergence: spawns pre-grown at full 3 segments rather than
animating the browser's ~0.5s emerge-and-grow beat — the growth window is
cosmetic and under a second in the source.

**CLOAKER, MAGNA, DRAPER** (`scripts/cloaker.gd`/`magna.gd`/`draper.gd`) —
the last 3 of the browser's full ~21-type roster (`tuning.js waves.pool`),
closing it out:
- **CLOAKER** (enemy.js v143) — visible -> cloak-and-flank (opacity 0.14,
  shimmering, runs to a point ~90 degrees around the player) -> decloak tell
  (strobing rim) -> a 3-shot burst, then back to visible. **Still hittable
  the entire cloaked phase** — enemy.js's own comment is "tracking pays" —
  so this needed no special collision handling at all; a lower `alpha_amt`
  on the shared gel shader IS the whole mechanic, and the existing
  radius-overlap collision does the rest for free.
- **MAGNA** (main.js v144) — never fires; holds ~8 units and lets its PULL
  do the chasing. Every living Magna within 11 units drags the player
  (1.1/s each, combined cap 2.0/s), an amber tether line showing exactly
  when it has hold. Dashing grants ~1.2s of pull immunity — momentum
  breaks it (`Player.magna_immune_t`, decremented in `player.gd`, since it
  is dash state the player already tracks every frame). The pull itself is
  cross-cutting (it moves the PLAYER, is summed across every Magna, and
  needs to know the player's dash state) so it lives in `main.gd`'s
  `_apply_magna_pull()`, the same reason BAMBU's splashdown damage isn't
  applied from inside `bambu.gd`.
- **DRAPER** (enemy.js v171) — "wall-weaver": holds ~11 units, turns to
  FACE the player (the loom itself is the tell — nothing else in the
  roster turns to face you), strobes for 0.9s, then looms a 15-slot bullet
  curtain marching straight ahead with one 2-slot gap to escape through.
  The march direction locks to wherever it was facing when the strobe
  ended, so the tell is the entire warning — it does not re-aim at the
  last instant.

**Cargo convoy** (`scripts/cargo_cluster.gd`, main.js `CargoCluster`) — a
formation of 3-5 golden goo-moths flies a straight line across the arena with
a sinusoidal sweep, once per wave (3-8s in, base/Classic mode only — the
same scoping as Daily's weapon-pod-bearing systems below, since Rush/
Challenge already suppress pod drops outright and a convoy's whole point is
dropping them). They never attack; the event is a bonus window. Shoot every
moth before any of them crosses the far edge and it drops a GUARANTEED
weapon pod; leave one to escape and each kill instead rolls a smaller,
individual payout — a weapon pod, a "score" nugget, or a "scoremult" window
(classic split 55/25/20). Spawn edge/curve/timing all draw from
`WaveDirector.rng`, not global `randf()`, so two Daily Run players on the
same date see the same convoy at the same time.

**Living-arena objectives** (`scripts/vault_crate.gd`/`escort_bot.gd`,
main.js v175) — two more per-wave bonus events, base/Classic mode only
(same scoping as the cargo convoy above), alternating on offset beats so
they never stack:
- **VaultCrate** — every 4th wave from 5 (never a boss wave), a locked
  crate with 8 HP appears at a random point. Shoot it down and it cracks:
  a guaranteed weapon pod plus a cash pickup (800 + wave×60), and a 40%
  chance of a second "scoremult" pickup beside it. Every hit before that
  also PINGS the room — every living enemy within 9 units surges toward
  the player for 0.7s (reusing `Enemy.surge_t`, the exact field SIREN's
  scream already drives) — so cracking it open costs something.
- **EscortBot** — every 4th wave from 6, offset from the vault's (never a
  boss wave), a small robot enters from one side wall and crosses to the
  other over ~14s. Enemies never chase it, but stray enemy fire costs it
  HP and any touch-attacking body (main.js's `MELEE_TYPES`) kills it
  outright — protecting it is pure positioning, not a fight. Deliver it
  to the far wall and it gifts a guaranteed weapon pod.

**Gates** (`scripts/gate.gd`, main.js v175 "M5b gates, round 2") — laser
barriers between two posts, spawning one per wave from wave 3 (every kind,
including boss waves — unlike vault/escort/cargo above), capped at 2 alive
at once (the OLDEST is evicted, not just deactivated, when a 3rd would
spawn) and, unlike vault/escort, **persisting across waves** rather than
being swept at the next wave's setup. Dash through a live one and it pays
out a random buff pickup (hp/invincible/firerate/scoremult) and deactivates;
bank a second one within 6s and a climbing GATE CHAIN bonus fires
(500 x the chain length). Two variants layer on from there: **RISK** gates
(35% chance, from wave 5) alternate green/red on a readable 1.6s clock —
dashing on green pays DOUBLE, red is a harmless dud. **DRIFT** gates (from
wave 10) wander slowly, bouncing inside the walls, so the late-game route
keeps changing. Enemies pay too: anything touching a live beam takes damage
on a 0.5s-per-gate cooldown, independent of the player entirely.
**Divergence**: main.js explicitly suppresses the revenge volley for
gate/vent/"env" kills ("vaporize cleanly... so a barricade can never become
a bullet fountain you farm from cover") — this port's revenge fire runs
from `WaveDirector`'s own corpse sweep rather than from the collision site
that killed a body, so it isn't suppressed by kill source here. A
gate-killed enemy still rings its normal revenge volley.

**CLEANSE FOAM** (`scripts/foam_zone.gd`, main.js `FoamZone`) — the third
"living-arena" bonus event, offset onto its own beat (wave >= 6, every 4th
wave from there, `w%4==2` — never the same wave as VaultCrate's `w%4==3` or
EscortBot's `w%4==1`) and, like Gates, **persisting across waves** rather
than being swept at the next wave's setup. A circle of foam on the floor:
stand inside it and a charge ring fills over 1.2s of CONTINUOUS presence;
step out and it decays at 1.5x the build rate, rewarding commitment over a
quick tag. Fully charge it and every enemy bullet on screen vanishes (the
player's own shots are untouched), paid per bullet cleared (500 + 10 each)
— a defensive panic button you have to stand still and earn, not press.

**Non-weapon value pickups** (`scripts/powerup_pool.gd`'s `VALUES` table +
`value_taken` signal, main.js's `Powerup` class) — the walk-over pickups the
three systems above actually drop, closing the divergence cargo/vault used
to carry (an instant score award standing in for a pickup that didn't
exist). Reuses `PowerupPool`'s existing pooled rendering rather than a
second pickup system:
- `score` pays its carried value once.
- `scoremult` starts (main.js: *overwrites, not stacks*) a real 10s x2
  window (`main.gd`'s `score_mult_t`), applied uniformly through a new
  `_add_score()` helper rather than threaded through every individual
  `score +=` site by hand (kills, graze, wave-clear, cargo/vault/gate loot).
- `hp` heals 1, capped at max.
- `invincible` grants 3s of i-frames (`Player.grant_invincibility()`,
  folded into the existing `invincible` getter alongside dash/mercy/rush).
- `firerate` grants 8s at the fire interval x0.4
  (`Player.grant_fire_rate_boost()`); both buffs are `max()` REFRESHES like
  the source, not stacking adds.

**Scoped down from the source's 8 pickup types**: `item`/`key`/`potion` are
KAIKKI-mode SHAPED pickups (a key that looks like a key, a flask that looks
like a flask — a different mode's own art) and stay out of scope. The other
five — every type this port's OWN drop sources (cargo, VaultCrate, Gate)
actually roll for — are all ported.

**Daily Run** (`scripts/daily.gd`, main.js v130/v179) — a new MODE_ROWS
entry under Challenges. Everyone on the same UTC date plays the same seed and
the same one-in-four twist, no server needed, since both are pure functions
of the date string:
- **The seed** — the browser hashes the date through `mulberry32`; this port
  hashes it through a Thomas Wang integer mix instead (not Godot's own
  `hash()`, which isn't promised stable across engine versions — a seed that
  moves on an engine upgrade defeats the point of a daily). Cross-engine
  bit-parity with the browser was never the goal; "every Godot player on the
  same date gets the same seed" is.
- **GLASS** and **RICH DAY** are direct ports (1 HP; budget ×1.4, `tuning.js`
  `waves.budget.rich`). **SURGE DAY is a divergence**: the browser tightens
  HAZARD/curtain/drain cadence, none of which exist in this port yet (no
  room-graph, no steam vents). What this port DOES have is the wave rhythm
  itself, so surge tightens that instead — spikes every 3rd wave instead of
  4th, swarms every 2nd instead of 3rd. Same intent ("the floor fights
  harder" on a shorter clock), different system underneath it.
- Daily runs record into the same save bucket as Normal — the browser's
  separate per-day leaderboard/best (`tokoDropDailyBest`) isn't ported.

**Boss waves and the wave-kind banner** (base/Classic mode only, owner
direction 2026-08-25 — Rush and Challenge already have their own escalation
reads and do not need a second one)
- **Boss** — the biggest-radius body in an every-8th-wave is promoted:
  ×3 HP, ×1.5 size, a gold aura ring on the floor, and it ALWAYS rings on
  death regardless of its species' own revenge dialect (main.js: *"a boss
  corpse is an arena event, not a duel"*). Picking the biggest body rather
  than just the first one spawned matters — the first attempt promoted
  whatever happened to be first in the list, which could be the smallest
  thing on screen with a WARDEN aura the same size sitting next to it.
- **The banner** — a fading toast naming the wave kind (BOSS / SPIKE / SWARM
  / BREATHER), so an escalation the source signals is not silent here.

**60fps pass** (owner direction: always aim for it)
- **Adaptive gel quality.** SSS is a per-pixel screen-space cost over every
  body's visible area, so the thing that actually threatens the frame rate is
  TOTAL ALIVE COUNT, not any one system. `Enemy.quality` is a shared static
  main.gd scales down smoothly above 10 live bodies (floor 0.35, never fully
  off) — the frame rate degrades gracefully instead of falling off a cliff
  right at the body cap.
- The back light (SSS transmittance only, never meant to cast a visible
  shadow) no longer has `shadow_enabled` — a second shadow-casting light was
  doubling the shadow pass for a shadow nobody was meant to see.
- SSR steps 32 → 16, and the directional shadow atlas 4096 → 2048: both cuts
  that do not cost the arena's fixed top-down camera visible detail.

**Feedback**
- The browser's v212 CONTEXTUAL question, ported: every damage site records
  what hit you and how, and the deck asks about THAT, skipping anything asked
  recently. Explicit consent (SEND only), never claims an unmade delivery,
  and an empty submission records nothing. Files under `tokodropgodot`,
  its own catalogue id.

**HUD**
- **Parity with the browser build's layout** (`js/main.js` drawHud): `WAVE N`
  top-left, a progress bar beneath it, HP pips under that, score top-right.
  This port previously ran one centred row, which was the HUD divergence
  recorded here; it is closed, which also settles Q-015. Rush's clock and
  chain take a line UNDER that stack rather than fighting it for the centre.
- One honest divergence: the browser's bar is a wave TIMER (`waveTimer /
  ROUND_DUR`), because its waves escalate on a clock. This port's waves are
  clear-based, so the same bar shows how much of the wave is dead. Same slot,
  same question, different quantity.

**Run readouts — parity pass 3**
- **Seed.** `WaveDirector.reseed()` sets an explicit, showable run seed and
  `seed_text()` prints it as six hex digits, the way the browser prints
  `SEED ED1E2E`. A seeded run you cannot name is one you cannot ask anyone
  else to try.
- **Corner readouts**: version + FPS bottom-left, seed bottom-right.
- **Time survived** is now a first-class stat. The browser's death screen
  reads `WAVE 1 · 5s · 0 PTS` and keeps a best of the TIME as well as the
  score; this port had no notion of it. Records are starred separately
  (★ BEST SCORE / ★ BEST TIME) because a run can be your longest without
  being your highest, and one "best" line hides that.
- **The red death wash.** The browser floods the screen red on death, and it
  is most of why dying LANDS — a text swap alone reads as a menu appearing.

**Motion trails and ground**
- **Per-species motion trails** (`scripts/trail_pool.gd`) — pooled ghost
  spheres shrinking to nothing over 0.45s, one MultiMesh for the whole swarm.
  Cadence and size per species from `enemy.js`'s `TRAIL_CFG`; a species absent
  from that table leaves none. Ghosts spawn **one body-radius behind** the
  mover along its velocity (main.js v100) — at the body's own position they
  are hidden inside it. This is most of why the browser swarm reads as
  *flowing* rather than as independently teleporting dots.
- **Poison field** (`scripts/poison_field.gd`) — SLUDGE's patches as a
  MultiMesh of floor discs, with one shared damage tick so standing in three
  overlapping patches is a bad place to stand rather than instant death.

**Ranged combat**
- Enemy-fired bullets through the same `BulletPool`, and enemy-bullet-vs-
  player collision in `main.gd`'s loop (ordered after contact damage so one
  frame can never cost two HP — mercy i-frames from the first hit absorb
  the second).
- `enemy.gd` carries the shared shooter scaffolding every ranged type needs:
  `_tick_fire()` (interval → telegraph → the one frame the volley fires),
  `_hold_at_range()` (the HOLDER archetype's hysteresis band, from
  `TUNING.movement.roles.HOLDER`), and `_ring()` / `_fan()` volley shapes.

**Death, and the corpses biting back**
- Death pop — a killed body swells `1 + t·1.3` while fading on a SQUARED
  curve over 0.28s, so it is mostly transparent by the time it is large
  (`enemy.js` updateDeath()). Corpses leave the live list immediately (they
  cannot be shot again and never hold up a wave clear) and finish popping in
  `WaveDirector.corpses`.
- **Revenge volleys** — CLOSE COMBAT, the headline of the roadmap's own
  tagline (`main.js` onKill(), v187/v220). A corpse's retaliation *speaks the
  species' language*: SPITTOR spits a slow AIMED burst of 3, FANNER throws a
  slow FAN of 5, everything else blooms the classic RING (4, or 7 for a body
  over radius 0.75). All of it at `TUNING.revenge.speedMult` 0.6 — "the graze
  game, not a wall" — behind the same 240-bullet pool guard the source uses so
  a mass grave cannot starve the living of bullets.
- Revenge **palette shift** (`main.js` revengeColor()): warm goes dark blood,
  yellow goes poison green, cool goes deep venom. A corpse never wears living
  colours, so the two attack classes read apart at a glance.

**Rush Mode** (`scripts/rush_rules.gd`, designed in `RUSH_MODE.md`)
- A second, self-contained ruleset selectable from the front page under
  ROGUELIKE MODE. Boost is a held state that grants invulnerability, kills on
  contact and builds a chain — but **firing cancels the shield**, and boosting
  heats you until it locks out. The weapon is a shotgun. Lives, not HP.
  Difficulty levels run 60s/90s/longer and move DOWN when you lose a life.
  Four selectable abilities (Heat Exchange, Hyper Bomb, Overcharge, Quantum
  Shield), and levels drive the wave director's composition so levelling down
  really is easier.
- Built from research into Blade Rush (Noba, 2025) — its Steam patch notes
  state the intent outright: *"prioritising boosting over shooting"*, and
  *"boost invulnerability ends... from disabling it by shooting"*.
- The roadmap's "No Geometry Wars aesthetic drift" holds: structure only, no
  new materials. Rush state rides on the gel shader's existing per-instance
  rim colour.

**Game feel**
- **Debris** (`scripts/debris_pool.gd`) — ballistic gel lumps with a floor
  bounce, at `TUNING.fx` counts: 8 droplets on a hit, 22 droplets + 5 bigger
  chunks on a kill. Lit rather than unlit, because unlit spheres of a flat
  colour read as confetti instead of as bits of the same gel.
- **Camera shake** — main.js's trauma model: events add trauma, it decays at
  ~2.8/s, and the offset is trauma SQUARED. The squaring is what stops a
  stream of small hits reading as constant judder while a kill still lands.
  Taking damage shakes hardest — it is the one event you must not miss.

**Challenges — the campaign** (`scripts/challenges.gd`)
- A Geometry Wars 3-shaped Adventure: named levels played in order, each one a
  RULE rather than just a different spawn table. GW3's identity is Pacifism /
  Deflector / King; ours is BOOST ONLY / CLOSE QUARTERS / ONE LIFE /
  ARTILLERY / SWARM / GRAVEYARD, each bending a system the game already has,
  so a level is data and an archetype is a parameter.
- **Ten levels**, covering all seven rule archetypes, all measured.
- **Timed** — every level runs a fixed clock and the score at the buzzer is
  the grade. **Tier C or better opens the next level**, so a player merely
  finishing keeps moving and the higher letters are for those who want them.
- **Abilities unlock over the campaign** (GW3's drones do the same): only
  HEAT EXCHANGE at the start, the rest arrive with cleared levels.
- **Thresholds are MEASURED, never guessed** — `tools/measure.gd` plays each
  level headless with a fixed yardstick bot and sets C/B/A/S from its median.
  A BOOST ONLY level and an ARTILLERY level have completely different kill
  rates, so one shared formula would be wrong on both. Every level carries a
  `measured` flag; a guess is marked as a guess.
- The camera scales with the room, so CLOSE QUARTERS reads as walls that are
  actually close rather than a small board adrift in a full-size frame.

**Material**
- One shared `shaders/gel.gdshader`: vertex ripple + hit shockwave, Fresnel
  rim glow, clearcoat, CPU-driven spring squash. Per-instance uniforms via
  `set_shader_parameter`, same "one shader drives every body" shape as the
  browser's `makeSatinMat`. This is **PORT_BRIEF.md §1's step 1** ("author
  one `shader_type spatial` gel shader… so a single material drives all
  enemies via per-instance uniforms").
- **True subsurface scattering — PORT_BRIEF.md §2a**, the "gummy-bear read".
  `SSS_STRENGTH` + `SSS_TRANSMITTANCE_*` + `BACKLIGHT`, with thickness taken
  analytically from the silhouette (`1 - |N·V|`, so thin edges glow brightest)
  rather than from a shipped texture. Three things had to move together for it
  to read at all, and each is load-bearing:
  1. **The material is OPAQUE.** Godot's SSS is a screen-space pass over
     opaque geometry, so an alpha-blended body gets none of it. Fades now use
     `ALPHA_HASH_SCALE` (hashed alpha, still in the opaque pass).
  2. **Bodies sit at alpha 1.0 at rest.** Any lower and the hash dithers them
     into visible static. Alpha is only for bodies on their way out.
  3. **There is a back light.** Transmittance is light passing *through* a
     body — with only a key light overhead it scatters into nothing. The
     camera is on +Z, so a second directional fires from the far side.
- IBL from a `ProceduralSkyMaterial` (ambient + reflections), while the
  visible background stays the browser's near-black void. PORT_BRIEF.md §0
  notes the source needs IBL "for transmission + clearcoat"; with a flat
  ambient colour a clearcoat has nothing to reflect, which was most of why
  the first render came out as matte plastic.
- `WorldEnvironment`: glow (bloom floor dropped to 0.05 so the HDR threshold
  actually decides what blooms), SSAO, SSR, ACES tonemap — **PORT_BRIEF.md
  §6**, "biggest single jump, near-free".

**Testing**
- `tests/smoke.gd` — 127 checks, bare `SceneTree`, no GPU. Run before every
  commit touching `scripts/`.
- **`main.gd`'s collision resolution is now covered.** `_collide_player_bullets`
  / `_collide_enemy_bullets` / `_collide_contact` are methods the gate drives
  directly. They used to be inline loops reachable only through
  `_process_playing()`, which needs live input — which is exactly how a bug
  that made PLAYER BULLETS DAMAGE THE PLAYER shipped past a green 155-check
  suite. If a system is only reachable through input, the gate cannot see it.
- `tests/smoke.gd` — 106 checks, bare `SceneTree`, no GPU. Run before every
  commit touching `scripts/`. The determinism checks are mutation-tested:
  reverting `compose()` to the global rng fails exactly two of them, including
  "shooting does not move the swarm". A gate that cannot fail is not a gate.
- `tools/capture.gd` — screenshots the REAL game on a GPU. This is the other
  half of the gate and it is not optional: the source repo's own recorded
  diagnosis is that its games stall at prototype feel because "the smoke
  gates certify *works* and prototype-feel lives entirely in the part they
  cannot see". **Look at the output after any change to how the game looks.**

  The first time this port was ever rendered — after three commits, all green
  — it had the whole stat row printed across the middle of the screen with
  WAVE on top of the player, an arena clipped at the bottom with the void
  showing past its far edge, and no visible boundary at all on the line
  bodies are actually clamped against. Every one of those passed 55 checks.

## Modes that exist only here — flagged 2026-08-27

Owner direction that day: *"We should aim the push of graphics and physics
here on Godot. Otherwise follow the lead of the JS version."* The JS build
leads on gameplay; this build leads on look, feel and physics; a feature is
never designed twice. Auditing this port against that rule turns up drift
that PREDATES it, so it is recorded rather than quietly acted on:

**Corrected the same day — read the method note below before trusting any
audit like this one.**

| mode | browser build (deployed) | this port |
|---|---|---|
| CLASSIC | yes (default) | yes |
| ROGUELIKE | **yes, shipped** (`roguelikeMode`, a 3-state OFF/A/B toggle) | **"SOON" — not ported** |
| DAILY RUN | yes (`dailyMode`) | yes |
| RUSH | **yes — shipped as v224**, "boost is the answer, the gun is the fallback" (PR #308) | yes |
| CHALLENGES | **no — still does not exist** | yes, a whole campaign |

**Method note, and it is the point of this entry.** The first version of this
table said RUSH did not exist upstream. That was wrong within the hour: it was
grepped against a local clone of `mbace1/Suds-Jack` sitting on `main`, which
was many commits behind, while the game actually ships from **`gh-pages`** —
and Rush landed there as v224 the same day. **Audit the DEPLOYED tree, not a
local `main`**, because for this project `main` is not where the game lives.

What survives the correction:
- ~~**ROGUELIKE is the one real follow-the-lead gap.**~~ **Ported
  2026-08-27** (mode A). The browser's rule is "upgrade cards every 3rd
  wave"; `scripts/upgrades.gd` carries the card catalogue with the browser's
  own ids and numbers, `main.gd` gains a `State.CARDS` draft that holds the
  run until you pick, and the mode row is playable.
  **A labelling bug went with it:** the row read *"no upgrades — pure arcade
  survival"*, which is the browser's text for the mode being **OFF**. The row
  was describing the ABSENCE of the feature as though it were the feature.
  **Ported: 8 of 20 cards.** The ones whose hooks exist here — hp, speed,
  firerate, dashcd, longdash, nuke, and the cursed x_berserk / x_leadfeet.
  The other twelve are listed in `Upgrades.PENDING` rather than dropped,
  because they need systems this port does not have yet (bullet scale and
  piercing on the pool; magnet/shield/dashboom player state; graze, vampire,
  ripple, tiredlegs, minnow and the remaining cursed pair need scoring and
  hit hooks). An unported card must never look implemented, so `PENDING` is
  not drawn from.
  **Not ported: mode B**, the browser's "cards + rare BONUS GAUNTLET runs".
  Also found and fixed while wiring it: `State.CARDS` was not counted as
  "in a run", so the whole HUD vanished the moment the draft opened — caught
  by forcing the draft open and looking at it, not by any assertion.
- **CHALLENGES is still Godot-only** — no `challengeMode`, no campaign
  machinery upstream at all — and it was designed in THIS repo
  (`design/CAMPAIGN_LEVELS.md`, `design/RUSH_TIERS_AND_LEVELS.md`). That is
  the remaining piece sitting on the wrong side of the "never design a
  feature twice" line, and it is the owner's to settle: migrate it upstream,
  grandfather it as Godot-only and say so in both repos, or retire it.
- **RUSH resolved itself the right way round** — the design went upstream and
  shipped there. Whatever this port does with Rush from now on is a port of a
  browser feature, not a second design, and the two should be reconciled
  against v224 rather than assumed to match.

**This is the owner's to settle, and nothing here should be extended until
they do.** The three obvious options, none of them free:
1. Migrate Rush + Challenges upstream into the browser build, then port them
   back the normal way — most work, but puts the design where the rule says
   it belongs and gets them played by more people.
2. Grandfather them as Godot-exclusive modes and say so out loud in both
   repos, so nobody later "fixes" the browser build to match.
3. Retire them here.

Whichever is chosen, **porting ROGUELIKE is not blocked by it** — that one is
a straight follow-the-lead port of a mode the browser already ships, and it
is the one mode gap this port has in the direction the rule points.

## Not ported yet — in priority order

Work that is *designed but not started* — including anything that lands in the
browser repo rather than here — is tracked in `QUEUE.md` with its own IDs; the
first entries there are the Rush mode proposal in `design/RUSH_MODE.md`. This
list stays the port's own ordered backlog.

Gameplay breadth first (each item is small and mostly mechanical), then the
visual landmarks from `PORT_BRIEF.md` §2 onward (each is a real R&D task):

**Re-audited 2026-08-26** (the previous pass had drifted stale — items
2-4 described the port's state from before weapons, touch and debris
existed, and read as done from the "Ported" section above; each is now
checked directly against the code rather than trusted from memory).

**Main.js classes surveyed 2026-08-26 and deliberately left unported**,
so the next hunt doesn't re-open them as if they were missed:
- `Civilian`, `Generator`, `KkCrate` — TOKOTRON/GAUNDROP/KAIKKI-exclusive
  (a tile dungeon, ghost-stream generators, a cash-crate minigame). Those
  modes were never in this port's scope; porting these would mean building
  the mode around them first.
- `ScreamRing`, `BubblePool`, `SplatPool` — pure visual polish (an
  expanding ring on SIREN's scream, floating bubble particles, pooled
  ground-decal puddles/slime trails) layered onto mechanics this port
  already has. No new gameplay, purely cosmetic; lower priority than
  anything above that changes what a run can do.
- `PoisonZone` — checked and it's already covered: this is SLUDGE_CUBE's
  walking poison trail, which is `poison_field.gd` here (`SludgeCube`'s
  `poison` wiring in `wave_director.gd`), not a separate gap.

1. ~~Enemy roster.~~ **Done, 2026-08-26.** The browser's full `tuning.js`
   `waves.pool` (21 types) is now entirely ported — CLOAKER, MAGNA, and
   DRAPER (this port's last three) closed it out; see the "Ported" section
   above. Next roster work, if any, is the browser's OTHER pools this port
   has never drawn from at all (`poolMelee`'s CLOSE COMBAT-only reskins,
   the TOKOTRON/SMASH-mode-exclusive types like TROOPER/THUG/PRISM/
   CUSTODIAN/GRUNT/TURRET/WRAITH) — a different scope, not a gap in this one.
2. ~~Kill particles.~~ **Done — checked 2026-08-26, was already in.**
   `debris_pool.gd` is a `MultiMeshInstance3D` pool with CPU ballistic
   integration + floor bounce, `burst()` called at every kill/hit site in
   `main.gd` with the source's own counts (22 kill droplets, 5 chunks, 8 hit
   droplets). Only the ground *splat decal* is still missing — that's
   `SplatPool` above, cosmetic-only.
3. ~~Player weapon modes.~~ **Done — checked 2026-08-26, was already in.**
   `player.gd` has SPREAD/SPREAD2/BURST/BURST2/LASER/LASER2/RAPID/RAPID2,
   `powerup_pool.gd` drops the pods (level-2 only from wave 4, 28% of the
   time), matching `main.js` `WEAPON_PODS`. HOMING/HOMING2 are implemented
   in `player.gd` but deliberately excluded from the drop table — that is
   the source's own rule (`enemy.js` v88: homing became BOTFLY-exclusive),
   not a gap; `powerup_pool.gd`'s header comment records it so it does not
   get "fixed" by mistake.
4. ~~Touch controls.~~ **Done — checked 2026-08-26, was already in.**
   `input_manager.gd` fully implements the browser's dual virtual-stick
   scheme (`js/input.js`): left-half move stick, right-half aim stick that
   autofires and dashes on release, a top-centre pause strip, tap-to-dash,
   plus the Rush-only boost pad/scheme toggle. See the HUD/touch section
   above for the fixes that made it actually usable on a real phone.
5. ~~Verlet tentacles~~ **Done, 2026-08-27** (`PORT_BRIEF.md` §2b) — the
   landmark "alive" feature the brief is written around.
   `scripts/tentacle.gd` is a verlet chain (8 segments, gravity, 3 relaxation
   passes, floor clamp INSIDE the iteration so a limb piles and drags rather
   than sliding through). The hero enemy is the **boss**: `apply_boss()`
   already promotes exactly one body every 8th wave, so the per-segment cost
   is rate-limited without a separate cap. Swarm bodies stay bare — the
   brief's own answer for those is a baked VAT, which is item 9.
   Two deliberate divergences from the brief's code sketch, both for reasons
   this repo already had written down:
   - **Stepped by an explicit `update(delta)`, never `_physics_process`**
     (the sketch uses the latter). `CLAUDE.md`'s rule is that enemies are
     driven by `WaveDirector`, and that is what makes pause free — a
     `_physics_process` would keep the limbs swinging on the pause screen.
   - **Drawn as one `MultiMeshInstance3D` of tapered beads**, not a skinned
     `Skeleton3D` or a per-frame tube mesh (the brief offers both): one draw
     call, no per-frame geometry allocation, and beads suit a body already
     made of gel — `debris_pool.gd` renders the same way.
   Three visual passes were needed and each failure is worth keeping, because
   all three looked fine in code and only a capture showed them:
   rooting the limbs UNDER the body put every root at floor height, so the
   floor clamp pinned the chain on frame one and the solver could only splay
   the beads into a stiff star; rooting them near the axis hid them entirely
   inside a wide squat boss, with only the root bead poking through the top;
   and a taper down to 0.34 shrank the tip beads below the segment spacing,
   turning the limb into a dotted line. Roots now sit at the RIM, level with
   the body's own centre height, derived from `base_shape` rather than from
   one radius — bodies here are squat domes as often as spheres.
   Covered by `_test_tentacles` (7 checks): the chain holds together, stays
   pinned to its body, never sinks below the floor, and the tip LAGS a moving
   root rather than teleporting with it — that lag being the drag the brief
   actually asks for, and the one thing a still frame cannot show.
6. **Drip particles** — **half done, 2026-08-27.** `scripts/drip_pool.gd`
   delivers §3's stated result ("droplets slide down the body, fall, splat
   on the floor and spread"): gel lets go of the lower silhouette of every
   BLOB-family body, falls, stretches as it goes, lands and spreads into a
   flattening disc. Cubes stay dry — they are the same gel but read as
   SOLID (flat faces, `wobble_amp` 0), and gel running off a hard edge reads
   as a leak rather than as something moist.
   **Deliberately NOT `GPUParticles3D`, which is what §3's snippet reaches
   for**, and the reason is in that snippet's own performance note:
   "thousands of particles at 60fps on mobile **via Vulkan**". The web build
   runs `gl_compatibility` (WebGL2 — `project.godot` says so under
   `[rendering]`), where the two things the snippet actually depends on,
   `collision_mode = COLLISION_RIGID` and a collision sub-emitter, are not
   the safe bet they are under Vulkan. Building the landmark "moist" feature
   on a path that works on the desktop it is tested on and silently does
   nothing in the browser it is played in is precisely the `SystemFont` bug
   this port already shipped once. One shared CPU pool drawn as a single
   MultiMesh instead — the pattern `debris_pool.gd` and `trail_pool.gd`
   already use — which is one draw call for every droplet in the arena and
   behaves identically on both renderers.
   Covered by `_test_drips` (5 checks): a drip falls, lands rather than
   passing through the floor, becomes a splat, fades instead of piling up,
   and over-emitting recycles rather than growing the pool. That lifecycle
   is the whole feature and no single frame shows it.
   **The dew is in too, so §3 is closed.** `gel.gdshader` grows a
   `fract`-tiled lattice of hemisphere bumps perturbing `NORMAL_MAP`, with
   droplets also made glossier than the body under them — that roughness
   CONTRAST is the glisten; without it the bumps read as texture rather than
   as wet. Generated in-shader rather than authored as a texture: cheaper to
   compute than to sample, no asset, and tunable live from a uniform.
   `dew_amount` defaults to 0 so nothing that does not opt in changes look;
   blobs get 0.42, cubes stay at 0 for the same reason they stay dry.
   Verified by EXAGGERATING it first (amount 1.0, tiling 7) and capturing the
   Web build — at that setting the bumps are unmistakable, which is what
   proved `NORMAL_MAP` survives `gl_compatibility` at all, and only then
   dialled back to a glisten. At the shipping value the effect is subtle
   enough that a screenshot alone could not have told "working" from "doing
   nothing", which is exactly why the exaggerated pass came first.
7. ~~Trails~~ — **Done, checked 2026-08-26.** `trail_pool.gd` exists and is
   wired into `main.gd`.
8. **Death FX (visual half)** (`PORT_BRIEF.md` §5) — **the material half is
   done, 2026-08-27.** Death chunks and drips now use `gel.gdshader` itself
   rather than a plain lit material, so they scatter, rim and bloom like the
   bodies they came off — §5's "so they refract and bloom as they fly". The
   shader grows a `use_instance_color` switch: a MultiMesh whose instances
   each carry a colour can share ONE gel material, which keeps the whole
   arena's debris at one draw call.
   **Not done, and deliberately:** §5's `RigidBody3D` chunks and `SoftBody3D`
   SPLITTA tear. `debris_pool.gd` already does ballistic motion with a floor
   bounce for a few hundred chunks in one draw call; converting that to dozens
   of rigid bodies per death would cost more and control less. The genuine gap
   was the MATERIAL, and that is what got closed. Revisit the soft-body tear
   only if SPLITTA's split actually needs to deform rather than scale.
   Two traps paid for here, both of which looked like the same bug:
   - a MultiMesh's per-instance colour is available as `COLOR` in the VERTEX
     stage; the fragment stage needs it passed through an explicit `varying`.
     The owner's own Godot notes already warn that MultiMesh instance colours
     fail SILENTLY, and this is the shader-side face of that.
   - with `rim_color` left on its white default, the fresnel rim SWAMPED every
     chunk. On a body most of the surface faces the camera so the rim is a
     thin edge; on a 6cm chunk almost the whole surface is near-silhouette, so
     every chunk rendered white regardless of its colour — which looks exactly
     like "instance colour never arrives", and is not. The rim follows the
     instance colour now.
   And one non-bug worth recording, because it burned three export cycles:
   debris lives ~1s, so a screenshot taken a moment too late shows an empty
   arena and reads as "nothing renders". It was only settled by bursting
   debris EVERY FRAME so the timing could not hide it.
9. **Compositor passes** — chromatic aberration, heat shimmer
   (`PORT_BRIEF.md` §6).
10. Screen-space refraction in `gel.gdshader` itself (currently approximated
    with plain alpha blending — see the shader's own header comment).

The remaining open items (5, 6, 8, 9, 10) are all `PORT_BRIEF.md` visual
landmarks — each is a real R&D task, not a mechanical port, and none of
them change what a run can do. Gameplay breadth is now believed complete
against `tuning.js`'s base-mode pool; the next *gameplay* gap, if one
exists, is more likely to turn up by playing than by re-reading this list.

## Side-by-side against the shipped browser build (2026-08-24)

The browser game was captured running (Playwright + a local server over the
real `toko-drop/` tree, scratch harness kept outside both repos) and compared
frame to frame against `tools/capture.gd` output. What that found, and what
was fixed in the same pass:

| | browser build | this port, before | now |
|---|---|---|---|
| Arena | **38 × 22**, wide landscape room | 18 × 18 square | 38 × 22 |
| Camera | `[0, 20.5, 13.5]` → `[0, 0, 2.5]`, fov 60 | derived guess, fov 55 | the source's, verbatim |
| Floor | pulsing cyan/violet neon **grid** | featureless grey slab | ported shader, same math |
| Border | `0x5555cc` violet | ad-hoc blue | `0x5555cc` |
| Fog | `0x0d0d1a`, 42→80 | none | ported |
| Blobs | squat grounded **domes** | round balls | `TUNING.blob.shape` per species |
| Player | Kirby eyes tracking aim | featureless white ball | eyes, on the surface |

**The arena was the big one.** A square 18 × 18 made every body look huge,
left no room to run, and framed nothing like the real game — the browser build
is a *wide room you cross*. Almost every other "this feels off" symptom was
downstream of it: bullets looked oversized because the arena was half the size
it should be, and waves bunched into the middle because they spawned on a
circle of the smaller half-extent (they use an ellipse now, one radius per
axis, or the wide ends of the room stay empty).

Two deliberate DIVERGENCES from the source, both recorded because they are
choices rather than drift:

1. **The floor grid is emissive-on-lit, not `MeshBasicMaterial` unlit.** The
   lines glow and bloom identically, but the plane still receives the cast
   shadows this port has, and a body's contact shadow is most of how you read
   where it actually is on the plane.
2. **The eyes sit ON the body surface, not inside it.** The browser can embed
   them at 0.4 of a 0.5 radius because its player is transmissive gel; this
   port's gel is opaque, which is what buys it real SSS, so embedded eyes
   render as nothing at all (the first attempt was a blank white ball).

Still different, and still open: the browser's per-species **motion trails**
(the streak marks the swarm leaves on the floor — `TRAIL_CFG` in `enemy.js`,
and item 7 below), and its HUD layout (WAVE plus a wave-progress bar top-left
with HP pips beneath it, score top-right; this port runs HP / WAVE / SCORE
across one top row).

## What the first render showed (2026-08-24)

Fixed in the same pass: the HUD layout bug, camera framing (now derived from
`HALF_X`/`HALF_Z` so resizing the arena cannot silently push it off-screen
again), and an emissive rail on the clamp line so the arena has a visible
edge.

~~1. **The gel does not read as gel.**~~ **Done** — see Material above. Bodies
   now have a translucent interior, a wet highlight and real cast shadows.
   Two things only a render could have caught, both fixed in the same pass:
   the hashed alpha turned every body to TV static at the default 0.9 alpha,
   and the player's *smooth* mercy-flicker ramp through that hash read as
   broken graphics rather than i-frames (it is a square 12Hz mesh blink now,
   which is what the source does too).

Still open, in the order they hurt:

~~1. **The player has no identity.**~~ **Done** — eyes ported, see above.

~~2. **The floor is a featureless slab.**~~ **Done** — the browser's neon grid
   is ported, which was `PORT_BRIEF.md` §6's arena pass in its shipped form.

## Known gaps / deliberate simplifications

- Blob geometry is a plain `SphereMesh`, not the SDF gel-dome from
  `TOKO_DROP_PORT_BRIEF.md` Part 2 (flat-bottomed dome, origin at floor
  contact). Enemies currently rest with their mesh center offset up by
  `radius`, which is visually close enough for a first pass but not the
  real geometry.
- ~~No score/wave persistence~~ **Stale as of 2026-08-26 — this is done.**
  `save_service.gd` writes `user://toko_drop.json` (the `user://`
  equivalent of `localStorage`), keyed per mode bucket (`hi_score`, `runs`);
  daily-run seeding and challenge-level grades ride on the same file.
- Camera is a fixed angled `Camera3D`, not a scene-relative rig — now with
  separate landscape/portrait presets (see the dual-arena fix above) rather
  than one fixed frame, but still not scene-relative. Revisit if the arena
  ever needs to change shape mid-run rather than only at the title screen.
