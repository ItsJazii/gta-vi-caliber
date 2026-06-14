class_name TestLogicFixes4
extends GdUnitTestSuite
## Regression tests for hunt-3 fixes:
##   - SideJob.time_bonus linear-decay band (over-par used to pay 0)
##   - BusinessVenture acquire/upgrade negative-cost money printer
##   - WantedTracker.clear() leaving in-flight witness reports queued


func test_side_job_time_bonus_decays_linearly() -> void:
	assert_int(SideJob.time_bonus(20.0, 30.0, 500)).is_equal(500)  # under par -> full
	assert_int(SideJob.time_bonus(37.5, 30.0, 500)).is_equal(375)  # 1.25x par -> 75%
	assert_int(SideJob.time_bonus(45.0, 30.0, 500)).is_equal(250)  # 1.5x par -> 50%
	assert_int(SideJob.time_bonus(60.0, 30.0, 500)).is_equal(0)  # 2x par -> 0


func test_business_acquire_rejects_negative_cost() -> void:
	var bv := BusinessVenture.new()
	var r := bv.acquire("coke_lab", -100, 1000)
	assert_bool(r["success"]).is_false()
	assert_int(r["new_balance"]).is_equal(1000)  # wallet unchanged, not minted


func test_business_upgrade_rejects_negative_cost() -> void:
	var bv := BusinessVenture.new()
	bv.acquire("coke_lab", 0, 1000)  # own it first (cost 0 is valid)
	var r := bv.upgrade("coke_lab", -500, 1000)
	assert_bool(r["success"]).is_false()
	assert_int(r["new_balance"]).is_equal(1000)


func test_wanted_clear_drops_pending_reports() -> void:
	var w: WantedTracker = auto_free(WantedTracker.new())
	add_child(w)  # _ready builds the WantedSystem
	w._pending_reports.append({"dummy": true})  # simulate an in-flight witness report
	w.clear()
	assert_bool(w._pending_reports.is_empty()).is_true()
