class_name NavGrid
extends RefCounted
## A* pathfinding over a uniform planar (XZ) grid — the shared routing core for
## pedestrian navmesh-flows and the vehicle road graph (roadmap M4).
##
## Scene-free and deterministic so it unit-tests headless
## (tests/unit/test_nav_grid.gd). A caller builds the grid once, marks blocked
## cells (building footprints, water, walls) via set_blocked / block_world_rect,
## then asks find_path for a list of world waypoints. Movement is 8-directional
## with octile distance; diagonal steps may not cut the corner between two
## blocked orthogonal neighbours, so paths never clip through a wall diagonally.

const SQRT2: float = 1.4142135623730951

var cols: int
var rows: int
var cell_size: float
var origin: Vector3
var _blocked: PackedByteArray


func _init(p_cols: int, p_rows: int, p_cell_size: float, p_origin: Vector3 = Vector3.ZERO) -> void:
	cols = maxi(p_cols, 0)
	rows = maxi(p_rows, 0)
	cell_size = maxf(p_cell_size, 0.0001)
	origin = p_origin
	_blocked = PackedByteArray()
	_blocked.resize(cols * rows)


func in_bounds(c: int, r: int) -> bool:
	return c >= 0 and c < cols and r >= 0 and r < rows


func _index(c: int, r: int) -> int:
	return r * cols + c


func set_blocked(c: int, r: int, blocked: bool = true) -> void:
	if in_bounds(c, r):
		_blocked[_index(c, r)] = 1 if blocked else 0


func is_blocked(c: int, r: int) -> bool:
	# Out-of-bounds reads as blocked so the search never leaves the grid.
	if not in_bounds(c, r):
		return true
	return _blocked[_index(c, r)] == 1


## World XZ position of a cell's centre (y = grid origin's y).
func cell_to_world(c: int, r: int) -> Vector3:
	return Vector3(origin.x + (c + 0.5) * cell_size, origin.y, origin.z + (r + 0.5) * cell_size)


## Cell containing a world position (clamped to the grid).
func world_to_cell(pos: Vector3) -> Vector2i:
	var c := int(floor((pos.x - origin.x) / cell_size))
	var r := int(floor((pos.z - origin.z) / cell_size))
	return Vector2i(clampi(c, 0, maxi(cols - 1, 0)), clampi(r, 0, maxi(rows - 1, 0)))


## Mark every cell whose centre falls inside an axis-aligned world rectangle as
## blocked — the cheap way to stamp a building footprint or water body into the
## grid. min_xz/max_xz are (x, z) corners.
func block_world_rect(min_xz: Vector2, max_xz: Vector2) -> void:
	var lo := world_to_cell(Vector3(min_xz.x, origin.y, min_xz.y))
	var hi := world_to_cell(Vector3(max_xz.x, origin.y, max_xz.y))
	for r in range(mini(lo.y, hi.y), maxi(lo.y, hi.y) + 1):
		for c in range(mini(lo.x, hi.x), maxi(lo.x, hi.x) + 1):
			set_blocked(c, r, true)


## A* over cells. Returns the cell path inclusive of start and goal, or an empty
## array if either endpoint is blocked or no route exists.
func find_path_cells(start: Vector2i, goal: Vector2i) -> Array:
	if is_blocked(start.x, start.y) or is_blocked(goal.x, goal.y):
		return []
	if start == goal:
		return [start]

	var start_i := _index(start.x, start.y)
	var goal_i := _index(goal.x, goal.y)
	var came_from := {}
	var g_score := {start_i: 0.0}
	# Binary min-heap of [f_score, insertion_seq, cell_index]; insertion_seq keeps
	# ordering deterministic when f-scores tie.
	var open: Array = []
	var seq := 0
	_heap_push(open, [_octile(start, goal), seq, start_i])
	var closed := {}

	while not open.is_empty():
		var top: Array = _heap_pop(open)
		var ci: int = top[2]
		if closed.has(ci):
			continue
		closed[ci] = true
		if ci == goal_i:
			return _reconstruct(came_from, start_i, goal_i)
		var cc := ci % cols
		var cr := ci / cols
		for n in _neighbours(cc, cr):
			var ni := _index(n.x, n.y)
			if closed.has(ni):
				continue
			var step: float = SQRT2 if (n.x != cc and n.y != cr) else 1.0
			var tentative: float = g_score[ci] + step
			if not g_score.has(ni) or tentative < g_score[ni]:
				came_from[ni] = ci
				g_score[ni] = tentative
				seq += 1
				_heap_push(open, [tentative + _octile(n, goal), seq, ni])
	return []


## Convenience: path as world waypoints (cell centres) between two world points.
## Empty if unreachable.
func find_path(from_world: Vector3, to_world: Vector3) -> PackedVector3Array:
	var cells := find_path_cells(world_to_cell(from_world), world_to_cell(to_world))
	var out := PackedVector3Array()
	for cell: Vector2i in cells:
		out.append(cell_to_world(cell.x, cell.y))
	return out


func _neighbours(c: int, r: int) -> Array:
	var out: Array = []
	for d: Vector2i in [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]:
		var nc := c + d.x
		var nr := r + d.y
		if is_blocked(nc, nr):
			continue
		# No diagonal corner-cutting: both shared orthogonal cells must be open.
		if d.x != 0 and d.y != 0:
			if is_blocked(c + d.x, r) or is_blocked(c, r + d.y):
				continue
		out.append(Vector2i(nc, nr))
	return out


func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + (SQRT2 - 1.0) * float(mini(dx, dy))


func _reconstruct(came_from: Dictionary, start_i: int, goal_i: int) -> Array:
	var path: Array = []
	var cur := goal_i
	while cur != start_i:
		path.append(Vector2i(cur % cols, cur / cols))
		cur = came_from[cur]
	path.append(Vector2i(start_i % cols, start_i / cols))
	path.reverse()
	return path


# --- tiny binary min-heap over Array entries compared by element [0] ----------
func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent][0] <= heap[i][0]:
			break
		var tmp: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := 2 * i + 1
			var rgt := 2 * i + 2
			var smallest := i
			if l < n and heap[l][0] < heap[smallest][0]:
				smallest = l
			if rgt < n and heap[rgt][0] < heap[smallest][0]:
				smallest = rgt
			if smallest == i:
				break
			var tmp: Array = heap[smallest]
			heap[smallest] = heap[i]
			heap[i] = tmp
			i = smallest
	return top
