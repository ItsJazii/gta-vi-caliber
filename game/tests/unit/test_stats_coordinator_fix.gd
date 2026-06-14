class_name TestStatsCoordinatorFix
extends GdUnitTestSuite
## Regression test: dying while wanted must NOT be counted as a "bust evaded".
## The wanted level clears on the death/respawn, which used to look identical to
## an escape and inflated the lifetime busts_evaded stat.


class WantedStub:
	extends Node
	var w: bool = false

	func is_wanted() -> bool:
		return w


class HealthStub:
	extends Node
	signal died


func _build() -> Array:
	var wanted: WantedStub = auto_free(WantedStub.new())
	wanted.add_to_group("wanted")
	add_child(wanted)
	var health: HealthStub = auto_free(HealthStub.new())
	health.add_to_group("player_health")
	add_child(health)
	var sc: StatsCoordinator = auto_free(StatsCoordinator.new())
	add_child(sc)  # _ready connects to the two stubs above
	return [wanted, health, sc]


func test_death_while_wanted_is_not_an_evasion() -> void:
	var nodes := _build()
	var wanted: WantedStub = nodes[0]
	var health: HealthStub = nodes[1]
	var sc: StatsCoordinator = nodes[2]
	wanted.w = true
	sc._process(0.0)  # observe the rising wanted level
	health.died.emit()  # death arms the suppress flag
	wanted.w = false
	sc._process(0.0)  # wanted clears on death — must NOT count
	assert_float(sc.stat("busts_evaded")).is_equal(0.0)


func test_escaping_a_wanted_level_still_counts() -> void:
	var nodes := _build()
	var wanted: WantedStub = nodes[0]
	var sc: StatsCoordinator = nodes[2]
	wanted.w = true
	sc._process(0.0)
	wanted.w = false
	sc._process(0.0)  # cleared by escape, not death -> counts
	assert_float(sc.stat("busts_evaded")).is_equal(1.0)


func test_death_while_clean_does_not_suppress_a_later_escape() -> void:
	var nodes := _build()
	var wanted: WantedStub = nodes[0]
	var health: HealthStub = nodes[1]
	var sc: StatsCoordinator = nodes[2]
	health.died.emit()  # not wanted -> flag must NOT arm
	wanted.w = true
	sc._process(0.0)
	wanted.w = false
	sc._process(0.0)  # genuine escape -> counts
	assert_float(sc.stat("busts_evaded")).is_equal(1.0)
