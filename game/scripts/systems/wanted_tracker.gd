class_name WantedTracker
extends Node
## Scene bridge for the wanted system.
##
## Owns a WantedSystem (pure, tested), listens for crimes from the player's
## WeaponController, cools heat each frame, and exposes stars()/is_wanted() for
## police AI and HUDs. Joins group "wanted" so anything can find it without a
## hard reference. One per world scene.

signal stars_changed(stars: int)

@export var wound_heat: float = 0.7
@export var kill_heat: float = 2.5
@export var decay_rate: float = 0.35
@export var heat_cap: float = 20.0

var _wanted: WantedSystem
var _stars: int = -1


func _ready() -> void:
	_wanted = WantedSystem.new(decay_rate, heat_cap)
	add_to_group("wanted")
	call_deferred("_bind")


func _bind() -> void:
	for controller in get_tree().get_nodes_in_group("weapon_controller"):
		if controller.has_signal("crime_committed"):
			controller.crime_committed.connect(_on_crime)


func _on_crime(killed: bool) -> void:
	_wanted.add_crime(kill_heat if killed else wound_heat)
	_refresh()


## Report a crime from a non-gun source (melee, vehicular, ...).
func report_crime(killed: bool) -> void:
	_on_crime(killed)


func _process(delta: float) -> void:
	_wanted.tick(delta, false)
	_refresh()


func stars() -> int:
	return _wanted.stars()


func is_wanted() -> bool:
	return _wanted.is_wanted()


## Wipe all heat (e.g. on death/arrest). The player escapes the law.
func clear() -> void:
	_wanted.heat = 0.0
	_refresh()


## Snapshot for SaveManager.
func serialize() -> Dictionary:
	return {"heat": _wanted.heat}


func restore(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("heat"):
		return
	_wanted.heat = maxf(float((data as Dictionary)["heat"]), 0.0)
	_refresh()


func _refresh() -> void:
	var current := _wanted.stars()
	if current != _stars:
		_stars = current
		stars_changed.emit(current)
