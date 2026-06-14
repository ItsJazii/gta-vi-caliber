class_name SettingsPanel
extends Control
## Shared settings overlay used by both the main menu and the pause menu.
##
## Exposes master volume, fullscreen and mouse-sensitivity controls and applies
## them to the live engine (AudioServer / DisplayServer). Settings persist to
## user://settings.cfg so they survive between sessions and across scene loads.
## Saved input remaps are applied at the same boot-time hook. The
## audio/sensitivity maths live in static helpers so they can be unit-tested
## without a running tree (tests/unit/test_settings_panel.gd).

signal closed

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "options"
const MASTER_BUS: String = "Master"

## Slider 0 maps to silence; this is the dB applied at the top of the slider.
const MAX_DB: float = 0.0
## Below this slider value the bus is fully muted instead of a very low dB.
const MUTE_THRESHOLD: float = 0.001

var _binding_buttons: Dictionary = {}
var _pending_action: String = ""

@onready var _volume: HSlider = $Panel/Margin/VBox/VolumeRow/Volume
@onready var _fullscreen: CheckButton = $Panel/Margin/VBox/FullscreenRow/Fullscreen
@onready var _graphics: OptionButton = $Panel/Margin/VBox/GraphicsRow/Graphics
@onready var _sensitivity: HSlider = $Panel/Margin/VBox/SensRow/Sensitivity
@onready var _bindings: VBoxContainer = $Panel/Margin/VBox/BindingsScroll/Bindings
@onready var _reset_bindings: Button = $Panel/Margin/VBox/ResetBindings
@onready var _back: Button = $Panel/Margin/VBox/Back


func _ready() -> void:
	var cfg := load_settings()
	_volume.value = cfg["volume"]
	_fullscreen.button_pressed = cfg["fullscreen"]
	_graphics.selected = cfg["graphics"]
	_sensitivity.value = cfg["sensitivity"]
	apply(cfg, get_tree())
	_build_binding_rows()
	_refresh_binding_rows()

	_volume.value_changed.connect(func(_v): _on_changed())
	_sensitivity.value_changed.connect(func(_v): _on_changed())
	_fullscreen.toggled.connect(func(_v): _on_changed())
	_graphics.item_selected.connect(func(_idx): _on_changed())
	_reset_bindings.pressed.connect(_on_reset_bindings)
	_back.pressed.connect(_on_back)


func _input(event: InputEvent) -> void:
	if _pending_action == "" or not visible:
		return
	if _is_cancel_event(event):
		_finish_rebind("")
		accept_event()
		return
	if not _is_rebind_event(event):
		return
	var cfg := InputRemap.event_to_dict(event)
	if cfg.is_empty():
		return
	var overrides := InputRemap.load_overrides()
	overrides[_pending_action] = [cfg]
	if InputRemap.save_overrides(overrides) == OK:
		InputRemap.apply_saved()
	_finish_rebind("")
	_refresh_binding_rows()
	accept_event()


func _on_changed() -> void:
	var cfg := current()
	apply(cfg, get_tree())
	save_settings(cfg)


func current() -> Dictionary:
	return {
		"volume": _volume.value,
		"fullscreen": _fullscreen.button_pressed,
		"sensitivity": _sensitivity.value,
		"graphics": _graphics.selected,
	}


func _on_back() -> void:
	_finish_rebind("")
	hide()
	closed.emit()


func _build_binding_rows() -> void:
	for child in _bindings.get_children():
		child.queue_free()
	_binding_buttons.clear()
	for action in rebind_actions():
		var row := HBoxContainer.new()
		row.name = "%sRow" % action
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.custom_minimum_size = Vector2(150, 0)
		label.text = InputRemap.action_label(action)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_begin_rebind.bind(action))
		row.add_child(button)
		_binding_buttons[action] = button
		_bindings.add_child(row)


func _begin_rebind(action: String) -> void:
	_finish_rebind(action)
	var button := _binding_buttons.get(action) as Button
	if button != null:
		button.text = "Press key/button"
		button.grab_focus()


func _finish_rebind(next_action: String) -> void:
	if _pending_action != "" and _binding_buttons.has(_pending_action):
		var button := _binding_buttons[_pending_action] as Button
		if button != null:
			button.text = _label_for_action(_pending_action)
	_pending_action = next_action


func _on_reset_bindings() -> void:
	_finish_rebind("")
	InputRemap.restore_defaults()
	_refresh_binding_rows()


func _refresh_binding_rows() -> void:
	var current_bindings := InputRemap.capture(rebind_actions())
	for action in _binding_buttons:
		var button := _binding_buttons[action] as Button
		if button != null:
			button.text = InputRemap.first_event_label(current_bindings, action)


func _label_for_action(action: String) -> String:
	return InputRemap.first_event_label(InputRemap.capture(rebind_actions()), action)


func _is_rebind_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= 0.5
	return false


func _is_cancel_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE
	return false


static func rebind_actions() -> PackedStringArray:
	return PackedStringArray(
		[
			"move_forward",
			"move_back",
			"move_left",
			"move_right",
			"jump",
			"sprint",
			"interact",
			"look_behind",
			"fire",
			"aim",
			"reload",
			"melee",
			"dive",
			"phone",
			"weapon_wheel",
			"throw_grenade",
		]
	)


# --- Engine application ---------------------------------------------------


## Push a settings dict onto the live engine. Static so it has no node deps
## beyond the global servers; callable before the panel is in the tree.
static func apply(cfg: Dictionary, tree: SceneTree = null) -> void:
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
	apply_graphics(int(cfg.get("graphics", 1)), tree)
	InputRemap.apply_saved()


## Applies the graphics quality presets.
static func apply_graphics(quality: int, tree: SceneTree) -> void:
	if not tree or not tree.root:
		return
	var root := tree.root
	match quality:
		0:  # Low
			root.msaa_3d = Viewport.MSAA_DISABLED
			root.scaling_3d_scale = 0.75
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		1:  # Medium
			root.msaa_3d = Viewport.MSAA_2X
			root.scaling_3d_scale = 1.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
		2:  # High
			root.msaa_3d = Viewport.MSAA_4X
			root.scaling_3d_scale = 1.0
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
	tree.call_group("density_aware", "apply_graphics_setting", quality)


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
	return {"volume": 0.8, "fullscreen": false, "sensitivity": 0.5, "graphics": 1}


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
	out["graphics"] = int(cfg.get_value(SECTION, "graphics", out["graphics"]))
	return out


static func save_settings(cfg_dict: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "volume", cfg_dict.get("volume", 0.8))
	cfg.set_value(SECTION, "fullscreen", cfg_dict.get("fullscreen", false))
	cfg.set_value(SECTION, "sensitivity", cfg_dict.get("sensitivity", 0.5))
	cfg.set_value(SECTION, "graphics", cfg_dict.get("graphics", 1))
	cfg.save(CONFIG_PATH)
