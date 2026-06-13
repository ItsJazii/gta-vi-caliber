class_name Billboards
extends Node3D
## Roadside satirical billboards along the bay-facing shore — the GTA staple the
## player drives past. Each is a posted, framed ad panel with a faintly emissive
## face (so it reads as a lit hoarding day or night) carrying original parody
## copy. Extends the humor/tone axis opened by AirBanner, plus set-dressing
## density. Curated positions in FloridaBackdrop-local space; built in populate()
## so it's headless-testable. Added by FloridaBackdrop.

## Original parody ad copy — punchy, obviously satire, nothing from a real brand.
const ADS: Array[String] = [
	"LIBERTY LOANS\n0% APR* (*NOT REAL)",
	"COUGAR ENERGY DRINK\nLEGALLY A BEVERAGE",
	"VICE BEACH CONDOS\nNOW WITH FLOORS",
	"DR. SUNNY'S TANNING\nMELANOMA OPTIONAL",
	"BAIT & SWITCH REALTY\nWE HID THE MOLD",
	"GATORADE? NO. GATOR-AIDE.\nIT'S MOSTLY GATOR",
	"HONEST AL'S USED BOATS\nMOST OF THEM FLOAT",
	"THE FORK & KNIFE\nNOW SERVING FOOD",
]

@export var ground_y: float = 0.0
## Billboards march along z at this x (bay-facing shore), facing +x (the bay).
@export var line_x: float = 1320.0
@export var z_start: float = -2200.0
@export var z_end: float = 2200.0
@export var count: int = 9
@export var rng_seed: int = 5150

var _count: int = 0
var _post_mat: StandardMaterial3D
var _frame_mat: StandardMaterial3D


func _ready() -> void:
	populate()


func populate() -> int:
	if _count > 0:
		return _count
	_post_mat = StandardMaterial3D.new()
	_post_mat.albedo_color = Color(0.18, 0.18, 0.2)
	_post_mat.metallic = 0.6
	_post_mat.roughness = 0.5
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = Color(0.1, 0.1, 0.11)
	_frame_mat.roughness = 0.7

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var n := maxi(count, 1)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var z := lerpf(z_start, z_end, t) + rng.randf_range(-60.0, 60.0)
		var node := _make_billboard(ADS[i % ADS.size()], rng)
		# Face the bay (+x); alternate a few to face -x so both sides get ads.
		node.rotation.y = (PI * 0.5) if (i % 3 != 0) else (-PI * 0.5)
		node.position = Vector3(line_x, ground_y, z)
		add_child(node)
	_count = n
	return _count


## A billboard faces +z by default (panel normal +z); the caller yaws it.
func _make_billboard(ad_text: String, rng: RandomNumberGenerator) -> Node3D:
	var board := Node3D.new()
	var panel_w := 13.0
	var panel_h := 5.0
	var deck_y := 6.5  # bottom of the panel above ground

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.5, deck_y + panel_h, 0.5)
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = _post_mat
		post.position = Vector3(sx * panel_w * 0.32, (deck_y + panel_h) * 0.5, -0.2)
		board.add_child(post)

	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(panel_w + 0.6, panel_h + 0.6, 0.35)
	frame.mesh = frame_mesh
	frame.material_override = _frame_mat
	frame.position = Vector3(0.0, deck_y + panel_h * 0.5, 0.0)
	board.add_child(frame)

	var face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(panel_w, panel_h, 0.12)
	face.mesh = face_mesh
	var face_mat := StandardMaterial3D.new()
	var tint := Color.from_hsv(rng.randf(), 0.5, 0.95)
	face_mat.albedo_color = tint
	face_mat.roughness = 0.55
	# Faint self-illumination so the hoarding reads as lit, day or night.
	face_mat.emission_enabled = true
	face_mat.emission = tint
	face_mat.emission_energy_multiplier = 0.35
	face.mesh.surface_set_material(0, face_mat)
	face.position = Vector3(0.0, deck_y + panel_h * 0.5, 0.2)
	board.add_child(face)

	var label := Label3D.new()
	label.text = ad_text
	label.font_size = 130
	label.pixel_size = 0.013
	label.modulate = Color(0.05, 0.05, 0.06)
	label.outline_size = 16
	label.outline_modulate = Color(1, 1, 1)
	label.position = Vector3(0.0, deck_y + panel_h * 0.5, 0.28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(label)
	return board
