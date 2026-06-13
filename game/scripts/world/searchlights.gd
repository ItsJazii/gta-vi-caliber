class_name Searchlights
extends Node3D
## Sweeping searchlight beams over the night skyline — the club/premiere drama
## the static night sky was missing. A cluster of lamps, each casting a
## fake-volumetric shaft (cone + searchlight_beam.gdshader) that sweeps in yaw
## and breathes in tilt, staggered per lamp so the beams cross. Pure additive
## emissive, no volumetric-fog dependency. Built in populate() (headless-test),
## swept in _process. Placed via FloridaBackdrop.

@export var count: int = 4
@export var spacing: float = 9.0
@export var beam_height: float = 175.0
@export var beam_top_radius: float = 7.5
@export var tilt_deg: float = 38.0
@export var sweep_deg: float = 55.0
@export var sweep_speed: float = 0.5
@export var beam_color: Color = Color(0.82, 0.88, 1.0)

var _lamps: Array = []
var _time: float = 0.0


func _ready() -> void:
	populate()


func populate() -> int:
	if not _lamps.is_empty():
		return _lamps.size()
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.08, 0.08, 0.1)
	base_mat.metallic = 0.5
	base_mat.roughness = 0.5
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = beam_color
	lamp_mat.emission_enabled = true
	lamp_mat.emission = beam_color
	lamp_mat.emission_energy_multiplier = 4.0

	var beam_mesh := CylinderMesh.new()
	beam_mesh.bottom_radius = 0.5
	beam_mesh.top_radius = beam_top_radius
	beam_mesh.height = beam_height
	beam_mesh.radial_segments = 14

	for i in count:
		var x := (float(i) - float(count - 1) * 0.5) * spacing
		# Housing.
		var base := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(1.6, 1.0, 1.6)
		base.mesh = bmesh
		base.material_override = base_mat
		base.position = Vector3(x, 0.5, 0.0)
		add_child(base)
		# Glowing lamp lens.
		var lens := MeshInstance3D.new()
		var lmesh := SphereMesh.new()
		lmesh.radius = 0.6
		lmesh.height = 1.2
		lens.mesh = lmesh
		lens.material_override = lamp_mat
		lens.position = Vector3(x, 1.1, 0.0)
		add_child(lens)
		# Pivot at the lamp; the beam cone rises from it.
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 1.1, 0.0)
		add_child(pivot)
		var beam := MeshInstance3D.new()
		beam.mesh = beam_mesh
		var beam_mat := ShaderMaterial.new()
		beam_mat.shader = load("res://shaders/searchlight_beam.gdshader")
		beam_mat.set_shader_parameter("beam_color", beam_color)
		beam_mat.set_shader_parameter("height", beam_height)
		beam.material_override = beam_mat
		beam.position = Vector3(0.0, beam_height * 0.5, 0.0)
		pivot.add_child(beam)
		_lamps.append(
			{"pivot": pivot, "phase": float(i) * 1.7, "ydir": 1.0 if i % 2 == 0 else -1.0}
		)
	_apply(0.0)
	return _lamps.size()


func _process(delta: float) -> void:
	_time += delta
	_apply(_time)


func _apply(t: float) -> void:
	var tilt := deg_to_rad(tilt_deg)
	for lamp in _lamps:
		var phase: float = lamp["phase"]
		var ydir: float = lamp["ydir"]
		var yaw := deg_to_rad(sweep_deg) * sin(t * sweep_speed + phase) * ydir
		# A little tilt breathing so the beams aren't locked to one cone angle.
		var tilt_now := tilt + 0.12 * sin(t * 0.37 + phase)
		var pivot: Node3D = lamp["pivot"]
		pivot.rotation = Vector3(tilt_now, yaw, 0.0)
