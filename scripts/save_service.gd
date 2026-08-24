## save_service.gd — per-mode hi-scores and run history.
##
## TOKO_DROP_ROADMAP.md Phase 4 ("Full Meta", the Early Access gate) lists
## "Score model, end-of-run summary, local bests, daily seed". This covers the
## local bests and the run history; the daily seed is still open.
##
## The browser keeps these in localStorage; `user://` is the direct equivalent.
## Nothing leaves the machine — no leaderboard, no network call anywhere.
##
## ── Schema v2, and why the migration exists ────────────────────────────────
## v1 was `{"hi_score": int, "runs": [...]}` — mode-blind and unversioned. The
## moment Rush Mode shipped, a 3-minute Rush score landed in the same
## `hi_score` as the Normal best and the death screen began comparing runs
## that have nothing to do with each other. That was a real, silent data loss
## on every Rush run, and it was called before it happened, in
## `design/RUSH_MODE.md` §7 (PR #1, Q-006).
##
##   {"v": 2, "modes": {"normal": {"hi_score": int, "runs": [...]}, "rush": …}}
##
## Migration keys off the SHAPE, because v1 has no version to branch on: a
## parsed dictionary with no "v" key is v1, and its hi_score/runs move verbatim
## under modes.normal. A v1 file is not corrupt and must never be discarded.
class_name SaveService
extends Node

const PATH := "user://toko_drop.json"
const VERSION := 2
const HISTORY_MAX := 10   # js/main.js keeps the last 10 runs, newest first

const NORMAL := "normal"
const RUSH := "rush"

## Overridable so tests can point at a scratch file. A gate that writes to the
## player's real save is a gate that eats their hi-score.
var path := PATH

## mode key -> {"hi_score": int, "runs": Array}
var modes: Dictionary = {}

func _ready() -> void:
	load_state()

func _blank() -> Dictionary:
	return {"hi_score": 0, "runs": []}

func _ensure(mode: String) -> Dictionary:
	if not modes.has(mode):
		modes[mode] = _blank()
	return modes[mode]

func load_state() -> void:
	modes = {NORMAL: _blank(), RUSH: _blank()}
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
		# v1 — mode-blind. Everything it holds was a Normal run.
		modes[NORMAL] = {
			"hi_score": int(parsed.get("hi_score", 0)),
			"runs": parsed.get("runs", []) if typeof(parsed.get("runs", [])) == TYPE_ARRAY else [],
		}
		save_state()    # stamp it, once
		return

	var m = parsed.get("modes", {})
	if typeof(m) != TYPE_DICTIONARY:
		return
	for key in m.keys():
		var entry = m[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		modes[key] = {
			"hi_score": int(entry.get("hi_score", 0)),
			"runs": entry.get("runs", []) if typeof(entry.get("runs", [])) == TYPE_ARRAY else [],
		}

func save_state() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": VERSION, "modes": modes}))
	f.close()

func hi_score_for(mode: String) -> int:
	return int(_ensure(mode)["hi_score"])

func runs_for(mode: String) -> Array:
	return _ensure(mode)["runs"]

## Records a finished run under one mode. `extra` carries whatever that mode's
## summary needs — Normal stores `wave`; Rush stores `kills` and `heat_peak`,
## because "wave" is a virtual number there and printing it would be a lie.
## Returns true if this beat that mode's stored best.
func record(mode: String, score: int, extra: Dictionary = {}) -> bool:
	var m := _ensure(mode)
	var best: bool = score > int(m["hi_score"])
	if best:
		m["hi_score"] = score
	var row := {"score": score, "at": Time.get_datetime_string_from_system(true)}
	for k in extra.keys():
		row[k] = extra[k]
	var runs: Array = m["runs"]
	runs.push_front(row)
	while runs.size() > HISTORY_MAX:
		runs.pop_back()
	save_state()
	return best

## The last few runs of one mode, for the death screen. Skips index 0 — that is
## the run you are already looking at the big number for.
func recent_line(mode: String, count := 3) -> String:
	var runs := runs_for(mode)
	if runs.size() < 2:
		return ""
	var parts: Array[String] = []
	for i in range(1, mini(runs.size(), count + 1)):
		var r: Dictionary = runs[i]
		var sc := int(r.get("score", 0))
		if mode == RUSH:
			parts.append("%d (%dk)" % [sc, int(r.get("kills", 0))])
		else:
			parts.append("%d (w%d)" % [sc, int(r.get("wave", 0))])
	return "recent: " + " · ".join(parts)
