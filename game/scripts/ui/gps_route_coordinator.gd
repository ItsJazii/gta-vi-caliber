class_name GpsRouteCoordinator
extends Node
## Live bridge from active objectives to the minimap GPS route.
##
## Minimap already knows how to draw a supplied route and fall back to a straight
## waypoint line. This node only supplies a NavGrid-backed route when one is
## available, so scenes without a baked nav grid keep the existing fallback.

@export var refresh_interval: float = 0.75
@export var repath_distance: float = 8.0
@export var arrival_radius: float = Minimap.GPS_ARRIVE_RADIUS
@export var nav_provider_names: PackedStringArray = PackedStringArray(
	["TrafficDirector", "CrowdDirector", "CityDirector"]
)

var _minimap: Node = null
var _player: Node3D = null
var _stats: Node = null
var _accum: float = 0.0
var _dirty: bool = true
var _has_managed_route: bool = false
var _last_player_pos: Vector3 = Vector3.INF
var _last_waypoint: Vector3 = Vector3.INF
var _last_nav: NavGrid = null


func _ready() -> void:
	add_to_group("gps_route")
	_minimap = get_parent()
	call_deferred("_bind")


func _process(delta: float) -> void:
	_accum += delta
	if _accum < refresh_interval and not _dirty:
		return
	_accum = 0.0
	if not _bound():
		_bind()
	if not _bound():
		return
	_refresh_route()


func _bind() -> void:
	if _minimap == null or not is_instance_valid(_minimap):
		_minimap = get_parent()
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var stats := get_tree().get_first_node_in_group("player_stats")
	if _stats != stats:
		_stats = stats
		if _stats != null and _stats.has_signal("objective_changed"):
			var callback := Callable(self, "_on_objective_changed")
			if not _stats.is_connected("objective_changed", callback):
				_stats.connect("objective_changed", callback)
	_dirty = true


func _on_objective_changed(_title: String, _has_waypoint: bool) -> void:
	_dirty = true
	if not _bound():
		_bind()
	if not _bound():
		return
	_refresh_route()


func _refresh_route() -> void:
	if not _has_waypoint():
		_clear_managed_route()
		_dirty = false
		return
	var waypoint: Vector3 = _stats.objective_waypoint
	if GpsNavigation.has_arrived(
		_player.global_position, [_player.global_position, waypoint], arrival_radius
	):
		_clear_managed_route()
		_dirty = false
		return
	var nav := _active_nav()
	if nav == null:
		_clear_managed_route()
		_dirty = false
		return
	if not _dirty and nav == _last_nav and waypoint.is_equal_approx(_last_waypoint):
		if (
			GpsNavigation.ground(_player.global_position - _last_player_pos).length()
			< repath_distance
		):
			return
	var path := PathSmoother.simplify_world(nav, nav.find_path(_player.global_position, waypoint))
	if path.size() >= 2:
		_minimap.call("set_gps_route", path)
		_has_managed_route = true
	else:
		_clear_managed_route()
	_last_nav = nav
	_last_player_pos = _player.global_position
	_last_waypoint = waypoint
	_dirty = false


func _active_nav() -> NavGrid:
	for name in nav_provider_names:
		var provider := get_tree().root.find_child(String(name), true, false)
		if provider != null and "nav" in provider:
			var nav := provider.nav as NavGrid
			if nav != null:
				return nav
	return null


func _clear_managed_route() -> void:
	if _has_managed_route and _minimap != null and _minimap.has_method("clear_gps_route"):
		_minimap.call("clear_gps_route")
	_has_managed_route = false
	_last_nav = null


func _bound() -> bool:
	return (
		_minimap != null
		and _minimap.has_method("set_gps_route")
		and _minimap.has_method("clear_gps_route")
		and _player != null
		and is_instance_valid(_player)
		and _stats != null
		and is_instance_valid(_stats)
	)


func _has_waypoint() -> bool:
	return (
		_stats != null
		and _stats.has_method("has_waypoint")
		and _stats.has_waypoint()
		and "objective_waypoint" in _stats
	)
