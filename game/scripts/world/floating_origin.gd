class_name FloatingOrigin
extends Node
## Shifts the world back toward the engine origin whenever the player anchor
## strays past the precision budget (math in OriginMath). Add one as a direct
## child of a world scene root — it walks its *parent's* Node3D children, so
## world scenes stay self-contained and streaming-ready (no autoload, no
## cross-scene paths). RigidBody velocities survive a uniform teleport, so
## physics carries on undisturbed.

signal origin_shifted(shift: Vector3, origin_offset: Vector3)

@export var threshold_m: float = OriginMath.DEFAULT_THRESHOLD_M
@export var grid_m: float = OriginMath.DEFAULT_GRID_M

## Where the engine origin sits in absolute world coordinates
## (absolute = local - origin_offset). Other systems read, never write.
var origin_offset: Vector3 = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	var anchor := get_tree().get_first_node_in_group("player") as Node3D
	if anchor == null:
		return
	if not OriginMath.should_shift(anchor.global_position, threshold_m):
		return
	var shift := OriginMath.shift_for(anchor.global_position, grid_m)
	_apply_shift(shift)
	origin_offset = OriginMath.accumulate_offset(origin_offset, shift)
	origin_shifted.emit(shift, origin_offset)


func _apply_shift(shift: Vector3) -> void:
	var world_root := get_parent()
	if world_root == null:
		return
	for child in world_root.get_children():
		var spatial := child as Node3D
		if spatial != null:
			spatial.global_position += shift
