class_name TestSceneLoadState
extends GdUnitTestSuite
## Unit tests for the pure threaded-load transition rules used by MainMenu.


func test_loading_percent_clamps_progress() -> void:
	assert_int(SceneLoadState.loading_percent([-0.5])).is_equal(0)
	assert_int(SceneLoadState.loading_percent([0.456])).is_equal(46)
	assert_int(SceneLoadState.loading_percent([2.0])).is_equal(100)


func test_world_waits_for_load_and_fade() -> void:
	(
		assert_bool(SceneLoadState.can_enter_world(ResourceLoader.THREAD_LOAD_IN_PROGRESS, true))
		. is_false()
	)
	assert_bool(SceneLoadState.can_enter_world(ResourceLoader.THREAD_LOAD_LOADED, false)).is_false()
	assert_bool(SceneLoadState.can_enter_world(ResourceLoader.THREAD_LOAD_LOADED, true)).is_true()


func test_failed_status_is_detected() -> void:
	assert_bool(SceneLoadState.has_failed(ResourceLoader.THREAD_LOAD_FAILED)).is_true()
	assert_bool(SceneLoadState.has_failed(ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)).is_true()
	assert_bool(SceneLoadState.has_failed(ResourceLoader.THREAD_LOAD_LOADED)).is_false()


func test_delayed_request_starts_once() -> void:
	assert_bool(SceneLoadState.should_request(1.0, 2.0, false, false)).is_false()
	assert_bool(SceneLoadState.should_request(2.0, 2.0, false, false)).is_true()
	assert_bool(SceneLoadState.should_request(3.0, 2.0, true, false)).is_false()
	assert_bool(SceneLoadState.should_request(3.0, 2.0, false, true)).is_false()
