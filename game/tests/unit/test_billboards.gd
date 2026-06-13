extends RefCounted
## Functional guards for Billboards — the satirical roadside hoardings. Pure
## construction, runs headless via populate(). Guards the row is built, spread
## along the shore, and that every hoarding actually carries a parody ad (the
## joke must be on the board).


func test_builds_requested_count() -> bool:
	var boards := Billboards.new()
	boards.count = 6
	var n := boards.populate()
	var made := boards.get_child_count()
	boards.free()
	return n == 6 and made == 6


func test_each_board_carries_an_ad() -> bool:
	var boards := Billboards.new()
	boards.populate()
	var ok := true
	for board in boards.get_children():
		var text := ""
		for part in (board as Node3D).get_children():
			if part is Label3D:
				text = (part as Label3D).text
		if text == "" or not Billboards.ADS.has(text):
			ok = false
	boards.free()
	return ok


func test_boards_spread_along_shore() -> bool:
	var boards := Billboards.new()
	boards.count = 8
	boards.z_start = -2000.0
	boards.z_end = 2000.0
	boards.populate()
	var min_z := INF
	var max_z := -INF
	for board in boards.get_children():
		var z: float = (board as Node3D).position.z
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)
	boards.free()
	# A spread row, not a stack at one point.
	return max_z - min_z > 2000.0


func test_populate_is_idempotent() -> bool:
	var boards := Billboards.new()
	var first := boards.populate()
	var second := boards.populate()
	var made := boards.get_child_count()
	boards.free()
	return first == second and made == first
