class_name CinematicCamera
extends Camera3D
## A camera that flies a Catmull-Rom path for trailer/cutscene capture (roadmap
## M6). Give it waypoints and a duration; it eases along the spline (CameraPath,
## pure + tested) looking slightly ahead so it banks into turns. Becomes the
## active camera while playing and can loop for a continuous flythrough.

## World-space control points the camera flies through.
@export var waypoints: Array[Vector3] = []
## Seconds for one full pass along the path.
@export var duration: float = 12.0
## How far ahead (in path-t) to aim, so the camera looks where it's going.
@export var look_ahead: float = 0.04
@export var loop: bool = true
@export var autostart: bool = false

var _t: float = 0.0
var _playing: bool = false


func _ready() -> void:
	if autostart:
		play()


## Start (or restart) the flythrough and take over as the active camera.
func play() -> void:
	if waypoints.size() < 2:
		return
	_t = 0.0
	_playing = true
	current = true


func stop() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing or waypoints.size() < 2:
		return
	_t += delta / maxf(duration, 0.001)
	if _t >= 1.0:
		if loop:
			_t = fposmod(_t, 1.0)
		else:
			_t = 1.0
			_playing = false

	var pos := CameraPath.sample(waypoints, _t)
	global_position = pos
	var ahead := CameraPath.sample(waypoints, minf(_t + look_ahead, 1.0))
	if ahead.distance_to(pos) > 0.001:
		look_at(ahead, Vector3.UP)
