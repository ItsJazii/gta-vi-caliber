class_name TestBuildingUse
extends GdUnitTestSuite
## Unit tests for BuildingUse, the pure kind-to-interaction classifier that wires
## shops onto the right buildings and survives the swap to real 3D assets.


func test_shop_kinds_are_shops() -> void:
	assert_bool(BuildingUse.is_shop("retail")).is_true()
	assert_bool(BuildingUse.is_shop("commercial")).is_true()
	assert_bool(BuildingUse.is_shop("supermarket")).is_true()


func test_non_shop_public_kinds_are_not_shops() -> void:
	assert_bool(BuildingUse.is_shop("office")).is_false()
	assert_bool(BuildingUse.is_shop("hotel")).is_false()
	assert_bool(BuildingUse.is_shop("church")).is_false()


func test_unknown_and_empty_kind_is_not_a_shop() -> void:
	assert_bool(BuildingUse.is_shop("")).is_false()
	assert_bool(BuildingUse.is_shop("apartments")).is_false()


func test_catalogue_for_shop_is_non_empty() -> void:
	assert_int(BuildingUse.catalogue_for("retail").size()).is_greater(0)


func test_catalogue_entries_are_priced_dicts() -> void:
	var catalogue := BuildingUse.catalogue_for("retail")
	var first: Dictionary = catalogue[0]
	assert_bool(first.has("id") and first.has("price")).is_true()
