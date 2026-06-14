extends RefCounted
## Unit tests for InputRemap (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). Covers the pure conversion/merge/
## validation/persistence and a small InputMap capture integration path.

const TEST_PATH: String = "user://test_input_remap.cfg"


func test_key_round_trips() -> bool:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	var rebuilt := InputRemap.dict_to_event(InputRemap.event_to_dict(key)) as InputEventKey
	return rebuilt != null and rebuilt.physical_keycode == KEY_W


func test_joy_button_round_trips() -> bool:
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	var dict := InputRemap.event_to_dict(button)
	var rebuilt := InputRemap.dict_to_event(dict) as InputEventJoypadButton
	return dict["type"] == "joy_button" and rebuilt.button_index == JOY_BUTTON_A


func test_mouse_button_round_trips() -> bool:
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	var dict := InputRemap.event_to_dict(mouse)
	var rebuilt := InputRemap.dict_to_event(dict) as InputEventMouseButton
	return dict["type"] == "mouse_button" and rebuilt.button_index == MOUSE_BUTTON_LEFT


func test_joy_axis_round_trips_sign() -> bool:
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.7
	var rebuilt := (
		InputRemap.dict_to_event(InputRemap.event_to_dict(motion)) as InputEventJoypadMotion
	)
	# Sign is preserved and normalized to a full ±1 deflection.
	return rebuilt.axis == JOY_AXIS_LEFT_X and absf(rebuilt.axis_value - 1.0) < 0.0001


func test_unknown_event_serializes_empty() -> bool:
	return InputRemap.event_to_dict(InputEventMouseMotion.new()).is_empty()


func test_dict_to_event_rejects_unknown() -> bool:
	return InputRemap.dict_to_event({"type": "telepathy"}) == null


func test_merge_override_replaces_action() -> bool:
	var defaults := {"jump": [{"type": "key", "keycode": KEY_SPACE}]}
	var overrides := {"jump": [{"type": "joy_button", "index": JOY_BUTTON_A}]}
	var merged := InputRemap.merge(defaults, overrides)
	return merged["jump"][0]["type"] == "joy_button"


func test_merge_passes_through_untouched_actions() -> bool:
	var defaults := {"jump": [{"type": "key", "keycode": KEY_SPACE}], "fire": []}
	var merged := InputRemap.merge(defaults, {"fire": [{"type": "key", "keycode": KEY_F}]})
	return merged["jump"][0]["keycode"] == KEY_SPACE


func test_merge_does_not_mutate_defaults() -> bool:
	var defaults := {"jump": [{"type": "key", "keycode": KEY_SPACE}]}
	InputRemap.merge(defaults, {"jump": [{"type": "key", "keycode": KEY_J}]})
	return defaults["jump"][0]["keycode"] == KEY_SPACE


func test_is_valid_accepts_well_formed() -> bool:
	return InputRemap.is_valid({"jump": [{"type": "key", "keycode": KEY_SPACE}]})


func test_is_valid_rejects_empty_event_list() -> bool:
	return not InputRemap.is_valid({"jump": []})


func test_is_valid_rejects_malformed_event() -> bool:
	return not InputRemap.is_valid({"jump": [{"type": "nope"}]})


func test_save_and_load_overrides_round_trip() -> bool:
	_delete_test_file()
	var overrides := {"jump": [{"type": "joy_button", "index": JOY_BUTTON_A}]}
	var err := InputRemap.save_overrides(overrides, TEST_PATH)
	var loaded := InputRemap.load_overrides(TEST_PATH)
	_delete_test_file()
	return err == OK and loaded.has("jump") and loaded["jump"][0]["index"] == JOY_BUTTON_A


func test_save_overrides_rejects_malformed() -> bool:
	_delete_test_file()
	var err := InputRemap.save_overrides({"jump": []}, TEST_PATH)
	_delete_test_file()
	return err == ERR_INVALID_DATA


func test_load_overrides_ignores_malformed_entries() -> bool:
	_delete_test_file()
	var cfg := ConfigFile.new()
	cfg.set_value(InputRemap.SECTION, "jump", [{"type": "joy_button", "index": JOY_BUTTON_A}])
	cfg.set_value(InputRemap.SECTION, "sprint", [])
	cfg.save(TEST_PATH)
	var loaded := InputRemap.load_overrides(TEST_PATH)
	_delete_test_file()
	return loaded.has("jump") and not loaded.has("sprint")


func test_capture_keeps_mouse_button_defaults() -> bool:
	var action := "__test_mouse_capture"
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event(action, mouse)
	var captured := InputRemap.capture(PackedStringArray([action]))
	InputMap.erase_action(action)
	return (
		captured.has(action)
		and captured[action].size() == 1
		and captured[action][0]["type"] == "mouse_button"
	)


func test_project_defaults_reads_authored_jump() -> bool:
	var defaults := InputRemap.project_defaults(PackedStringArray(["jump"]))
	return defaults.has("jump") and not defaults["jump"].is_empty()


func test_action_label_humanizes_action_id() -> bool:
	return InputRemap.action_label("move_forward") == "Move Forward"


func test_event_label_humanizes_mouse_button() -> bool:
	return (
		InputRemap.event_label({"type": "mouse_button", "index": MOUSE_BUTTON_LEFT}) == "Mouse Left"
	)


func test_first_event_label_handles_missing_action() -> bool:
	return InputRemap.first_event_label({}, "jump") == "Unbound"


func _delete_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
