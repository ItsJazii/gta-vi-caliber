class_name CityDirector
extends Node3D
## The conductor of city life: owns the day/night clock and the registry of
## points-of-interest (offices, diners, parks, bars, homes) that citizens plan
## their day around. Drop one into a world scene, add some Marker3D POIs in the
## matching "poi_<place>" groups, and every Citizen in the scene starts
## commuting, working, eating and drinking on schedule.
##
## Deliberately thin and stateless beyond the clock — all the hard decisions live
## in the pure, tested NpcMind/NpcNeeds/NpcSchedule layer. Citizens find this node
## via the "city_director" group and read it; nothing here reaches back into them
## (signals up, calls down).

## Places a citizen routine can name. A POI marker advertises its kind by joining
## the group "poi_<place>" (e.g. "poi_diner").
const PLACES: PackedStringArray = [
	"home", "office", "diner", "park", "bar", "gym", "street", "restroom"
]

## Clock hour the city starts at when the scene loads.
@export_range(0.0, 24.0) var start_hour: float = 8.0
## Real seconds for one in-game day (1440 = a 24-minute day).
@export var day_length_sec: float = 1440.0
## Follow the SkyController's time_of_day (group "sky") when one exists, so
## citizens commute on the same clock the HUD and lighting show. Without a sky
## (or with this off) the internal DayClock ticks at day_length_sec.
@export var follow_sky: bool = true

## Optional walkability map shared with the crowd. Assign in code (same NavGrid a
## CrowdDirector uses, with building/water footprints stamped) and citizens route
## around obstacles instead of walking through walls. Null = straight-line travel.
var nav: NavGrid = null

# Exists before _ready so citizens reading hour() during their own _ready are safe.
var _clock := DayClock.new()
var _sky: Node = null


func _ready() -> void:
	add_to_group("city_director")
	_clock = DayClock.new(start_hour, day_length_sec)


func _process(delta: float) -> void:
	if follow_sky:
		if _sky == null or not is_instance_valid(_sky):
			_sky = get_tree().get_first_node_in_group("sky")
		if _sky != null and "time_of_day" in _sky:
			_clock.hour = fposmod(float(_sky.time_of_day), 24.0)
			return
	_clock.advance(delta)


## Current clock hour in [0, 24).
func hour() -> float:
	return _clock.hour


## Part-of-day label ("morning"/"afternoon"/...).
func phase() -> String:
	return _clock.phase()


## "HH:MM" for debug HUDs.
func clock_text() -> String:
	return _clock.clock_text()


## World position of the nearest POI of `place` to `from`, or `from` itself if no
## such POI exists (the citizen simply stays put rather than teleporting to ZERO).
func position_for(place: String, from: Vector3) -> Vector3:
	var best := from
	var best_d := INF
	for node in get_tree().get_nodes_in_group("poi_%s" % place):
		var marker := node as Node3D
		if marker == null:
			continue
		var d := from.distance_squared_to(marker.global_position)
		if d < best_d:
			best_d = d
			best = marker.global_position
	return best


## World waypoints from `from` to `to` around blocked cells, or an empty array
## when no nav grid is set (the caller then walks straight there).
func path_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	if nav == null:
		return PackedVector3Array()
	return nav.find_path(from, to)


## True if at least one POI of any known kind is registered — lets a Citizen fall
## back to plain wandering when dropped into a world with no city laid out.
func has_pois() -> bool:
	for place in PLACES:
		if not get_tree().get_nodes_in_group("poi_%s" % place).is_empty():
			return true
	return false
