class_name PlayerStats
extends Node
## Reactive store for the HUD vitals that no other system owns yet: body armor,
## the wallet, and the active objective. Health lives in PlayerHealth (group
## "player_health") and heat in WantedTracker (group "wanted") — this fills the
## remaining gaps so the GTA-style HUD has real, live data to show.
##
## Joins group "player_stats" so any HUD or system finds it without a hard
## reference. The HUD only reads it; gameplay (pickups, shops, missions) pushes
## changes in. Clamp/absorb maths are static and unit-tested without a tree.

signal armor_changed(armor: float, max_armor: float)
signal money_changed(amount: int)
signal objective_changed(title: String, has_waypoint: bool)

@export var max_armor: float = 100.0
## Starting wallet so the HUD reads as a live game from the first frame.
@export var starting_money: int = 1500
## Seed objective so the quest tracker isn't empty on a fresh world.
@export var starting_objective: String = "Explore the city"

var armor: float = 0.0
var money: int
var objective_title: String = ""
var objective_waypoint: Vector3 = Vector3.ZERO
var _has_waypoint: bool = false


func _ready() -> void:
	add_to_group("player_stats")
	money = starting_money
	if objective_title == "" and starting_objective != "":
		set_objective(starting_objective, Vector3.ZERO, false)


# --- Mutators (called by gameplay, never by the HUD) ----------------------


## Soak incoming damage with armor first; returns the overflow that should reach
## health, so a damage source can route the remainder to PlayerHealth. Pure-ish:
## updates armor and emits, but the arithmetic is in the static absorb() helper.
func soak_damage(amount: float) -> float:
	if amount <= 0.0:
		return maxf(amount, 0.0)
	var result := absorb(armor, amount)
	if result[0] != armor:
		armor = result[0]
		armor_changed.emit(armor, max_armor)
	return result[1]


func add_armor(amount: float) -> void:
	# Ignore negatives (a pickup/shop only ADDS armor) — damage drains armor via
	# soak_damage, not through here. Matches PlayerHealthModel.add_armor.
	armor = clampf(armor + maxf(amount, 0.0), 0.0, max_armor)
	armor_changed.emit(armor, max_armor)


func add_money(amount: int) -> void:
	# Floor at zero so a large negative adjustment (a fine, a failed deal) can't
	# drive the wallet negative — matches CharacterRoster.add_money. spend_money
	# stays the guarded debit path for affordability checks.
	money = maxi(0, money + amount)
	money_changed.emit(money)


## Spend if affordable; returns true on success so callers can gate purchases.
func spend_money(amount: int) -> bool:
	if amount <= 0 or money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true


func set_objective(
	title: String, waypoint: Vector3 = Vector3.ZERO, has_waypoint: bool = false
) -> void:
	objective_title = title
	objective_waypoint = waypoint
	_has_waypoint = has_waypoint
	objective_changed.emit(title, has_waypoint)


func clear_objective() -> void:
	set_objective("", Vector3.ZERO, false)


func has_waypoint() -> bool:
	return _has_waypoint


# --- Persistence (SaveManager) ---------------------------------------------


func serialize() -> Dictionary:
	return {"money": money, "armor": armor}


## Rebuild from a serialize() snapshot; malformed/missing fields keep current
## values. Emits the change signals so the HUD redraws the restored wallet.
func restore(data: Dictionary) -> void:
	money = maxi(int(SaveData.number_or(data.get("money"), money)), 0)
	armor = clampf(SaveData.number_or(data.get("armor"), armor), 0.0, max_armor)
	money_changed.emit(money)
	armor_changed.emit(armor, max_armor)


# --- Pure helpers (unit-tested) -------------------------------------------


## Apply `damage` against an armor pool. Returns [remaining_armor,
## overflow_to_health]: armor absorbs up to its value, the rest spills over.
static func absorb(armor_value: float, damage: float) -> Array:
	var soaked := minf(maxf(armor_value, 0.0), maxf(damage, 0.0))
	return [armor_value - soaked, maxf(damage, 0.0) - soaked]


## Bar fill fraction in 0..1, safe against a zero/negative maximum.
static func fraction(value: float, maximum: float) -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(value / maximum, 0.0, 1.0)
