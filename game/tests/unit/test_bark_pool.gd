extends RefCounted
## Unit tests for BarkPool (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_idle_line_nonempty() -> bool:
	return BarkPool.line(BarkPool.Situation.IDLE, 0) != ""


func test_flee_line_nonempty() -> bool:
	return BarkPool.line(BarkPool.Situation.FLEE, 0) != ""


func test_index_wraps() -> bool:
	var count := BarkPool.count(BarkPool.Situation.FLEE)
	return (
		BarkPool.line(BarkPool.Situation.FLEE, count) == BarkPool.line(BarkPool.Situation.FLEE, 0)
	)


func test_negative_index_safe() -> bool:
	# posmod keeps negative counters valid.
	return BarkPool.line(BarkPool.Situation.IDLE, -1) != ""


func test_distinct_situations_have_lines() -> bool:
	return (
		BarkPool.count(BarkPool.Situation.IDLE) > 0
		and BarkPool.count(BarkPool.Situation.ALARMED) > 0
		and BarkPool.count(BarkPool.Situation.FLEE) > 0
	)


func test_should_bark_respects_cooldown() -> bool:
	return BarkPool.should_bark(3.0, 2.0) and not BarkPool.should_bark(1.0, 2.0)


func test_different_indices_can_differ() -> bool:
	# Across the pool, at least two indices yield different lines.
	var a := BarkPool.line(BarkPool.Situation.IDLE, 0)
	var b := BarkPool.line(BarkPool.Situation.IDLE, 1)
	return a != b
