## level.gd — an AUTHORED level, read from the SAME JSON the browser build
## plays. Q-032.
##
## The file is upstream's `toko-drop/levels/<id>.json` (format 1, written by
## `toko-drop/js/level.js`, v237). It reaches this project through
## `tools/sync-levels.sh` into the git-ignored `levels/` — never by hand, and
## never through an exporter with an allow-list: Eeri's exporter silently
## dropped two part types for two versions that way. Godot parses JSON
## natively, so there is no translation step to drop a field in.
##
## Validation is STRICT and mirrors level.js clause for clause (an unknown key
## is an error, moving shapes and pickups are refused by name), so a level
## that this build refuses is one the browser refuses too. The one number
## the two loaders share, MAX_SHAPES, is the floor's slot count; if a level
## names more shapes than a floor can draw it must not load anywhere.
class_name Level
extends RefCounted

const FORMAT := 1
const MAX_SHAPES := 4

const TOP_KEYS    := ["format", "id", "name", "arena", "duration", "spawns", "rules"]
const ARENA_KEYS  := ["combine", "shapes"]
const RECT_KEYS   := ["kind", "hx", "hz"]
const CIRCLE_KEYS := ["kind", "c", "r"]
const SPAWN_KEYS  := ["t", "type", "px", "pz", "speedMult", "intervalMult"]
const RULE_KEYS   := ["mode", "outside"]
const MODES       := ["arcade"]
const OUTSIDE     := ["push"]

var id := ""
var name := ""
var duration := 0.0
var arena_shape: Arena.Shape = null
var half_x := 0.0
var half_z := 0.0
## Each: {t, type (name), px, pz, speed_mult, interval_mult}, in authored order.
var spawns: Array = []
var rules := {}
## Every problem found, as text. Empty when the level loaded.
var errors: PackedStringArray = []


static func _is_num(v) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))


static func _unknown_keys(d: Dictionary, allowed: Array, where: String, errs: PackedStringArray) -> void:
	for k in d.keys():
		if not allowed.has(String(k)):
			errs.append('%s: unknown key "%s"' % [where, k])


## Every problem in the file, as text — the same clauses as level.js.
static func validate(json, type_names: Array) -> PackedStringArray:
	var errs: PackedStringArray = []
	if typeof(json) != TYPE_DICTIONARY:
		errs.append("level: not an object")
		return errs
	_unknown_keys(json, TOP_KEYS, "level", errs)
	if not json.has("format") or not _is_num(json["format"]) or int(json["format"]) != FORMAT:
		errs.append("level: format must be %d" % FORMAT)
	var id_re := RegEx.create_from_string("^[a-z0-9][a-z0-9-]*$")
	if typeof(json.get("id")) != TYPE_STRING or id_re.search(json["id"]) == null:
		errs.append("level: id must be a lowercase slug")
	if typeof(json.get("name")) != TYPE_STRING or json["name"].is_empty():
		errs.append("level: name must be a non-empty string")
	if not _is_num(json.get("duration")) or float(json["duration"]) <= 0.0:
		errs.append("level: duration must be a positive number of seconds")

	var A = json.get("arena")
	if typeof(A) != TYPE_DICTIONARY:
		errs.append("arena: missing")
	else:
		_unknown_keys(A, ARENA_KEYS, "arena", errs)
		if A.has("combine") and A["combine"] != "union" and A["combine"] != "intersect":
			errs.append('arena: combine must be "union" or "intersect"')
		var shapes = A.get("shapes")
		if typeof(shapes) != TYPE_ARRAY or shapes.is_empty():
			errs.append("arena: shapes must be a non-empty array")
		else:
			if shapes.size() > 1 and not A.has("combine"):
				errs.append("arena: several shapes need a combine")
			if shapes.size() > MAX_SHAPES:
				errs.append("arena: at most %d shapes (the floor draws that many)" % MAX_SHAPES)
			for i in shapes.size():
				var s = shapes[i]
				var w := "arena.shapes[%d]" % i
				if typeof(s) != TYPE_DICTIONARY:
					errs.append("%s: not an object" % w)
					continue
				var kind = s.get("kind")
				if kind == "rect":
					_unknown_keys(s, RECT_KEYS, w, errs)
					if not _is_num(s.get("hx")) or float(s["hx"]) <= 0.0 or not _is_num(s.get("hz")) or float(s["hz"]) <= 0.0:
						errs.append("%s: rect needs positive hx and hz" % w)
				elif kind == "circle":
					_unknown_keys(s, CIRCLE_KEYS, w, errs)
					var c = s.get("c")
					if typeof(c) != TYPE_ARRAY or c.size() != 2 or not _is_num(c[0]) or not _is_num(c[1]):
						errs.append("%s: circle needs c: [x, z]" % w)
					if not _is_num(s.get("r")) or float(s["r"]) <= 0.0:
						errs.append("%s: circle needs a positive r" % w)
				else:
					errs.append("%s: unknown kind %s (format %d knows rect, circle)" % [w, JSON.stringify(kind), FORMAT])
				if s.has("move"):
					errs.append('%s: "move" is not in format %d (moving shapes are upstream P3)' % [w, FORMAT])

	var S = json.get("spawns")
	if typeof(S) != TYPE_ARRAY:
		errs.append("spawns: must be an array")
	else:
		var prev_t := -INF
		for i in S.size():
			var s = S[i]
			var w := "spawns[%d]" % i
			if typeof(s) != TYPE_DICTIONARY:
				errs.append("%s: not an object" % w)
				continue
			if s.has("kind"):
				errs.append('%s: "kind" is not in format %d (pickups are P2); every spawn is an enemy' % [w, FORMAT])
			_unknown_keys(s, SPAWN_KEYS, w, errs)
			if not _is_num(s.get("t")) or float(s["t"]) < 0.0:
				errs.append("%s: t must be a non-negative number of seconds" % w)
			else:
				var t := float(s["t"])
				if absf(t * 10.0 - roundf(t * 10.0)) > 1e-9:
					errs.append("%s: t=%s is not on the 0.1 s grid" % [w, t])
				if t < prev_t:
					errs.append("%s: t=%s is earlier than the previous spawn (%s) — author in order" % [w, t, prev_t])
				prev_t = t
				if _is_num(json.get("duration")) and t > float(json["duration"]):
					errs.append("%s: t=%s is past the level's duration (%s)" % [w, t, json["duration"]])
			if typeof(s.get("type")) != TYPE_STRING or not type_names.has(s["type"]):
				errs.append("%s: unknown enemy type %s" % [w, JSON.stringify(s.get("type"))])
			if not _is_num(s.get("px")) or not _is_num(s.get("pz")):
				errs.append("%s: px and pz are required (an authored level places every body)" % w)
			for mk in ["speedMult", "intervalMult"]:
				if s.has(mk) and (not _is_num(s[mk]) or float(s[mk]) <= 0.0):
					errs.append("%s: %s must be a positive number" % [w, mk])
		if S.is_empty():
			errs.append("spawns: a level with nothing in it is not a level")

	var R = json.get("rules")
	if typeof(R) != TYPE_DICTIONARY:
		errs.append("rules: missing")
	else:
		_unknown_keys(R, RULE_KEYS, "rules", errs)
		if not MODES.has(R.get("mode")):
			errs.append("rules: mode must be one of %s" % ", ".join(MODES))
		if R.has("outside") and not OUTSIDE.has(R["outside"]):
			errs.append("rules: outside must be one of %s (owner decision 2026-09-04: push)" % ", ".join(OUTSIDE))
	return errs


static func shape_from_spec(spec: Dictionary) -> Arena.Shape:
	if spec["kind"] == "rect":
		return Arena.rect_shape(float(spec["hx"]), float(spec["hz"]))
	return Arena.circle_shape(float(spec["c"][0]), float(spec["c"][1]), float(spec["r"]))


static func arena_shape_from(json: Dictionary) -> Arena.Shape:
	var parts: Array = []
	for s in json["arena"]["shapes"]:
		parts.append(shape_from_spec(s))
	if parts.size() == 1:
		return parts[0]
	return Arena.union_shape(parts) if json["arena"].get("combine") == "union" else Arena.intersect_shape(parts)


## Validates, then builds. A Level with a non-empty `errors` did not load;
## every field of a loaded one is trustworthy. `type_names` is the director's
## roster (WaveDirector.KNOWN_TYPES) — passed in so this file stays pure.
static func parse(json, type_names: Array) -> Level:
	var lv := Level.new()
	lv.errors = validate(json, type_names)
	if not lv.errors.is_empty():
		return lv
	var shape := arena_shape_from(json)
	var probe := Arena.new(shape)
	# A static shape must have somewhere to stand at t=0, or the level is a
	# wall: the origin (where the player starts), else a coarse grid.
	if not probe.contains(0.0, 0.0, 0.5):
		var ok := false
		var x := -probe.half_x
		while x <= probe.half_x and not ok:
			var z := -probe.half_z
			while z <= probe.half_z and not ok:
				ok = probe.contains(x, z, 0.5)
				z += 1.0
			x += 1.0
		if not ok:
			lv.errors.append("level %s: the arena has nowhere to stand" % json["id"])
			return lv
	for i in json["spawns"].size():
		var s: Dictionary = json["spawns"][i]
		if not probe.contains(float(s["px"]), float(s["pz"]), 0.0):
			lv.errors.append("level %s: spawns[%d] (%s, %s) is outside the arena" % [json["id"], i, s["px"], s["pz"]])
	if not lv.errors.is_empty():
		return lv
	lv.id = json["id"]
	lv.name = json["name"]
	lv.duration = float(json["duration"])
	lv.arena_shape = shape
	lv.half_x = probe.half_x
	lv.half_z = probe.half_z
	for s in json["spawns"]:
		lv.spawns.append({
			"t": float(s["t"]), "type": String(s["type"]),
			"px": float(s["px"]), "pz": float(s["pz"]),
			"speed_mult": float(s.get("speedMult", 1.0)), "interval_mult": float(s.get("intervalMult", 1.0)),
		})
	lv.rules = { "mode": json["rules"]["mode"], "outside": json["rules"].get("outside", "push") }
	return lv


## Reads and parses `res://levels/<id>.json` (or any path). A missing file is
## an error like any other — never a silent empty level.
static func load_file(path: String, type_names: Array) -> Level:
	if not FileAccess.file_exists(path):
		var lv := Level.new()
		lv.errors.append("level: %s not found — run tools/sync-levels.sh" % path)
		return lv
	var text := FileAccess.get_file_as_string(path)
	var json = JSON.parse_string(text)
	if json == null:
		var lv := Level.new()
		lv.errors.append("level: %s is not valid JSON" % path)
		return lv
	return parse(json, type_names)


## The pump's queue: a COPY of the spawns sorted by t, authored order winning
## ties (Godot's sort is not stable, so the index is the tiebreak). No rng —
## the same file yields the same schedule, which is what the cross-build
## parity gate (tools/level-parity.mjs) compares against the browser.
func schedule() -> Array:
	var out: Array = []
	for i in spawns.size():
		var e: Dictionary = spawns[i].duplicate()
		e["_i"] = i
		out.append(e)
	out.sort_custom(func(a, b): return a["t"] < b["t"] if a["t"] != b["t"] else a["_i"] < b["_i"])
	for e in out:
		e.erase("_i")
	return out
