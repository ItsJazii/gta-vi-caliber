extends RefCounted
## Smoke test for the native TileStreamer GDExtension (engine/src/worldcore/).
## The streaming selection math is exhaustively covered in C++
## (engine/tests/test_worldcore.cpp); this just proves the class crosses into
## GDScript correctly. Skips when the native module isn't built, exactly like
## test_worldcore.gd, so the GDScript-only CI lane stays green.


func test_tile_streamer_selects_prioritizes_and_unloads() -> bool:
	if not ClassDB.class_exists("TileStreamer"):
		print("TileStreamer native module absent — skipping")
		return true

	var ts: Object = ClassDB.instantiate("TileStreamer")
	ts.set("tile_size", 256.0)
	ts.set("load_radius", 800.0)
	ts.set("unload_radius", 1100.0)
	ts.set("direction_bias", 0.8)

	# world_to_tile: 257 m on a 256 m grid is tile 1.
	if ts.call("world_to_tile", Vector2(257.0, 0.0)) != Vector2i(1, 0):
		return false

	# Moving +x from the center of tile (0,0): that tile loads first, and the
	# tile ahead (1,0) is prioritized over the symmetric one behind (-1,0).
	var tiles: Array = ts.call("desired_tiles", Vector2(128.0, 128.0), Vector2(10.0, 0.0))
	if tiles.is_empty() or tiles[0] != Vector2i(0, 0):
		return false
	var ahead := tiles.find(Vector2i(1, 0))
	var behind := tiles.find(Vector2i(-1, 0))
	if ahead < 0 or behind < 0 or ahead >= behind:
		return false

	# Hysteresis unload: a far resident tile drops, a near one stays.
	var drop: Array = ts.call(
		"tiles_to_unload", [Vector2i(0, 0), Vector2i(5, 0)], Vector2(128.0, 128.0)
	)
	return drop.size() == 1 and drop[0] == Vector2i(5, 0)
