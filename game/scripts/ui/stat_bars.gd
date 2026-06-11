class_name StatBars
extends Control
## Segmented health + armor bars, GTA-style. The GameHud sets `health` and
## `armor` (both 0..1 fractions) each frame and calls queue_redraw(); this only
## draws. Armor row hides itself when empty so a fresh player shows just health.

@export var health_color: Color = Color(0.45, 0.85, 0.4)
@export var health_low_color: Color = Color(0.9, 0.3, 0.25)
@export var armor_color: Color = Color(0.45, 0.7, 1.0)
@export var back_color: Color = Color(0, 0, 0, 0.55)
@export var bar_height: float = 9.0
@export var gap: float = 5.0
@export var segments: int = 10

var health: float = 1.0
var armor: float = 0.0


func _draw() -> void:
	var w := size.x
	_draw_bar(0.0, w, health, _health_tint())
	if armor > 0.001:
		_draw_bar(bar_height + gap, w, armor, armor_color)


func _health_tint() -> Color:
	return health_low_color if health <= 0.25 else health_color


func _draw_bar(y: float, w: float, fill: float, col: Color) -> void:
	var f := clampf(fill, 0.0, 1.0)
	# Backing.
	draw_rect(Rect2(0, y, w, bar_height), back_color)
	# Fill.
	if f > 0.0:
		draw_rect(Rect2(0, y, w * f, bar_height), col)
	# Segment ticks for the GTA "notched bar" read.
	if segments > 1:
		var seg_w := w / float(segments)
		for i in range(1, segments):
			var x := seg_w * i
			draw_line(Vector2(x, y), Vector2(x, y + bar_height), Color(0, 0, 0, 0.5), 1.0)
	# Thin outline.
	draw_rect(Rect2(0, y, w, bar_height), Color(0, 0, 0, 0.7), false, 1.0)
