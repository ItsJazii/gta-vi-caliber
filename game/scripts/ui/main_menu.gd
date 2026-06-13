class_name MainMenu
extends Control
## Start page / main menu — the game's entry scene.
##
## Procedural dusk-skyline backdrop, an animated title and the primary actions
## (Play / Settings / Quit). "Play" fades to black then loads the sandbox world.
## Settings are applied on boot so audio + window mode are correct before the
## player ever reaches gameplay. No gameplay logic lives here.

## World scene loaded when the player presses Play.
const PLAY_SCENE: String = "res://scenes/world/miami.tscn"
const BENCHMARK_SCENE: String = "res://scenes/tests/benchmark_runner.tscn"

## Seconds for the fade-to-black before the world loads.
@export var fade_time: float = 0.6

var _time: float = 0.0
var _starting: bool = false
var _fade_finished: bool = false

@onready var _title: Label = $Center/VBox/Title
@onready var _subtitle: Label = $Center/VBox/Subtitle
@onready var _play: Button = $Center/VBox/Buttons/Play
@onready var _settings_btn: Button = $Center/VBox/Buttons/Settings
@onready var _quit: Button = $Center/VBox/Buttons/Quit
@onready var _settings: SettingsPanel = $Settings
@onready var _fade: ColorRect = $Fade
@onready var _loading: Label = $Loading


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--benchmark"):
		get_tree().call_deferred("change_scene_to_file", BENCHMARK_SCENE)
		return

	# Boot-time: honour saved audio/display settings immediately.
	SettingsPanel.apply(SettingsPanel.load_settings(), get_tree())

	_settings.hide()
	_loading.hide()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_play.pressed.connect(_on_play)
	_settings_btn.pressed.connect(_on_settings)
	_quit.pressed.connect(_on_quit)
	_settings.closed.connect(_on_settings_closed)

	_play.grab_focus()
	# Fade up from black on entry.
	_fade.color = Color(0, 0, 0, 1)
	create_tween().tween_property(_fade, "color", Color(0, 0, 0, 0), 0.5)


func _process(delta: float) -> void:
	_time += delta
	# Gentle breathing glow on the title; subtitle does a slow shimmer.
	var pulse := 0.5 + 0.5 * sin(_time * 1.4)
	_title.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.78, 0.45), 0.35 * pulse)
	_subtitle.modulate.a = 0.55 + 0.25 * sin(_time * 0.9)
	if _starting:
		_poll_play_scene()


func _on_play() -> void:
	if _starting:
		return
	_starting = true
	_fade_finished = false
	_set_buttons_disabled(true)
	_loading.text = SceneLoadState.loading_text([])
	_loading.show()
	var error := ResourceLoader.load_threaded_request(PLAY_SCENE, "PackedScene")
	if error != OK:
		_cancel_start("LOAD FAILED")
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color", Color(0, 0, 0, 1), fade_time)
	tween.tween_callback(func(): _fade_finished = true)


func _poll_play_scene() -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(PLAY_SCENE, progress)
	_loading.text = SceneLoadState.loading_text(progress)
	if SceneLoadState.has_failed(status):
		_cancel_start("LOAD FAILED")
		return
	if not SceneLoadState.can_enter_world(status, _fade_finished):
		return
	var packed := ResourceLoader.load_threaded_get(PLAY_SCENE) as PackedScene
	if packed == null:
		_cancel_start("LOAD FAILED")
		return
	set_process(false)
	get_tree().change_scene_to_packed(packed)


func _cancel_start(message: String) -> void:
	_starting = false
	_fade_finished = false
	_loading.text = message
	_set_buttons_disabled(false)
	create_tween().tween_property(_fade, "color", Color(0, 0, 0, 0), 0.2)


func _on_settings() -> void:
	_settings.show()


func _on_settings_closed() -> void:
	_play.grab_focus()


func _on_quit() -> void:
	get_tree().quit()


func _set_buttons_disabled(disabled: bool) -> void:
	_play.disabled = disabled
	_settings_btn.disabled = disabled
	_quit.disabled = disabled
