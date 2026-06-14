class_name RadioReadout
extends Panel
## Small HUD bridge for vehicle radio and reactive city-news lines.
##
## VehicleRadio owns the station/track cursor. RadioNewsDirector owns scheduled
## DJ/ad/news copy. This control listens to both by group and renders the latest
## useful line without writing back to gameplay state.

const OFF_LINES: Array[String] = ["", "RADIO OFF", "NO SIGNAL"]

@export var default_source: String = "RADIO"

var _vehicle_radio: Node = null
var _radio_news: Node = null
var _current_source: String = ""
var _current_text: String = ""

@onready var _source_label: Label = $Margin/VBox/Source
@onready var _line_label: Label = $Margin/VBox/Line


func _ready() -> void:
	add_to_group("radio_readout")
	_set_line("", "")
	call_deferred("_bind")


func bind_vehicle_radio(radio: Node) -> void:
	_vehicle_radio = radio
	if radio == null:
		return
	var callback := Callable(self, "_on_vehicle_now_playing")
	if (
		radio.has_signal("now_playing_changed")
		and not radio.is_connected("now_playing_changed", callback)
	):
		radio.connect("now_playing_changed", callback)
	if radio.has_method("now_playing_text"):
		_on_vehicle_now_playing(String(radio.call("now_playing_text")))


func bind_radio_news(director: Node) -> void:
	_radio_news = director
	if director == null:
		return
	var callback := Callable(self, "_on_program_line_aired")
	if (
		director.has_signal("program_line_aired")
		and not director.is_connected("program_line_aired", callback)
	):
		director.connect("program_line_aired", callback)
	if director.has_method("last_line"):
		var line: Dictionary = director.call("last_line")
		_on_program_line_aired(String(line.get("text", "")), String(line.get("segment", "")))


func current_source() -> String:
	return _current_source


func current_text() -> String:
	return _current_text


static func source_for_segment(segment: String, fallback: String) -> String:
	return "NEWS" if segment == "NEWS" else fallback


static func should_hide_line(text: String) -> bool:
	return OFF_LINES.has(text.strip_edges().to_upper())


func _bind() -> void:
	bind_vehicle_radio(_first("vehicle_radio"))
	bind_radio_news(_first("radio_news"))


func _on_vehicle_now_playing(text: String) -> void:
	if should_hide_line(text):
		_set_line("", "")
		return
	_set_line(default_source, text)


func _on_program_line_aired(text: String, segment: String) -> void:
	if should_hide_line(text):
		return
	var source := source_for_segment(segment, default_source)
	_set_line(source, text)


func _set_line(source: String, text: String) -> void:
	_current_source = source.strip_edges()
	_current_text = text.strip_edges()
	visible = not _current_text.is_empty()
	_source_label.text = _current_source
	_line_label.text = _current_text


func _first(group: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null
