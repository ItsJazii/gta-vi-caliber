class_name SceneLoadState
extends RefCounted
## Pure presentation and transition rules for the threaded main-menu load.


static func loading_percent(progress: Array) -> int:
	if progress.is_empty():
		return 0
	return roundi(clampf(float(progress[0]), 0.0, 1.0) * 100.0)


static func loading_text(progress: Array) -> String:
	return "LOADING %d%%" % loading_percent(progress)


static func can_enter_world(status: int, fade_finished: bool) -> bool:
	return fade_finished and status == ResourceLoader.THREAD_LOAD_LOADED


static func has_failed(status: int) -> bool:
	return (
		status == ResourceLoader.THREAD_LOAD_FAILED
		or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	)


static func should_request(
	elapsed: float, delay: float, request_started: bool, scene_ready: bool
) -> bool:
	return not request_started and not scene_ready and elapsed >= maxf(delay, 0.0)
