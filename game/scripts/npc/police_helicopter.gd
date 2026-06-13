class_name PoliceHelicopter
extends Node3D
## Police air support. At 3+ stars (HelicopterPursuit.should_deploy) the chopper
## flies in and circles the player, sweeping a searchlight that tracks them; while
## the beam has line of sight it keeps the heat hot and the player's position
## known. Below 3 stars it peels off and hides. A single unit lives in the scene
## and shows/hides on demand, self-wiring by group (player, wanted). All flight
## math is the pure, tested HelicopterPursuit model; the body is a cheap greybox
## stand-in for the look-dev pass to replace.

## Stars at which the pursuit siren joins the rotor thump.
const SIREN_STARS: int = 4

@export var orbit_radius: float = 30.0
@export var altitude: float = 34.0
@export var angular_speed: float = 0.55
@export var cruise_speed: float = 26.0
@export var cone_degrees: float = 22.0
@export var rotor_rpm: float = 520.0

var _t: float = 0.0
var _active: bool = false
var _lit: bool = false
var _player: Node3D = null
var _tracker: Node = null
var _rotor: Node3D = null
var _light: SpotLight3D = null
var _audio: HelicopterAudio = null


func _ready() -> void:
	add_to_group("police_air")
	_build_body()
	_audio = HelicopterAudio.new()
	_audio.name = "Audio"
	add_child(_audio)
	visible = false


func _physics_process(delta: float) -> void:
	_bind()
	var stars := int(_tracker.stars()) if _tracker != null and _tracker.has_method("stars") else 0
	_set_active(HelicopterPursuit.should_deploy(stars) and _player != null)
	if _audio != null:
		_audio.set_siren(_active and stars >= SIREN_STARS)
	if not _active or _player == null:
		return
	_t += delta
	if _rotor != null:
		_rotor.rotate_y(deg_to_rad(rotor_rpm) * delta)
	var center := _player.global_position
	var goal := HelicopterPursuit.orbit_point(center, _t, orbit_radius, altitude, angular_speed)
	global_position = global_position.move_toward(goal, cruise_speed * delta)
	_aim_searchlight(center)


## True while the chopper is deployed and circling.
func is_active() -> bool:
	return _active


## True while the searchlight has an unobstructed line to the player (they break
## it with overhead cover — bridges, tunnels, interiors).
func is_lighting_target() -> bool:
	return _lit


func _set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	visible = on
	_lit = _lit and on
	if _audio != null:
		_audio.set_running(on)
	if on and _player != null:
		# Fly in from high above so it eases onto the orbit instead of popping in.
		global_position = _player.global_position + Vector3(0.0, altitude + 24.0, 0.0)


func _aim_searchlight(center: Vector3) -> void:
	if _light != null and global_position.distance_to(center) > 0.5:
		_light.look_at(center, Vector3.UP)
	_lit = _has_sightline(center)


func _has_sightline(center: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, center + Vector3.UP * 1.2)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider != null and collider.is_in_group("player")


func _bind() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _tracker == null or not is_instance_valid(_tracker):
		_tracker = get_tree().get_first_node_in_group("wanted")


func _build_body() -> void:
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.06, 0.07, 0.09)
	hull_mat.metallic = 0.4
	hull_mat.roughness = 0.5
	_add_box(Vector3.ZERO, Vector3(2.2, 1.5, 4.6), hull_mat)
	_add_box(Vector3(0.0, 0.3, -3.6), Vector3(0.4, 0.4, 3.2), hull_mat)
	_add_box(Vector3(0.0, 1.0, -5.2), Vector3(0.2, 1.4, 0.2), hull_mat)

	var rotor := Node3D.new()
	rotor.position = Vector3(0.0, 1.1, 0.0)
	add_child(rotor)
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.02, 0.02, 0.03)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(11.0, 0.08, 0.5)
	bm.material = blade_mat
	blade.mesh = bm
	rotor.add_child(blade)
	_rotor = rotor

	var light := SpotLight3D.new()
	light.position = Vector3(0.0, -0.6, 1.2)
	light.spot_range = 90.0
	light.spot_angle = clampf(cone_degrees * 2.0, 5.0, 80.0)
	light.light_energy = 8.0
	light.light_color = Color(0.92, 0.96, 1.0)
	add_child(light)
	_light = light


func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	add_child(mesh)
