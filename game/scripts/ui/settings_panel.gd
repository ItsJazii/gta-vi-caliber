class_name SettingsPanel
extends Control
## Shared settings overlay used by both the main menu and the pause menu.
##
## Exposes master volume, fullscreen and mouse-sensitivity controls and applies
## them to the live engine (AudioServer / DisplayServer). Settings persist to
## user://settings.cfg so they survive between sessions and across scene loads.
## The audio/sensitivity maths live in static helpers so they can be unit-tested
## without a running tree (tests/unit/test_settings_panel.gd).

signal closed

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "options"
const MASTER_BUS: String = "Master"

## Slider 0 maps to silence; this is the dB applied at the top of the slider.
const MAX_DB: float = 0.0
## Below this slider value the bus is fully muted instead of a very low dB.
const MUTE_THRESHOLD: float = 0.001

@onready var _volume: HSlider = $Panel/Margin/VBox/VolumeRow/Volume
@onready var _fullscreen: CheckButton = $Panel/Margin/VBox/FullscreenRow/Fullscreen
@onready var _sensitivity: HSlider = $Panel/Margin/VBox/SensRow/Sensitivity
@onready var _back: Button = $Panel/Margin/VBox/Back


func _ready() -> void:
	var cfg := load_settings()
	_volume.value = cfg["volume"]
	_fullscreen.button_pressed = cfg["fullscreen"]
	_sensitivity.value = cfg["sensitivity"]
	apply(cfg)

	_volume.value_changed.connect(func(_v): _on_changed())
	_sensitivity.value_changed.connect(func(_v): _on_changed())
	_fullscreen.toggled.connect(func(_v): _on_changed())
	_back.pressed.connect(_on_back)


func _on_changed() -> void:
	var cfg := current()
	apply(cfg)
	save_settings(cfg)


func current() -> Dictionary:
	return {
		"volume": _volume.value,
		"fullscreen": _fullscreen.button_pressed,
		"sensitivity": _sensitivity.value,
	}


func _on_back() -> void:
	hide()
	closed.emit()


# --- Engine application ---------------------------------------------------


## Push a settings dict onto the live engine. Static so it has no node deps
## beyond the global servers; callable before the panel is in the tree.
static func apply(cfg: Dictionary) -> void:
	var bus := AudioServer.get_bus_index(MASTER_BUS)
	if bus >= 0:
		var vol := float(cfg.get("volume", 0.8))
		AudioServer.set_bus_mute(bus, vol < MUTE_THRESHOLD)
		AudioServer.set_bus_volume_db(bus, volume_to_db(vol))
	var mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if bool(cfg.get("fullscreen", false))
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)


# --- Pure helpers (unit-tested) ------------------------------------------


## Map a 0..1 slider value to a bus dB. 0 (and anything under the mute
## threshold) returns -80 dB (effectively silent); 1 returns MAX_DB. The curve
## is perceptual (linear_to_db) so the slider feels even to the ear.
static func volume_to_db(value: float) -> float:
	var v := clampf(value, 0.0, 1.0)
	if v < MUTE_THRESHOLD:
		return -80.0
	return clampf(linear_to_db(v), -80.0, MAX_DB)


## Map a 0..1 slider value to a mouse-look multiplier in [0.25, 2.0], with the
## default 0.5 landing on 1.0x so the midpoint is "normal" sensitivity.
static func sensitivity_to_multiplier(value: float) -> float:
	var v := clampf(value, 0.0, 1.0)
	if v <= 0.5:
		return lerpf(0.25, 1.0, v / 0.5)
	return lerpf(1.0, 2.0, (v - 0.5) / 0.5)


# --- Persistence ----------------------------------------------------------


static func defaults() -> Dictionary:
	return {"volume": 0.8, "fullscreen": false, "sensitivity": 0.5}


static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	var out := defaults()
	if cfg.load(CONFIG_PATH) != OK:
		return out
	out["volume"] = clampf(float(cfg.get_value(SECTION, "volume", out["volume"])), 0.0, 1.0)
	out["fullscreen"] = bool(cfg.get_value(SECTION, "fullscreen", out["fullscreen"]))
	out["sensitivity"] = clampf(
		float(cfg.get_value(SECTION, "sensitivity", out["sensitivity"])), 0.0, 1.0
	)
	return out


static func save_settings(cfg_dict: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "volume", cfg_dict.get("volume", 0.8))
	cfg.set_value(SECTION, "fullscreen", cfg_dict.get("fullscreen", false))
	cfg.set_value(SECTION, "sensitivity", cfg_dict.get("sensitivity", 0.5))
	cfg.save(CONFIG_PATH)
