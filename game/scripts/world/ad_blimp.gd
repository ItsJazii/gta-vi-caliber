class_name AdBlimp
extends Node3D
## A slow advertising blimp circling high over downtown — chosen because, unlike
## the ground-level coastal props, a big object at altitude is visible from the
## player's actual playspace and reads in the map's fixed dusk grade (not just
## at night). Carries an original parody ad on its flank. Pure time-driven
## drift; built in populate() (headless-testable), animated in _process. Added
## by FloridaBackdrop.

const ADS: Array[String] = [
	"EGO CHASER — THE COLOGNE",
	"PASTOR RICH'S MIRACLE CRUISE",
	"DREAMQUEST: RESULTS MAY VARY",
	"BLISS LITE — NOW 2% JUICE",
]

@export var centre: Vector3 = Vector3(200.0, 270.0, -250.0)
@export var radius: float = 700.0
@export var speed: float = 0.014  # ~10 m/s — a realistic, majestic blimp drift
@export var ad_color: Color = Color(0.95, 0.2, 0.35)

var _time: float = 0.0
var _ad_index: int = 0
var _beacon: Node3D


func _ready() -> void:
	populate()


func populate() -> int:
	if get_child_count() > 0:
		return get_child_count()
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	var hmesh := SphereMesh.new()
	hmesh.radius = 7.0
	hmesh.height = 14.0
	hull.mesh = hmesh
	hull.scale = Vector3(1.0, 1.0, 2.9)  # stretch into a blimp envelope
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.9, 0.9, 0.93)
	hull_mat.roughness = 0.45
	hull.material_override = hull_mat
	add_child(hull)

	# A faint nose-to-tail stripe band of colour.
	var band := MeshInstance3D.new()
	var bmesh := SphereMesh.new()
	bmesh.radius = 7.05
	bmesh.height = 4.0
	band.mesh = bmesh
	band.scale = Vector3(1.0, 1.0, 2.9)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = ad_color
	band_mat.roughness = 0.5
	band.material_override = band_mat
	add_child(band)

	# Tail fins (cross).
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = ad_color
	fin_mat.roughness = 0.5
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
		var fin := MeshInstance3D.new()
		var fmesh := BoxMesh.new()
		fmesh.size = Vector3(0.3, 7.0, 5.0)
		fin.mesh = fmesh
		fin.material_override = fin_mat
		fin.position = Vector3(0.0, 0.0, 18.0)
		fin.rotation.z = ang
		fin.position = Vector3(sin(ang) * 5.0, cos(ang) * 5.0, 18.0)
		add_child(fin)

	# Gondola under the belly.
	var gondola := MeshInstance3D.new()
	var gmesh := BoxMesh.new()
	gmesh.size = Vector3(2.2, 1.6, 6.0)
	gondola.mesh = gmesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.15, 0.16, 0.2)
	gondola.material_override = gmat
	gondola.position = Vector3(0.0, -7.6, -2.0)
	add_child(gondola)

	# Ad on the flank: a slightly emissive panel + the parody text, readable in
	# dusk and glowing a touch at night.
	var ad_panel := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(0.3, 8.0, 30.0)
	ad_panel.mesh = pmesh
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.06, 0.06, 0.08)
	panel_mat.emission_enabled = true
	panel_mat.emission = ad_color
	panel_mat.emission_energy_multiplier = 0.5
	ad_panel.material_override = panel_mat
	ad_panel.position = Vector3(7.2, 0.0, -2.0)
	add_child(ad_panel)

	var label := Label3D.new()
	label.name = "Ad"
	label.text = ADS[_ad_index % ADS.size()]
	label.font_size = 120
	label.pixel_size = 0.022
	label.modulate = Color(1, 1, 1)
	label.outline_size = 18
	label.outline_modulate = Color(0.1, 0.0, 0.04)
	label.rotation = Vector3(0.0, PI * 0.5, 0.0)
	label.position = Vector3(7.45, 0.0, -2.0)
	label.double_sided = true
	add_child(label)

	_build_nav_lights()
	_apply(0.0)
	return get_child_count()


## Aircraft nav/beacon lights so the blimp reads in the dusk grade (and at night):
## steady red (port) + green (starboard) at the tail, and a blinking red strobe.
func _build_nav_lights() -> void:
	var dot := SphereMesh.new()
	dot.radius = 0.45
	dot.height = 0.9
	for spec in [[-1.0, Color(1.0, 0.1, 0.1)], [1.0, Color(0.1, 1.0, 0.2)]]:
		var nav := MeshInstance3D.new()
		nav.mesh = dot
		var m := StandardMaterial3D.new()
		m.albedo_color = spec[1]
		m.emission_enabled = true
		m.emission = spec[1]
		m.emission_energy_multiplier = 3.0
		nav.material_override = m
		nav.position = Vector3(float(spec[0]) * 5.5, 0.0, 16.0)
		add_child(nav)

	_beacon = MeshInstance3D.new()
	(_beacon as MeshInstance3D).mesh = dot
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.15, 0.1)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.15, 0.1)
	bm.emission_energy_multiplier = 5.0
	(_beacon as MeshInstance3D).material_override = bm
	_beacon.name = "Beacon"
	_beacon.position = Vector3(0.0, -7.8, -2.0)
	add_child(_beacon)


func _process(delta: float) -> void:
	_time += delta
	_apply(_time)
	# Anti-collision strobe: a quick double-blink each ~1.3 s.
	if _beacon != null:
		var ph := fmod(_time, 1.3)
		_beacon.visible = ph < 0.08 or (ph > 0.18 and ph < 0.26)


func _apply(t: float) -> void:
	var ang := t * speed
	var pos := centre + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
	pos.y = centre.y + sin(t * 0.12) * 8.0  # gentle altitude bob
	var tangent := Vector3(-sin(ang), 0.0, cos(ang))
	position = pos
	# +z is the blimp's nose; face the travel tangent.
	rotation.y = atan2(tangent.x, tangent.z)
