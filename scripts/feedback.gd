## feedback.gd — the death screen's question, and where the answer goes.
##
## Ported from the browser build's v212 CONTEXTUAL FEEDBACK, whose own comment
## is the design argument:
##
##   "The generic 'what went wrong?' form asks every player the same thing
##    forever; this asks about the body you just lost to, shows it, and
##    rotates so repeat runs don't get the same prompt twice."
##
## So this is not a comment box. It remembers what killed you and how, picks
## the most specific question that fits, and skips anything it asked recently.
##
## ── Rules this inherits, and they are not negotiable ────────────────────────
##  - **Explicit consent.** The POST fires ONLY on SEND. SKIP sends nothing.
##  - **Never claim a delivery that did not happen.** Fire-and-forget: offline,
##    blocked or over quota all fail silently, and the UI never says "sent"
##    unless a request actually came back OK.
##  - **Saying nothing records nothing.** An empty submission is discarded
##    rather than filed as an empty opinion.
##  - **One GAME ID per cabinet, matching the arcade catalogue.** The browser
##    build shipped 'toko-drop' where its catalogue id was 'tokodrop', which
##    put the death screen's notes in a different bucket from everything else
##    said about the same game — invisible until you sort the sheet and find
##    two spellings. This is a DIFFERENT cabinet on that floor, so it files
##    under its own id.
class_name Feedback
extends Node

## The arcade catalogue id for this cabinet (hub/games.js). Must match exactly.
const GAME_ID := "tokodropgodot"

## The browser's documented fallback sink. Empty disables sending entirely and
## the UI then promises nothing — that is the honest default, not a broken one.
const ENDPOINT := "https://formspree.io/f/mdarbpve"

const ARCHIVE := "user://feedback.json"
const ASKED_MAX := 4        # how many recent prompts to avoid repeating

## How the fatal blow arrived. The question deck keys off this.
enum Cause { UNKNOWN, MELEE, BULLET, HAZARD }

## Ordered MOST SPECIFIC FIRST. The first entry that fits and has not been
## asked recently wins, so the deck works through its variety on its own.
const DECK := [
	{"id": "killer_read", "cause": Cause.MELEE, "needs_name": true,
	 "q": "You went down to a %s. Could you read what it was about to do?"},
	{"id": "killer_shot", "cause": Cause.BULLET, "needs_name": true,
	 "q": "A %s shot you. Did you see the shot coming, or did it arrive out of nowhere?"},
	{"id": "hazard", "cause": Cause.HAZARD, "needs_name": false,
	 "q": "The arena killed you, not an enemy. Did the hazard telegraph clearly enough?"},
	{"id": "swarm_read", "cause": Cause.UNKNOWN, "needs_name": true, "crowd": true,
	 "q": "You died in a crowd. With that many bodies on screen, could you still tell a %s apart?"},
	{"id": "movement", "cause": Cause.UNKNOWN, "needs_name": true,
	 "q": "How did the %s MOVE? Did it behave like its own creature, or like everything else?"},
	{"id": "general", "cause": Cause.UNKNOWN, "needs_name": false,
	 "q": "What was the last thing that surprised you in that run?"},
]

## What went wrong. Kept short enough to be a tappable chip.
const WRONG := [
	"too fast", "felt unfair", "got swarmed at once", "could not tell them apart",
]
## What landed. Mode-aware in the browser; ours asks about the systems this
## port actually has.
const LIKED := [
	"movement / boost feel", "bullet dodging", "the abilities", "the level rules",
]

var _asked: Array = []
var _http: HTTPRequest

## Tests point the archive at scratch; a gate that writes the player's real
## feedback file is a gate that files opinions they never had.
var archive_path := ARCHIVE

func path_override_for_test() -> void:
	archive_path = "user://_smoke_feedback.json"

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_load()

func _load() -> void:
	if not FileAccess.file_exists(archive_path):
		return
	var f := FileAccess.open(archive_path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) == TYPE_DICTIONARY:
		var a = d.get("asked", [])
		_asked = a if typeof(a) == TYPE_ARRAY else []

func _save(entries: Array) -> void:
	var existing: Array = []
	if FileAccess.file_exists(archive_path):
		var rf := FileAccess.open(archive_path, FileAccess.READ)
		if rf != null:
			var d = JSON.parse_string(rf.get_as_text())
			rf.close()
			if typeof(d) == TYPE_DICTIONARY:
				var n = d.get("notes", [])
				existing = n if typeof(n) == TYPE_ARRAY else []
	for e in entries:
		existing.push_front(e)
	while existing.size() > 50:
		existing.pop_back()
	var f := FileAccess.open(archive_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"asked": _asked, "notes": existing}))
	f.close()

## Picks a question for the run that just ended. `crowd` is how many bodies
## were alive at death — the deck has a prompt specifically about telling
## things apart in a crush.
func pick(cause: int, enemy_name: String, crowd: int) -> Dictionary:
	for entry in DECK:
		if _asked.has(entry["id"]):
			continue
		if entry["cause"] != Cause.UNKNOWN and entry["cause"] != cause:
			continue
		if bool(entry.get("needs_name", false)) and enemy_name == "":
			continue
		if bool(entry.get("crowd", false)) and crowd < 4:
			continue
		return _use(entry, enemy_name)
	# Everything recent — clear the memory and take the generic one.
	_asked.clear()
	return _use(DECK[DECK.size() - 1], enemy_name)

func _use(entry: Dictionary, enemy_name: String) -> Dictionary:
	_asked.push_front(entry["id"])
	while _asked.size() > ASKED_MAX:
		_asked.pop_back()
	var q: String = entry["q"]
	if bool(entry.get("needs_name", false)):
		q = q % enemy_name
	return {"id": entry["id"], "question": q}

## Files a note. Returns "" if there was nothing to file, "saved" when it was
## kept locally only, or "sent" once a POST actually succeeds (reported later
## via the returned signal on the request node).
func submit(prompt_id: String, answer: String, liked: Array, wrong: Array,
		run: Dictionary) -> String:
	# Saying nothing records nothing, rather than filing an empty opinion.
	if answer.strip_edges() == "" and liked.is_empty() and wrong.is_empty():
		return ""

	var note := {
		"game": GAME_ID,
		"build": "godot",
		"prompt": prompt_id,
		"answer": answer.strip_edges(),
		"liked": liked,
		"wrong": wrong,
		"at": Time.get_datetime_string_from_system(true),
	}
	for k in run.keys():
		note[k] = run[k]

	_save([note])
	if ENDPOINT == "":
		return "saved"          # no sink configured: promise nothing
	_post(note)
	return "saved"              # never claim delivery before it happens

func _post(note: Dictionary) -> void:
	# Fire and forget. Offline, ad-blocked or over quota all fail silently and
	# never touch what was already saved locally.
	if _http == null:
		return          # no request node yet (headless gate) — the note is saved
	var headers := ["Content-Type: application/json", "Accept: application/json"]
	_http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(note))
