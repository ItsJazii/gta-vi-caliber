class_name CloudLayer
extends MeshInstance3D
## A high-altitude broken-cumulus sheet driving shaders/cloud_plane.gdshader.
## Builds one large horizontal plane above the map at runtime; the shader carves
## drifting clouds from fbm and dissolves them into the horizon haze, giving the
## flat ProceduralSky gradient depth and motion. Added by FloridaBackdrop so the
## playable map gets a real sky without touching the (shared) scene environment.

## Height of the cloud sheet above sea level, metres.
@export var altitude: float = 640.0
## Edge length of the cloud plane, metres. Large so its rim sits past the
## shader's distance fade and never shows as a hard line.
@export var size_m: float = 32000.0
## 0 = clear, 1 = overcast. Tune for the scene's mood.
@export_range(0.0, 1.0) var coverage: float = 0.52
## Warm sky-horizon colour the far clouds melt into (match the scene sky).
@export var sky_haze: Color = Color(0.72, 0.50, 0.40)


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m, size_m)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	mesh = plane
	position.y = altitude
	# Static plane far overhead — keep it visible from anywhere under it.
	extra_cull_margin = size_m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cloud_plane.gdshader")
	mat.set_shader_parameter("coverage", coverage)
	mat.set_shader_parameter("sky_haze", sky_haze)
	material_override = mat
