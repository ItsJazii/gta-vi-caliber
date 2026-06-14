extends SceneTree
## Runtime probe for SettingsPanel control rebinding.
##
## Instantiates the real settings scene, starts a jump rebind, feeds a key event,
## verifies the override reached InputMap + disk, then resets to project defaults.
## Run headless:
##   godot --headless --path game --script res://tests/settings_input_remap_probe.gd

const SETTINGS_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const SETTLE_FRAMES: int = 3

var _panel: SettingsPanel = null
var _frames: int = 0
var _saved_config_existed: bool = false
var _saved_config_text: String = ""


func _initialize() -> void:
	_backup_user_config()
	InputRemap.clear_overrides()
	InputRemap.restore_defaults()
	_panel = SETTINGS_SCENE.instantiate() as SettingsPanel
	root.add_child(_panel)
	_panel.show()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	return _run()


func _run() -> bool:
	_panel._begin_rebind("jump")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	_panel._input(key)
	var overrides := InputRemap.load_overrides()
	if not overrides.has("jump"):
		return _fail("jump override was not saved")
	if int(overrides["jump"][0].get("keycode", 0)) != KEY_J:
		return _fail("jump override saved the wrong key")
	if not _jump_is_bound_to(KEY_J):
		return _fail("InputMap did not receive the jump override")
	_panel._on_reset_bindings()
	if not InputRemap.load_overrides().is_empty():
		return _fail("reset did not clear saved overrides")
	if not _jump_is_bound_to(KEY_SPACE):
		return _fail("reset did not restore project default jump key")
	return _pass()


func _jump_is_bound_to(keycode: int) -> bool:
	for event in InputMap.action_get_events("jump"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _backup_user_config() -> void:
	var path := ProjectSettings.globalize_path(InputRemap.CONFIG_PATH)
	_saved_config_existed = FileAccess.file_exists(path)
	if not _saved_config_existed:
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		_saved_config_text = file.get_as_text()


func _restore_user_config() -> void:
	var path := ProjectSettings.globalize_path(InputRemap.CONFIG_PATH)
	if not _saved_config_existed:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(_saved_config_text)


func _pass() -> bool:
	print("settings input remap probe: OK (capture + reset)")
	_restore_user_config()
	InputRemap.apply_saved()
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("settings input remap probe FAIL: %s" % reason)
	_restore_user_config()
	InputRemap.apply_saved()
	quit(1)
	return true
