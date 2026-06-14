class_name InputRemap
extends RefCounted
## Rebindable input: (de)serialize InputEvents to plain dicts, merge user
## overrides onto defaults, and apply a config to the live InputMap. The pure
## conversion/merge/validation/persistence is unit-tested
## (tests/unit/test_input_remap.gd); the apply/capture helpers touch the
## InputMap singleton and are the thin layer a settings screen or the save
## system calls. Supports the event kinds a rebind UI produces: keyboard keys,
## mouse buttons, gamepad buttons, and gamepad axes.

const CONFIG_PATH: String = "user://input_remap.cfg"
const SECTION: String = "bindings"


## Serialize one InputEvent to a savable dict, or {} if it's a kind we don't
## persist (so callers can filter it out).
static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "keycode": (event as InputEventKey).physical_keycode}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "index": (event as InputEventMouseButton).button_index}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "index": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": motion.axis, "value": signf(motion.axis_value)}
	return {}


## Rebuild an InputEvent from a dict produced by event_to_dict, or null if the
## dict is malformed/unknown.
static func dict_to_event(cfg: Dictionary) -> InputEvent:
	match cfg.get("type", ""):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(cfg.get("keycode", 0))
			return key
		"mouse_button":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(cfg.get("index", 0))
			return mouse
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(cfg.get("index", 0))
			return button
		"joy_axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(cfg.get("axis", 0))
			motion.axis_value = float(cfg.get("value", 1.0))
			return motion
	return null


## Merge user overrides onto defaults: an action present in `overrides` replaces
## the whole event list for that action; actions only in `defaults` pass through.
## Returns a new dict and never mutates its inputs.
static func merge(defaults: Dictionary, overrides: Dictionary) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	for action in overrides:
		result[action] = overrides[action]
	return result


## True when `config` is a well-formed action->event-list map: every value is a
## non-empty Array of dicts that dict_to_event can rebuild.
static func is_valid(config: Dictionary) -> bool:
	for action in config:
		var events = config[action]
		if not (events is Array) or (events as Array).is_empty():
			return false
		for event_cfg in events:
			if not (event_cfg is Dictionary) or dict_to_event(event_cfg) == null:
				return false
	return true


## Read the current bindings for `actions` from the live InputMap into a config
## dict (the defaults a rebind UI starts from). Unknown actions are skipped.
static func capture(actions: PackedStringArray) -> Dictionary:
	var config: Dictionary = {}
	for action in actions:
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action):
			var cfg := event_to_dict(event)
			if not cfg.is_empty():
				events.append(cfg)
		config[action] = events
	return config


## Read the bindings authored in project.godot, not the current live InputMap.
## This gives settings UI a true "reset controls" target even after overrides
## have already been applied to the singleton.
static func project_defaults(actions: PackedStringArray) -> Dictionary:
	var config: Dictionary = {}
	for action in actions:
		var setting_key := "input/%s" % action
		if not ProjectSettings.has_setting(setting_key):
			continue
		var setting = ProjectSettings.get_setting(setting_key)
		if not (setting is Dictionary):
			continue
		var setting_events = setting.get("events", [])
		if not (setting_events is Array):
			continue
		var events: Array = []
		for event in setting_events:
			if not (event is InputEvent):
				continue
			var cfg := event_to_dict(event)
			if not cfg.is_empty():
				events.append(cfg)
		if not events.is_empty():
			config[action] = events
	return config


## Apply a config to the live InputMap, replacing each named action's events.
## Ignores actions that don't exist and malformed event dicts. Returns the count
## of actions actually rebound.
static func apply(config: Dictionary) -> int:
	var rebound := 0
	for action in config:
		if not InputMap.has_action(action):
			continue
		var events = config[action]
		if not (events is Array):
			continue
		InputMap.action_erase_events(action)
		for event_cfg in events:
			var event := dict_to_event(event_cfg)
			if event != null:
				InputMap.action_add_event(action, event)
		rebound += 1
	return rebound


## Canonical gameplay actions whose remaps should persist between sessions.
static func default_actions() -> PackedStringArray:
	return PackedStringArray(
		[
			"move_left",
			"move_right",
			"move_forward",
			"move_back",
			"jump",
			"sprint",
			"interact",
			"look_behind",
			"fire",
			"aim",
			"reload",
			"holster",
			"melee",
			"quick_save",
			"quick_load",
			"weapon_next",
			"dive",
			"pause",
			"phone",
			"weapon_wheel",
			"throw_grenade",
		]
	)


## Persist user overrides only. Callers usually capture the project defaults,
## merge these overrides on top, then apply the merged config.
static func save_overrides(overrides: Dictionary, path: String = CONFIG_PATH) -> int:
	if not overrides.is_empty() and not is_valid(overrides):
		return ERR_INVALID_DATA
	var cfg := ConfigFile.new()
	for action in overrides:
		cfg.set_value(SECTION, str(action), overrides[action])
	return cfg.save(path)


## Remove user overrides so the next boot falls back to project.godot bindings.
static func clear_overrides(path: String = CONFIG_PATH) -> int:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Load saved user overrides. Malformed entries are ignored so a hand-edited or
## stale config file cannot break input at boot.
static func load_overrides(path: String = CONFIG_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var out: Dictionary = {}
	if cfg.load(path) != OK or not cfg.has_section(SECTION):
		return out
	for action in cfg.get_section_keys(SECTION):
		var events = cfg.get_value(SECTION, action, [])
		var candidate := {action: events}
		if is_valid(candidate):
			out[action] = events
	return out


## Capture the live project defaults, merge saved user overrides, and apply the
## result. Returns the number of actions rebound.
static func apply_saved(
	actions: PackedStringArray = PackedStringArray(), path: String = CONFIG_PATH
) -> int:
	var resolved_actions := actions
	if resolved_actions.is_empty():
		resolved_actions = default_actions()
	var defaults := project_defaults(resolved_actions)
	if defaults.is_empty():
		defaults = capture(resolved_actions)
	var effective := merge(defaults, load_overrides(path))
	if not is_valid(effective):
		return 0
	return apply(effective)


## Apply project defaults and clear saved overrides in one call.
static func restore_defaults(
	actions: PackedStringArray = PackedStringArray(), path: String = CONFIG_PATH
) -> int:
	var resolved_actions := actions
	if resolved_actions.is_empty():
		resolved_actions = default_actions()
	var defaults := project_defaults(resolved_actions)
	if defaults.is_empty():
		defaults = capture(resolved_actions)
	var rebound := apply(defaults)
	clear_overrides(path)
	return rebound


static func action_label(action: String) -> String:
	return action.replace("_", " ").capitalize()


static func first_event_label(config: Dictionary, action: String) -> String:
	if not config.has(action):
		return "Unbound"
	var events = config[action]
	if not (events is Array) or (events as Array).is_empty():
		return "Unbound"
	return event_label((events as Array)[0])


static func event_label(event_cfg: Dictionary) -> String:
	match event_cfg.get("type", ""):
		"key":
			var text := OS.get_keycode_string(int(event_cfg.get("keycode", 0)))
			return text if text != "" else "Key"
		"mouse_button":
			return _mouse_button_label(int(event_cfg.get("index", 0)))
		"joy_button":
			return _joy_button_label(int(event_cfg.get("index", 0)))
		"joy_axis":
			return _joy_axis_label(
				int(event_cfg.get("axis", 0)), float(event_cfg.get("value", 1.0))
			)
	return "Unknown"


static func _mouse_button_label(index: int) -> String:
	match index:
		MOUSE_BUTTON_LEFT:
			return "Mouse Left"
		MOUSE_BUTTON_RIGHT:
			return "Mouse Right"
		MOUSE_BUTTON_MIDDLE:
			return "Mouse Middle"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
	return "Mouse %d" % index


static func _joy_button_label(index: int) -> String:
	match index:
		JOY_BUTTON_A:
			return "Pad A"
		JOY_BUTTON_B:
			return "Pad B"
		JOY_BUTTON_X:
			return "Pad X"
		JOY_BUTTON_Y:
			return "Pad Y"
		JOY_BUTTON_BACK:
			return "Pad Back"
		JOY_BUTTON_START:
			return "Pad Start"
		JOY_BUTTON_LEFT_STICK:
			return "Pad L3"
		JOY_BUTTON_RIGHT_STICK:
			return "Pad R3"
		JOY_BUTTON_LEFT_SHOULDER:
			return "Pad LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "Pad RB"
	return "Pad Button %d" % index


static func _joy_axis_label(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left Stick X%s" % _axis_sign(value)
		JOY_AXIS_LEFT_Y:
			return "Left Stick Y%s" % _axis_sign(value)
		JOY_AXIS_RIGHT_X:
			return "Right Stick X%s" % _axis_sign(value)
		JOY_AXIS_RIGHT_Y:
			return "Right Stick Y%s" % _axis_sign(value)
		JOY_AXIS_TRIGGER_LEFT:
			return "Pad LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "Pad RT"
	return "Pad Axis %d%s" % [axis, _axis_sign(value)]


static func _axis_sign(value: float) -> String:
	if value < 0.0:
		return "-"
	return "+"
