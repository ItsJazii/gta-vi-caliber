extends SceneTree
## Diagnostic probe for the generated Mara GLB. Prints mesh bounds/materials so
## broken generated shell pieces can be identified by data instead of guesswork.

const MARA_MESH := "res://assets/characters/char_textured.glb"


func _initialize() -> void:
	var scene := load(MARA_MESH) as PackedScene
	if scene == null:
		_fail("could not load Mara GLB")
		return
	var root_node := scene.instantiate()
	root.add_child(root_node)
	_report(root_node, root_node.name)
	quit(0)


func _report(node: Node, path: String) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var bounds := mi.get_aabb()
		print("%s mesh=%s center=%s size=%s" % [path, mi.mesh, bounds.get_center(), bounds.size])
		if mi.mesh != null:
			for surface in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(surface)
				print("  surface=%d material=%s %s" % [surface, mat, _material_summary(mat)])
	for child in node.get_children():
		_report(child, "%s/%s" % [path, child.name])


func _material_summary(mat: Material) -> String:
	var standard := mat as StandardMaterial3D
	if standard == null:
		return ""
	return (
		"albedo=%s texture=%s metallic=%.3f roughness=%.3f"
		% [
			standard.albedo_color,
			standard.albedo_texture,
			standard.metallic,
			standard.roughness,
		]
	)


func _fail(message: String) -> void:
	push_error("player_mara_import_probe: %s" % message)
	quit(1)
