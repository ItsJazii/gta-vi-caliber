class_name LifeguardTowers
extends Node3D
## The pastel Art-Deco lifeguard stands of Miami Beach — a row of raised huts in
## candy colours facing the water, one of Vice City's most photographed motifs.
## Each is a stilted platform with an open-front hut, a peaked roof, a back
## ladder and a flag. Curated placement via FloridaBackdrop; built in populate()
## so it's headless-testable.

## Signature pastel body colours, cycled per stand.
const PASTELS: Array[Color] = [
	Color(0.96, 0.52, 0.62),  # flamingo pink
	Color(0.40, 0.80, 0.80),  # teal
	Color(0.98, 0.86, 0.42),  # sun yellow
	Color(0.98, 0.60, 0.42),  # coral
	Color(0.62, 0.90, 0.72),  # mint
	Color(0.62, 0.76, 0.96),  # sky blue
]

@export var ground_y: float = 0.0
@export var line_x: float = 1360.0
@export var z_start: float = -1800.0
@export var z_end: float = 1800.0
@export var count: int = 8
## Towers face +x by default (toward the water); FloridaBackdrop sets line_x to
## the shore and the row looks out over the bay.
@export var face_yaw: float = 0.0

var _count: int = 0
var _trim_mat: StandardMaterial3D
var _post_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D


func _ready() -> void:
	populate()


func populate() -> int:
	if _count > 0:
		return _count
	_trim_mat = StandardMaterial3D.new()
	_trim_mat.albedo_color = Color(0.97, 0.97, 0.95)  # white deco trim
	_trim_mat.roughness = 0.6
	_post_mat = StandardMaterial3D.new()
	_post_mat.albedo_color = Color(0.5, 0.42, 0.32)  # weathered timber legs
	_post_mat.roughness = 0.9
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.85, 0.3, 0.32)  # red-stripe roof
	_roof_mat.roughness = 0.7

	var n := maxi(count, 1)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var z := lerpf(z_start, z_end, t)
		var tower := _make_tower(PASTELS[i % PASTELS.size()])
		tower.position = Vector3(line_x, ground_y, z)
		tower.rotation.y = face_yaw
		add_child(tower)
	_count = n
	return _count


## A stand faces +x (open front toward the water). deck at ~2.4 m on four legs.
func _make_tower(body: Color) -> Node3D:
	var tower := Node3D.new()
	var deck_y := 2.4
	var hut_w := 3.6
	var hut_d := 3.2
	var hut_h := 2.4

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body
	body_mat.roughness = 0.55

	# Four legs.
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.22, deck_y, 0.22)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			leg.mesh = leg_mesh
			leg.material_override = _post_mat
			leg.position = Vector3(sx * hut_w * 0.4, deck_y * 0.5, sz * hut_d * 0.4)
			tower.add_child(leg)

	# Deck.
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(hut_w + 0.6, 0.2, hut_d + 0.6)
	deck.mesh = deck_mesh
	deck.material_override = _trim_mat
	deck.position = Vector3(0.0, deck_y, 0.0)
	tower.add_child(deck)

	# Back + side walls (open front toward +x). Back wall at -x.
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.18, hut_h, hut_d)
	back.mesh = back_mesh
	back.material_override = body_mat
	back.position = Vector3(-hut_w * 0.5, deck_y + hut_h * 0.5, 0.0)
	tower.add_child(back)
	for sz in [-1.0, 1.0]:
		var side := MeshInstance3D.new()
		var side_mesh := BoxMesh.new()
		side_mesh.size = Vector3(hut_w, hut_h, 0.18)
		side.mesh = side_mesh
		side.material_override = body_mat
		side.position = Vector3(0.0, deck_y + hut_h * 0.5, sz * hut_d * 0.5)
		tower.add_child(side)

	# Low front rail (so the open front still reads as a booth).
	var rail := MeshInstance3D.new()
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.16, 0.9, hut_d)
	rail.mesh = rail_mesh
	rail.material_override = _trim_mat
	rail.position = Vector3(hut_w * 0.5, deck_y + 0.55, 0.0)
	tower.add_child(rail)

	# Peaked roof: two slabs leaning to a ridge.
	for sx in [-1.0, 1.0]:
		var slab := MeshInstance3D.new()
		var slab_mesh := BoxMesh.new()
		slab_mesh.size = Vector3(hut_w * 0.62, 0.16, hut_d + 0.8)
		slab.mesh = slab_mesh
		slab.material_override = _roof_mat
		slab.rotation.z = sx * 0.5
		slab.position = Vector3(sx * hut_w * 0.22, deck_y + hut_h + 0.55, 0.0)
		tower.add_child(slab)

	# Flag pole + flag.
	var pole := MeshInstance3D.new()
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.08, 2.4, 0.08)
	pole.mesh = pole_mesh
	pole.material_override = _trim_mat
	pole.position = Vector3(-hut_w * 0.45, deck_y + hut_h + 1.6, hut_d * 0.45)
	tower.add_child(pole)
	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.05, 0.6, 1.0)
	flag.mesh = flag_mesh
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.9, 0.15, 0.15)
	flag.mesh.surface_set_material(0, flag_mat)
	flag.position = Vector3(-hut_w * 0.45, deck_y + hut_h + 2.3, hut_d * 0.45 + 0.55)
	tower.add_child(flag)

	# Back ladder.
	var ladder := MeshInstance3D.new()
	var ladder_mesh := BoxMesh.new()
	ladder_mesh.size = Vector3(0.1, deck_y + 0.4, 0.9)
	ladder.mesh = ladder_mesh
	ladder.material_override = _post_mat
	ladder.rotation.z = 0.32
	ladder.position = Vector3(-hut_w * 0.5 - 0.7, deck_y * 0.5, 0.0)
	tower.add_child(ladder)
	return tower
