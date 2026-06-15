extends RefCounted
## Unit tests for RadioReadout's pure display decisions. The scene wiring itself
## is covered by tests/radio_news_probe.gd.


func test_off_lines_are_hidden() -> bool:
	return (
		RadioReadout.should_hide_line("")
		and RadioReadout.should_hide_line("radio off")
		and RadioReadout.should_hide_line(" NO SIGNAL ")
	)


func test_playing_line_is_visible() -> bool:
	return not RadioReadout.should_hide_line("WAVE 87.4 - Neon Mirage")


func test_news_segment_labels_source_as_news() -> bool:
	return RadioReadout.source_for_segment("NEWS", "RADIO") == "NEWS"


func test_non_news_segment_uses_fallback_source() -> bool:
	return RadioReadout.source_for_segment("SONG", "RADIO") == "RADIO"
