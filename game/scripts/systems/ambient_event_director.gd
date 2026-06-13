class_name AmbientEventDirector
extends Node
## Self-wiring driver for AmbientEvents: on a timer it builds the player's context
## (wanted stars from the live `wanted` group + the active district) and asks the
## model for the next freeroam encounter, emitting a signal the scene connects to
## actual spawn logic. Drop the node in and it finds the wanted tracker by group
## (cf. PaySprayShop); the encounter selection/cooldown math lives in the
## unit-tested AmbientEvents model, while this node's wiring is exercised by
## tests/ambient_event_probe.gd.

## Emitted when an encounter should spawn, with its id and kind tag.
signal encounter_triggered(id: String, kind: String)

## Seconds between encounter rolls.
@export var tick_interval: float = 20.0
## District the encounters happen in (a real scene updates this from player location).
@export var active_district: String = "downtown"

## The model. Public so a UI / debug overlay can read eligible encounters.
var events: AmbientEvents

var _rng: RandomNumberGenerator
var _elapsed: float = 0.0
var _since_tick: float = 0.0
var _stars: int = 0


func _init() -> void:
	events = AmbientEvents.new()
	_rng = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	call_deferred("_connect_wanted")


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_elapsed += delta
	_since_tick += delta
	if _since_tick >= tick_interval:
		_since_tick = 0.0
		_roll()


## Seed the RNG for deterministic behaviour (tests / replays).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func _connect_wanted() -> void:
	var tracker := get_tree().get_first_node_in_group("wanted")
	if tracker == null or not tracker.has_signal("stars_changed"):
		return
	tracker.connect("stars_changed", _on_stars_changed)
	if tracker.has_method("stars"):
		_stars = tracker.stars()


func _on_stars_changed(stars: int) -> void:
	_stars = stars


func _roll() -> void:
	var context := {"stars": _stars, "district": active_district}
	var id := events.trigger_next(_rng, _elapsed, context)
	if not id.is_empty():
		encounter_triggered.emit(id, events.kind_of(id))
