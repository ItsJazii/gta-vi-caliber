class_name LodUtil
extends RefCounted
## Small shared helper for distance LOD culling of procedurally-built prop groups.


## Apply a visibility-range cull to every GeometryInstance3D under `root`.
## visibility_range_* lives on GeometryInstance3D, NOT Node3D — setting it on a
## plain container node throws at runtime and culls nothing, so prop groups that
## nest mesh instances under Node3D holders both error on every build and never
## actually LOD-cull. Walk to the real mesh instances and set the range there.
static func apply_range(root: Node, dist: float) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = dist
			child.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		apply_range(child, dist)
