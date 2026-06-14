class_name PauseMenu
extends CanvasLayer
## In-game pause overlay. Drop into any world scene; toggles on the "pause"
## action (Esc). Pauses the SceneTree, dims the world and offers Resume /
## Settings / Quit to Menu. Set to PROCESS_MODE_ALWAYS so it keeps running
## while the rest of the tree is frozen.

## Scene returned to from "Quit to Menu".
const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

@onready var _root: Control = $Root
@onready var _resume: Button = $Root/Center/VBox/Resume
@onready var _settings_btn: Button = $Root/Center/VBox/Settings
@onready var _quit: Button = $Root/Center/VBox/QuitToMenu
@onready var _settings: SettingsPanel = $Root/Settings


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.hide()
	_settings.hide()
	_resume.pressed.connect(resume)
	_settings_btn.pressed.connect(_settings.show)
	_quit.pressed.connect(_on_quit)
	_settings.closed.connect(func(): _resume.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if _settings.visible:
		_settings.hide()
		_resume.grab_focus()
	elif get_tree().paused:
		resume()
	else:
		_open()


func _open() -> void:
	get_tree().paused = true
	_root.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume.grab_focus()


func resume() -> void:
	_settings.hide()
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
