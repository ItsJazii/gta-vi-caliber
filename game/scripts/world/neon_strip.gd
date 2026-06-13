class_name NeonStrip
extends Node3D
## An Ocean-Drive-style beachfront strip — a row of small pastel Art-Deco hotels
## with neon rooflines, vertical marquee signs, and lit windows. Reads as pastel
## Deco by day and a glowing neon strip by night (pure emissive trim, so no
## dependency on the shared env). Original parody hotel names. Built in
## populate() for headless tests; placed along the shore via FloridaBackdrop.

## Pastel Deco body colours, cycled per building.
const BODIES: Array[Color] = [
	Color(0.97, 0.78, 0.82),  # rose
	Color(0.78, 0.93, 0.92),  # aqua
	Color(0.98, 0.92, 0.74),  # cream yellow
	Color(0.86, 0.80, 0.95),  # lavender
	Color(0.80, 0.92, 0.80),  # mint
]
## Neon trim colours, cycled offset from the body so they pop.
const NEONS: Array[Color] = [
	Color(0.1, 0.95, 1.0),  # cyan
	Color(1.0, 0.13, 0.6),  # magenta
	Color(0.7, 0.3, 1.0),  # violet
	Color(1.0, 0.55, 0.1),  # amber
	Color(0.3, 1.0, 0.5),  # lime
]
## Original parody hotel names.
const NAMES: Array[String] = [
	"FLAMINGO", "STARFISH", "NEPTUNE", "THE DECO", "SEABREEZE", "CORAL", "THE TIDE", "LAGOON"
]

@export var ground_y: float = 0.0
@export var line_x: float = 1340.0
@export var z_start: float = -1500.0
@export var z_end: float = 1500.0
@export var count: int = 7
@export var face_yaw: float = 0.0  # faces +x (the water) by default

var _count: int = 0


func _ready() -> void:
	populate()


func populate() -> int:
	if _count > 0:
		return _count
	var n := maxi(count, 1)
	var pitch := (z_end - z_start) / float(n)
	for i in n:
		var z := z_start + pitch * (float(i) + 0.5)
		var b := _make_building(
			BODIES[i % BODIES.size()], NEONS[i % NEONS.size()], NAMES[i % NAMES.size()]
		)
		b.position = Vector3(line_x, ground_y, z)
		b.rotation.y = face_yaw
		add_child(b)
	_count = n
	return _count


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Building faces +x (front = +x face). Body + parapet + neon roofline + window
## grid + a vertical marquee sign.
func _make_building(body_color: Color, neon: Color, hotel: String) -> Node3D:
	var b := Node3D.new()
	var w := 12.0
	var depth := 11.0
	var h := 9.5
	var front := w * 0.5  # +x face

	var body := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(w, h, depth)
	body.mesh = bmesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body_mat.roughness = 0.6
	body.material_override = body_mat
	body.position = Vector3(0.0, h * 0.5, 0.0)
	b.add_child(body)

	# White Deco parapet cap.
	var cap := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(w + 0.5, 0.6, depth + 0.5)
	cap.mesh = cmesh
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.97, 0.95)
	cap.material_override = white
	cap.position = Vector3(0.0, h + 0.3, 0.0)
	b.add_child(cap)

	# Neon roofline tube along the front edge.
	var neon_mat := _emissive(neon, 3.0)
	var roof := MeshInstance3D.new()
	var rmesh := BoxMesh.new()
	rmesh.size = Vector3(w + 0.2, 0.16, 0.16)
	roof.mesh = rmesh
	roof.name = "NeonRoofline"
	roof.material_override = neon_mat
	roof.position = Vector3(0.0, h + 0.05, front + 0.05)
	b.add_child(roof)

	# Lit window grid on the front face (warm interior glow).
	var win := Node3D.new()
	win.name = "Windows"
	b.add_child(win)
	var win_mat := _emissive(Color(1.0, 0.86, 0.6), 1.3)
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(1.3, 1.3, 0.1)
	var cols := 3
	var rows := 3
	for r in rows:
		for c in cols:
			var cell := MeshInstance3D.new()
			cell.mesh = win_mesh
			cell.material_override = win_mat
			var wx := (float(c) - float(cols - 1) * 0.5) * 3.0
			var wy := 2.2 + float(r) * 2.4
			cell.position = Vector3(wx, wy, front + 0.06)
			win.add_child(cell)

	# Vertical marquee sign on the front, with the hotel name.
	var marquee := MeshInstance3D.new()
	var mmesh := BoxMesh.new()
	mmesh.size = Vector3(2.0, 6.0, 0.25)
	marquee.mesh = mmesh
	marquee.material_override = _emissive(neon, 2.2)
	marquee.position = Vector3(w * 0.5 - 1.4, h * 0.55, front + 0.2)
	b.add_child(marquee)
	var label := Label3D.new()
	label.name = "Marquee"
	label.text = hotel
	label.font_size = 90
	label.pixel_size = 0.012
	label.modulate = Color(1, 1, 1)
	label.outline_size = 14
	label.outline_modulate = Color(0.05, 0.05, 0.08)
	label.rotation.z = PI * 0.5  # read vertically up the marquee
	label.position = Vector3(w * 0.5 - 1.4, h * 0.55, front + 0.34)
	b.add_child(label)
	return b
