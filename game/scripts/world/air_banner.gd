class_name AirBanner
extends Node3D
## The Miami beach banner-tow plane — a light aircraft circling the coast,
## dragging a satirical advertising banner. Hits two Track Q axes at once:
## ambient life (a moving aircraft over the skyline) and humor/tone (the ad is
## the joke). Pure time-driven circular flight; banner trails behind with a
## gentle sway. Built in populate() so it's headless-testable. Added by
## FloridaBackdrop.

## Banner ad lines — original satirical Miami copy (rotated per plane). Keep them
## punchy and obviously parody; nothing lifted from any real product.
const ADS: Array[String] = [
	"SUNBURN INSURANCE — CLAIM BY DUSK",
	"VICE BEACH P.D.: SMILE, YOU'RE ON CAMERA",
	"GATOR JERKY — IT BITES BACK",
	"DIVORCE-A-RAMA: WALK-INS WELCOME",
	"NEON DENTAL — FINANCING AVAILABLE",
]

@export var centre: Vector3 = Vector3(5900.0, 75.0, -700.0)
@export var radius: float = 460.0
@export var speed: float = 0.085
@export var count: int = 1
@export var ad_color: Color = Color(0.95, 0.16, 0.42)
@export var rng_seed: int = 909

var _planes: Array = []
var _time: float = 0.0
var _body_mat: StandardMaterial3D
var _banner_mat: StandardMaterial3D


func _ready() -> void:
	populate()


func populate() -> void:
	if not _planes.is_empty():
		return
	_build_materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in count:
		var node := _make_plane(ADS[i % ADS.size()])
		add_child(node)
		_planes.append(
			{
				"node": node,
				"banner": node.get_node("Banner"),
				"angle": rng.randf() * TAU,
				"alt": centre.y + rng.randf_range(-12.0, 12.0),
				"dir": 1.0 if rng.randf() < 0.5 else -1.0
			}
		)
	_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	_apply(_time)


func _apply(t: float) -> void:
	for p in _planes:
		var dir: float = p["dir"]
		var ang: float = p["angle"] + t * speed * dir
		var pos := centre + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
		pos.y = p["alt"]
		var tangent := Vector3(-sin(ang), 0.0, cos(ang)) * dir
		var heading := atan2(tangent.x, tangent.z)
		var node: Node3D = p["node"]
		node.position = pos
		# Bank slightly into the turn for life.
		node.rotation = Vector3(0.0, heading, -0.18 * dir)
		# Banner sways on its tow point.
		(p["banner"] as Node3D).rotation.y = sin(t * 0.8 + p["angle"]) * 0.12


func _build_materials() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.9, 0.9, 0.92)
	_body_mat.roughness = 0.5
	_banner_mat = StandardMaterial3D.new()
	_banner_mat.albedo_color = ad_color
	_banner_mat.roughness = 0.7
	_banner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## Plane (+z forward) = fuselage + wing + tail, with a banner trailing at -z.
func _make_plane(ad_text: String) -> Node3D:
	var plane := Node3D.new()

	var fuselage := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(0.7, 0.8, 5.0)
	fuselage.mesh = fmesh
	fuselage.material_override = _body_mat
	plane.add_child(fuselage)

	var wing := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(7.0, 0.14, 1.1)
	wing.mesh = wmesh
	wing.position = Vector3(0.0, 0.1, 0.4)
	wing.material_override = _body_mat
	plane.add_child(wing)

	var tail := MeshInstance3D.new()
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(0.12, 1.0, 0.9)
	tail.mesh = tmesh
	tail.position = Vector3(0.0, 0.5, -2.3)
	tail.material_override = _body_mat
	plane.add_child(tail)

	# Banner: a long horizontal sheet trailing behind, standing vertically with
	# its normal along ±x so it reads broadside as the plane circles. The pivot
	# (Banner node) sits just behind the tail and sways; the sheet trails from it.
	var banner_len := 22.0
	var banner := Node3D.new()
	banner.name = "Banner"
	banner.position = Vector3(0.0, 0.0, -3.0)
	var sheet := MeshInstance3D.new()
	var smesh := PlaneMesh.new()
	smesh.size = Vector2(2.6, banner_len)  # x=height, y=length (before rotation)
	sheet.mesh = smesh
	# PlaneMesh lies in x-z (normal +y); rotate about z 90° → height along y,
	# length stays along z, normal along x.
	sheet.rotation = Vector3(0.0, 0.0, PI * 0.5)
	sheet.position = Vector3(0.0, 0.0, -banner_len * 0.5 - 1.0)
	sheet.material_override = _banner_mat
	banner.add_child(sheet)

	var label := Label3D.new()
	label.text = ad_text
	label.font_size = 110
	label.modulate = Color(1, 1, 1)
	label.outline_size = 22
	label.outline_modulate = Color(0, 0, 0)
	label.pixel_size = 0.01
	# Face +x (text runs along the banner length); double-sided so both passes read.
	label.rotation = Vector3(0.0, PI * 0.5, 0.0)
	label.position = Vector3(0.05, 0.0, -banner_len * 0.5 - 1.0)
	label.double_sided = true
	banner.add_child(label)

	plane.add_child(banner)
	return plane
