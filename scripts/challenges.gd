## challenges.gd — the campaign: a list of levels, each one a RULE.
##
## Owner direction (2026-08-25), and the shape is Geometry Wars 3's Adventure
## mode: a sequence of named levels you unlock one at a time, where the level
## is not just a different spawn table but a different set of rules. GW3's
## identity is Pacifism / Deflector / King / Waves; ours is BOOST ONLY /
## CLOSE QUARTERS / ONE LIFE / ARTILLERY / SWARM / GRAVEYARD.
##
## Decided:
##  - **Levels are TIMED.** The first three run a fixed clock and your score at
##    the buzzer is the grade. (Other challenge shapes exist in Blade Rush and
##    may follow; these three are timed.)
##  - **Unlock at tier C or better.** Not A — a player who is merely finishing
##    keeps moving. Grades above C are for the player who wants them.
##  - **Thresholds are MEASURED per level**, not derived from one formula. A
##    BOOST ONLY level has a completely different kill rate from an ARTILLERY
##    one, so a shared formula would be wrong on both. `tools/measure.gd` runs
##    a level headless and prints the percentiles the table below is authored
##    from; anything not yet measured is marked ESTIMATED.
##  - **Abilities unlock over the campaign** rather than all being available
##    from level 1 (GW3's drones do the same).
##
## Everything about a level is DATA. The rules are read by main.gd when a run
## starts; adding a level is an entry here, not new code.
class_name Challenges
extends RefCounted

## The rule twists. Each one bends a system the game already has, which is why
## they are cheap: no new subsystems, just parameters read at run start.
enum Rule {
	NONE,           # a straight fight
	BOOST_ONLY,     # the gun is disabled; boosting through bodies is the only kill
	CLOSE_QUARTERS, # the arena clamps down; boost stops being an escape
	ONE_LIFE,       # lives = 1
	ARTILLERY,      # shooters only, shooter cap lifted
	SWARM,          # melee only, body cap raised
	GRAVEYARD,      # revenge volleys amplified — corpses are the puzzle
	FOCUS,          # the support species arrive early — break off or drown
}

const RULE_NAME := {
	Rule.NONE: "",
	Rule.BOOST_ONLY: "BOOST ONLY",
	Rule.CLOSE_QUARTERS: "CLOSE QUARTERS",
	Rule.ONE_LIFE: "ONE LIFE",
	Rule.ARTILLERY: "ARTILLERY",
	Rule.SWARM: "SWARM",
	Rule.GRAVEYARD: "GRAVEYARD",
	Rule.FOCUS: "FOCUS",
}

const RULE_BLURB := {
	Rule.NONE: "a straight fight",
	Rule.BOOST_ONLY: "no gun — boost through them or nothing",
	Rule.CLOSE_QUARTERS: "a smaller arena; nowhere to run to",
	Rule.ONE_LIFE: "one life, no second chance",
	Rule.ARTILLERY: "shooters only — read the bullets",
	Rule.SWARM: "bodies only, and a lot of them",
	Rule.GRAVEYARD: "every corpse bites back, harder",
	Rule.FOCUS: "shepherds and sirens — kill the conductor first",
}

## Levels, in order. `tiers` is [C, B, A, S] score thresholds.
##
## `measured` true means the thresholds came out of tools/measure.gd: a fixed
## yardstick bot plays the level ten times and the tiers are set as multiples
## of its median. The bot plays like a competent first-timer, so C sits just
## under it and the higher letters demand play it cannot manage. Re-run the
## tool whenever a level's rule or spawn budget changes.
##
## `measured` false means the numbers are a guess. Marking it is the point: a campaign where some levels have real
## numbers and others have guesses, silently, is how A becomes routine on one
## level and impossible on the next.
const LEVELS := [
	{
		"id": "L1", "name": "FIRST LIGHT",
		"rule": Rule.NONE, "duration": 60.0, "difficulty": 2,
		"tiers": [6400, 11550, 17950, 26500], "measured": true,
		"unlocks_ability": -1,
	},
	{
		"id": "L2", "name": "COLD START",
		"rule": Rule.BOOST_ONLY, "duration": 60.0, "difficulty": 2,
		"tiers": [3800, 6800, 10600, 15650], "measured": true,
		# The mode's signature level hands you the ability that plays off it.
		"unlocks_ability": RushRules.Ability.HYPER_BOMB,
	},
	{
		"id": "L3", "name": "THE VICE",
		"rule": Rule.CLOSE_QUARTERS, "duration": 90.0, "difficulty": 3,
		"tiers": [7650, 13750, 21400, 31600], "measured": true,
		"unlocks_ability": -1,
	},
	{
		"id": "L4", "name": "CROSSFIRE",
		"rule": Rule.ARTILLERY, "duration": 60.0, "difficulty": 4,
		"tiers": [4650, 8350, 13000, 19200], "measured": true,
		"unlocks_ability": RushRules.Ability.QUANTUM_SHIELD,
	},
	{
		"id": "L5", "name": "THE TIDE",
		"rule": Rule.SWARM, "duration": 90.0, "difficulty": 4,
		"tiers": [5550, 10000, 15550, 22950], "measured": true,
		"unlocks_ability": -1,
	},
	{
		"id": "L6", "name": "CONDUCTOR",
		"rule": Rule.FOCUS, "duration": 90.0, "difficulty": 5,
		"tiers": [7550, 13550, 21100, 31150], "measured": true,
		"unlocks_ability": RushRules.Ability.OVERCHARGE,
	},
	{
		"id": "L7", "name": "AFTERLIFE",
		"rule": Rule.GRAVEYARD, "duration": 90.0, "difficulty": 5,
		"tiers": [10050, 18100, 28150, 41550], "measured": true,
		"unlocks_ability": -1,
	},
	{
		"id": "L8", "name": "THE NARROWS",
		"rule": Rule.CLOSE_QUARTERS, "duration": 90.0, "difficulty": 7,
		"tiers": [13550, 24350, 37900, 55950], "measured": true,
		"unlocks_ability": -1,
	},
	{
		"id": "L9", "name": "NO SECOND CHANCE",
		"rule": Rule.ONE_LIFE, "duration": 60.0, "difficulty": 6,
		"tiers": [8950, 16150, 25100, 37050], "measured": true,
		"unlocks_ability": -1,
	},
	{
		"id": "L10", "name": "BARE HANDS",
		"rule": Rule.BOOST_ONLY, "duration": 120.0, "difficulty": 8,
		"tiers": [10300, 18550, 28900, 42650], "measured": true,
		"unlocks_ability": -1,
	},
]


const TIER_LETTERS := ["C", "B", "A", "S"]

## CLOSE_QUARTERS clamps the arena to this fraction of its half-extents.
const CLOSE_QUARTERS_SCALE := 0.55

static func count() -> int:
	return LEVELS.size()

static func get_level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]

static func index_of(id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i]["id"] == id:
			return i
	return -1

## The grade for a score, as a letter, or "" below C. Below C shows the score
## with no letter — the same rule Rush uses.
static func grade_for(level: Dictionary, score: int) -> String:
	var tiers: Array = level["tiers"]
	var out := ""
	for i in tiers.size():
		if score >= int(tiers[i]):
			out = TIER_LETTERS[i]
	return out

## Tier C or better clears a level (owner direction). Anything below is a
## score you can be proud of and still have to try again.
static func cleared(level: Dictionary, score: int) -> bool:
	return score >= int(level["tiers"][0])

## A level is playable if it is the first, or the one before it was cleared.
static func unlocked(i: int, save: SaveService) -> bool:
	if i <= 0:
		return true
	var prev: Dictionary = LEVELS[i - 1]
	var rec = save.levels.get(prev["id"], {})
	if typeof(rec) != TYPE_DICTIONARY:
		return false
	return String(rec.get("grade", "")) != ""

## Which abilities the player has earned, given what they have cleared.
## HEAT_EXCHANGE is always available; the rest arrive with the campaign.
static func unlocked_abilities(save: SaveService) -> Array[int]:
	var out: Array[int] = [RushRules.Ability.HEAT_EXCHANGE]
	for lv in LEVELS:
		var want: int = lv["unlocks_ability"]
		if want < 0:
			continue
		var rec = save.levels.get(lv["id"], {})
		if typeof(rec) == TYPE_DICTIONARY and String(rec.get("grade", "")) != "":
			if not out.has(want):
				out.append(want)
	return out
