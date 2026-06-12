class_name BayBoats
extends Node3D
## Ambient watercraft scattered across the open bay — sailboats and motor yachts
## that bob and tilt on the Gerstner ocean (via OceanMath, the CPU twin of the
## water shader) and drift slowly along their heading, wrapping within the bay
## rectangle. Fills the large empty water with life. Added by FloridaBackdrop.
##
## OceanMath is pure, so the motion is headless-testable (test_bay_boats.gd) and
## the fleet needs no reference to the Ocean node.

@export var count: int = 26
@export var area_min: Vector2 = Vector2(1300.0, -2400.0)
@export var area_max: Vector2 = Vector2(4700.0, 1900.0)
@export var ocean_y: float = -0.18
@export var amplitude_scale: float = 0.75
@export var drift_speed_min: float = 1.0
@export var drift_speed_max: float = 4.0
@export var rng_seed: int = 4242

var _boats: Array = []
var _time: float = 0.0
var _hull_mats: Array[StandardMaterial3D] = []
var _cabin_mat: StandardMaterial3D
var _sail_mat: StandardMaterial3D
var _hull_mesh: BoxMesh
var _bow_mesh: PrismMesh
var _cabin_mesh: BoxMesh
var _mast_mesh: BoxMesh
var _sail_mesh: PrismMesh


func _ready() -> void:
	populate()


## Builds the fleet. Separate from _ready so it can be driven headless in tests
## (where _ready does not fire synchronously before the first frame).
func populate() -> void:
	if not _boats.is_empty():
		return
	_build_shared()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for _i in count:
		var pos := Vector2(
			rng.randf_range(area_min.x, area_max.x), rng.randf_range(area_min.y, area_max.y)
		)
		var node := _make_boat(rng.randf() < 0.6, rng)
		add_child(node)
		_boats.append(
			{
				"node": node,
				"pos": pos,
				"heading": rng.randf() * TAU,
				"speed": rng.randf_range(drift_speed_min, drift_speed_max)
			}
		)
	_apply_transforms()


func _process(delta: float) -> void:
	_time += delta
	for b in _boats:
		var p: Vector2 = b["pos"]
		var h: float = b["heading"]
		# heading 0 → +z; advance and wrap inside the bay rectangle.
		p += Vector2(sin(h), cos(h)) * (b["speed"] * delta)
		p.x = wrapf(p.x, area_min.x, area_max.x)
		p.y = wrapf(p.y, area_min.y, area_max.y)
		b["pos"] = p
	_apply_transforms()


## Sits each boat on the wave surface, yawed to its heading and tilted to the
## local wave slope so the fleet rocks instead of sliding flat.
func _apply_transforms() -> void:
	for b in _boats:
		var p: Vector2 = b["pos"]
		var node: Node3D = b["node"]
		var y := ocean_y + OceanMath.wave_height_at(p, _time, amplitude_scale)
		var n := OceanMath.surface_normal(p, _time, amplitude_scale)
		node.transform = _boat_basis(n, b["heading"], Vector3(p.x, y, p.y))


## Build a transform whose up axis is the wave normal and whose forward (+z)
## points along the heading, projected onto the tilted deck.
func _boat_basis(up: Vector3, heading: float, origin: Vector3) -> Transform3D:
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var right := fwd.cross(up).normalized()
	var fwd2 := up.cross(right).normalized()
	return Transform3D(Basis(right, up.normalized(), -fwd2), origin)


func _build_shared() -> void:
	_hull_mesh = BoxMesh.new()
	_hull_mesh.size = Vector3(3.0, 1.1, 9.0)
	_cabin_mesh = BoxMesh.new()
	_cabin_mesh.size = Vector3(1.9, 0.95, 3.4)
	_mast_mesh = BoxMesh.new()
	_mast_mesh.size = Vector3(0.12, 5.2, 0.12)
	_sail_mesh = PrismMesh.new()
	_sail_mesh.size = Vector3(2.6, 4.0, 0.06)
	# Pointed bow wedge: a prism rotated so its apex points forward (+z), giving
	# the hull a real prow instead of a blunt box front.
	_bow_mesh = PrismMesh.new()
	_bow_mesh.size = Vector3(3.0, 2.6, 1.1)

	for c in [Color(0.93, 0.91, 0.87), Color(0.11, 0.16, 0.32), Color(0.62, 0.13, 0.13)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.45
		_hull_mats.append(m)
	_cabin_mat = StandardMaterial3D.new()
	_cabin_mat.albedo_color = Color(0.82, 0.83, 0.85)
	_cabin_mat.roughness = 0.4
	_sail_mat = StandardMaterial3D.new()
	_sail_mat.albedo_color = Color(0.95, 0.94, 0.9)
	_sail_mat.roughness = 0.7
	_sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _make_boat(is_sail: bool, rng: RandomNumberGenerator) -> Node3D:
	var boat := Node3D.new()
	var s := rng.randf_range(0.8, 1.5)
	boat.scale = Vector3(s, s, s)

	var hull_mat := _hull_mats[rng.randi() % _hull_mats.size()]
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh
	hull.material_override = hull_mat
	hull.position.y = 0.15
	boat.add_child(hull)

	# Pointed bow at the front of the hull (apex forward via -90° about X).
	var bow := MeshInstance3D.new()
	bow.mesh = _bow_mesh
	bow.material_override = hull_mat
	bow.rotation.x = -PI * 0.5
	bow.position = Vector3(0.0, 0.15, 4.5)
	boat.add_child(bow)

	if is_sail:
		var mast := MeshInstance3D.new()
		mast.mesh = _mast_mesh
		mast.position = Vector3(0.0, 2.7, 0.2)
		boat.add_child(mast)
		var sail := MeshInstance3D.new()
		sail.mesh = _sail_mesh
		sail.material_override = _sail_mat
		# Thin in z by default → rotate 90° about Y so the triangle stands in the
		# fore-aft plane (a mainsail), bottom near the boom, leaning slightly back.
		sail.rotation.y = PI * 0.5
		sail.position = Vector3(0.0, 2.3, -0.4)
		boat.add_child(sail)
	else:
		var cabin := MeshInstance3D.new()
		cabin.mesh = _cabin_mesh
		cabin.material_override = _cabin_mat
		cabin.position = Vector3(0.0, 0.95, -0.6)
		boat.add_child(cabin)
	return boat
