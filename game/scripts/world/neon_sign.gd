class_name NeonSign
extends Node3D
## A glowing neon gateway sign — the Vice City night signature. A dark hoarding
## on two posts, framed by emissive "neon tube" borders, with a bright hot-pink
## headline over a cyan tagline. Pure emissive so it reads as lit at night with
## no dependency on the (shared) scene environment; blooms where glow is on.
## Built in populate() so it's headless-testable. Placed via FloridaBackdrop.

@export var headline: String = "VICE BEACH"
@export var tagline: String = "· THE PIER ·"
@export var neon_a: Color = Color(1.0, 0.13, 0.6)  # hot pink
@export var neon_b: Color = Color(0.1, 0.95, 1.0)  # cyan
@export var panel_w: float = 16.0
@export var panel_h: float = 5.0
@export var deck_y: float = 7.0


func _ready() -> void:
	populate()


func populate() -> int:
	if get_child_count() > 0:
		return get_child_count()
	_build_posts()
	_build_panel()
	_build_neon_border()
	_build_text()
	return get_child_count()


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _build_posts() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.1, 0.1, 0.12)
	post_mat.metallic = 0.5
	post_mat.roughness = 0.5
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.5, deck_y + panel_h, 0.5)
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = post_mat
		post.position = Vector3(sx * panel_w * 0.42, (deck_y + panel_h) * 0.5, -0.2)
		add_child(post)


func _build_panel() -> void:
	var panel := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(panel_w, panel_h, 0.3)
	panel.mesh = pmesh
	panel.name = "Panel"
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.04, 0.06)
	dark.roughness = 0.6
	panel.material_override = dark
	panel.position = Vector3(0.0, deck_y + panel_h * 0.5, 0.0)
	add_child(panel)


## Emissive tube border (top/bottom/left/right) framing the panel — the neon
## outline that reads even before the text.
func _build_neon_border() -> void:
	var border := Node3D.new()
	border.name = "NeonBorder"
	add_child(border)
	var cy := deck_y + panel_h * 0.5
	var tube_h := BoxMesh.new()
	tube_h.size = Vector3(panel_w - 0.4, 0.18, 0.18)
	var tube_v := BoxMesh.new()
	tube_v.size = Vector3(0.18, panel_h - 0.4, 0.18)
	var mat := _emissive(neon_a, 3.0)
	for sy in [-1.0, 1.0]:
		var h := MeshInstance3D.new()
		h.mesh = tube_h
		h.material_override = mat
		h.position = Vector3(0.0, cy + sy * (panel_h * 0.5 - 0.2), 0.18)
		border.add_child(h)
	for sx in [-1.0, 1.0]:
		var v := MeshInstance3D.new()
		v.mesh = tube_v
		v.material_override = mat
		v.position = Vector3(sx * (panel_w * 0.5 - 0.2), cy, 0.18)
		border.add_child(v)


func _build_text() -> void:
	var cy := deck_y + panel_h * 0.5
	var head := Label3D.new()
	head.name = "Headline"
	head.text = headline
	head.font_size = 200
	head.pixel_size = 0.014
	head.modulate = neon_a
	head.outline_size = 28
	head.outline_modulate = Color(0.3, 0.0, 0.12)
	head.position = Vector3(0.0, cy + 0.9, 0.22)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(head)

	var tag := Label3D.new()
	tag.name = "Tagline"
	tag.text = tagline
	tag.font_size = 120
	tag.pixel_size = 0.013
	tag.modulate = neon_b
	tag.outline_size = 18
	tag.outline_modulate = Color(0.0, 0.18, 0.22)
	tag.position = Vector3(0.0, cy - 1.4, 0.22)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tag)
