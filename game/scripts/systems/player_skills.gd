class_name PlayerSkills
extends RefCounted
## Pure activity-based proficiency model — the genre's "get better by doing"
## progression (San Andreas / V): driving, shooting, stamina, strength, etc. each
## climb 0..100 as the player performs the matching activity, with diminishing
## returns so the last points are the hardest. Distinct from PlayerProgression,
## which is a single global respect/XP -> level curve; here each skill advances
## independently from its own activity.
##
## No nodes, no scene access: gameplay nodes call train() when the player does the
## thing (drives a distance, lands a shot) and read bonus() to scale their own
## numbers (recoil bloom, tire grip, sprint drain) — so the gain curve and tiers
## stay unit-testable headless (tests/unit/test_player_skills.gd).
##
## Each skill is a Dictionary {id, rate}; rate scales how fast it learns. Garbage
## entries (missing/empty id, non-positive rate) are dropped at construction. State
## serializes to/from a flat {id: value} Dictionary for the save system.

## Ceiling every skill climbs toward.
const MAX_SKILL: float = 100.0

## Named proficiency tiers, each as [floor, label] in ascending order.
const TIERS: Array = [
	[0.0, "novice"],
	[20.0, "competent"],
	[40.0, "skilled"],
	[60.0, "expert"],
	[85.0, "master"],
]

## id -> {value: float in [0, MAX_SKILL], rate: float > 0}. Insertion-ordered.
var _skills: Dictionary = {}


func _init(skills: Array = []) -> void:
	var source: Array = skills if not skills.is_empty() else default_skills()
	for entry: Variant in source:
		_register(entry)


## The built-in skill set used when an empty list is passed. Rates differ so some
## skills (stamina) build faster than others (flying).
static func default_skills() -> Array:
	return [
		{"id": "driving", "rate": 1.0},
		{"id": "shooting", "rate": 0.8},
		{"id": "stamina", "rate": 1.2},
		{"id": "strength", "rate": 0.9},
		{"id": "stealth", "rate": 0.7},
		{"id": "lung_capacity", "rate": 0.6},
		{"id": "flying", "rate": 0.5},
	]


func skill_count() -> int:
	return _skills.size()


## True if the skill id exists.
func has_skill(id: String) -> bool:
	return _skills.has(id)


## Every skill id, in first-seen order.
func skills() -> Array:
	return _skills.keys()


## Current proficiency of a skill in [0, MAX_SKILL] (0.0 if unknown).
func level(id: String) -> float:
	if not _skills.has(id):
		return 0.0
	return _skills[id]["value"]


## Practise a skill: `effort` is the raw activity amount (e.g. shots landed,
## hundreds of metres driven). Gain = effort * rate * (1 - value/MAX), so progress
## slows as the skill nears mastery and never overshoots the cap. Returns the
## actual gain applied (0.0 for unknown id or non-positive effort).
func train(id: String, effort: float) -> float:
	if not _skills.has(id) or effort <= 0.0:
		return 0.0
	var value: float = _skills[id]["value"]
	var headroom := 1.0 - value / MAX_SKILL
	if headroom <= 0.0:
		return 0.0
	var gain: float = effort * _skills[id]["rate"] * headroom
	var new_value := clampf(value + gain, 0.0, MAX_SKILL)
	_skills[id]["value"] = new_value
	return new_value - value


## The named tier a skill currently sits in (the highest TIERS floor it meets).
## "" for an unknown skill.
func tier(id: String) -> String:
	if not _skills.has(id):
		return ""
	var value: float = _skills[id]["value"]
	var label := ""
	for band: Array in TIERS:
		if value >= band[0]:
			label = band[1]
	return label


## Normalised proficiency in [0, 1] for gameplay systems to scale their own numbers
## (e.g. recoil *= 1 - 0.5 * bonus("shooting")). 0.0 for an unknown skill.
func bonus(id: String) -> float:
	return level(id) / MAX_SKILL


## Directly set a skill's value (loading a save, a cheat, a story grant), clamped
## to [0, MAX_SKILL]. No-op for an unknown id.
func set_level(id: String, value: float) -> void:
	if not _skills.has(id):
		return
	_skills[id]["value"] = clampf(value, 0.0, MAX_SKILL)


## Mean proficiency across all skills in [0, 1] — a single "how developed is this
## character" number for stat screens / 100% tracking. 0.0 with no skills.
func overall_mastery() -> float:
	if _skills.is_empty():
		return 0.0
	var sum := 0.0
	for id: Variant in _skills:
		sum += _skills[id]["value"]
	return sum / (float(_skills.size()) * MAX_SKILL)


## Flatten to {id: value} for the save system.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: Variant in _skills:
		out[id] = _skills[id]["value"]
	return out


## Restore from a {id: value} Dictionary. Unknown ids and non-number values are
## ignored; known skills are clamped into range. Skills absent from the data keep
## their current value.
func load_dict(data: Dictionary) -> void:
	for id: Variant in data:
		var key: String = str(id)
		if not _skills.has(key):
			continue
		var raw: Variant = data[id]
		if raw is float or raw is int:
			set_level(key, float(raw))


## Validate and register one skill entry; malformed entries are silently dropped.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	if id.is_empty() or _skills.has(id):
		return
	var rate := float(dict.get("rate", 1.0))
	if rate <= 0.0:
		return
	_skills[id] = {"value": clampf(float(dict.get("value", 0.0)), 0.0, MAX_SKILL), "rate": rate}
