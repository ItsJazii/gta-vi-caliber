class_name TestSaveManagerLifetimeStats
extends GdUnitTestSuite
## SaveManager bridges the live StatsCoordinator under a distinct
## `lifetime_stats` key so it does not collide with PlayerStats' wallet/armor
## payload, which already owns the `stats` save key.


class LifetimeStatsStub:
	extends Node

	var restored: Dictionary = {}

	func serialize() -> Dictionary:
		return {"stats": {"missions_passed": 4.0, "busts_evaded": 2.0}}

	func restore(data: Dictionary) -> void:
		restored = data


func test_gather_writes_lifetime_stats_key() -> void:
	var manager: SaveManager = auto_free(SaveManager.new())
	add_child(manager)
	var stats: LifetimeStatsStub = auto_free(LifetimeStatsStub.new())
	stats.add_to_group("stats")
	add_child(stats)

	var snapshot: Dictionary = manager.call("_gather")
	var lifetime: Dictionary = snapshot["lifetime_stats"]
	var counters: Dictionary = lifetime["stats"]

	assert_dict(snapshot).contains_keys("lifetime_stats")
	assert_float(counters["missions_passed"]).is_equal(4.0)
	assert_bool(snapshot.has("stats")).is_false()


func test_apply_restores_lifetime_stats_key() -> void:
	var manager: SaveManager = auto_free(SaveManager.new())
	add_child(manager)
	var stats: LifetimeStatsStub = auto_free(LifetimeStatsStub.new())
	stats.add_to_group("stats")
	add_child(stats)

	manager.call("_apply", {"lifetime_stats": {"stats": {"busts_evaded": 3.0}}})
	var counters: Dictionary = stats.restored["stats"]

	assert_float(counters["busts_evaded"]).is_equal(3.0)
