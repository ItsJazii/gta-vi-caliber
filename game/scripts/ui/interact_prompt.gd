class_name InteractPrompt
extends CanvasLayer
## Tiny code-built HUD overlay that shows the current interact hint (e.g.
## "Enter shop") near the bottom-centre of the screen, or nothing when there is
## no target in reach. Built in code and spawned by Player, like the phone and
## footstep audio, so it never touches a .tscn and can't collide with parallel
## scene edits. A dumb view: Player pushes text via set_prompt(); empty hides it.

var _label: Label


func _ready() -> void:
	layer = 50
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -240.0
	_label.offset_right = 240.0
	_label.offset_top = -104.0
	_label.offset_bottom = -64.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_label.visible = false


## Show `text` as the active hint, or hide the overlay when it is empty.
func set_prompt(text: String) -> void:
	if text == "":
		_label.visible = false
		return
	_label.text = text
	_label.visible = true
