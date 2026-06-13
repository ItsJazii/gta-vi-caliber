class_name VehicleCondition
extends RefCounted
## Pure per-vehicle wear/fuel ledger — the persistent ownership layer the vehicle
## sim was missing. Each registered vehicle carries fuel (litres), engine wear and
## tire wear (each 0 new .. 1 shot). Driving a distance burns fuel by the vehicle's
## economy and accrues engine + tire wear (faster under hard/aggressive driving);
## a crash bumps engine wear. From that it derives a single overall condition (0..1)
## — exactly the float ChopShop.value()/deliver() already expect but that nothing
## produced — plus drivability gates: a worn engine caps top-speed, slick tires cut
## grip (composes with VehicleHandling), an empty tank stalls the car. refuel() and
## service() restore state, closing the gas-station / mechanic loop.
##
## No nodes, no scene access: a Car node owns one keyed by the active vehicle id,
## calls drive()/apply_crash() as it moves and crashes, reads fuel_fraction()/
## condition()/top_speed_factor()/grip_factor() for the HUD + handling, and persists
## via to_dict()/load_dict(). Stays unit-tested headless
## (tests/unit/test_vehicle_condition.gd).
##
## Catalogue entry: {id, tank, economy?, engine_wear?, tire_wear?}. Rows with no/
## empty id or a non-positive tank are dropped; duplicate ids are dropped.

## Default fuel burn (litres per metre) when an entry omits economy.
const DEFAULT_ECONOMY: float = 0.001
## Wear added per metre driven (before the intensity multiplier).
const ENGINE_WEAR_PER_M: float = 0.00002
const TIRE_WEAR_PER_M: float = 0.00003
## Engine wear added by a full-severity (1.0) crash.
const CRASH_ENGINE_WEAR: float = 0.4
## How much engine vs tire wear weighs into overall condition.
const ENGINE_CONDITION_WEIGHT: float = 0.6
## A shot engine still reaches this fraction of top speed; slick tires this much grip.
const ENGINE_FLOOR: float = 0.5
const TIRE_FLOOR: float = 0.6
## Even coasting movement costs at least this intensity, so a positive-distance drive
## always burns fuel and wears — no free driving by passing intensity 0.
const MIN_INTENSITY: float = 0.25

## id -> {tank: float, economy: float, fuel: float, engine_wear: float, tire_wear: float}.
var _vehicles: Dictionary = {}


func _init(vehicles: Array = []) -> void:
	var source: Array = vehicles if not vehicles.is_empty() else default_vehicles()
	for entry: Variant in source:
		_register(entry)


## Built-in roster used when an empty array is passed: a few classes with sane
## tank sizes and fuel economy. Vehicle ids deliberately match ChopShop class ids
## so condition() feeds straight into ChopShop.value().
static func default_vehicles() -> Array:
	return [
		{"id": "sedan", "tank": 60.0, "economy": 0.0009},
		{"id": "sports", "tank": 70.0, "economy": 0.0014},
		{"id": "bike", "tank": 18.0, "economy": 0.0005},
		{"id": "muscle", "tank": 75.0, "economy": 0.0016},
	]


# --- Catalogue queries ----------------------------------------------------


func vehicle_count() -> int:
	return _vehicles.size()


func has_vehicle(id: String) -> bool:
	return _vehicles.has(id)


## Registered ids in first-seen order.
func ids() -> Array:
	return _vehicles.keys()


# --- State queries (all neutral for an unknown vehicle) -------------------


func fuel_of(id: String) -> float:
	return _vehicles[id]["fuel"] if _vehicles.has(id) else 0.0


## Fuel as a 0..1 fraction of tank capacity.
func fuel_fraction(id: String) -> float:
	if not _vehicles.has(id):
		return 0.0
	var tank: float = _vehicles[id]["tank"]
	if tank <= 0.0:
		return 0.0
	return clampf(float(_vehicles[id]["fuel"]) / tank, 0.0, 1.0)


func engine_wear_of(id: String) -> float:
	return _vehicles[id]["engine_wear"] if _vehicles.has(id) else 0.0


func tire_wear_of(id: String) -> float:
	return _vehicles[id]["tire_wear"] if _vehicles.has(id) else 0.0


## Overall 0..1 condition (1 pristine) blending engine and tire wear — the float
## ChopShop.value() consumes. 1.0 for an unknown vehicle.
func condition(id: String) -> float:
	if not _vehicles.has(id):
		return 1.0
	var engine_ok: float = 1.0 - float(_vehicles[id]["engine_wear"])
	var tire_ok: float = 1.0 - float(_vehicles[id]["tire_wear"])
	return clampf(
		ENGINE_CONDITION_WEIGHT * engine_ok + (1.0 - ENGINE_CONDITION_WEIGHT) * tire_ok, 0.0, 1.0
	)


func is_out_of_fuel(id: String) -> bool:
	return _vehicles.has(id) and float(_vehicles[id]["fuel"]) <= 0.0


## Top-speed multiplier in [ENGINE_FLOOR, 1.0] from engine wear. 0.0 if out of fuel
## (a stalled car does not move); 1.0 for an unknown vehicle.
func top_speed_factor(id: String) -> float:
	if not _vehicles.has(id):
		return 1.0
	if float(_vehicles[id]["fuel"]) <= 0.0:
		return 0.0
	return clampf(
		ENGINE_FLOOR + (1.0 - ENGINE_FLOOR) * (1.0 - float(_vehicles[id]["engine_wear"])),
		ENGINE_FLOOR,
		1.0,
	)


## Grip multiplier in [TIRE_FLOOR, 1.0] from tire wear (feeds VehicleHandling).
## 1.0 for an unknown vehicle.
func grip_factor(id: String) -> float:
	if not _vehicles.has(id):
		return 1.0
	return clampf(
		TIRE_FLOOR + (1.0 - TIRE_FLOOR) * (1.0 - float(_vehicles[id]["tire_wear"])), TIRE_FLOOR, 1.0
	)


# --- Driving --------------------------------------------------------------


## Drive `distance_m` metres at `intensity` (1.0 normal, higher = harder/aggressive):
## burns fuel by economy*distance*intensity (floored at empty) and adds engine + tire
## wear scaled the same way. Returns {fuel_used, stalled, engine_wear, tire_wear}.
## No-op for an unknown vehicle or a non-positive distance.
func drive(id: String, distance_m: float, intensity: float = 1.0) -> Dictionary:
	if not _vehicles.has(id):
		return {"fuel_used": 0.0, "stalled": false, "engine_wear": 0.0, "tire_wear": 0.0}
	var v: Dictionary = _vehicles[id]
	if distance_m <= 0.0:
		return {
			"fuel_used": 0.0,
			"stalled": float(v["fuel"]) <= 0.0,
			"engine_wear": v["engine_wear"],
			"tire_wear": v["tire_wear"],
		}
	# A stalled (empty-tank) car does not move, so it neither burns fuel nor wears.
	if float(v["fuel"]) <= 0.0:
		return {
			"fuel_used": 0.0,
			"stalled": true,
			"engine_wear": v["engine_wear"],
			"tire_wear": v["tire_wear"],
		}
	var inten: float = maxf(intensity, MIN_INTENSITY)
	var effort: float = distance_m * inten
	var want_fuel: float = float(v["economy"]) * effort
	var fuel_used: float = minf(want_fuel, float(v["fuel"]))
	v["fuel"] = maxf(float(v["fuel"]) - want_fuel, 0.0)
	v["engine_wear"] = clampf(float(v["engine_wear"]) + ENGINE_WEAR_PER_M * effort, 0.0, 1.0)
	v["tire_wear"] = clampf(float(v["tire_wear"]) + TIRE_WEAR_PER_M * effort, 0.0, 1.0)
	return {
		"fuel_used": fuel_used,
		"stalled": float(v["fuel"]) <= 0.0,
		"engine_wear": v["engine_wear"],
		"tire_wear": v["tire_wear"],
	}


## Add engine wear from a collision (severity 0..1). No-op unknown / non-positive.
func apply_crash(id: String, severity: float) -> void:
	if not _vehicles.has(id) or severity <= 0.0:
		return
	var v: Dictionary = _vehicles[id]
	v["engine_wear"] = clampf(
		float(v["engine_wear"]) + CRASH_ENGINE_WEAR * clampf(severity, 0.0, 1.0), 0.0, 1.0
	)


# --- Service --------------------------------------------------------------


## Add fuel up to the tank; `liters` < 0 fills to full. Returns litres actually
## added. No-op (returns 0) for an unknown vehicle.
func refuel(id: String, liters: float = -1.0) -> float:
	if not _vehicles.has(id):
		return 0.0
	var v: Dictionary = _vehicles[id]
	var space: float = maxf(float(v["tank"]) - float(v["fuel"]), 0.0)
	var add: float = space if liters < 0.0 else clampf(liters, 0.0, space)
	v["fuel"] = float(v["fuel"]) + add
	return add


## Mechanic visit: reset the chosen wear channels to 0. No-op for an unknown vehicle.
func service(id: String, engine: bool = true, tires: bool = true) -> void:
	if not _vehicles.has(id):
		return
	var v: Dictionary = _vehicles[id]
	if engine:
		v["engine_wear"] = 0.0
	if tires:
		v["tire_wear"] = 0.0


# --- Persistence ----------------------------------------------------------


## {id: {fuel, engine_wear, tire_wear}} for the save system (tank/economy are
## catalogue tuning, not saved).
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: String in _vehicles:
		out[id] = {
			"fuel": _vehicles[id]["fuel"],
			"engine_wear": _vehicles[id]["engine_wear"],
			"tire_wear": _vehicles[id]["tire_wear"],
		}
	return out


## Restore fuel/wear for known ids; values clamped to valid ranges. Unknown ids and
## non-numeric values are ignored.
func load_dict(data: Dictionary) -> void:
	for key: Variant in data:
		var id: String = str(key)
		if not _vehicles.has(id) or not (data[key] is Dictionary):
			continue
		var row: Dictionary = data[key]
		var v: Dictionary = _vehicles[id]
		if _is_num(row.get("fuel")):
			v["fuel"] = clampf(float(row["fuel"]), 0.0, float(v["tank"]))
		if _is_num(row.get("engine_wear")):
			v["engine_wear"] = clampf(float(row["engine_wear"]), 0.0, 1.0)
		if _is_num(row.get("tire_wear")):
			v["tire_wear"] = clampf(float(row["tire_wear"]), 0.0, 1.0)


# --- Internal -------------------------------------------------------------


## Validate and store one entry; a fresh vehicle starts with a full tank and the
## entry's (clamped) wear, defaulting to unworn. Malformed rows are dropped.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var row: Dictionary = entry
	if not row.has("id"):
		return
	var id: String = str(row["id"])
	if id.is_empty() or _vehicles.has(id):
		return
	var tank: float = float(row.get("tank", 0.0))
	if tank <= 0.0:
		return
	var economy: float = float(row.get("economy", DEFAULT_ECONOMY))
	var raw_engine: Variant = row.get("engine_wear", 0.0)
	var raw_tire: Variant = row.get("tire_wear", 0.0)
	_vehicles[id] = {
		"tank": tank,
		"economy": economy if economy > 0.0 else DEFAULT_ECONOMY,
		"fuel": tank,
		"engine_wear": clampf(float(raw_engine), 0.0, 1.0) if _is_num(raw_engine) else 0.0,
		"tire_wear": clampf(float(raw_tire), 0.0, 1.0) if _is_num(raw_tire) else 0.0,
	}


## Whether a Variant is a usable number (mirrors what load_dict / _register accept).
static func _is_num(value: Variant) -> bool:
	return value is float or value is int
