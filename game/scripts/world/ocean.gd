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
## With a fine region (below), this is the fine grid's resolution instead.
@export_range(16, 512) var resolution: int = 280
## Half-extent (m) of the densely tessellated centre square. 0 keeps the
## classic uniform plane. Positive values build a tiered mesh (OceanMeshBuilder):
## fine vertices where displacement is visible, flat far-field quads beyond —
## a 12 km backdrop drops from ~74k to ~19k triangles while the playable water
## gets a finer grid than before. Displacement fades out across fade_band_m
## approaching the fine edge (GPU and CPU alike) so the tier seam stays flat.
@export var fine_extent_m: float = 0.0
## Approximate far-field quad edge (m) when fine_extent_m > 0.
@export var far_cell_m: float = 750.0
## Width (m) of the displacement fade band inside the fine-region edge.
@export var fade_band_m: float = 250.0
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
## Open-water whitecap foam, decoupled from the shoreline band so a calm bay
## over a flat seabed can stay thin at the sand yet still froth on the swell.
@export_range(0.0, 2.0) var whitecap_strength: float = 1.0
## Gerstner Jacobian below which whitecaps form. 1.0 = only true wave overlap;
## raise it to feather caps onto steep-but-unbroken crests on a livelier sea.
@export_range(0.4, 1.6) var whitecap_coverage: float = 1.0
@export var foam_color: Color = Color(0.96, 0.97, 0.94, 1.0)

var _material: ShaderMaterial
var _time: float = 0.0
# Snapped fine-square half-extent; INF means uniform mesh (no fade anywhere).
var _fine_half: float = INF


func _ready() -> void:
	if fine_extent_m > 0.0 and fine_extent_m < size_m * 0.5:
		var geo := OceanMeshBuilder.build(size_m, fine_extent_m, resolution, far_cell_m)
		_fine_half = geo["fine_half"]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = geo["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = geo["normals"]
		arrays[Mesh.ARRAY_INDEX] = geo["indices"]
		var tiered := ArrayMesh.new()
		tiered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh = tiered
	else:
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
	if _fine_half != INF:
		# Track origin shifts (FloatingOrigin) so the fade stays mesh-centred.
		var origin := _origin()
		_material.set_shader_parameter("u_fade_center", Vector2(origin.x, origin.z))


## Surface height in world space at world_pos.xz, for buoyancy queries.
## Matches the rendered surface — see the OceanMath/shader contract; with a
## tiered mesh this includes the same far-field displacement fade as the GPU.
func wave_height_at(world_pos: Vector3) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _origin().y + OceanMath.wave_height_at(xz, _time, _amp_scale_at(xz))


## Effective amplitude scale at a world XZ: the authored scale, faded toward
## zero across the band inside the fine-region edge (tiered meshes only).
func _amp_scale_at(world_xz: Vector2) -> float:
	if _fine_half == INF:
		return amplitude_scale
	var origin := _origin()
	var rel := world_xz - Vector2(origin.x, origin.z)
	var fade_start := maxf(_fine_half - maxf(fade_band_m, 0.0), 0.0)
	return amplitude_scale * OceanMeshBuilder.displacement_falloff(rel, fade_start, _fine_half)


## Node origin in world space; falls back to the local position out of tree
## (pure unit tests) where global_position would error.
func _origin() -> Vector3:
	return global_position if is_inside_tree() else position


## Buoyancy convenience matching the floater/boat API (world x/z -> surface y).
## Lets Floater bodies bob on this GPU ocean the same way they do on the CPU sea.
func surface_height(world_x: float, world_z: float) -> float:
	return wave_height_at(Vector3(world_x, 0.0, world_z))


func _push_look_params() -> void:
	_material.set_shader_parameter("u_time", _time)
	_material.set_shader_parameter("u_amplitude_scale", amplitude_scale)
	if _fine_half != INF:
		var origin := _origin()
		_material.set_shader_parameter("u_fade_center", Vector2(origin.x, origin.z))
		_material.set_shader_parameter(
			"u_fade_start", maxf(_fine_half - maxf(fade_band_m, 0.0), 0.0)
		)
		_material.set_shader_parameter("u_fade_end", _fine_half)
	_material.set_shader_parameter("u_shallow_color", shallow_color)
	_material.set_shader_parameter("u_deep_color", deep_color)
	_material.set_shader_parameter("u_horizon_color", horizon_color)
	_material.set_shader_parameter("u_absorption", absorption_per_m)
	_material.set_shader_parameter("u_edge_fade", edge_fade_m)
	_material.set_shader_parameter("u_roughness", surface_roughness)
	_material.set_shader_parameter("u_foam_depth", foam_depth_m)
	_material.set_shader_parameter("u_foam_strength", foam_strength)
	_material.set_shader_parameter("u_whitecap_strength", whitecap_strength)
	_material.set_shader_parameter("u_whitecap_coverage", whitecap_coverage)
	_material.set_shader_parameter("u_foam_color", foam_color)
