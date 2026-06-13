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

## Seconds for the fade-to-black before the world loads.
@export var fade_time: float = 0.6

var _time: float = 0.0
var _starting: bool = false

@onready var _title: Label = $Center/VBox/Title
@onready var _subtitle: Label = $Center/VBox/Subtitle
@onready var _play: Button = $Center/VBox/Buttons/Play
@onready var _settings_btn: Button = $Center/VBox/Buttons/Settings
@onready var _quit: Button = $Center/VBox/Buttons/Quit
@onready var _settings: SettingsPanel = $Settings
@onready var _fade: ColorRect = $Fade


func _ready() -> void:
	# Boot-time: honour saved audio/display settings immediately.
	SettingsPanel.apply(SettingsPanel.load_settings(), get_tree())

	_settings.hide()
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


func _on_play() -> void:
	if _starting:
		return
	_starting = true
	_set_buttons_disabled(true)
	var tween := create_tween()
	tween.tween_property(_fade, "color", Color(0, 0, 0, 1), fade_time)
	tween.tween_callback(func(): get_tree().change_scene_to_file(PLAY_SCENE))


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
