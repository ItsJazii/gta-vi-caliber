class_name CombatText
extends Node3D
## Floating damage numbers.
##
## Anything that deals damage calls popup(amount, world_position, lethal) after
## finding this by group "combat_text". Each number is a billboarded Label3D
## that eases upward and fades via CombatTextMotion (pure, tested). One per world
## scene; pure UI, never drives gameplay.

@export var duration: float = 0.85
@export var height: float = 1.1
@export var color: Color = Color(1.0, 0.95, 0.55)
@export var kill_color: Color = Color(1.0, 0.4, 0.3)
@export var font_size: int = 44

var _active: Array = []


func _ready() -> void:
	add_to_group("combat_text")


func popup(amount: float, world_position: Vector3, lethal: bool = false) -> void:
	var label := Label3D.new()
	label.text = str(int(round(maxf(amount, 0.0))))
	label.modulate = kill_color if lethal else color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.008
	label.font_size = font_size
	label.outline_size = 8
	add_child(label)
	var base := world_position + Vector3.UP * 0.3
	label.global_position = base
	_active.append({"label": label, "base": base, "t": 0.0})


func _process(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[i]
		entry["t"] += delta
		var label: Label3D = entry["label"]
		if not is_instance_valid(label) or CombatTextMotion.is_done(entry["t"], duration):
			if is_instance_valid(label):
				label.queue_free()
			_active.remove_at(i)
			continue
		label.global_position = (
			entry["base"] + Vector3.UP * CombatTextMotion.rise(entry["t"], duration, height)
		)
		var tint: Color = label.modulate
		tint.a = CombatTextMotion.alpha(entry["t"], duration)
		label.modulate = tint
