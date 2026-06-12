extends RefCounted
## Unit tests for BayIslands — the Biscayne Bay residential islands the
## causeways thread between.


func test_island_roster() -> bool:
	var isles := BayIslands.islands()
	var names := {}
	for isle in isles:
		names[isle["name"]] = true
	# At least the headline islands, all uniquely named.
	return (
		isles.size() >= 8
		and names.size() == isles.size()
		and names.has("star")
		and names.has("palm")
		and names.has("hibiscus")
	)


func test_islands_sit_in_the_bay() -> bool:
	# Every island lies in the open water between mainland (x≈700) and the
	# beaches (x≈5400), north of the lower district band.
	for isle in BayIslands.islands():
		var c: Vector2 = isle["center"]
		if c.x < 700.0 or c.x > 5400.0:
			return false
		if c.y < -1300.0 or c.y > -200.0:
			return false
		if isle["radius"] <= 0.0:
			return false
	return true


func test_each_island_hugs_a_causeway() -> bool:
	# An island that floats far from every span looks placed at random; keep
	# them within reach of the deck they belong to.
	for isle in BayIslands.islands():
		var d := BayIslands.nearest_causeway_distance(isle["center"])
		if d > 420.0:
			return false
	return true


func test_islands_do_not_stack() -> bool:
	var isles := BayIslands.islands()
	for i in isles.size():
		for j in range(i + 1, isles.size()):
			var ci: Vector2 = isles[i]["center"]
			var cj: Vector2 = isles[j]["center"]
			if ci.distance_to(cj) < 120.0:
				return false
	return true


func test_ring_is_closed_and_has_area() -> bool:
	var poly := BayIslands.ring(Vector2(2000, -500), 150.0, 24)
	if poly.size() != 24:
		return false
	# A radius-150 disc is ~70k m²; wobble keeps it in the right ballpark.
	var area := BayIslands.polygon_area(poly)
	return area > 50000.0 and area < 90000.0


func test_polygon_area_of_unit_square() -> bool:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)])
	return absf(BayIslands.polygon_area(sq) - 4.0) < 0.001


func test_total_land_area_is_substantial() -> bool:
	# Nine pads of 110–220 m radius add up to a lot of new walkable land.
	return BayIslands.total_land_area() > 400000.0


func test_nearest_causeway_distance_on_deck_is_zero() -> bool:
	# A point taken straight off the MacArthur centreline has ~zero distance.
	var mac := CausewayNetwork.centerline("macarthur")
	var on_deck := mac[1]
	return BayIslands.nearest_causeway_distance(on_deck) < 1.0
