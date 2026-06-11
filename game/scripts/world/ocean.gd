class_name Ocean
extends MeshInstance3D
## Gerstner-wave ocean surface (M4 "Ocean v1"). Builds a large subdivided
## plane at runtime and drives game/shaders/ocean.gdshader, which displaces
## it in the vertex stage. Wave shape constants live in OceanMath and the
## shader (mirrored — see the contract note in both files); this node owns
## the *look* knobs (colors, clarity) and the shared wave clock.
##
## The shader uses world-space coordinates, so wave_height_at() is only
## valid while this node keeps identity rotation and scale (translation is
## fine: x/z shift the wave field on both sides identically, y offsets the
## resting level, which wave_height_at() adds back).

## Edge length of the square ocean plane, metres.
@export var size_m: float = 1400.0
## Subdivisions per side. Vertex spacing = size_m / resolution; short waves
## below that still shade correctly (per-pixel normals) but won't displace.
@export_range(16, 512) var resolution: int = 280
## Scales every wave amplitude; 0 is a dead-flat sea.
@export_range(0.0, 4.0) var amplitude_scale: float = 1.0
## Time multiplier for wave travel speed.
@export_range(0.0, 4.0) var wave_speed: float = 1.0
@export var shallow_color: Color = Color(0.02, 0.6, 0.56)
@export var deep_color: Color = Color(0.0, 0.12, 0.28)
@export var horizon_color: Color = Color(0.16, 0.38, 0.55)
## Beer-Lambert extinction per metre of water along the view ray.
@export_range(0.01, 1.0) var absorption_per_m: float = 0.3
## Water thinner than this fades out (soft shoreline edge), metres.
@export_range(0.05, 5.0) var edge_fade_m: float = 0.6
@export_range(0.0, 1.0) var surface_roughness: float = 0.08
## Depth band (m) that generates surf foam in the shader. Smaller values keep
## broad shallow flats from turning into white paint.
@export_range(0.05, 3.0) var foam_depth_m: float = 1.1
@export_range(0.0, 2.0) var foam_strength: float = 1.0
@export var foam_color: Color = Color(0.96, 0.97, 0.94, 1.0)

var _material: ShaderMaterial
var _time: float = 0.0


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m, size_m)
	plane.subdivide_width = resolution
	plane.subdivide_depth = resolution
	mesh = plane

	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/ocean.gdshader")
	material_override = _material
	# Vertex displacement moves geometry outside the static AABB.
	extra_cull_margin = 4.0 * OceanMath.max_height(amplitude_scale) + 4.0
	_push_look_params()


func _process(delta: float) -> void:
	_time += delta * wave_speed
	_material.set_shader_parameter("u_time", _time)


## Surface height in world space at world_pos.xz, for buoyancy queries.
## Matches the rendered surface — see the OceanMath/shader contract.
func wave_height_at(world_pos: Vector3) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return global_position.y + OceanMath.wave_height_at(xz, _time, amplitude_scale)


## Buoyancy convenience matching the floater/boat API (world x/z -> surface y).
## Lets Floater bodies bob on this GPU ocean the same way they do on the CPU sea.
func surface_height(world_x: float, world_z: float) -> float:
	return wave_height_at(Vector3(world_x, 0.0, world_z))


func _push_look_params() -> void:
	_material.set_shader_parameter("u_time", _time)
	_material.set_shader_parameter("u_amplitude_scale", amplitude_scale)
	_material.set_shader_parameter("u_shallow_color", shallow_color)
	_material.set_shader_parameter("u_deep_color", deep_color)
	_material.set_shader_parameter("u_horizon_color", horizon_color)
	_material.set_shader_parameter("u_absorption", absorption_per_m)
	_material.set_shader_parameter("u_edge_fade", edge_fade_m)
	_material.set_shader_parameter("u_roughness", surface_roughness)
	_material.set_shader_parameter("u_foam_depth", foam_depth_m)
	_material.set_shader_parameter("u_foam_strength", foam_strength)
	_material.set_shader_parameter("u_foam_color", foam_color)
