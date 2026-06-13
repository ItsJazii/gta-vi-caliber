class_name AmbientEvents
extends RefCounted
## Pure freeroam ambient-encounter director — the "the city throws something at
## you" loop: a mugging in progress, a street-race challenge, a getaway-driver
## job, a gang shootout. It weight-picks an eligible encounter for the player's
## current context (wanted level, district) while respecting per-event cooldowns
## and a global anti-spam gap, so encounters feel spontaneous but never spam.
##
## No nodes, no scene access; all randomness flows through a caller-supplied
## RandomNumberGenerator (cf. LootTable), so selection stays deterministic and
## unit-tested headless (tests/unit/test_ambient_events.gd). A world director calls
## trigger_next() on a timer and spawns the returned encounter id.
##
## Each event is a Dictionary {id, kind, weight, min_stars, max_stars, district,
## cooldown}; `district` "" means any. Malformed entries (missing id, non-positive
## weight) are dropped at construction.

## Minimum seconds between ANY two ambient events.
const GLOBAL_GAP: float = 30.0

## id -> {kind, weight, min_stars, max_stars, district, cooldown, last_fired}.
var _events: Dictionary = {}
var _last_any_fired: float = -INF


func _init(events: Array = []) -> void:
	var source: Array = events if not events.is_empty() else default_events()
	for entry: Variant in source:
		_register(entry)


## The built-in encounter table spanning calm-to-hot situations.
static func default_events() -> Array:
	return [
		{
			"id": "mugging",
			"kind": "crime",
			"weight": 3.0,
			"min_stars": 0,
			"max_stars": 2,
			"cooldown": 60.0
		},
		{
			"id": "stranded_motorist",
			"kind": "help",
			"weight": 2.0,
			"min_stars": 0,
			"max_stars": 0,
			"cooldown": 90.0
		},
		{
			"id": "street_race",
			"kind": "race",
			"weight": 2.0,
			"min_stars": 0,
			"max_stars": 1,
			"cooldown": 120.0
		},
		{
			"id": "getaway_driver",
			"kind": "crime",
			"weight": 1.5,
			"min_stars": 1,
			"max_stars": 3,
			"cooldown": 120.0
		},
		{
			"id": "gang_shootout",
			"kind": "combat",
			"weight": 1.5,
			"min_stars": 2,
			"max_stars": 5,
			"district": "docks",
			"cooldown": 150.0
		},
		{
			"id": "security_van",
			"kind": "heist",
			"weight": 1.0,
			"min_stars": 0,
			"max_stars": 2,
			"cooldown": 180.0
		},
	]


func event_count() -> int:
	return _events.size()


func has_event(id: String) -> bool:
	return _events.has(id)


func ids() -> Array:
	return _events.keys()


## Category tag of an event ("" if unknown).
func kind_of(id: String) -> String:
	if not _events.has(id):
		return ""
	return _events[id]["kind"]


## Whether an event may fire right now given the context (wanted stars in range,
## district matches or unrestricted, and its own cooldown elapsed). The global gap
## is enforced separately by trigger_next.
func can_fire(id: String, now: float, context: Dictionary) -> bool:
	if not _events.has(id):
		return false
	var e: Dictionary = _events[id]
	var stars: int = int(context.get("stars", 0))
	if stars < e["min_stars"] or stars > e["max_stars"]:
		return false
	var district: String = e["district"]
	if not district.is_empty() and district != str(context.get("district", "")):
		return false
	return now - e["last_fired"] >= e["cooldown"]


## Ids that could fire right now for the given context.
func eligible_ids(now: float, context: Dictionary) -> Array:
	var out: Array = []
	for id: Variant in _events:
		if can_fire(id, now, context):
			out.append(id)
	return out


## Pick and fire the next ambient encounter, or "" if the global gap hasn't passed
## or nothing is eligible. Marks the chosen event (and the global clock) as fired.
func trigger_next(rng: RandomNumberGenerator, now: float, context: Dictionary) -> String:
	if rng == null or now - _last_any_fired < GLOBAL_GAP:
		return ""
	var eligible := eligible_ids(now, context)
	if eligible.is_empty():
		return ""
	var id := _weighted_pick(rng, eligible)
	_events[id]["last_fired"] = now
	_last_any_fired = now
	return id


## Force-mark an event as fired now (e.g. a scripted spawn), updating cooldowns.
func trigger(id: String, now: float) -> void:
	if _events.has(id):
		_events[id]["last_fired"] = now
		_last_any_fired = now


## When an event last fired (-INF if never / unknown).
func last_fired_of(id: String) -> float:
	if not _events.has(id):
		return -INF
	return _events[id]["last_fired"]


## Clear all cooldowns (new game / chapter).
func reset() -> void:
	_last_any_fired = -INF
	for id: Variant in _events:
		_events[id]["last_fired"] = -INF


## Deterministic-test helper: a fresh rng seeded with `seed_value`.
static func make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _weighted_pick(rng: RandomNumberGenerator, eligible: Array) -> String:
	var total := 0.0
	for id: Variant in eligible:
		total += _events[id]["weight"]
	var roll := rng.randf() * total
	for id: Variant in eligible:
		roll -= _events[id]["weight"]
		if roll <= 0.0:
			return id
	return str(eligible[eligible.size() - 1])


func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	if id.is_empty() or _events.has(id):
		return
	var weight := float(dict.get("weight", 1.0))
	if weight <= 0.0:
		return
	_events[id] = {
		"kind": str(dict.get("kind", "misc")),
		"weight": weight,
		"min_stars": int(dict.get("min_stars", 0)),
		"max_stars": int(dict.get("max_stars", 5)),
		"district": str(dict.get("district", "")),
		"cooldown": maxf(0.0, float(dict.get("cooldown", 60.0))),
		"last_fired": -INF,
	}
