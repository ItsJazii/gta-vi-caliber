class_name WantedEvasionController
extends Node
## Closes the wanted loop: escalation already works (crime -> stars -> police);
## this adds de-escalation by EVASION. While the police can still see the player
## the heat holds; once the player breaks line of sight, a search countdown runs
## and the wanted level clears when the player has stayed unseen long enough
## ("go cold"). Drives the pure, tested WantedEvasion model from live police
## sightlines. Self-wires by group (player, wanted, police) — no scene plumbing.

## Officers beyond this planar range can't see the player.
@export var sight_radius: float = 50.0
## Eye height for the sightline ray (matches the player camera / cop eye).
@export var eye_height: float = 1.6
## Seconds unseen before the player goes cold and the stars drop.
@export var search_duration: float = 8.0

var _evasion: WantedEvasion
var _tracker: Node = null
var _player: Node3D = null
var _police: GroupCache = null


func _ready() -> void:
	_evasion = WantedEvasion.new(search_duration)
	_police = GroupCache.for_group(get_tree(), "police")
	add_to_group("wanted_evasion")


func _physics_process(delta: float) -> void:
	_bind()
	if _player == null or _tracker == null or not _tracker.has_method("is_wanted"):
		return
	if not _tracker.is_wanted():
		# Not wanted: nothing to evade, keep the timer primed for next time.
		_evasion.reset()
		return
	_evasion.update(_seen_by_police(delta), delta)
	if _evasion.is_cold() and _tracker.has_method("clear"):
		_tracker.clear()
		_evasion.reset()


## 0 while in sight, ramping to 1 as the player nears going cold (HUD star flash).
func search_progress() -> float:
	return _evasion.search_progress() if _evasion != null else 0.0


func is_searching() -> bool:
	return _evasion != null and _evasion.is_searching()


func _bind() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _tracker == null or not is_instance_valid(_tracker):
		_tracker = get_tree().get_first_node_in_group("wanted")


## True if any living officer is within range and has an unobstructed sightline
## (a ray masked to world geometry that reaches the player without being blocked).
## The officer list comes from the GroupCache, not a per-frame group scan.
func _seen_by_police(delta: float) -> bool:
	if _player == null:
		return false
	var eye := _player.global_position + Vector3.UP * eye_height
	var space := _player.get_world_3d().direct_space_state
	for cop in _police.nodes(delta):
		var officer := cop as Node3D
		if officer == null:
			continue
		if officer.has_method("is_dead") and officer.is_dead():
			continue
		var from := officer.global_position + Vector3.UP * eye_height
		if from.distance_to(eye) > sight_radius:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, eye, 1)
		if space.intersect_ray(query).is_empty():
			return true
	return false
