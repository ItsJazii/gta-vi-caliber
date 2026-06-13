class_name WetlandFlora
extends RefCounted
## Layered subtropical wetland vegetation (clustered cypress + low palmetto
## understory) built as cheap MultiMeshes. Extracted from FloridaBackdrop so the
## flora can be unit-tested (test_wetland_flora.gd) and reviewed in isolation
## (wetland_flora_capture.gd) instead of hunting sparse trees in the full map.
##
## Each wetland seed point becomes a jittered CLUSTER of cypress (trunk + two
## stacked crowns) over a denser shrub understory, so the wetland reads as lush
## Everglades rather than ~150 lollipops scattered across a 12 km landmass.

const TREES_PER_CLUSTER_MIN := 3
const TREES_PER_CLUSTER_MAX := 6
const SHRUBS_PER_CLUSTER_MIN := 4
const SHRUBS_PER_CLUSTER_MAX := 9
const CLUSTER_RADIUS_M := 17.0


## Builds the three vegetation layers under `parent` and returns instance counts
## ({trees, crowns, shrubs}) so tests can assert the clustering without a GPU.
## `leaf_mat`/`shrub_mat` get vertex_color_use_as_albedo enabled so per-instance
## tone variation reads (olive → deep green) without a material per tree.
static func build(
	parent: Node3D,
	points: PackedVector2Array,
	ground_y: float,
	trunk_mat: Material,
	leaf_mat: Material,
	shrub_mat: Material,
	rng_seed: int = 811
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var trunk_xforms: Array[Transform3D] = []
	var crown_xforms: Array[Transform3D] = []
	var crown_colors := PackedColorArray()
	var shrub_xforms: Array[Transform3D] = []
	var shrub_colors := PackedColorArray()

	for p in points:
		var n_trees := rng.randi_range(TREES_PER_CLUSTER_MIN, TREES_PER_CLUSTER_MAX)
		for _t in n_trees:
			var off := _disc(rng, CLUSTER_RADIUS_M)
			var base := Vector3(p.x + off.x, ground_y, p.y + off.y)
			var s := rng.randf_range(0.7, 1.6)
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			trunk_xforms.append(
				Transform3D(yaw.scaled(Vector3(s, s, s)), base + Vector3(0.0, 2.6 * s, 0.0))
			)
			# Two stacked crowns (wide lower + narrow upper) → fuller columnar canopy.
			var tone := rng.randf()
			var crown_col := Color(0.10, 0.22, 0.10).lerp(Color(0.21, 0.34, 0.14), tone)
			crown_xforms.append(
				Transform3D(
					yaw.scaled(Vector3(s * 1.15, s, s * 1.15)), base + Vector3(0.0, 5.4 * s, 0.0)
				)
			)
			crown_colors.append(crown_col)
			crown_xforms.append(
				Transform3D(
					yaw.scaled(Vector3(s * 0.75, s * 0.9, s * 0.75)),
					base + Vector3(0.0, 7.5 * s, 0.0)
				)
			)
			crown_colors.append(crown_col.lightened(0.06))
		var n_shrubs := rng.randi_range(SHRUBS_PER_CLUSTER_MIN, SHRUBS_PER_CLUSTER_MAX)
		for _sh in n_shrubs:
			var off2 := _disc(rng, CLUSTER_RADIUS_M * 1.3)
			var ss := rng.randf_range(0.6, 1.4)
			var yaw2 := Basis(Vector3.UP, rng.randf() * TAU)
			shrub_xforms.append(
				Transform3D(
					yaw2.scaled(Vector3(ss, ss * 0.6, ss)),
					Vector3(p.x + off2.x, ground_y + 0.35 * ss, p.y + off2.y)
				)
			)
			shrub_colors.append(Color(0.16, 0.28, 0.12).lerp(Color(0.26, 0.36, 0.15), rng.randf()))

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.40
	trunk_mesh.height = 5.2
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.7
	crown_mesh.height = 4.6
	var shrub_mesh := SphereMesh.new()
	shrub_mesh.radius = 1.4
	shrub_mesh.height = 1.5

	if leaf_mat is BaseMaterial3D:
		(leaf_mat as BaseMaterial3D).vertex_color_use_as_albedo = true
	if shrub_mat is BaseMaterial3D:
		(shrub_mat as BaseMaterial3D).vertex_color_use_as_albedo = true

	_add_layer(
		parent, "WetlandCypressTrunks", trunk_mesh, trunk_mat, trunk_xforms, PackedColorArray()
	)
	_add_layer(parent, "WetlandCypressCrowns", crown_mesh, leaf_mat, crown_xforms, crown_colors)
	_add_layer(parent, "WetlandShrubs", shrub_mesh, shrub_mat, shrub_xforms, shrub_colors)

	return {
		"trees": trunk_xforms.size(), "crowns": crown_xforms.size(), "shrubs": shrub_xforms.size()
	}


## Uniform sample inside a disc (sqrt keeps clusters from bunching at the centre).
static func _disc(rng: RandomNumberGenerator, radius: float) -> Vector2:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	return Vector2(cos(a) * r, sin(a) * r)


static func _add_layer(
	parent: Node3D,
	layer_name: String,
	mesh: Mesh,
	mat: Material,
	xforms: Array[Transform3D],
	colors: PackedColorArray
) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = layer_name
	inst.multimesh = mm
	inst.material_override = mat
	parent.add_child(inst)
