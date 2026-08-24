## save_service.gd — hi-score and run history, per mode.
##
## TOKO_DROP_ROADMAP.md Phase 4 ("Full Meta", the Early Access gate) lists
## "Score model, end-of-run summary, local bests, daily seed" — all shipped in
## the browser build. This covers the local bests and the run history; the daily
## seed is still open (design/DETERMINISM_AND_SEEDS.md).
##
## The browser keeps these in localStorage; `user://` is the direct equivalent.
## Nothing leaves the machine, exactly as in the source — there is no
## leaderboard and no network call anywhere in this project.
##
## SCHEMA v2 — per-mode buckets. v1 was flat and MODE-BLIND
## (`{hi_score, runs}`), so the first Rush run would have overwritten the
## Normal best with a number from a different game (design/RUSH_MODE.md §7).
## It also had no version field, so the migration keys off the shape: a parsed
## dictionary with no `"v"` is v1. `levels` is reserved here rather than added
## later because the campaign's per-level records are a DIFFERENT shape from a
## run list, and bolting them on afterwards would cost a v3 migration for
## nothing (design/CAMPAIGN_LEVELS.md §4).
class_name SaveService
extends Node

const PATH := "user://toko_drop.json"
const VERSION := 2
const HISTORY_MAX := 10   # js/main.js keeps the last 10 runs, newest first

const MODE_NORMAL := "normal"
const MODE_RUSH := "rush"

## Overridable so tests can point at a scratch file. A gate that writes to the
## player's real save is a gate that eats their hi-score — the first version of
## tests/smoke.gd did exactly that, and a capture run afterwards showed
## "BEST 900" from a number the test had invented.
var path := PATH

## Which bucket `hi_score` / `runs` / `record()` read and write. Set this before
## touching them; everything else follows from it.
var mode := MODE_NORMAL

## mode name -> {"hi_score": int, "runs": Array}
var modes := {}
## level id -> {"best_score": int, "grade": String, "goals": Array}
var levels := {}

## The current mode's best. Kept as a property so main.gd and the death screen
## read the same name they always did, while the storage underneath is per-mode.
var hi_score: int:
	get:
		return int(_bucket().get("hi_score", 0))
	set(value):
		_bucket()["hi_score"] = value

## The current mode's run history, newest first.
var runs: Array:
	get:
		return _bucket()["runs"]
	set(value):
		_bucket()["runs"] = value

func _ready() -> void:
	load_state()

func _bucket(m := "") -> Dictionary:
	var key: String = m if m != "" else mode
	if not modes.has(key):
		modes[key] = {"hi_score": 0, "runs": []}
	return modes[key]

func load_state() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return          # corrupt or hand-edited: start clean rather than crash

	if not parsed.has("v"):
		# v1: flat and mode-blind. NOT corrupt, just older — carry it across
		# rather than discarding a real save because it lacks a field.
		_migrate_v1(parsed)
		save_state()    # stamp v2 so this only ever happens once
		return

	var m = parsed.get("modes", {})
	modes = m if typeof(m) == TYPE_DICTIONARY else {}
	var l = parsed.get("levels", {})
	levels = l if typeof(l) == TYPE_DICTIONARY else {}

## Moves a v1 payload under `modes.normal` verbatim. Idempotent: running it on
## an already-migrated in-memory state yields the same result.
func _migrate_v1(parsed: Dictionary) -> void:
	var b := _bucket(MODE_NORMAL)
	b["hi_score"] = int(parsed.get("hi_score", 0))
	var r = parsed.get("runs", [])
	b["runs"] = r if typeof(r) == TYPE_ARRAY else []

func save_state() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": VERSION, "modes": modes, "levels": levels}))
	f.close()

## Records a finished run in the current mode. Returns true if it beat that
## mode's stored best, so the death screen can say so.
##
## `wave` is only stored for the wave-based mode. Rush has no waves — its
## virtual wave is an internal escalation clock — and printing one on a Rush
## summary would be a lie, so pass its `kills` / `heat_peak` through `extra`
## instead (design/RUSH_MODE.md §7).
func record(score: int, wave: int, extra: Dictionary = {}) -> bool:
	var b := _bucket()
	var best: bool = score > int(b.get("hi_score", 0))
	if best:
		b["hi_score"] = score

	var entry := {
		"score": score,
		"at": Time.get_datetime_string_from_system(true),
	}
	if mode == MODE_NORMAL:
		entry["wave"] = wave
	for k in extra:
		entry[k] = extra[k]

	var list: Array = b["runs"]
	list.push_front(entry)
	while list.size() > HISTORY_MAX:
		list.pop_back()
	save_state()
	return best

## Records an attempt at a campaign level. Keeps only the BEST attempt — a
## level's record is its high-water mark, not a history (design/CAMPAIGN_LEVELS.md
## §3). Returns true if this attempt improved it.
func record_level(id: String, score: int, grade: String, goals: Array = []) -> bool:
	var prev: Dictionary = levels.get(id, {})
	var better: bool = score > int(prev.get("best_score", -1))
	if better:
		levels[id] = {"best_score": score, "grade": grade, "goals": goals}
		save_state()
	return better

func level_best(id: String) -> Dictionary:
	return levels.get(id, {})

## The last few runs of the current mode, formatted for the death screen. Skips
## index 0 — that is the run you are already looking at the big number for, and
## showing it twice is the redundancy hyperdagger's own death recap calls out.
##
## The suffix is per-mode: a wave number for the wave mode, a kill count for
## Rush, because those are the figures each mode actually earns.
func recent_line(count := 3) -> String:
	var list: Array = _bucket()["runs"]
	if list.size() < 2:
		return ""
	var parts: Array[String] = []
	for i in range(1, mini(list.size(), count + 1)):
		var r: Dictionary = list[i]
		var score := int(r.get("score", 0))
		if r.has("wave"):
			parts.append("%d (w%d)" % [score, int(r["wave"])])
		elif r.has("kills"):
			parts.append("%d (%d kills)" % [score, int(r["kills"])])
		else:
			parts.append("%d" % score)
	return "recent: " + " · ".join(parts)
