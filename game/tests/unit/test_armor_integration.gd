class_name TestArmorIntegration
extends GdUnitTestSuite
## Integration test for the critical "paid armor does nothing" fix.
##
## Shop-bought (and HUD-shown) body armor lives on the PlayerStats node, whose
## soak_damage() had ZERO callers — so a purchased vest gave no protection and
## its HUD bar never drained. PlayerHealth.take_damage now routes the hit through
## PlayerStats.soak_damage first; these tests assert the vest absorbs damage and
## only the overflow reaches health.


func _build_player() -> Array:
	var stats: PlayerStats = auto_free(PlayerStats.new())
	add_child(stats)  # _ready -> joins "player_stats"
	var health: PlayerHealth = auto_free(PlayerHealth.new())
	add_child(health)  # _ready -> joins "player_health", builds the model
	return [stats, health]


func test_armor_absorbs_damage_below_its_value() -> void:
	var nodes := _build_player()
	var stats: PlayerStats = nodes[0]
	var health: PlayerHealth = nodes[1]
	stats.armor = 100.0
	health.take_damage(50.0)
	assert_float(stats.armor).is_equal(50.0)  # vest soaked the whole 50
	assert_float(health.fraction()).is_equal(1.0)  # health untouched


func test_damage_overflows_to_health_once_armor_is_gone() -> void:
	var nodes := _build_player()
	var stats: PlayerStats = nodes[0]
	var health: PlayerHealth = nodes[1]
	stats.armor = 100.0
	health.take_damage(150.0)
	assert_float(stats.armor).is_equal(0.0)  # vest depleted
	assert_float(health.fraction()).is_equal_approx(0.5, 0.0001)  # 50 overflow -> 100->50 HP
