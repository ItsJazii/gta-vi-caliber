class_name TestGpsRouteCoordinator
extends GdUnitTestSuite
## Scene-aware tests for GPS route feeding into the minimap.

const GPS_ROUTE_COORDINATOR_SCRIPT := preload("res://scripts/ui/gps_route_coordinator.gd")


class MinimapStub:
	extends Node

	var route: Array = []
	var set_count: int = 0
	var clear_count: int = 0

	func set_gps_route(value: Variant) -> void:
		route = Minimap.route_to_array(value)
		set_count += 1

	func clear_gps_route() -> void:
		route.clear()
		clear_count += 1


class NavProviderStub:
	extends Node

	var nav: NavGrid = null


func test_nav_route_feeds_minimap() -> void:
	var host: MinimapStub = auto_free(MinimapStub.new())
	add_child(host)
	var player := _player_at(Vector3(0.5, 0.0, 0.5))
	var stats := _stats_with_waypoint(Vector3(5.5, 0.0, 0.5))
	_provider_with_nav(_open_grid())
	var coordinator: Node = auto_free(GPS_ROUTE_COORDINATOR_SCRIPT.new())
	host.add_child(coordinator)

	coordinator.call("_bind")
	coordinator.call("_refresh_route")

	assert_int(host.set_count).is_equal(1)
	assert_array(host.route).has_size(2)
	assert_vector(host.route[0]).is_equal(player.global_position)
	assert_vector(host.route[1]).is_equal(stats.objective_waypoint)


func test_missing_nav_clears_only_a_managed_route() -> void:
	var host: MinimapStub = auto_free(MinimapStub.new())
	add_child(host)
	_player_at(Vector3(0.5, 0.0, 0.5))
	_stats_with_waypoint(Vector3(5.5, 0.0, 0.5))
	var provider := _provider_with_nav(_open_grid())
	var coordinator: Node = auto_free(GPS_ROUTE_COORDINATOR_SCRIPT.new())
	host.add_child(coordinator)
	coordinator.call("_bind")
	coordinator.call("_refresh_route")

	provider.nav = null
	coordinator.call("_refresh_route")

	assert_int(host.clear_count).is_equal(1)
	assert_array(host.route).is_empty()


func test_inactive_waypoint_clears_managed_route() -> void:
	var host: MinimapStub = auto_free(MinimapStub.new())
	add_child(host)
	_player_at(Vector3(0.5, 0.0, 0.5))
	var stats := _stats_with_waypoint(Vector3(5.5, 0.0, 0.5))
	_provider_with_nav(_open_grid())
	var coordinator: Node = auto_free(GPS_ROUTE_COORDINATOR_SCRIPT.new())
	host.add_child(coordinator)
	coordinator.call("_bind")
	coordinator.call("_refresh_route")

	stats.clear_objective()
	coordinator.call("_refresh_route")

	assert_int(host.clear_count).is_equal(1)
	assert_array(host.route).is_empty()


func test_repath_waits_until_player_moves_enough() -> void:
	var host: MinimapStub = auto_free(MinimapStub.new())
	add_child(host)
	var player := _player_at(Vector3(0.5, 0.0, 0.5))
	_stats_with_waypoint(Vector3(11.5, 0.0, 0.5))
	_provider_with_nav(_open_grid())
	var coordinator: Node = auto_free(GPS_ROUTE_COORDINATOR_SCRIPT.new())
	host.add_child(coordinator)
	coordinator.call("_bind")
	coordinator.call("_refresh_route")

	player.global_position = Vector3(2.0, 0.0, 0.5)
	coordinator.call("_refresh_route")
	assert_int(host.set_count).is_equal(1)

	player.global_position = Vector3(9.0, 0.0, 0.5)
	coordinator.call("_refresh_route")
	assert_int(host.set_count).is_equal(2)


func _player_at(pos: Vector3) -> Node3D:
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(player)
	player.global_position = pos
	return player


func _stats_with_waypoint(waypoint: Vector3) -> PlayerStats:
	var stats: PlayerStats = auto_free(PlayerStats.new())
	add_child(stats)
	stats.set_objective("Go there", waypoint, true)
	return stats


func _provider_with_nav(nav: NavGrid) -> NavProviderStub:
	var provider: NavProviderStub = auto_free(NavProviderStub.new())
	provider.name = "TrafficDirector"
	provider.nav = nav
	add_child(provider)
	return provider


func _open_grid() -> NavGrid:
	return NavGrid.new(12, 12, 1.0)
