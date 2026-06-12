extends RefCounted
## Unit tests for TrafficSignal (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). Timings: green 8s, yellow 2s.


func test_fresh_phase_is_ns_green() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	return s.phase() == TrafficSignal.Phase.NS_GREEN and is_equal_approx(s.time_in_phase(), 0.0)


func test_tick_advances_to_ns_yellow() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(8.0)
	return s.phase() == TrafficSignal.Phase.NS_YELLOW


func test_full_cycle_in_order() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	var order: Array[int] = []
	order.append(s.phase())
	s.tick(8.0)
	order.append(s.phase())
	s.tick(2.0)
	order.append(s.phase())
	s.tick(8.0)
	order.append(s.phase())
	return (
		order[0] == TrafficSignal.Phase.NS_GREEN
		and order[1] == TrafficSignal.Phase.NS_YELLOW
		and order[2] == TrafficSignal.Phase.EW_GREEN
		and order[3] == TrafficSignal.Phase.EW_YELLOW
	)


func test_cycle_wraps_to_ns_green() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(8.0)  # -> NS_YELLOW
	s.tick(2.0)  # -> EW_GREEN
	s.tick(8.0)  # -> EW_YELLOW
	s.tick(2.0)  # -> NS_GREEN (wrap)
	return s.phase() == TrafficSignal.Phase.NS_GREEN


func test_large_delta_skips_multiple_phases() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	# 8 + 2 + 8 = 18 lands at the start of EW_YELLOW.
	s.tick(18.0)
	return s.phase() == TrafficSignal.Phase.EW_YELLOW


func test_time_in_phase_carries_remainder() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(9.0)  # 8 ends NS_GREEN, 1 carries into NS_YELLOW
	return s.phase() == TrafficSignal.Phase.NS_YELLOW and is_equal_approx(s.time_in_phase(), 1.0)


func test_light_for_ns_green_phase() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	return (
		s.light_for(TrafficSignal.Axis.NS) == TrafficSignal.Light.GREEN
		and s.light_for(TrafficSignal.Axis.EW) == TrafficSignal.Light.RED
	)


func test_light_for_ns_yellow_phase() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(8.0)
	return (
		s.light_for(TrafficSignal.Axis.NS) == TrafficSignal.Light.YELLOW
		and s.light_for(TrafficSignal.Axis.EW) == TrafficSignal.Light.RED
	)


func test_light_for_ew_green_phase() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(10.0)  # NS_GREEN + NS_YELLOW -> EW_GREEN
	return (
		s.light_for(TrafficSignal.Axis.EW) == TrafficSignal.Light.GREEN
		and s.light_for(TrafficSignal.Axis.NS) == TrafficSignal.Light.RED
	)


func test_light_for_ew_yellow_phase() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(18.0)  # -> EW_YELLOW
	return (
		s.light_for(TrafficSignal.Axis.EW) == TrafficSignal.Light.YELLOW
		and s.light_for(TrafficSignal.Axis.NS) == TrafficSignal.Light.RED
	)


func test_should_stop_on_red() -> bool:
	return TrafficSignal.should_stop(TrafficSignal.Light.RED, 30.0, 10.0, 3.0)


func test_should_not_stop_on_green() -> bool:
	return not TrafficSignal.should_stop(TrafficSignal.Light.GREEN, 1.0, 20.0, 3.0)


func test_yellow_stops_when_room_to_brake() -> bool:
	# v=10, brake=5 -> braking distance = 100/10 = 10m; 30m away can stop.
	return TrafficSignal.should_stop(TrafficSignal.Light.YELLOW, 30.0, 10.0, 5.0)


func test_yellow_proceeds_in_dilemma_zone() -> bool:
	# v=10, brake=5 -> needs 10m; only 4m left, can't stop -> clear the box.
	return not TrafficSignal.should_stop(TrafficSignal.Light.YELLOW, 4.0, 10.0, 5.0)


func test_yields_to_car_on_right() -> bool:
	# Mine heads +Z; a car on my right crosses toward +X.
	return TrafficSignal.yields_to(Vector3(0, 0, 1), Vector3(1, 0, 0))


func test_no_yield_to_car_on_left() -> bool:
	# Mine heads +Z; a car from my left crosses toward -X — they yield to me.
	return not TrafficSignal.yields_to(Vector3(0, 0, 1), Vector3(-1, 0, 0))


func test_yields_to_oncoming() -> bool:
	# Head-on: turning across oncoming traffic gives way.
	return TrafficSignal.yields_to(Vector3(0, 0, 1), Vector3(0, 0, -1))


func test_no_yield_same_direction() -> bool:
	return not TrafficSignal.yields_to(Vector3(0, 0, 1), Vector3(0, 0, 1))


func test_is_clear_to_go_green_no_cross() -> bool:
	return TrafficSignal.is_clear_to_go(TrafficSignal.Light.GREEN, false)


func test_not_clear_green_with_cross_traffic() -> bool:
	return not TrafficSignal.is_clear_to_go(TrafficSignal.Light.GREEN, true)


func test_not_clear_on_red() -> bool:
	return not TrafficSignal.is_clear_to_go(TrafficSignal.Light.RED, false)


func test_negative_delta_ignored() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(-5.0)
	return s.phase() == TrafficSignal.Phase.NS_GREEN and is_equal_approx(s.time_in_phase(), 0.0)


func test_reset_restarts_cycle() -> bool:
	var s := TrafficSignal.new(8.0, 2.0)
	s.tick(12.0)
	s.reset()
	return s.phase() == TrafficSignal.Phase.NS_GREEN and is_equal_approx(s.time_in_phase(), 0.0)
