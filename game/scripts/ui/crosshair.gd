class_name Crosshair
extends Control
## A four-tick crosshair whose gap widens with the weapon's current spread.
##
## Pure drawing: WeaponHud sets `gap` each frame and calls queue_redraw(). UI
## observes, never drives gameplay (docs/ARCHITECTURE.md).

@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var tick_length: float = 9.0
@export var thickness: float = 2.0
@export var show_dot: bool = true

@export var kill_color: Color = Color(1.0, 0.25, 0.2)

## Distance (px) from centre to the start of each tick; driven by spread.
var gap: float = 6.0
## Hit-marker: WeaponHud sets to 1.0 on a confirmed hit and fades it; drawn as
## a diagonal X (red on a kill).
var hit_flash: float = 0.0
var hit_kill: bool = false


func _draw() -> void:
	var c := size * 0.5
	var half := thickness * 0.5
	# Right, left, down, up ticks.
	draw_rect(Rect2(c + Vector2(gap, -half), Vector2(tick_length, thickness)), color)
	draw_rect(Rect2(c + Vector2(-gap - tick_length, -half), Vector2(tick_length, thickness)), color)
	draw_rect(Rect2(c + Vector2(-half, gap), Vector2(thickness, tick_length)), color)
	draw_rect(Rect2(c + Vector2(-half, -gap - tick_length), Vector2(thickness, tick_length)), color)
	if show_dot:
		draw_circle(c, 1.3, color)
	if hit_flash > 0.0:
		var marker := kill_color if hit_kill else Color(1, 1, 1)
		marker.a = clampf(hit_flash, 0.0, 1.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 4.0, c + d * 11.0, marker, thickness)
