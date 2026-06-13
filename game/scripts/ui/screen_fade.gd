class_name ScreenFade
extends CanvasLayer
## A full-screen black overlay for short transitions (stepping into a building).
## Code-built so it needs no .tscn. Await to_black() to darken, do the teleport
## while the screen is covered, then await from_black() to clear it.

@export var duration: float = 0.25

var _rect: ColorRect


func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


## Fade up to opaque black and return once the screen is fully covered.
func to_black() -> void:
	await _tween_alpha(1.0)


## Fade back to clear and return once the screen is fully visible again.
func from_black() -> void:
	await _tween_alpha(0.0)


func _tween_alpha(target: float) -> void:
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", target, duration)
	await tween.finished
