class_name DebugInspector
extends Node
## On-demand geometry inspector for hunting z-fighting and grounding bugs, ported
## from the Three.js debug-inspector pattern (build the tool, stop guessing).
##
## F3 toggles it on. While on, it raycasts from the mouse cursor into the world
## and lists every MeshInstance3D whose footprint is near the cursor hit, with the
## world Y of its top face. Any pair of surfaces whose top faces sit within
## COPLANAR_EPS of each other are flagged [Z-FIGHT] (the shimmer cause); meshes
## with a transparent material are flagged [TRANSPARENT] (depth-sort thrash). F4
## freezes the readout so you can orbit while reading it, and prints the frozen
## list to the console.
##
## Diagnostic only, it never drives gameplay (docs/ARCHITECTURE.md). For the
## sinking check (collider floor below the visible floor), also enable the
## editor's Debug > Visible Collision Shapes: that draws colliders, this draws
## rendered surfaces, and the gap between them is the bug.

const TOGGLE_KEY := KEY_F3
const LOCK_KEY := KEY_F4
const COPLANAR_EPS := 0.05  # 50 mm: top faces within this + XZ overlap = z-fight risk
const SEARCH_RADIUS := 3.0  # metres around the cursor hit to consider a mesh "near"
const RAY_LENGTH := 2000.0
const MAX_LISTED := 14

var _active := false
var _locked := false
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 150)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = false
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == TOGGLE_KEY:
		_active = not _active
		_locked = false
		_label.visible = _active
		if _active:
			_label.text = "[inspector] on, hover a surface, F4 to freeze"
	elif key.keycode == LOCK_KEY and _active:
		_locked = not _locked
		if _locked:
			print("\n=== DebugInspector freeze ===\n", _label.text)


func _process(_delta: float) -> void:
	if not _active or _locked:
		return
	_label.text = _scan()


func _scan() -> String:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return "[inspector] no active camera"

	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var space := camera.get_world_3d().direct_space_state
	if space == null:
		return "[inspector] no physics space"

	var query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH)
	var hit := space.intersect_ray(query)
	if not hit.has("position"):
		return "[inspector] no surface under cursor"
	var hit_point: Vector3 = hit["position"]

	var scene := get_tree().current_scene
	if scene == null:
		return "[inspector] no scene"

	# Gather nearby rendered surfaces with their top-face world Y.
	var near: Array = []  # each: {name, top_y, transparent}
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var wa := _world_aabb(mi)
		if _xz_closest_dist(hit_point, wa) > SEARCH_RADIUS:
			continue
		(
			near
			. append(
				{
					"name": String(mi.name),
					"top_y": wa.position.y + wa.size.y,
					"transparent": _is_transparent(mi),
				}
			)
		)

	near.sort_custom(func(a, b): return a["top_y"] > b["top_y"])

	var lines := PackedStringArray()
	lines.append("[inspector] hit y=%.3f  (%d surfaces near)" % [hit_point.y, near.size()])
	var shown := mini(near.size(), MAX_LISTED)
	for i in shown:
		var item: Dictionary = near[i]
		var tags := ""
		if _has_coplanar_neighbour(near, i):
			tags += " [Z-FIGHT]"
		if item["transparent"]:
			tags += " [TRANSPARENT]"
		lines.append("  y=%.3f  %s%s" % [item["top_y"], item["name"], tags])
	if near.size() > shown:
		lines.append("  ... %d more" % (near.size() - shown))
	return "\n".join(lines)


# True if another listed surface's top face is within COPLANAR_EPS of this one.
func _has_coplanar_neighbour(near: Array, idx: int) -> bool:
	var y: float = near[idx]["top_y"]
	for j in near.size():
		if j == idx:
			continue
		if absf(near[j]["top_y"] - y) <= COPLANAR_EPS:
			return true
	return false


# World-space AABB by transforming the local AABB's eight corners.
func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local := mi.get_aabb()
	var t := mi.global_transform
	var wa := AABB(t * local.position, Vector3.ZERO)
	for i in 8:
		var corner := (
			local.position
			+ Vector3(
				local.size.x if (i & 1) != 0 else 0.0,
				local.size.y if (i & 2) != 0 else 0.0,
				local.size.z if (i & 4) != 0 else 0.0
			)
		)
		wa = wa.expand(t * corner)
	return wa


# Closest planar (XZ) distance from a point to an AABB's footprint.
func _xz_closest_dist(p: Vector3, a: AABB) -> float:
	var cx := clampf(p.x, a.position.x, a.position.x + a.size.x)
	var cz := clampf(p.z, a.position.z, a.position.z + a.size.z)
	return Vector2(p.x - cx, p.z - cz).length()


func _is_transparent(mi: MeshInstance3D) -> bool:
	var mat: Material = mi.material_override
	if mat == null:
		mat = mi.get_active_material(0)
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	return false
