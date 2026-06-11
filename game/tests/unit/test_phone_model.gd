extends RefCounted
## Unit tests for PhoneModel (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_max_offset_zero_when_content_fits() -> bool:
	return PhoneModel.max_offset(400.0, 600.0) == 0.0


func test_max_offset_is_overflow() -> bool:
	return is_equal_approx(PhoneModel.max_offset(1000.0, 600.0), 400.0)


func test_clamp_offset_floors_at_top() -> bool:
	return PhoneModel.clamp_offset(-50.0, 1000.0, 600.0) == 0.0


func test_clamp_offset_caps_at_bottom() -> bool:
	return is_equal_approx(PhoneModel.clamp_offset(999.0, 1000.0, 600.0), 400.0)


func test_scroll_by_clamps_into_range() -> bool:
	var o := PhoneModel.scroll_by(380.0, 100.0, 1000.0, 600.0)
	return is_equal_approx(o, 400.0)


func test_integrate_scroll_moves_by_velocity() -> bool:
	var r := PhoneModel.integrate_scroll(0.0, 100.0, 2000.0, 600.0, 0.1)
	# Started mid-range, so it just advances by velocity*delta (10px) — no clamp.
	return is_equal_approx(r["offset"], 10.0)


func test_integrate_scroll_decays_velocity() -> bool:
	var r := PhoneModel.integrate_scroll(200.0, 800.0, 2000.0, 600.0, 0.1)
	return r["velocity"] < 800.0 and r["velocity"] > 0.0


func test_integrate_scroll_stops_at_top_edge() -> bool:
	var r := PhoneModel.integrate_scroll(5.0, -500.0, 2000.0, 600.0, 0.1)
	return r["offset"] == 0.0 and r["velocity"] == 0.0


func test_integrate_scroll_stops_at_bottom_edge() -> bool:
	var limit := PhoneModel.max_offset(2000.0, 600.0)
	var r := PhoneModel.integrate_scroll(limit - 2.0, 500.0, 2000.0, 600.0, 0.1)
	return is_equal_approx(r["offset"], limit) and r["velocity"] == 0.0


func test_integrate_scroll_kills_tiny_velocity() -> bool:
	var r := PhoneModel.integrate_scroll(300.0, 1.0, 2000.0, 600.0, 0.016)
	return r["velocity"] == 0.0


func test_advance_call_dialing_holds_then_rings() -> bool:
	var holds := PhoneModel.advance_call(PhoneModel.Call.DIALING, 0.5, true, 3.0)
	var rings := PhoneModel.advance_call(PhoneModel.Call.DIALING, 1.3, true, 3.0)
	return holds == PhoneModel.Call.DIALING and rings == PhoneModel.Call.RINGING


func test_advance_call_ringing_connects_when_answered() -> bool:
	var s := PhoneModel.advance_call(PhoneModel.Call.RINGING, 3.1, true, 3.0)
	return s == PhoneModel.Call.CONNECTED


func test_advance_call_ringing_ends_when_unanswered() -> bool:
	var s := PhoneModel.advance_call(PhoneModel.Call.RINGING, 3.1, false, 3.0)
	return s == PhoneModel.Call.ENDED


func test_advance_call_connected_is_terminal() -> bool:
	var s := PhoneModel.advance_call(PhoneModel.Call.CONNECTED, 99.0, false, 3.0)
	return s == PhoneModel.Call.CONNECTED


func test_call_status_text_tracks_state() -> bool:
	return (
		PhoneModel.call_status_text(PhoneModel.Call.DIALING, 0.0) == "Calling…"
		and PhoneModel.call_status_text(PhoneModel.Call.RINGING, 0.0) == "Ringing…"
		and PhoneModel.call_status_text(PhoneModel.Call.ENDED, 0.0) == "Call ended"
	)


func test_call_status_connected_shows_duration() -> bool:
	return PhoneModel.call_status_text(PhoneModel.Call.CONNECTED, 75.0) == "1:15"


func test_format_duration_pads_seconds() -> bool:
	return PhoneModel.format_duration(5.0) == "0:05" and PhoneModel.format_duration(0.0) == "0:00"


func test_home_apps_are_wired() -> bool:
	# Each grid app must name a real App enum value and a label.
	for entry in PhoneModel.HOME_APPS:
		if not entry.has("app") or String(entry.get("label", "")).is_empty():
			return false
	return true
