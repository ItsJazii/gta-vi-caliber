class_name GroupCache
extends RefCounted
## Caches a SceneTree group lookup for per-frame hot paths. get_nodes_in_group
## allocates a fresh Array every call, and several systems (evasion, arrest,
## player water/ladder probes) were polling groups every physics frame. Group
## membership only changes when things spawn or despawn, so the cache re-pulls
## the list on a slow clock and prunes freed nodes in between; if pruning
## empties the list it re-pulls immediately, so a respawned singleton (player
## health, tracker) is never missed for more than one call.

## Seconds between full re-pulls from the source.
var refresh_interval: float

var _source: Callable
var _nodes: Array[Node] = []
var _since_refresh: float = INF


## `source` returns the live node list (untyped Array); injectable for tests.
func _init(source: Callable, interval: float = 0.5) -> void:
	_source = source
	refresh_interval = interval


## The common case: cache a live SceneTree group.
static func for_group(tree: SceneTree, group: StringName, interval: float = 0.5) -> GroupCache:
	return GroupCache.new(func() -> Array: return tree.get_nodes_in_group(group), interval)


## The cached node list. `delta` advances the refresh clock; pass the caller's
## frame delta. Entries are guaranteed valid (freed nodes are pruned). The
## returned array is the cache's live internal list — iterate it immediately,
## don't store it across frames.
func nodes(delta: float) -> Array[Node]:
	_since_refresh += delta
	if _since_refresh >= refresh_interval:
		_refresh()
	_prune()
	if _nodes.is_empty() and _since_refresh > 0.0:
		# An emptied cache is indistinguishable from "everything despawned";
		# re-pull so a freshly respawned node is picked up right away.
		_refresh()
	return _nodes


## Drop the cached list so the next nodes() call re-pulls immediately.
func invalidate() -> void:
	_since_refresh = INF


func _refresh() -> void:
	_since_refresh = 0.0
	_nodes.assign(_source.call())


func _prune() -> void:
	# Reverse index walk: remove_at keeps the typed array intact, and freed
	# entries never pass through a typed parameter (which would error).
	for i in range(_nodes.size() - 1, -1, -1):
		if not is_instance_valid(_nodes[i]):
			_nodes.remove_at(i)
