## daily.gd — DAILY RUN.
##
## main.js v130 (roadmap M3): "everyone who flips the chip plays the same
## UTC-date-derived seed that day — no server needed." v179 (M6) adds DAILY
## MODIFIERS on the same principle: pure date math picks the day's twist, so
## every player worldwide lands on the same one without a handshake.
##
## Two calls, both pure functions of a "YYYY-MM-DD" string:
##   seed_for(date) — the run's gameplay seed (feeds WaveDirector.reseed()).
##   mod_for(date)  — today's twist, cycling ["", glass, surge, rich] every
##                     4 days off the day's position since the Unix epoch.
class_name Daily
extends RefCounted

## main.js DAILY_MODS rotation: a classic day, then GLASS / SURGE DAY / RICH
## DAY, repeating. Index 0 is "no modifier" (main.js's `null`).
const MODS: Array[String] = ["", "glass", "surge", "rich"]

## Today's UTC date as "YYYY-MM-DD" — the same shape `new
## Date().toISOString().slice(0, 10)` produces in the browser build.
static func today() -> String:
	return Time.get_date_string_from_system(true)

## main.js todaysMod(): `Math.floor(Date.UTC(y,m,d) / 86400000) % 4`, i.e.
## days since the Unix epoch, mod 4.
static func mod_for(date_str: String) -> String:
	var day := _epoch_day(date_str)
	return MODS[((day % 4) + 4) % 4]     # GDScript % can return negative; MODS can't take one

## main.js: `mulberry32(Number(date.replaceAll('-','')))() * 0xFFFFFF | 0`.
## mulberry32 is a 32-bit-float JS PRNG this port has no reason to reproduce
## bit-for-bit — the contract that matters is "every Godot player on the same
## UTC date gets the same seed", not cross-engine parity with the browser's
## own number. So this hashes the same input (the date with its dashes
## stripped) through a Thomas Wang integer mix instead of Godot's built-in
## `hash()`, which the engine does not promise to keep stable across
## versions — a seed that silently moves on a Godot upgrade defeats the
## entire point of a DAILY run.
static func seed_for(date_str: String) -> int:
	var n := int(date_str.replace("-", ""))
	return _wang_hash(n) & 0xFFFFFF

static func _wang_hash(n: int) -> int:
	var x := n & 0xFFFFFFFF
	x = ((x ^ 61) ^ (x >> 16)) & 0xFFFFFFFF
	x = (x + (x << 3)) & 0xFFFFFFFF
	x = (x ^ (x >> 4)) & 0xFFFFFFFF
	x = (x * 0x27d4eb2d) & 0xFFFFFFFF
	x = (x ^ (x >> 15)) & 0xFFFFFFFF
	return x

static func _epoch_day(date_str: String) -> int:
	var parts := date_str.split("-")
	var iso := "%s-%s-%sT00:00:00" % [parts[0], parts[1], parts[2]]
	var unix := Time.get_unix_time_from_datetime_string(iso)
	return int(floor(unix / 86400.0))
