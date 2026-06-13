class_name CrowdDirector
extends Node3D
## Keeps a living pedestrian crowd around the player: spawns varied peds at the
## edge of view, culls them once they fall far behind, and respawns to maintain
## a target headcount — so a district feels inhabited without ever paying for
## people the player can't see (roadmap M4: "spawn/despawn invisible to player").
##
## All placement uses CrowdDistribution (pure, tested); the peds themselves use
## the imported coastal-resident character variants. Ground height is taken
## from the player's Y — flat-world assumption for now; a navmesh/raycast
## sample is a later refinement.

## Pedestrian scene to populate the crowd with. Defaults to the standard one so
## the director works the moment it is dropped into a scene.
@export var pedestrian_scene: PackedScene = preload("res://scenes/npc/pedestrian.tscn")
## Optional Citizen scene (life-sim pedestrians: schedules, needs, barks).
## When set, citizen_fraction of spawns use it instead of pedestrian_scene,
## interleaved deterministically (CrowdDistribution.is_citizen_slot) so the
## street reads as a mix of commuters and drifters.
@export var citizen_scene: PackedScene = null
@export_range(0.0, 1.0) var citizen_fraction: float = 0.0
## How many peds to keep alive around the player.
@export var target_count: int = 12
## Peds spawn in this annulus (m) around the player — far enough to fade in at
## the edge of view, never on top of them.
@export var spawn_min_radius: float = 18.0
@export var spawn_max_radius: float = 32.0
## Past this distance (m) a ped is recycled. Must exceed spawn_max_radius so a
## fresh spawn isn't instantly culled.
@export var cull_radius: float = 44.0
## Seconds between maintenance ticks — cheap, so the crowd doesn't churn the
## physics frame.
@export var tick_interval: float = 0.5
## Max peds instantiated per tick, so populating a scene is spread over a few
## ticks instead of one hitching frame.
@export var spawn_budget: int = 3
## Per-person stature: each ped is uniformly scaled within this range so the
## crowd has a believable spread of heights instead of identical clones.
@export var stature_min: float = 0.92
@export var stature_max: float = 1.08
## Per-person gait: walk/run speeds are scaled within this range (independent of
## stature) so some people stride and others amble.
@export var gait_min: float = 0.85
@export var gait_max: float = 1.15
## Snap each spawn down onto the ground with a raycast, so peds stand on hills
## and steps instead of floating or sinking. The ray starts this far above the
## player's height and probes this far below it.
@export var snap_to_ground: bool = true
@export var ground_probe_up: float = 8.0
@export var ground_probe_down: float = 40.0
## A spawn whose ground sits more than this far above the player's feet is
## treated as a rooftop/ledge and rejected, so peds don't appear on building
## tops. A spawn that finds no ground at all (a void) is rejected too.
@export var max_walkable_rise: float = 2.5
## Physics layers the ground/world lives on (the ray ignores anything else, so
## it doesn't catch other pedestrians).
@export_flags_3d_physics var ground_mask: int = 1
## Candidate spawn offsets to try per ped when a nav grid is set, before giving
## up for this tick — keeps peds out of buildings/water without busy-looping.
@export var walkable_attempts: int = 8

## Auto-build a walkability map from the physics world the first time the crowd
## ticks: a coarse grid is raycast straight down and any cell whose ground is
## missing or sits above max_walkable_rise (a building, a wall, water with no
## floor) is marked blocked. Gives peds a real navmesh of the streets with zero
## coupling to how the world was built. Leave off for a flat sandbox.
@export var bake_nav: bool = false
@export var nav_cell_size: float = 2.0
## Half-extent (m) of the baked grid around the player's start position.
@export var nav_radius: float = 90.0
## The bake raycast starts this far above the player so it hits a building's roof
## first (and so marks the footprint blocked) instead of starting inside a tall
## tower. Must clear the tallest building in range.
@export var nav_probe_height: float = 400.0

## Optional walkability map. Assigned by bake_nav, or set in code (stamp
## building/water footprints with NavGrid.block_world_rect). When present, spawns
## are rejected on blocked cells so pedestrians appear on streets and sidewalks,
## never inside a wall. Null = spawn anywhere (flat-sandbox behaviour).
var nav: NavGrid = null

var _peds: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0
# Monotonic spawn counter driving the citizen/pedestrian interleave.
var _spawn_slot: int = 0
var _base_target_count: int = -1


func _ready() -> void:
	_rng.randomize()
	add_to_group("density_aware")
	apply_graphics_setting(int(SettingsPanel.load_settings().get("graphics", 1)))


func apply_graphics_setting(quality: int) -> void:
	if _base_target_count == -1:
		_base_target_count = target_count
	match quality:
		0:
			target_count = maxi(1, int(_base_target_count * 0.25))
		1:
			target_count = maxi(1, int(_base_target_count * 0.6))
		2:
			target_count = _base_target_count


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < tick_interval:
		return
	_accum = 0.0
	var player := _player()
	if player == null:
		return
	if bake_nav and nav == null:
		_bake_nav(player.global_position)
	_cull(player.global_position)
	_spawn(player.global_position)


## Recycle peds that have drifted past the cull radius (or were freed elsewhere,
## e.g. by another system) so the active list stays tight.
func _cull(center: Vector3) -> void:
	var survivors: Array[Node3D] = []
	for ped in _peds:
		if not is_instance_valid(ped):
			continue
		var d := NpcBrain.planar_distance(ped.global_position, center)
		if CrowdDistribution.should_despawn(d, cull_radius):
			ped.queue_free()
		else:
			survivors.append(ped)
	_peds = survivors


## Top the crowd back up to target_count, a few at a time, at the spawn annulus.
func _spawn(center: Vector3) -> void:
	if pedestrian_scene == null:
		return
	var n := CrowdDistribution.spawn_count(_peds.size(), target_count, spawn_budget)
	for _i in n:
		var pos := _find_spawn(center)
		if pos == Vector3.INF:
			continue  # nowhere walkable this tick; try again next tick
		var ped := _next_scene().instantiate() as Node3D
		if ped == null:
			return
		_spawn_slot += 1
		_apply_variety(ped)
		add_child(ped)
		ped.global_position = pos
		_peds.append(ped)


## The scene for the next successful spawn: a Citizen on citizen slots when a
## citizen scene is wired, the plain pedestrian otherwise.
func _next_scene() -> PackedScene:
	if citizen_scene != null and CrowdDistribution.is_citizen_slot(_spawn_slot, citizen_fraction):
		return citizen_scene
	return pedestrian_scene


## Raycast a coarse grid of the surrounding area into a NavGrid: every cell whose
## ground is missing or above max_walkable_rise (relative to the player's feet)
## becomes blocked. Runs once; the result drives nav-aware spawning and is there
## for pedestrian routing. Cost is a one-off burst of cell raycasts at the chosen
## resolution — keep nav_cell_size coarse on big worlds.
func _bake_nav(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var cells := maxi(int(2.0 * nav_radius / nav_cell_size), 1)
	var grid_origin := Vector3(center.x - nav_radius, center.y, center.z - nav_radius)
	var grid := NavGrid.new(cells, cells, nav_cell_size, grid_origin)
	var ceiling := center.y + max_walkable_rise
	for r in cells:
		for c in cells:
			var at := grid.cell_to_world(c, r)
			var gy := _ground_probe(at, center.y, nav_probe_height)
			if is_nan(gy) or gy > ceiling:
				grid.set_blocked(c, r, true)
	nav = grid


## Find a walkable world spawn point in the annulus, or Vector3.INF if none of
## the sampled candidates pass this tick. A candidate is rejected when it falls
## on a blocked nav cell (if a grid is set), over a void, or on a rooftop/ledge
## above max_walkable_rise — so peds only ever appear on reachable ground.
func _find_spawn(center: Vector3) -> Vector3:
	var probing: bool = nav != null or snap_to_ground
	var attempts: int = walkable_attempts if probing else 1
	for _a in attempts:
		var offset := CrowdDistribution.spawn_offset(
			spawn_min_radius, spawn_max_radius, _rng.randf(), _rng.randf()
		)
		var pos := center + offset
		if nav != null:
			var cell := nav.world_to_cell(pos)
			if nav.is_blocked(cell.x, cell.y):
				continue
		if snap_to_ground:
			var gy := _ground_probe(pos, center.y)
			if is_nan(gy) or gy > center.y + max_walkable_rise:
				continue  # void or rooftop
			pos.y = gy
		else:
			pos.y = center.y
		return pos
	return Vector3.INF


## Give a fresh ped its own stature and gait before it enters the tree, so two
## pedestrians from the same scene never look or move identically. Uniform scale
## keeps the capsule collider valid; gait is set on the exported speeds the
## pedestrian reads each frame, so it takes effect immediately.
func _apply_variety(ped: Node3D) -> void:
	var stature := _rng.randf_range(stature_min, stature_max)
	ped.scale = Vector3(stature, stature, stature)
	var gait := _rng.randf_range(gait_min, gait_max)
	if "walk_speed" in ped:
		ped.walk_speed = ped.walk_speed * gait
	if "run_speed" in ped:
		ped.run_speed = ped.run_speed * gait


## Raycast straight down through (x, z) for the ground height under a candidate
## spawn. Returns the hit Y, or NAN when nothing is hit within the probe window
## (a void) so the caller can reject that candidate. The space state can be null
## for a frame before the director is fully in the tree; treat that as a miss.
func _ground_probe(at: Vector3, base_y: float, up: float = ground_probe_up) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var from := Vector3(at.x, base_y + up, at.z)
	var to := Vector3(at.x, base_y - ground_probe_down, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, ground_mask)
	var hit := space.intersect_ray(query)
	return hit.position.y if hit.has("position") else NAN


## Current live crowd size — handy for a streaming-debug HUD and for tests that
## drive the director with a stub player.
func population() -> int:
	var live := 0
	for ped in _peds:
		if is_instance_valid(ped):
			live += 1
	return live


func _player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D
