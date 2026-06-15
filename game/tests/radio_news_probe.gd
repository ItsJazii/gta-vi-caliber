extends SceneTree
## Headless probe for RadioNewsDirector and the HUD radio readout.
##
## A wanted spike should file a CrimeReactionDirector headline, the radio director
## should self-wire to that headline queue, and the first scheduled NEWS slot should
## air and drain that exact line.
## Run headless:
##   godot --headless --path game --script res://tests/radio_news_probe.gd

const SETTLE_FRAMES: int = 3
const MAX_ADVANCES: int = 200
const RADIO_NEWS_SCRIPT := preload("res://scripts/systems/radio_news_director.gd")
const HUD_SCENE := preload("res://scenes/ui/game_hud.tscn")

var _crime: CrimeReactionDirector = null
var _radio: Node = null
var _mock: MockWanted = null
var _vehicle: MockVehicleRadio = null
var _hud: CanvasLayer = null
var _frames: int = 0
var _aired_news: String = ""


class MockWanted:
	extends Node
	signal stars_changed(stars: int)
	var _stars: int = 0

	func _ready() -> void:
		add_to_group("wanted")

	func stars() -> int:
		return _stars

	func escalate(to_stars: int) -> void:
		_stars = to_stars
		stars_changed.emit(to_stars)


class MockVehicleRadio:
	extends Node
	signal now_playing_changed(text: String)
	var _text: String = "RADIO OFF"

	func _ready() -> void:
		add_to_group("vehicle_radio")

	func now_playing_text() -> String:
		return _text

	func air(text: String) -> void:
		_text = text
		now_playing_changed.emit(text)


func _initialize() -> void:
	_mock = MockWanted.new()
	root.add_child(_mock)
	_vehicle = MockVehicleRadio.new()
	root.add_child(_vehicle)
	_crime = CrimeReactionDirector.new()
	root.add_child(_crime)
	_radio = RADIO_NEWS_SCRIPT.new()
	root.add_child(_radio)
	_radio.configure_program([], [], "VCX News")
	_radio.set_seed(23)
	_radio.connect("news_bulletin_aired", _on_news)
	_hud = HUD_SCENE.instantiate()
	root.add_child(_hud)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	return _run()


func _on_news(text: String) -> void:
	_aired_news = text


func _run() -> bool:
	if not _radio.has_news_source():
		return _fail("radio did not self-wire to CrimeReactionDirector.news")
	var vehicle_line := "WAVE 87.4 - Neon Mirage by The Pastel Hours"
	_vehicle.air(vehicle_line)
	if _readout_text() != vehicle_line:
		return _fail("radio readout did not show vehicle now-playing")
	_mock.escalate(4)
	var headline := _crime.news.peek_latest()
	if headline.is_empty():
		return _fail("crime did not file a headline")
	for _i in range(MAX_ADVANCES):
		var line: Dictionary = _radio.advance_program()
		if String(line.get("segment", "")) == "NEWS":
			return _check_news_line(headline, String(line.get("text", "")))
	return _fail("scheduler did not yield a NEWS slot within %d advances" % MAX_ADVANCES)


func _check_news_line(headline: String, text: String) -> bool:
	if text != headline:
		return _fail("NEWS slot aired '%s' instead of '%s'" % [text, headline])
	if _aired_news != headline:
		return _fail("news_bulletin_aired did not emit the headline")
	if _crime.news.has_pending():
		return _fail("headline queue was not drained")
	if _readout_text() != headline or _readout_source() != "NEWS":
		return _fail("radio readout did not surface the NEWS line")
	return _pass(headline)


func _pass(headline: String) -> bool:
	print("radio news probe: OK (aired '%s')" % headline)
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("radio news probe FAIL: %s" % reason)
	quit(1)
	return true


func _readout() -> Node:
	return get_first_node_in_group("radio_readout")


func _readout_text() -> String:
	var readout := _readout()
	if readout == null:
		return ""
	return String(readout.call("current_text"))


func _readout_source() -> String:
	var readout := _readout()
	if readout == null:
		return ""
	return String(readout.call("current_source"))
