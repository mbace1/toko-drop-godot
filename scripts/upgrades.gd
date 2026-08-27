## upgrades.gd — ROGUELIKE's upgrade cards.
##
## Ported from the browser build's `applyUpgrade()` / `showUpgradeCards()`
## (`js/main.js`), which is the LEAD build for gameplay — see this repo's
## `CLAUDE.md`. The browser's ROGUELIKE toggle is three-state:
##
##   OFF — "No upgrades — pure arcade survival"
##   A   — "upgrade cards every 3rd wave"
##   B   — "cards + rare BONUS GAUNTLET runs (big multipliers)"
##
## This ports **A**. B's gauntlet runs are not here yet and the mode row says
## so rather than pretending otherwise.
##
## A note on what this port had before: its ROGUELIKE row was labelled "no
## upgrades — pure arcade survival", which is the browser's text for the mode
## being **OFF**. The row described the absence of the feature as though it
## were the feature.
class_name Upgrades

## Every card the browser can offer in ROGUELIKE, with its own `applyUpgrade`
## id kept verbatim so the two builds can be diffed by grep. `x_` ids are the
## browser's CURSED cards — a real gain paid for with a real loss.
##
## `hook` says who implements it, so an unported card cannot silently look
## implemented: "player" ones are live here; anything marked "pending" is
## listed for completeness and is NOT offered yet.
const CARDS := [
	{"id": "hp", "name": "VITALITY", "blurb": "+1 max HP, and heal 1",
	 "hook": "player"},
	{"id": "speed", "name": "QUICK FEET", "blurb": "move 20% faster",
	 "hook": "player"},
	{"id": "firerate", "name": "TRIGGER", "blurb": "fire 20% faster",
	 "hook": "player"},
	{"id": "dashcd", "name": "SHORT REST", "blurb": "dash recharges sooner",
	 "hook": "player"},
	{"id": "longdash", "name": "LONG DASH", "blurb": "dash lasts longer",
	 "hook": "player"},
	{"id": "nuke", "name": "CLEAR THE AIR", "blurb": "wipe every enemy bullet now",
	 "hook": "player"},
	# Cursed — the browser's `x_` family. A gain and a cost in one card.
	{"id": "x_berserk", "name": "BERSERK", "blurb": "fire much faster, lose 1 max HP",
	 "hook": "player"},
	{"id": "x_leadfeet", "name": "LEAD FEET", "blurb": "+2 max HP, but slower",
	 "hook": "player"},
]

## Cards the browser has that this port cannot honour yet, because the systems
## they hook into do not exist here. Listed rather than dropped so the gap is
## visible: bigbullets/pierce need bullet-scale and piercing on the pool,
## magnet/shield/dashboom need player state, graze/vampire/ripple/tiredlegs/
## minnow/x_gambler/x_glasscannon need scoring and hit hooks in main.gd.
const PENDING := [
	"bigbullets", "pierce", "magnet", "shield", "dashboom", "graze",
	"vampire", "ripple", "tiredlegs", "minnow", "x_gambler", "x_glasscannon",
]

## The browser offers THREE cards to choose from, and draws them without
## repeats within the offer.
const OFFER_SIZE := 3
## `wave % 3 == 0` in the browser (`js/main.js`: "cards every 3rd wave").
const EVERY_N_WAVES := 3

static func card_by_id(id: String) -> Dictionary:
	for c in CARDS:
		if c["id"] == id:
			return c
	return {}

## Draws an offer. `rng` is the run's GAMEPLAY stream — which cards you are
## offered is part of what a seed decides, so this must NOT use global randf()
## (`design/DETERMINISM_AND_SEEDS.md`; two players on one seed must see the
## same choices).
static func draw_offer(rng: RandomNumberGenerator, taken: Array) -> Array:
	var pool: Array = []
	for c in CARDS:
		# Repeatable cards can come round again; one-shot ones cannot. The
		# browser lets its stat cards stack, so only the cursed pair is capped.
		if String(c["id"]).begins_with("x_") and taken.has(c["id"]):
			continue
		pool.append(c)
	var out: Array = []
	while out.size() < OFFER_SIZE and pool.size() > 0:
		var i := rng.randi() % pool.size()
		out.append(pool[i])
		pool.remove_at(i)
	return out

## Applies one card. Mirrors the browser's `applyUpgrade` arm for arm; the
## numbers are its numbers.
static func apply(id: String, player, bullets) -> void:
	match id:
		"hp":
			player.max_hp += 1
			player.hp = mini(player.hp + 1, player.max_hp)
		"speed":
			player.up_speed_mult *= 1.2
		"firerate":
			player.up_fire_rate_mult *= 0.8
		"dashcd":
			# Browser: `max(0.2, mult - 0.15)` — a floor, so it cannot reach 0.
			player.up_dash_cd_mult = maxf(0.2, player.up_dash_cd_mult - 0.15)
		"longdash":
			# Browser: `min(1.7, mult * 1.3)`.
			player.up_dash_dur_mult = minf(1.7, player.up_dash_dur_mult * 1.3)
		"nuke":
			if bullets != null:
				bullets.clear_enemy_bullets()
		"x_berserk":
			player.up_fire_rate_mult *= 0.7
			_drop_max_hp(player, 1)
		"x_leadfeet":
			player.max_hp += 2
			player.hp = mini(player.hp + 2, player.max_hp)
			player.up_speed_mult *= 0.85

## The browser's `dropMaxHp` — max HP falls but never below 1, and current HP
## is clamped under it so a curse cannot leave you above your own ceiling.
static func _drop_max_hp(player, n: int) -> void:
	player.max_hp = maxi(1, player.max_hp - n)
	player.hp = mini(player.hp, player.max_hp)
