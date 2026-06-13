class_name Pier
extends Node3D
## A recreational fishing pier reaching from the shore out over the bay — the
## other half of the ledger's "palms/pier" postcard note, and a built landmark
## distinct from the scattered ambient props. Deck on regular pilings, railings
## with posts down both sides, warm lamp posts, and a widened platform at the
## sea end. Curated placement via FloridaBackdrop; built in populate() so it's
## headless-testable.

@export var deck_y: float = 1.6
@export var width: float = 7.0
@export var length: float = 115.0
@export var piling_spacing: float = 8.0
@export var lamp_spacing: float = 22.0

var _count_pilings: int = 0
var _deck_mat: StandardMaterial3D
var _piling_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	populate()


## Builds the pier (deck extends along +z from the shore at z=0). Returns the
## piling count so tests can assert the structure without a GPU.
func populate() -> int:
	if _count_pilings > 0:
		return _count_pilings
	_make_materials()
	_build_deck()
	_build_railings()
	_build_lamps()
	return _build_pilings()


func _make_materials() -> void:
	_deck_mat = StandardMaterial3D.new()
	_deck_mat.albedo_color = Color(0.46, 0.36, 0.26)  # weathered boardwalk wood
	_deck_mat.roughness = 0.9
	_piling_mat = StandardMaterial3D.new()
	_piling_mat.albedo_color = Color(0.34, 0.3, 0.27)  # creosote piling
	_piling_mat.roughness = 0.92
	_rail_mat = StandardMaterial3D.new()
	_rail_mat.albedo_color = Color(0.14, 0.15, 0.17)
	_rail_mat.metallic = 0.5
	_rail_mat.roughness = 0.5
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(1.0, 0.9, 0.7)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.85, 0.6)
	_lamp_mat.emission_energy_multiplier = 1.6


func _build_deck() -> void:
	var deck := MeshInstance3D.new()
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(width, 0.4, length)
	deck.mesh = dmesh
	deck.material_override = _deck_mat
	deck.name = "Deck"
	deck.position = Vector3(0.0, deck_y, length * 0.5)
	add_child(deck)

	# Widened platform at the sea end (the fishing/observation head).
	var head := MeshInstance3D.new()
	var hmesh := BoxMesh.new()
	hmesh.size = Vector3(width + 8.0, 0.4, 16.0)
	head.mesh = hmesh
	head.material_override = _deck_mat
	head.position = Vector3(0.0, deck_y, length + 4.0)
	add_child(head)


func _build_railings() -> void:
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.12, 0.12, length)
	for sx in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.mesh = rail_mesh
		rail.material_override = _rail_mat
		rail.position = Vector3(sx * width * 0.5, deck_y + 1.1, length * 0.5)
		add_child(rail)
	# Railing posts every ~4 m.
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.1, 1.1, 0.1)
	var z := 4.0
	while z < length:
		for sx in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.material_override = _rail_mat
			post.position = Vector3(sx * width * 0.5, deck_y + 0.75, z)
			add_child(post)
		z += 4.0


func _build_lamps() -> void:
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.14, 3.2, 0.14)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.4, 0.5)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.12, 0.12, 0.14)
	pole_mat.roughness = 0.5
	var lamps := Node3D.new()
	lamps.name = "Lamps"
	add_child(lamps)
	var z := lamp_spacing
	while z < length:
		var pole := MeshInstance3D.new()
		pole.mesh = pole_mesh
		pole.material_override = pole_mat
		pole.position = Vector3(width * 0.5 - 0.3, deck_y + 1.8, z)
		lamps.add_child(pole)
		var lamp := MeshInstance3D.new()
		lamp.mesh = head_mesh
		lamp.material_override = _lamp_mat
		lamp.position = Vector3(width * 0.5 - 0.3, deck_y + 3.4, z)
		lamps.add_child(lamp)
		z += lamp_spacing


func _build_pilings() -> int:
	# Pilings drop from under the deck into the water on both sides.
	var piling_mesh := BoxMesh.new()
	piling_mesh.size = Vector3(0.5, deck_y + 4.0, 0.5)
	var container := Node3D.new()
	container.name = "Pilings"
	add_child(container)
	var n := 0
	var z := 3.0
	while z <= length + 8.0:
		for sx in [-1.0, 1.0]:
			var piling := MeshInstance3D.new()
			piling.mesh = piling_mesh
			piling.material_override = _piling_mat
			piling.position = Vector3(sx * width * 0.42, deck_y - (deck_y + 4.0) * 0.5, z)
			container.add_child(piling)
			n += 1
		z += piling_spacing
	_count_pilings = n
	return n
