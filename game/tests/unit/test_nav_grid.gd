extends RefCounted
## Unit tests for NavGrid A* (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func _grid(cols: int = 10, rows: int = 10, cs: float = 1.0) -> NavGrid:
	return NavGrid.new(cols, rows, cs)


func test_world_cell_roundtrip() -> bool:
	var g := _grid(10, 10, 2.0)
	var cell := g.world_to_cell(Vector3(5.0, 0.0, 7.0))
	# x=5 / 2 -> col 2 ; z=7 / 2 -> row 3
	return cell == Vector2i(2, 3)


func test_cell_to_world_is_centre() -> bool:
	var g := _grid(10, 10, 2.0)
	var w := g.cell_to_world(2, 3)
	return is_equal_approx(w.x, 5.0) and is_equal_approx(w.z, 7.0)


func test_world_to_cell_clamps() -> bool:
	var g := _grid(4, 4, 1.0)
	return g.world_to_cell(Vector3(999, 0, -999)) == Vector2i(3, 0)


func test_straight_path_length() -> bool:
	var g := _grid(10, 1, 1.0)
	var path: Array = g.find_path_cells(Vector2i(0, 0), Vector2i(9, 0))
	return path.size() == 10 and path[0] == Vector2i(0, 0) and path[9] == Vector2i(9, 0)


func test_same_start_goal() -> bool:
	var g := _grid()
	return g.find_path_cells(Vector2i(3, 3), Vector2i(3, 3)) == [Vector2i(3, 3)]


func test_diagonal_is_shorter_than_manhattan() -> bool:
	var g := _grid(10, 10, 1.0)
	var path: Array = g.find_path_cells(Vector2i(0, 0), Vector2i(5, 5))
	# Pure diagonal across an open grid = 6 cells (0,0)..(5,5).
	return path.size() == 6


func test_routes_around_wall() -> bool:
	var g := _grid(7, 7, 1.0)
	# Vertical wall at col 3 spanning rows 0..5, leaving a gap at row 6.
	for r in range(0, 6):
		g.set_blocked(3, r, true)
	var path: Array = g.find_path_cells(Vector2i(1, 1), Vector2i(5, 1))
	if path.is_empty():
		return false
	# Path must detour through the open row 6 and never enter a blocked cell.
	var dipped := false
	for cell: Vector2i in path:
		if g.is_blocked(cell.x, cell.y):
			return false
		if cell.y >= 6:
			dipped = true
	return dipped


func test_no_path_when_fully_walled() -> bool:
	var g := _grid(7, 7, 1.0)
	for r in range(0, 7):
		g.set_blocked(3, r, true)  # full vertical wall, no gap
	return g.find_path_cells(Vector2i(1, 1), Vector2i(5, 1)).is_empty()


func test_blocked_endpoint_returns_empty() -> bool:
	var g := _grid()
	g.set_blocked(5, 5, true)
	return g.find_path_cells(Vector2i(0, 0), Vector2i(5, 5)).is_empty()


func test_no_diagonal_corner_cut() -> bool:
	var g := _grid(3, 3, 1.0)
	# Block (1,0) and (0,1) so the only diagonal (0,0)->(1,1) would cut the corner.
	g.set_blocked(1, 0, true)
	g.set_blocked(0, 1, true)
	# (1,1) is now reachable only by going around — but both orthogonal routes are
	# blocked, so from (0,0) there is no legal move to (1,1)'s region: no path.
	var path: Array = g.find_path_cells(Vector2i(0, 0), Vector2i(2, 2))
	# Whatever path exists, it must never step diagonally through the blocked corner.
	for i in range(1, path.size()):
		var a: Vector2i = path[i - 1]
		var b: Vector2i = path[i]
		if a.x != b.x and a.y != b.y:
			if g.is_blocked(b.x, a.y) or g.is_blocked(a.x, b.y):
				return false
	return true


func test_block_world_rect_marks_cells() -> bool:
	var g := _grid(10, 10, 1.0)
	g.block_world_rect(Vector2(2.5, 2.5), Vector2(4.5, 4.5))
	return g.is_blocked(2, 2) and g.is_blocked(4, 4) and not g.is_blocked(0, 0)


func test_find_path_world_waypoints() -> bool:
	var g := _grid(5, 5, 2.0)
	var wp := g.find_path(Vector3(1, 0, 1), Vector3(9, 0, 1))
	# 5 columns along row 0 -> 5 waypoints, first centred at (1,0,1).
	return wp.size() == 5 and is_equal_approx(wp[0].x, 1.0) and is_equal_approx(wp[0].z, 1.0)
