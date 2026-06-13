class_name SeabirdFlock
extends Node3D
## Ambient coastal gulls wheeling over the bay — the moving life the static
## scenery (boats, palms, clouds) doesn't provide. Each bird circles a slowly
## drifting flock centre at its own radius/altitude/phase, banks into the turn,
## and flaps its wings. Pure time-driven motion (no per-frame allocation), built
## in populate() so it's headless-testable (test_seabird_flock.gd). Added by
## FloridaBackdrop.

@export var count: int = 26
@export var centre: Vector3 = Vector3(2600.0, 70.0, 200.0)
@export var spread: float = 900.0
@export var altitude_min: float = 45.0
@export var altitude_max: float = 130.0
@export var flap_speed: float = 6.0
@export var rng_seed: int = 1771

var _birds: Array = []
var _time: float = 0.0
var _body_mesh: BoxMesh
var _wing_mesh: BoxMesh
var _bird_mat: StandardMaterial3D


func _ready() -> void:
	populate()


## Builds the flock. Separate from _ready so it runs headless in tests.
func populate() -> void:
	if not _birds.is_empty():
		return
	_build_shared()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for _i in count:
		var node := _make_bird()
		add_child(node)
		_birds.append(
			{
				"node": node,
				"left": node.get_node("L"),
				"right": node.get_node("R"),
				"radius": rng.randf_range(spread * 0.18, spread * 0.5),
				"alt": rng.randf_range(altitude_min, altitude_max),
				"angle": rng.randf() * TAU,
				"ang_speed": rng.randf_range(0.08, 0.20) * (1.0 if rng.randf() < 0.7 else -1.0),
				"bob_phase": rng.randf() * TAU,
				"flap_phase": rng.randf() * TAU,
				"off":
				Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * spread * 0.3
			}
		)
	_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	_apply(_time)


func _apply(t: float) -> void:
	# Whole flock drifts slowly so it never feels pinned to one spot.
	var drift := Vector3(sin(t * 0.02) * spread * 0.25, 0.0, cos(t * 0.017) * spread * 0.25)
	for b in _birds:
		var ang: float = b["angle"] + t * b["ang_speed"]
		var r: float = b["radius"]
		var pos := (
			centre
			+ drift
			+ Vector3(b["off"].x, 0.0, b["off"].y)
			+ Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		)
		pos.y = b["alt"] + sin(t * 0.6 + b["bob_phase"]) * 4.0
		var node: Node3D = b["node"]
		# Face the flight tangent (derivative of the circle), bank into the turn.
		var tangent := Vector3(-sin(ang), 0.0, cos(ang)) * signf(b["ang_speed"])
		var heading := atan2(tangent.x, tangent.z)
		node.position = pos
		node.rotation = Vector3(0.0, heading, -0.35 * signf(b["ang_speed"]))
		var flap := sin(t * flap_speed + b["flap_phase"]) * 0.7
		(b["left"] as Node3D).rotation.z = flap
		(b["right"] as Node3D).rotation.z = -flap


func _build_shared() -> void:
	_body_mesh = BoxMesh.new()
	_body_mesh.size = Vector3(0.4, 0.32, 1.5)
	_wing_mesh = BoxMesh.new()
	_wing_mesh.size = Vector3(2.4, 0.06, 0.7)
	_bird_mat = StandardMaterial3D.new()
	_bird_mat.albedo_color = Color(0.92, 0.93, 0.95)
	_bird_mat.roughness = 0.8


## A bird = body + two wing pivots (L/R). The wing box is offset out along the
## pivot's +x so rotating the pivot about z flaps the wing like a hinge.
func _make_bird() -> Node3D:
	var bird := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.material_override = _bird_mat
	bird.add_child(body)
	bird.add_child(_make_wing("L", 1.0))
	bird.add_child(_make_wing("R", -1.0))
	return bird


func _make_wing(wing_name: String, side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = wing_name
	var wing := MeshInstance3D.new()
	wing.mesh = _wing_mesh
	wing.material_override = _bird_mat
	wing.position = Vector3(side * 1.3, 0.0, 0.0)
	pivot.add_child(wing)
	return pivot
