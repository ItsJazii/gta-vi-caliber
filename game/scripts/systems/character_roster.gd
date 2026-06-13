class_name CharacterRoster
extends RefCounted
## Pure dual-protagonist roster — the modern open-world "switch between playable
## leads" mechanic. Each character keeps INDEPENDENT persistent state (wallet,
## wanted level, world position); switching parks the current lead where they are
## and resumes the other exactly where you left them, after a short cooldown. A
## game controller owns one, loads the active character's state into the live
## PlayerStats / world on a switch, and writes it back before switching away.
##
## No nodes, no scene access: the roster/switch/cooldown logic stays unit-tested
## headless (tests/unit/test_character_roster.gd). Original characters — no
## affiliation with any real title.
##
## Each character is a Dictionary {id, name, money}; position/wanted start neutral
## and accrue in play. Malformed entries (missing/empty id) are dropped.

## Minimum seconds between switches (anti-spam, matches the genre's switch wheel).
const SWITCH_COOLDOWN: float = 3.0
## Wanted stars are clamped to this ceiling.
const MAX_STARS: int = 5

## id -> {name, money:int>=0, wanted:int[0,5], position:Vector3}. Insertion-ordered.
var _characters: Dictionary = {}
var _active: String = ""
var _last_switch_at: float = -INF


func _init(characters: Array = []) -> void:
	var source: Array = characters if not characters.is_empty() else default_characters()
	for entry: Variant in source:
		_register(entry)
	if not _characters.is_empty():
		_active = _characters.keys()[0]


## The built-in two leads (the project's Mara plus an original second protagonist).
static func default_characters() -> Array:
	return [
		{"id": "mara", "name": "Mara", "money": 2500},
		{"id": "rico", "name": "Rico", "money": 1500},
	]


func character_count() -> int:
	return _characters.size()


func has_character(id: String) -> bool:
	return _characters.has(id)


func ids() -> Array:
	return _characters.keys()


## The active character's id ("" if the roster is empty).
func active() -> String:
	return _active


func active_name() -> String:
	return name_of(_active)


## Display name of a character, or "" if unknown.
func name_of(id: String) -> String:
	if not _characters.has(id):
		return ""
	return _characters[id]["name"]


## Whether a switch to `id` is allowed at time `now`: a known, non-active character,
## and the cooldown since the last switch has elapsed.
func can_switch(id: String, now: float) -> bool:
	if not _characters.has(id) or id == _active:
		return false
	return now - _last_switch_at >= SWITCH_COOLDOWN


## Switch the active lead. Returns false if the switch isn't allowed (unknown id,
## already active, or still cooling down). `now` defaults to far-future so a
## caller that doesn't track time can always switch.
func switch_to(id: String, now: float = INF) -> bool:
	if not can_switch(id, now):
		return false
	_active = id
	# A caller that doesn't track time (now == INF) must never be cooldown-blocked
	# on the next switch, so park the stamp at -INF instead of INF.
	_last_switch_at = -INF if is_inf(now) else now
	return true


## A character's wallet (0 if unknown).
func money_of(id: String) -> int:
	if not _characters.has(id):
		return 0
	return _characters[id]["money"]


## Add to (or, with a negative amount, spend from) a character's wallet, floored at
## 0. No-op for an unknown id.
func add_money(id: String, amount: int) -> void:
	if _characters.has(id):
		_characters[id]["money"] = maxi(0, _characters[id]["money"] + amount)


func set_money(id: String, amount: int) -> void:
	if _characters.has(id):
		_characters[id]["money"] = maxi(0, amount)


## A character's wanted stars (0 if unknown).
func wanted_of(id: String) -> int:
	if not _characters.has(id):
		return 0
	return _characters[id]["wanted"]


func set_wanted(id: String, stars: int) -> void:
	if _characters.has(id):
		_characters[id]["wanted"] = clampi(stars, 0, MAX_STARS)


## A character's last world position (Vector3.ZERO if unknown).
func position_of(id: String) -> Vector3:
	if not _characters.has(id):
		return Vector3.ZERO
	return _characters[id]["position"]


func set_position(id: String, pos: Vector3) -> void:
	if _characters.has(id):
		_characters[id]["position"] = pos


## Flatten to a Dictionary for the save system (positions as arrays).
func to_dict() -> Dictionary:
	var out: Dictionary = {"active": _active, "characters": {}}
	for id: Variant in _characters:
		var c: Dictionary = _characters[id]
		var p: Vector3 = c["position"]
		out["characters"][id] = {
			"name": c["name"], "money": c["money"], "wanted": c["wanted"], "pos": [p.x, p.y, p.z]
		}
	return out


## Restore from to_dict() output. Unknown/malformed entries are ignored; known
## characters are updated in place.
func load_dict(data: Dictionary) -> void:
	var chars: Variant = data.get("characters", {})
	if chars is Dictionary:
		for id: Variant in chars:
			_load_one(str(id), chars[id])
	var active: Variant = data.get("active", "")
	if _characters.has(str(active)):
		_active = str(active)


func _load_one(id: String, raw: Variant) -> void:
	if not (_characters.has(id) and raw is Dictionary):
		return
	var c: Dictionary = raw
	if c.has("money"):
		set_money(id, int(c["money"]))
	if c.has("wanted"):
		set_wanted(id, int(c["wanted"]))
	var p: Variant = c.get("pos", null)
	if p is Array and (p as Array).size() == 3:
		set_position(id, Vector3(float(p[0]), float(p[1]), float(p[2])))


func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	if id.is_empty() or _characters.has(id):
		return
	_characters[id] = {
		"name": str(dict.get("name", id)),
		"money": maxi(0, int(dict.get("money", 0))),
		"wanted": 0,
		"position": Vector3.ZERO,
	}
