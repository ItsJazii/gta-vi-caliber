class_name NeighborGrid
extends RefCounted
## Uniform-grid 2D radius queries for steering neighbours (traffic flow, crowd
## separation). Fronts the native worldcore SpatialHash when the GDExtension is
## built (ClassDB-guarded, ~21x faster in native_bench_probe) and falls back to
## a GDScript Dictionary-bucket grid with identical semantics otherwise, so
## gameplay behaves the same with or without the engine module.
##
## Usage mirrors the native class: rebuild per tick — clear(), insert() every
## agent id+XZ (ids unique per rebuild), then query_radius() per agent.
## Queries true-distance refine, and include the query point's own id.

## Bucket edge length (m). Pick ~half the typical query radius.
var cell_size: float

var _native: Object = null
var _buckets: Dictionary = {}
var _positions: Dictionary = {}


## `allow_native = false` forces the GDScript path (used by parity tests).
func _init(p_cell_size: float = 8.0, allow_native: bool = true) -> void:
	cell_size = maxf(p_cell_size, 0.001)
	if allow_native and ClassDB.class_exists("SpatialHash"):
		_native = ClassDB.instantiate("SpatialHash")
		_native.set("cell_size", cell_size)


## True when queries are served by the native worldcore module.
func is_native() -> bool:
	return _native != null


func clear() -> void:
	if _native != null:
		_native.call("clear")
		return
	_buckets.clear()
	_positions.clear()


func insert(id: int, xz: Vector2) -> void:
	if _native != null:
		_native.call("insert", id, xz)
		return
	_positions[id] = xz
	var key := _cell_of(xz)
	var bucket: Array = _buckets.get(key, [])
	bucket.append(id)
	_buckets[key] = bucket


func size() -> int:
	if _native != null:
		return int(_native.call("size"))
	return _positions.size()


## Ids within `radius` of `xz`. Scans only the overlapped buckets, then refines
## by true distance — same contract as the native SpatialHash.query_radius.
func query_radius(xz: Vector2, radius: float) -> PackedInt32Array:
	if _native != null:
		return _native.call("query_radius", xz, radius)
	var out := PackedInt32Array()
	var r := maxf(radius, 0.0)
	var r2 := r * r
	var min_cell := _cell_of(xz - Vector2(r, r))
	var max_cell := _cell_of(xz + Vector2(r, r))
	for cy in range(min_cell.y, max_cell.y + 1):
		for cx in range(min_cell.x, max_cell.x + 1):
			var bucket: Array = _buckets.get(Vector2i(cx, cy), [])
			for id in bucket:
				var pos: Vector2 = _positions[id]
				if pos.distance_squared_to(xz) <= r2:
					out.append(int(id))
	return out


## floori keeps buckets consistent across negative coordinates (-0.5 -> cell -1,
## not cell 0 as int truncation would give).
func _cell_of(xz: Vector2) -> Vector2i:
	return Vector2i(floori(xz.x / cell_size), floori(xz.y / cell_size))
