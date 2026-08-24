## save_service.gd — hi-score and run history.
##
## TOKO_DROP_ROADMAP.md Phase 4 ("Full Meta", the Early Access gate) lists
## "Score model, end-of-run summary, local bests, daily seed" — all shipped in
## the browser build, none of it in this port until now. This covers the local
## bests and the run history; the daily seed is still open.
##
## The browser keeps these in localStorage; `user://` is the direct equivalent.
## Nothing leaves the machine, exactly as in the source — there is no
## leaderboard and no network call anywhere in this project.
class_name SaveService
extends Node

const PATH := "user://toko_drop.json"
const HISTORY_MAX := 10   # js/main.js keeps the last 10 runs, newest first

## Overridable so tests can point at a scratch file. A gate that writes to the
## player's real save is a gate that eats their hi-score — the first version of
## tests/smoke.gd did exactly that, and a capture run afterwards showed
## "BEST 900" from a number the test had invented.
var path := PATH

var hi_score := 0
var runs: Array = []      # [{score, wave, at}], newest first

func _ready() -> void:
	load_state()

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
	hi_score = int(parsed.get("hi_score", 0))
	var r = parsed.get("runs", [])
	runs = r if typeof(r) == TYPE_ARRAY else []

func save_state() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"hi_score": hi_score, "runs": runs}))
	f.close()

## Records a finished run. Returns true if it beat the stored best, so the
## death screen can say so.
func record(score: int, wave: int) -> bool:
	var best := score > hi_score
	if best:
		hi_score = score
	runs.push_front({
		"score": score,
		"wave": wave,
		"at": Time.get_datetime_string_from_system(true),
	})
	while runs.size() > HISTORY_MAX:
		runs.pop_back()
	save_state()
	return best

## The last few runs, formatted for the death screen. Skips index 0 — that is
## the run you are already looking at the big number for, and showing it twice
## is the redundancy hyperdagger's own death recap calls out.
func recent_line(count := 3) -> String:
	if runs.size() < 2:
		return ""
	var parts: Array[String] = []
	for i in range(1, mini(runs.size(), count + 1)):
		parts.append("%d (w%d)" % [int(runs[i].get("score", 0)), int(runs[i].get("wave", 0))])
	return "recent: " + " · ".join(parts)
