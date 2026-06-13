extends RefCounted
## Unit tests for NewsBulletin (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Deterministic: templates are chosen by severity, not RNG. Includes a StatTracker
## composition test (a crime count feeds a {count} headline).


func test_kinds_present() -> bool:
	var n := NewsBulletin.new()
	return n.kinds().has("crime") and n.kinds().has("heist")


func test_fresh_is_empty() -> bool:
	var n := NewsBulletin.new()
	return not n.has_pending() and n.pending_count() == 0 and n.peek_latest() == ""


func test_report_enqueues_headline() -> bool:
	var n := NewsBulletin.new()
	var text := n.report("crime", 1, {"place": "South Beach"})
	return text == "Petty crime reported in South Beach." and n.pending_count() == 1


func test_severity_picks_wording() -> bool:
	var n := NewsBulletin.new()
	var low := n.report("crime", 1, {"place": "downtown"})
	var high := n.report("crime", 5, {"place": "downtown"})
	return low != high and high == "City-wide manhunt underway across downtown."


func test_severity_clamps_to_top_template() -> bool:
	var n := NewsBulletin.new()
	# rampage has 3 tiers; severity 5 clamps to the last.
	var text := n.report("rampage", 5, {"place": "the docks"})
	return text == "the docks locked down amid a violent rampage."


func test_place_defaults() -> bool:
	var n := NewsBulletin.new()
	return n.report("crime", 1) == "Petty crime reported in the city."


func test_unknown_kind_is_ignored() -> bool:
	var n := NewsBulletin.new()
	return n.report("gossip", 1) == "" and not n.has_pending()


func test_next_bulletin_is_fifo() -> bool:
	var n := NewsBulletin.new()
	n.report("crime", 1, {"place": "A"})
	n.report("heist", 1, {"place": "B"})
	var first := n.next_bulletin()
	var second := n.next_bulletin()
	return first.contains("A") and second.contains("B") and not n.has_pending()


func test_next_bulletin_filler_when_empty() -> bool:
	var n := NewsBulletin.new()
	return n.next_bulletin() == NewsBulletin.FILLER


func test_queue_bounded() -> bool:
	var n := NewsBulletin.new()
	for _i in range(NewsBulletin.MAX_QUEUE + 5):
		n.report("crime", 1)
	return n.pending_count() == NewsBulletin.MAX_QUEUE


func test_recent_newest_first() -> bool:
	var n := NewsBulletin.new()
	n.report("crime", 1, {"place": "first"})
	n.report("crime", 1, {"place": "second"})
	var recent := n.recent(2)
	return recent.size() == 2 and recent[0].contains("second") and recent[1].contains("first")


func test_clear_empties_queue() -> bool:
	var n := NewsBulletin.new()
	n.report("heist", 3)
	n.clear()
	return not n.has_pending()


func test_count_from_stat_tracker() -> bool:
	# Composition: a crime count from StatTracker fills a {count} headline.
	var st := StatTracker.new()
	st.add("crimes", 1.0)
	st.add("crimes", 1.0)
	st.add("crimes", 1.0)
	var n := NewsBulletin.new()
	var text := n.report("spree", 2, {"count": int(st.get_stat("crimes"))})
	return text == "Crime spree: 3 offences and counting."
