class_name Terrain
extends Node3D
## Builds a grid of terrain chunks from TerrainModel and drops them into the
## scene as MeshInstance3D tiles with trimesh colliders. This is the static
## foundation the streaming tile loader (M3 GDExtension) will later replace with
## load/unload around the camera — the chunk math already tiles seamlessly, so
## that swap is drop-in.
##
## Add one to a world scene; it builds (2*grid_radius+1)² chunks centred on its
## own origin in _ready. Other systems can ask `height_at(x, z)` to sit props,
## spawns or the player on the surface.

signal terrain_built(chunk_count: int)

## Seed for the heightfield; same seed → same world.
@export var terrain_seed: int = 1337
## Side length of one chunk in metres.
@export var chunk_span: float = 128.0
## Subdivisions per chunk side (mesh resolution).
@export var chunk_res: int = 32
## Chunks built in each direction from centre: (2r+1)² total.
@export var grid_radius: int = 4
## Build trimesh colliders so the player and vehicles walk/drive on the terrain.
@export var build_collision: bool = true
## Surface material; a height/slope-blended terrain shader is used if unset.
@export var material: Material


func _ready() -> void:
	if material == null:
		material = _default_material()
	_build()


## World-space ground height at (x, z) — for placing the player, props, spawns.
func height_at(x: float, z: float) -> float:
	return TerrainModel.height_at(x, z, terrain_seed)


## A point on the surface plus a small lift, handy for spawning without clipping.
func surface_point(x: float, z: float, lift: float = 1.0) -> Vector3:
	return Vector3(x, height_at(x, z) + lift, z)


func _build() -> void:
	var count := 0
	for gz in range(-grid_radius, grid_radius + 1):
		for gx in range(-grid_radius, grid_radius + 1):
			var ox := float(gx) * chunk_span
			var oz := float(gz) * chunk_span
			_build_chunk(ox, oz)
			count += 1
	terrain_built.emit(count)


func _build_chunk(ox: float, oz: float) -> void:
	var arr := TerrainModel.chunk_arrays(ox, oz, chunk_span, chunk_res, terrain_seed)
	var mesh := ArrayMesh.new()
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = arr["vertices"]
	surface[Mesh.ARRAY_NORMAL] = arr["normals"]
	surface[Mesh.ARRAY_TEX_UV] = arr["uvs"]
	surface[Mesh.ARRAY_INDEX] = arr["indices"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	mesh.surface_set_material(0, material)

	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [int(ox), int(oz)]
	mi.mesh = mesh
	mi.position = Vector3(ox, 0.0, oz)
	add_child(mi)
	if build_collision:
		mi.create_trimesh_collision()


func _default_material() -> Material:
	var shader := load("res://assets/shaders/terrain.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		return mat
	var std := StandardMaterial3D.new()
	std.albedo_color = Color(0.27, 0.36, 0.18)
	std.roughness = 0.95
	return std
