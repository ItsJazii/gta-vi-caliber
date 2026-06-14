class_name TestProgressionRestore
extends GdUnitTestSuite
## Regression for the ProgressionTracker._ready clobber.
##
## _ready() used to unconditionally allocate a fresh PlayerProgression, so XP
## restored from a save BEFORE the node entered the tree was wiped back to zero
## the instant the node was added. _ready now keeps an already-restored
## progression. (Tree-dependent, so this is a gdUnit SceneTree suite — add_child
## fires _ready synchronously.)


func test_restore_before_tree_entry_survives_ready() -> void:
	var tracker: ProgressionTracker = auto_free(ProgressionTracker.new())
	tracker.restore({"total_xp": 1730})  # a save load can run before add_child
	add_child(tracker)  # _ready fires here — must NOT clobber the restored XP
	assert_int(tracker.total_xp()).is_equal(1730)


func test_fresh_tracker_starts_at_zero_xp() -> void:
	var tracker: ProgressionTracker = auto_free(ProgressionTracker.new())
	add_child(tracker)  # no prior restore -> _ready allocates a clean progression
	assert_int(tracker.total_xp()).is_equal(0)
