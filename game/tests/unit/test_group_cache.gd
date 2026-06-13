extends RefCounted
## Unit tests for GroupCache (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). The cache is fed an injectable source
## Callable instead of a live SceneTree, so these tests stay headless-pure.

const INTERVAL := 0.5


## Source + call counter; `pool` is the backing list the source snapshots.
class CountingSource:
	var calls: int = 0
	var pool: Array = []

	func pull() -> Array:
		calls += 1
		return pool.duplicate()


func test_first_call_pulls_from_source() -> bool:
	var src := CountingSource.new()
	var node := Node.new()
	src.pool = [node]
	var cache := GroupCache.new(Callable(src, "pull"), INTERVAL)
	var got := cache.nodes(0.0)
	var ok := src.calls == 1 and got.size() == 1 and got[0] == node
	node.free()
	return ok


func test_within_interval_reuses_cache() -> bool:
	var src := CountingSource.new()
	var node := Node.new()
	src.pool = [node]
	var cache := GroupCache.new(Callable(src, "pull"), INTERVAL)
	cache.nodes(0.0)
	cache.nodes(0.1)
	cache.nodes(0.1)
	var ok := src.calls == 1
	node.free()
	return ok


func test_repulls_after_interval() -> bool:
	var src := CountingSource.new()
	var first := Node.new()
	src.pool = [first]
	var cache := GroupCache.new(Callable(src, "pull"), INTERVAL)
	cache.nodes(0.0)
	var second := Node.new()
	src.pool = [first, second]
	var got := cache.nodes(INTERVAL)
	var ok := src.calls == 2 and got.size() == 2
	first.free()
	second.free()
	return ok


func test_prunes_freed_nodes_between_refreshes() -> bool:
	var src := CountingSource.new()
	var keep := Node.new()
	var doomed := Node.new()
	src.pool = [keep, doomed]
	var cache := GroupCache.new(Callable(src, "pull"), INTERVAL)
	cache.nodes(0.0)
	doomed.free()
	src.pool = [keep]
	var got := cache.nodes(0.1)
	var ok := got.size() == 1 and got[0] == keep and src.calls == 1
	keep.free()
	return ok


func test_emptied_cache_repulls_immediately() -> bool:
	var src := CountingSource.new()
	var doomed := Node.new()
	src.pool = [doomed]
	var cache := GroupCache.new(Callable(src, "pull"), INTERVAL)
	cache.nodes(0.0)
	doomed.free()
	var respawn := Node.new()
	src.pool = [respawn]
	var got := cache.nodes(0.1)
	var ok := got.size() == 1 and got[0] == respawn and src.calls == 2
	respawn.free()
	return ok


func test_invalidate_forces_repull() -> bool:
	var src := CountingSource.new()
	var node := Node.new()
	src.pool = [node]
	var cache := GroupCache.new(Callable(src, "pull"), INTERVAL)
	cache.nodes(0.0)
	cache.invalidate()
	cache.nodes(0.0)
	var ok := src.calls == 2
	node.free()
	return ok


func test_empty_group_stays_usable() -> bool:
	var src := CountingSource.new()
	var cache := GroupCache.new(Callable(src, "pull"), INTERVAL)
	# nodes() returns the cache's live list, so sample it before the next call.
	var was_empty := cache.nodes(0.0).is_empty()
	var node := Node.new()
	src.pool = [node]
	# An empty cache re-pulls eagerly, so the spawn is seen on the next call.
	var got := cache.nodes(0.1)
	var ok := was_empty and got.size() == 1
	node.free()
	return ok
