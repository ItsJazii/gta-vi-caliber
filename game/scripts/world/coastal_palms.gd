class_name CoastalPalms
extends Node3D
## A palm fringe threaded along the miami coastline — the iconic Vice City shore
## silhouette that frames every establishing/beauty shot (the bare tan sand had
## no foreground, a standing gap in docs/QUALITY.md). Walks FloridaMapModel's
## coast outline at a fixed spacing, offsets each palm slightly inland of the
## waterline, and renders trunks + fronds as two cheap MultiMeshes. Reuses
## PalmMesh; added by FloridaBackdrop. Built in populate() (not _ready) so it's
## headless-testable (see test_coastal_palms.gd).

@export var map_scale: float = 4.6
@export var ground_y: float = 0.0
## Metres between palms along the shore.
@export var spacing: float = 27.0
## Offset toward land from the waterline, metres (keeps palms out of the water).
@export var inland_m: float = 9.0
## Only fringe the coast inside this rectangle (the playable bay/beach span), so
## the whole state outline isn't ringed with palms nobody sees.
@export var region_min: Vector2 = Vector2(-1000.0, -5200.0)
@export var region_max: Vector2 = Vector2(6600.0, 3600.0)
@export var max_palms: int = 600
@export var rng_seed: int = 4242

var _count: int = 0


func _ready() -> void:
	populate()


## Builds the fringe and returns the palm count. Safe to call once; no-ops if
## already built.
func populate() -> int:
	if _count > 0:
		return _count
	var outline := FloridaMapModel.closed_outline(map_scale)
	if outline.size() < 3:
		return 0

	var centroid := Vector2.ZERO
	for p in outline:
		centroid += p
	centroid /= float(outline.size())

	var positions := _walk_shore(outline, centroid)
	if positions.is_empty():
		return 0

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var height := 9.0
	var bend := 1.3
	var trunk_mesh := TreeMesh.to_mesh(PalmMesh.trunk(height, bend, 0.34, 0.19))
	var crown_mesh := TreeMesh.to_mesh(PalmMesh.crown(9, 4.4, 0.8, rng_seed))
	var tip := PalmMesh.tip(height, bend)

	var trunk_xforms: Array[Transform3D] = []
	var crown_xforms: Array[Transform3D] = []
	for pos in positions:
		var s := rng.randf_range(0.85, 1.3)
		var yaw := rng.randf() * TAU
		var palm_basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		var origin := Vector3(pos.x, ground_y, pos.y)
		trunk_xforms.append(Transform3D(palm_basis, origin))
		var crown_basis := palm_basis * Basis(Vector3.UP, rng.randf() * TAU)
		crown_xforms.append(Transform3D(crown_basis, origin + palm_basis * tip))

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.36, 0.27)
	trunk_mat.roughness = 0.95
	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_color = Color(0.17, 0.41, 0.18)
	frond_mat.roughness = 0.9
	frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_add_layer("CoastalPalmTrunks", trunk_mesh, trunk_mat, trunk_xforms)
	_add_layer("CoastalPalmCrowns", crown_mesh, frond_mat, crown_xforms)
	_count = positions.size()
	return _count


## Arc-length walk of the closed outline, dropping a palm every `spacing` and
## offsetting it inland (toward the outline centroid). Region-clipped and capped.
func _walk_shore(outline: PackedVector2Array, centroid: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var leftover := 0.0
	for i in range(outline.size() - 1):
		var a := outline[i]
		var b := outline[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 0.0001:
			continue
		var dir := seg / seg_len
		var travel := leftover
		while travel < seg_len:
			var pt := a + dir * travel
			travel += spacing
			if pt.x < region_min.x or pt.x > region_max.x:
				continue
			if pt.y < region_min.y or pt.y > region_max.y:
				continue
			var inland := centroid - pt
			if inland.length() > 0.001:
				inland = inland.normalized()
			out.append(pt + inland * inland_m)
			if out.size() >= max_palms:
				return out
		leftover = travel - seg_len
	return out


func _add_layer(layer_name: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = layer_name
	inst.multimesh = mm
	inst.material_override = mat
	add_child(inst)
