class_name TestLootCrate
extends GdUnitTestSuite

const LOOT_CRATE_SCRIPT := preload("res://scripts/props/loot_crate.gd")


class LootDirectorStub:
	extends Node

	var drop_count: int = 0
	var last_position: Vector3 = Vector3.INF

	func drop_from_crate(pos: Vector3) -> bool:
		drop_count += 1
		last_position = pos
		return true


func test_nonlethal_damage_does_not_drop() -> void:
	var director := _director()
	var crate: Variant = _crate(Vector3(2.0, 0.0, 4.0))

	crate.take_damage(10.0, crate.global_position, Vector3.UP)

	assert_bool(crate.is_dead()).is_false()
	assert_int(director.drop_count).is_equal(0)


func test_lethal_damage_drops_once() -> void:
	var director := _director()
	var crate: Variant = _crate(Vector3(2.0, 0.0, 4.0))

	crate.take_damage(35.0, crate.global_position, Vector3.UP)
	crate.take_damage(35.0, crate.global_position, Vector3.UP)

	assert_bool(crate.is_dead()).is_true()
	assert_int(director.drop_count).is_equal(1)
	assert_vector(director.last_position).is_equal(crate.global_position + crate.drop_offset)


func _director() -> LootDirectorStub:
	var director: LootDirectorStub = auto_free(LootDirectorStub.new())
	director.add_to_group("loot_drop")
	add_child(director)
	return director


func _crate(pos: Vector3) -> Variant:
	var crate: Variant = auto_free(LOOT_CRATE_SCRIPT.new())
	crate.respawn_delay = 0.0
	add_child(crate)
	crate.global_position = pos
	return crate
