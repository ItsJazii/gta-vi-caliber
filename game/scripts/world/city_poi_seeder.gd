class_name CityPoiSeeder
extends Node3D
## Seeds the walking-distance points of interest (Marker3D in "poi_<place>"
## groups) that turn Citizen schedules into real destinations: home, office,
## diner, park, bar, gym, street, restroom. The Florida backdrop's POI markers
## are kilometres away — useless for a lunch break — so this drops a local set
## around wherever the district loader actually placed the player, snapped to
## the ground, once the spawn has settled. The markers also show up on the
## minimap/full map, which already colour these POI kinds.

const PLACES: PackedStringArray = [
	"home", "office", "diner", "park", "bar", "gym", "street", "restroom"
]

## Seconds after scene start before seeding — covers the time-sliced district
## build and the player's street placement.
@export var seed_delay_sec: float = 3.0
## POIs land on this ring (m) around the player, jittered per place.
@export var ring_radius_m: float = 34.0
## Ground-snap raycast window around the player's height.
@export var ground_probe_up: float = 60.0
@export var ground_probe_down: float = 80.0
@export_flags_3d_physics var ground_mask: int = 1

var _elapsed: float = 0.0


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < seed_delay_sec:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	_seed_around(player.global_position)
	set_physics_process(false)


func _seed_around(center: Vector3) -> void:
	for i in PLACES.size():
		var place := PLACES[i]
		# Spread places around the ring; the per-place hash jitters angle and
		# radius so the layout reads organic, not like a clock face.
		var jitter := float(absi(String(place).hash() % 1000)) / 1000.0
		var angle := TAU * (float(i) + jitter * 0.6) / float(PLACES.size())
		var radius := ring_radius_m * (0.7 + 0.5 * jitter)
		var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		pos.y = _ground_height(pos, center.y)
		var marker := Marker3D.new()
		marker.name = "Poi%s" % String(place).capitalize()
		marker.set_meta("map_label", String(place).capitalize())
		marker.add_to_group("poi_%s" % place)
		add_child(marker)
		marker.global_position = pos + Vector3.UP * 0.2


## Ground height under `at`, or the player's height when the ray finds nothing
## (open water, unbuilt block) so the marker never sinks out of reach.
func _ground_height(at: Vector3, fallback_y: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return fallback_y
	var from := Vector3(at.x, fallback_y + ground_probe_up, at.z)
	var to := Vector3(at.x, fallback_y - ground_probe_down, at.z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, ground_mask))
	return float(hit["position"].y) if hit.has("position") else fallback_y
