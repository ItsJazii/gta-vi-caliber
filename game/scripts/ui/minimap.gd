class_name Minimap
extends Control
## GTA-style circular minimap. Renders a top-down, player-up rotating view: a
## procedural street grid, the player arrow at centre, nearby pedestrian/vehicle
## blips, a north tick and the active waypoint (clamped to the rim with an arrow
## when off-map). Pure observation — it reads the player's position from the
## "player" group and the facing from the active 3D camera, and never writes.
##
## Projection lives in HudFormat.world_to_map so it matches any other map UI and
## is unit-tested. Segment/circle clipping keeps roads inside the disc.

## World metres mapped to one screen pixel's worth of zoom.
@export var pixels_per_meter: float = 1.6
## Street grid spacing in world metres.
@export var grid_spacing: float = 24.0

@export var disc_color: Color = Color(0.09, 0.11, 0.14, 0.82)
@export var road_color: Color = Color(0.32, 0.36, 0.42, 0.9)
@export var ring_color: Color = Color(0.95, 0.85, 0.4, 0.9)
@export var player_color: Color = Color(0.3, 0.7, 1.0)
@export var ped_color: Color = Color(0.55, 0.85, 0.55)
@export var vehicle_color: Color = Color(0.85, 0.75, 0.45)
@export var waypoint_color: Color = Color(0.95, 0.3, 0.75)

var _player: Node3D = null
var _stats: Node = null


func _ready() -> void:
	call_deferred("_bind")
	set_process(true)


func _bind() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]
	var stats := get_tree().get_nodes_in_group("player_stats")
	if not stats.is_empty():
		_stats = stats[0]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	if radius <= 1.0:
		return

	# Base disc + subtle inner shade.
	draw_circle(center, radius, disc_color)

	if _player == null:
		_bind()
	var forward := _facing()
	var player_xz := Vector2.ZERO
	if _player != null:
		player_xz = Vector2(_player.global_position.x, _player.global_position.z)

	_draw_streets(center, radius, player_xz, forward)
	_draw_blips(center, radius, player_xz, forward)
	_draw_waypoint(center, radius, player_xz, forward)
	_draw_player(center, radius)
	_draw_frame(center, radius, forward)


func _facing() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(0, 1)
	var fwd := -cam.global_transform.basis.z
	var flat := Vector2(fwd.x, fwd.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector2(0, 1)


func _draw_streets(center: Vector2, radius: float, player_xz: Vector2, forward: Vector2) -> void:
	# How far (world metres) the disc edge reaches; pad so rotated lines fill it.
	var reach := (radius / pixels_per_meter) * 1.5
	var g := grid_spacing
	# Snap the grid origin to the nearest line so it scrolls under the player.
	var min_x := floorf((player_xz.x - reach) / g) * g
	var max_x := player_xz.x + reach
	var min_z := floorf((player_xz.y - reach) / g) * g
	var max_z := player_xz.y + reach

	# Lines running along world Z (constant X).
	var x := min_x
	while x <= max_x:
		var a := HudFormat.world_to_map(Vector2(x, min_z) - player_xz, forward, pixels_per_meter)
		var b := HudFormat.world_to_map(Vector2(x, max_z) - player_xz, forward, pixels_per_meter)
		_draw_clipped(center + a, center + b, center, radius, road_color, 2.0)
		x += g
	# Lines running along world X (constant Z).
	var z := min_z
	while z <= max_z:
		var a := HudFormat.world_to_map(Vector2(min_x, z) - player_xz, forward, pixels_per_meter)
		var b := HudFormat.world_to_map(Vector2(max_x, z) - player_xz, forward, pixels_per_meter)
		_draw_clipped(center + a, center + b, center, radius, road_color, 2.0)
		z += g


func _draw_blips(center: Vector2, radius: float, player_xz: Vector2, forward: Vector2) -> void:
	for group in ["pedestrians", "police", "vehicles"]:
		var col := vehicle_color if group == "vehicles" else ped_color
		if group == "police":
			col = Color(0.4, 0.6, 1.0)
		for n in get_tree().get_nodes_in_group(group):
			var n3 := n as Node3D
			if n3 == null:
				continue
			var rel := Vector2(n3.global_position.x, n3.global_position.z) - player_xz
			var p := center + HudFormat.world_to_map(rel, forward, pixels_per_meter)
			if center.distance_to(p) <= radius - 3.0:
				draw_circle(p, 2.5, col)


func _draw_waypoint(center: Vector2, radius: float, player_xz: Vector2, forward: Vector2) -> void:
	if _stats == null or not _stats.has_method("has_waypoint") or not _stats.has_waypoint():
		return
	var wp: Vector3 = _stats.objective_waypoint
	var rel := Vector2(wp.x, wp.z) - player_xz
	var p := center + HudFormat.world_to_map(rel, forward, pixels_per_meter)
	var d := center.distance_to(p)
	if d > radius - 4.0 and d > 0.001:
		# Clamp to the rim so off-map objectives still show a direction.
		p = center + (p - center) / d * (radius - 4.0)
	_draw_diamond(p, 4.5, waypoint_color)


func _draw_player(center: Vector2, _radius: float) -> void:
	# A triangle pointing up (player always faces map-up in this rotating view).
	var pts := PackedVector2Array(
		[
			center + Vector2(0, -7),
			center + Vector2(-5, 5),
			center + Vector2(5, 5),
		]
	)
	draw_colored_polygon(pts, player_color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.0)


func _draw_frame(center: Vector2, radius: float, forward: Vector2) -> void:
	draw_arc(center, radius, 0.0, TAU, 48, ring_color, 2.5, true)
	# North tick: where world -Z lands on the rotated rim.
	var north := HudFormat.world_to_map(Vector2(0, -1), forward, 1.0).normalized()
	var tick := center + north * (radius - 2.0)
	draw_circle(tick, 3.0, Color(0.95, 0.3, 0.3))


# --- helpers --------------------------------------------------------------


func _draw_diamond(p: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]
		),
		col
	)


## Draw segment a→b clipped to the disc (centre, radius).
func _draw_clipped(
	a: Vector2, b: Vector2, center: Vector2, radius: float, col: Color, w: float
) -> void:
	var clipped := Minimap.clip_segment_circle(a - center, b - center, radius)
	if clipped.is_empty():
		return
	draw_line(center + clipped[0], center + clipped[1], col, w)


## Clip a segment (in centre-relative coords) to a circle of `radius` at origin.
## Returns [a2, b2] (centre-relative) or [] if it misses the disc. Pure/static.
static func clip_segment_circle(a: Vector2, b: Vector2, radius: float) -> Array:
	var inside_a := a.length() <= radius
	var inside_b := b.length() <= radius
	if inside_a and inside_b:
		return [a, b]
	var d := b - a
	var len2 := d.length_squared()
	if len2 < 0.000001:
		return []
	# Solve |a + t d|^2 = r^2 for t in [0,1].
	var bq := 2.0 * a.dot(d)
	var cq := a.length_squared() - radius * radius
	var disc := bq * bq - 4.0 * len2 * cq
	if disc < 0.0:
		return []
	var sq := sqrt(disc)
	var t0 := (-bq - sq) / (2.0 * len2)
	var t1 := (-bq + sq) / (2.0 * len2)
	var lo := maxf(0.0, minf(t0, t1))
	var hi := minf(1.0, maxf(t0, t1))
	if lo > hi:
		return []
	return [a + d * lo, a + d * hi]
