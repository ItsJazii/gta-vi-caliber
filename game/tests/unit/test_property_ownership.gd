extends RefCounted
## Unit tests for PropertyOwnership (see tests/run_tests.gd for the runner
## contract: test_* methods return true to pass).


# A small deterministic catalogue: one safehouse, two businesses.
func _fixture() -> PropertyOwnership:
	return (
		PropertyOwnership
		. new(
			[
				{
					"id": "loft",
					"name": "Loft",
					"price": 1000,
					"income_per_day": 0,
					"is_safehouse": true,
				},
				{
					"id": "club",
					"name": "Club",
					"price": 5000,
					"income_per_day": 200,
					"is_safehouse": false,
				},
				{
					"id": "taxi",
					"name": "Taxi Firm",
					"price": 2000,
					"income_per_day": 50,
					"is_safehouse": false,
				},
			]
		)
	)


func test_default_catalogue_non_empty() -> bool:
	var p := PropertyOwnership.new()
	return p.property_count() >= 4


func test_fixture_property_count() -> bool:
	return _fixture().property_count() == 3


func test_price_of_known_and_unknown() -> bool:
	var p := _fixture()
	return p.price_of("club") == 5000 and p.price_of("ghost") == -1


func test_income_of_business_and_safehouse() -> bool:
	var p := _fixture()
	return p.income_of("club") == 200 and p.income_of("loft") == 0


func test_buy_deducts_and_marks_owned() -> bool:
	var p := _fixture()
	var r := p.buy("club", 8000)
	return (
		bool(r["success"])
		and int(r["cost"]) == 5000
		and int(r["new_balance"]) == 3000
		and r["reason"] == ""
		and p.owns("club")
	)


func test_buy_unknown_fails_unchanged() -> bool:
	var p := _fixture()
	var r := p.buy("ghost", 9999)
	return (
		not bool(r["success"])
		and int(r["new_balance"]) == 9999
		and not p.owns("ghost")
		and str(r["reason"]).contains("unknown")
	)


func test_buy_already_owned_fails() -> bool:
	var p := _fixture()
	p.buy("taxi", 2000)
	var r := p.buy("taxi", 2000)
	return not bool(r["success"]) and str(r["reason"]).contains("already owned")


func test_buy_insufficient_fails_unchanged() -> bool:
	var p := _fixture()
	var r := p.buy("club", 4999)
	return (
		not bool(r["success"])
		and int(r["new_balance"]) == 4999
		and not p.owns("club")
		and str(r["reason"]).contains("insufficient")
	)


func test_owned_ids_update_and_sorted() -> bool:
	var p := _fixture()
	p.buy("taxi", 2000)
	p.buy("club", 5000)
	return p.owned_ids() == ["club", "taxi"]


func test_accrue_grows_pending_with_days() -> bool:
	var p := _fixture()
	p.buy("club", 5000)
	p.accrue(3.0)
	return is_equal_approx(p.pending_income(), 600.0)


func test_accrue_sums_owned_businesses() -> bool:
	var p := _fixture()
	p.buy("club", 5000)
	p.buy("taxi", 2000)
	p.accrue(2.0)
	# (200 + 50) * 2 = 500
	return is_equal_approx(p.pending_income(), 500.0)


func test_accrue_negative_ignored() -> bool:
	var p := _fixture()
	p.buy("club", 5000)
	p.accrue(-4.0)
	return is_equal_approx(p.pending_income(), 0.0)


func test_accrue_with_none_owned_stays_zero() -> bool:
	var p := _fixture()
	p.accrue(5.0)
	return is_equal_approx(p.pending_income(), 0.0)


func test_collect_returns_pending_and_zeroes() -> bool:
	var p := _fixture()
	p.buy("club", 5000)
	p.accrue(2.0)
	var picked := p.collect()
	return picked == 400 and is_equal_approx(p.pending_income(), 0.0)


func test_collect_nothing_pending_is_zero() -> bool:
	var p := _fixture()
	return p.collect() == 0


func test_daily_income_sums_owned() -> bool:
	var p := _fixture()
	p.buy("club", 5000)
	p.buy("taxi", 2000)
	return p.daily_income() == 250


func test_daily_income_zero_with_none_owned() -> bool:
	return _fixture().daily_income() == 0


func test_has_safehouse_after_buying_one() -> bool:
	var p := _fixture()
	if p.has_safehouse():
		return false
	p.buy("loft", 1000)
	return p.has_safehouse() and p.nearest_safehouse_owned() == "loft"


func test_total_invested() -> bool:
	var p := _fixture()
	p.buy("loft", 1000)
	p.buy("club", 5000)
	return p.total_invested() == 6000


func test_serialize_restore_round_trip() -> bool:
	var p := _fixture()
	p.buy("club", 5000)
	p.buy("loft", 1000)
	p.accrue(2.0)
	var snapshot := p.serialize()
	var q := _fixture()
	q.restore(snapshot)
	return (
		q.owned_ids() == ["club", "loft"]
		and is_equal_approx(q.pending_income(), 400.0)
		and q.daily_income() == 200
	)


func test_restore_drops_unknown_ids() -> bool:
	var p := _fixture()
	p.restore({"owned": ["club", "ghost"], "pending": 10.0})
	return p.owned_ids() == ["club"] and is_equal_approx(p.pending_income(), 10.0)


func test_reset_clears_everything() -> bool:
	var p := _fixture()
	p.buy("club", 5000)
	p.accrue(3.0)
	p.reset()
	return (
		p.owned_ids().is_empty()
		and is_equal_approx(p.pending_income(), 0.0)
		and p.daily_income() == 0
	)
