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

const POI_COLORS: Dictionary = {
	"city": Color(0.25, 0.72, 1.0),
	"landmark": Color(1.0, 0.72, 0.25),
	"marina": Color(0.25, 0.85, 0.72),
	"route": Color(0.9, 0.45, 0.8),
	"office": Color(0.45, 0.7, 1.0),
	"diner": Color(1.0, 0.62, 0.28),
	"bar": Color(0.85, 0.42, 0.95),
	"gym": Color(0.5, 0.9, 0.45),
	"home": Color(0.9, 0.85, 0.45),
	"park": Color(0.38, 0.75, 0.38),
	"restroom": Color(0.55, 0.85, 0.95),
	"street": Color(0.7, 0.7, 0.76),
}

## World metres mapped to one screen pixel's worth of zoom.
@export var pixels_per_meter: float = 1.6
## Street grid spacing in world metres.
@export var grid_spacing: float = 24.0
## Map refresh rate (Hz). The minimap is a HUD read, not a smooth viewport:
## ~10 Hz keeps blips and rotation current while cutting the every-frame
## full-disc redraw (streets + blips + POIs) that used to dominate UI time.
@export_range(1.0, 60.0) var refresh_hz: float = 10.0
## Seconds between re-pulls of the moving blip groups (peds, police, vehicles).
@export var blip_rescan_sec: float = 0.5
## Seconds between re-pulls of the static POI marker groups.
@export var poi_rescan_sec: float = 2.0

@export var disc_color: Color = Color(0.07, 0.09, 0.12, 0.92)
@export var disc_inner_color: Color = Color(0.14, 0.17, 0.22, 0.6)
@export var road_color: Color = Color(0.46, 0.51, 0.58, 0.95)
@export var road_casing_color: Color = Color(0.05, 0.06, 0.08, 0.9)
@export var ring_color: Color = Color(0.98, 0.86, 0.42, 1.0)
@export var player_color: Color = Color(0.35, 0.74, 1.0)
@export var ped_color: Color = Color(0.55, 0.88, 0.55)
@export var vehicle_color: Color = Color(0.95, 0.82, 0.45)
@export var waypoint_color: Color = Color(0.98, 0.32, 0.78)

## Health / armor arcs that wrap the minimap rim (GTA-V signature read).
@export var health_color: Color = Color(0.42, 0.86, 0.4)
@export var health_low_color: Color = Color(0.95, 0.3, 0.24)
@export var armor_color: Color = Color(0.4, 0.68, 1.0)
@export var arc_back_color: Color = Color(0.0, 0.0, 0.0, 0.55)

var _player: Node3D = null
var _stats: Node = null
var _health: Node = null
var _redraw_accum: float = 0.0
# Time to feed the blip/POI caches on the next draw (0 for engine-driven
# redraws like resizes, so cache clocks only advance with game time).
var _scan_delta: float = 0.0
var _blip_caches: Dictionary = {}
var _poi_caches: Dictionary = {}


func _ready() -> void:
	call_deferred("_bind")
	set_process(true)
	for group in ["pedestrians", "police", "vehicles"]:
		_blip_caches[group] = GroupCache.for_group(get_tree(), group, blip_rescan_sec)
	for kind in POI_COLORS.keys():
		_poi_caches[kind] = GroupCache.for_group(get_tree(), "poi_%s" % kind, poi_rescan_sec)


func _bind() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]
	var stats := get_tree().get_nodes_in_group("player_stats")
	if not stats.is_empty():
		_stats = stats[0]
	var health := get_tree().get_nodes_in_group("player_health")
	if not health.is_empty():
		_health = health[0]


func _process(delta: float) -> void:
	_redraw_accum += delta
	var period := 1.0 / maxf(refresh_hz, 1.0)
	if _redraw_accum < period:
		return
	_scan_delta = _redraw_accum
	_redraw_accum = fmod(_redraw_accum, period)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	# Leave room outside the disc for the wrapping health/armor arcs.
	var radius := minf(size.x, size.y) * 0.5 - 8.0
	if radius <= 1.0:
		return

	# Base disc with a soft inner glow for depth (dark rim → lit centre).
	draw_circle(center, radius, disc_color)
	draw_circle(center, radius * 0.62, disc_inner_color)

	if _player == null:
		_bind()
	var forward := _facing()
	var player_xz := Vector2.ZERO
	if _player != null:
		player_xz = Vector2(_player.global_position.x, _player.global_position.z)

	_draw_streets(center, radius, player_xz, forward)
	_draw_blips(center, radius, player_xz, forward)
	_draw_pois(center, radius, player_xz, forward)
	_draw_waypoint(center, radius, player_xz, forward)
	_draw_player(center, radius)
	_draw_frame(center, radius, forward)
	_draw_vitals(center, radius)
	_scan_delta = 0.0


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

	# Two passes: dark casings first, then the lighter road fill on top, so
	# streets read with an edged GTA look instead of flat hairlines.
	for pass_idx in range(2):
		var col := road_casing_color if pass_idx == 0 else road_color
		var wide := 4.5 if pass_idx == 0 else 2.4
		# Lines running along world Z (constant X).
		var x := min_x
		while x <= max_x:
			var a := HudFormat.world_to_map(
				Vector2(x, min_z) - player_xz, forward, pixels_per_meter
			)
			var b := HudFormat.world_to_map(
				Vector2(x, max_z) - player_xz, forward, pixels_per_meter
			)
			_draw_clipped(center + a, center + b, center, radius, col, wide)
			x += g
		# Lines running along world X (constant Z).
		var z := min_z
		while z <= max_z:
			var a := HudFormat.world_to_map(
				Vector2(min_x, z) - player_xz, forward, pixels_per_meter
			)
			var b := HudFormat.world_to_map(
				Vector2(max_x, z) - player_xz, forward, pixels_per_meter
			)
			_draw_clipped(center + a, center + b, center, radius, col, wide)
			z += g


func _draw_blips(center: Vector2, radius: float, player_xz: Vector2, forward: Vector2) -> void:
	for group in _blip_caches.keys():
		var col := vehicle_color if group == "vehicles" else ped_color
		if group == "police":
			col = Color(0.4, 0.6, 1.0)
		var cache: GroupCache = _blip_caches[group]
		for n in cache.nodes(_scan_delta):
			var n3 := n as Node3D
			if n3 == null:
				continue
			var rel := Vector2(n3.global_position.x, n3.global_position.z) - player_xz
			var p := center + HudFormat.world_to_map(rel, forward, pixels_per_meter)
			if center.distance_to(p) <= radius - 4.0:
				# Dark halo so blips pop against streets, then the colour dot.
				draw_circle(p, 3.4, Color(0, 0, 0, 0.5))
				draw_circle(p, 2.4, col)


func _draw_pois(center: Vector2, radius: float, player_xz: Vector2, forward: Vector2) -> void:
	for kind in POI_COLORS.keys():
		var cache: GroupCache = _poi_caches[kind]
		for n in cache.nodes(_scan_delta):
			var n3 := n as Node3D
			if n3 == null:
				continue
			var rel := Vector2(n3.global_position.x, n3.global_position.z) - player_xz
			var p := center + HudFormat.world_to_map(rel, forward, pixels_per_meter)
			var d := center.distance_to(p)
			if d > radius - 6.0:
				continue
			_draw_diamond(p, 3.8, POI_COLORS[kind])


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
	# Soft glow halo so the player marker stays legible over busy streets.
	draw_circle(center, 10.0, Color(player_color.r, player_color.g, player_color.b, 0.18))
	# A chevron pointing up (player always faces map-up in this rotating view).
	var pts := PackedVector2Array(
		[
			center + Vector2(0, -8.5),
			center + Vector2(-6, 6),
			center + Vector2(0, 3),
			center + Vector2(6, 6),
		]
	)
	draw_colored_polygon(pts, player_color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.85), 1.5, true)


func _draw_frame(center: Vector2, radius: float, forward: Vector2) -> void:
	# Layered rim: soft outer glow, dark casing, bright accent — gives the
	# minimap a polished bezel instead of a single flat hairline.
	draw_arc(
		center,
		radius + 2.5,
		0.0,
		TAU,
		64,
		Color(ring_color.r, ring_color.g, ring_color.b, 0.18),
		7.0,
		true
	)
	draw_arc(center, radius, 0.0, TAU, 64, Color(0, 0, 0, 0.7), 5.0, true)
	draw_arc(center, radius, 0.0, TAU, 64, ring_color, 2.2, true)
	# North tick: a small notch where world -Z lands on the rotated rim.
	var north := HudFormat.world_to_map(Vector2(0, -1), forward, 1.0).normalized()
	var tick := center + north * radius
	draw_circle(tick + north * 4.0, 4.5, Color(0.95, 0.28, 0.28))
	draw_circle(tick + north * 4.0, 4.5, Color(1, 1, 1, 0.7), false, 1.0)


## Health (bottom-left quadrant) + armor (bottom-right) arcs hugging the rim.
func _draw_vitals(center: Vector2, radius: float) -> void:
	var hp := 1.0
	if _health != null and _health.has_method("fraction"):
		hp = _health.fraction()
	var armor := 0.0
	if _stats != null and "armor" in _stats and "max_armor" in _stats:
		armor = PlayerStats.fraction(_stats.armor, _stats.max_armor)

	var arc_r := radius + 6.5
	var m := 0.06  # small gap at the bottom seam and the side ends
	var hp_col := health_low_color if hp <= 0.25 else health_color
	# Health sweeps up the left side from the bottom; armor up the right side.
	_draw_stat_arc(center, arc_r, PI * (0.5 + m), PI * (1.0 - m), hp, hp_col)
	if armor > 0.001:
		_draw_stat_arc(center, arc_r, PI * (0.5 - m), PI * m, armor, armor_color)


func _draw_stat_arc(
	center: Vector2, r: float, start: float, end: float, frac: float, col: Color
) -> void:
	# Dark casing frames the track; the empty track sits inside it.
	draw_arc(center, r, start, end, 32, Color(0, 0, 0, 0.7), 6.0, true)
	draw_arc(center, r, start, end, 32, arc_back_color, 4.0, true)
	var f := clampf(frac, 0.0, 1.0)
	if f <= 0.0:
		return
	var fill_end := start + (end - start) * f
	draw_arc(center, r, start, fill_end, 32, col, 4.0, true)
	# Bright inner highlight gives the fill a glossy GTA sheen.
	draw_arc(center, r - 1.2, start, fill_end, 32, col.lerp(Color(1, 1, 1), 0.35), 1.4, true)


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
