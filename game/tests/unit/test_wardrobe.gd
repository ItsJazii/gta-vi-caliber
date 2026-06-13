extends RefCounted
## Unit tests for Wardrobe (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Includes a Disguise composition test (changing clothes lowers police recognition).


func test_default_catalogue_loaded() -> bool:
	var w := Wardrobe.new()
	return w.item_count() == 6 and w.has_item("sharp_suit") and w.has_item("ski_mask")


func test_malformed_items_dropped() -> bool:
	var w := (
		Wardrobe
		. new(
			[
				{"id": "ok", "slot": "outfit", "price": 100},
				{"id": "", "slot": "outfit", "price": 100},
				{"slot": "outfit", "price": 100},  # no id
				{"id": "bad_slot", "slot": "shoes", "price": 100},  # unknown slot
				{"id": "negative", "slot": "hair", "price": -5},
				{"id": "ok", "slot": "hair", "price": 200},  # duplicate id
			]
		)
	)
	return w.item_count() == 1 and w.has_item("ok")


func test_starters_owned_and_worn() -> bool:
	var w := Wardrobe.new()
	return (
		w.owns("street_casual")
		and w.owns("buzz_cut")
		and w.worn_in("outfit") == "street_casual"
		and w.worn_in("hair") == "buzz_cut"
	)


func test_lookups() -> bool:
	var w := Wardrobe.new()
	return (
		w.price_of("sharp_suit") == 1500
		and w.slot_of("sharp_suit") == "outfit"
		and w.look_of("sharp_suit") == "suit"
	)


func test_items_in_slot() -> bool:
	var w := Wardrobe.new()
	var outfits := w.items_in_slot("outfit")
	return (
		outfits.has("street_casual") and outfits.has("sharp_suit") and not outfits.has("ski_mask")
	)


func test_buy_grants_ownership() -> bool:
	var w := Wardrobe.new()
	var r := w.buy("sharp_suit", 5000)
	return r["success"] and r["cost"] == 1500 and r["new_balance"] == 3500 and w.owns("sharp_suit")


func test_buy_already_owned_fails() -> bool:
	var w := Wardrobe.new()
	return not w.buy("street_casual", 5000)["success"]


func test_buy_insufficient_funds() -> bool:
	var w := Wardrobe.new()
	var r := w.buy("sharp_suit", 100)
	return not r["success"] and r["new_balance"] == 100 and not w.owns("sharp_suit")


func test_wear_requires_ownership() -> bool:
	var w := Wardrobe.new()
	var unowned := w.wear("sharp_suit")  # not bought yet
	w.buy("sharp_suit", 5000)
	var owned := w.wear("sharp_suit")
	return not unowned and owned and w.worn_in("outfit") == "sharp_suit"


func test_take_off_clears_slot() -> bool:
	var w := Wardrobe.new()
	w.buy("ski_mask", 5000)
	w.wear("ski_mask")
	w.take_off("mask")
	return w.worn_in("mask") == "" and w.worn_look("mask") == ""


func test_worn_looks_map() -> bool:
	var w := Wardrobe.new()
	var looks := w.worn_looks()
	return looks.get("outfit") == "casual" and looks.get("hair") == "buzz"


func test_changing_clothes_lowers_recognition() -> bool:
	# Composition: the worn outfit feeds Disguise; a wardrobe change alters how
	# recognizable the player is to police.
	var w := Wardrobe.new()
	var d := Disguise.new()
	for slot: Variant in w.worn_looks():
		d.set_appearance(slot, w.worn_looks()[slot])
	d.log_sighting()  # cops log the starter look -> fully recognized
	var before := d.recognition()
	w.buy("sharp_suit", 5000)
	w.wear("sharp_suit")
	d.set_appearance("outfit", w.worn_look("outfit"))  # now wearing the suit
	return is_equal_approx(before, 1.0) and d.recognition() < before
