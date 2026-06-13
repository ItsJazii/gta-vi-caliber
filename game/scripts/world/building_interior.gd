class_name BuildingInterior
extends Node3D
## Runtime owner of the single active building interior. Spawned lazily the first
## time a BuildingDoor is used and reused afterwards; only one interior exists at
## a time, since you can only stand in one building. It builds a sealed room from
## the footprint (pure InteriorBuilder), stages it far below the world so nothing
## overlaps, fades the screen, and teleports the player in and back out. The
## placement arithmetic is the pure BuildingEntry; this node only stages it.

## Where interiors are built, far under the world so they never touch it.
const STAGE_ORIGIN := Vector3(0.0, -3000.0, 0.0)
const CEILING_HEIGHT := 4.0
## How far in from the door to drop the player so they spawn within the walls.
const ENTRY_INSET := 1.6
## How far outside the door the player reappears when they leave.
const EXIT_NUDGE := 1.6
## Lift on the entry/exit teleport so the body drops onto the floor, not into it.
const DROP_HEIGHT := 1.0

var _fade: ScreenFade
var _room: Node3D = null
var _return_pos: Vector3 = Vector3.ZERO
var _busy := false


func _ready() -> void:
	add_to_group("building_interior")
	_fade = ScreenFade.new()
	add_child(_fade)


## The one interior manager under the current scene, created on first use.
static func instance(tree: SceneTree) -> BuildingInterior:
	var existing := tree.get_first_node_in_group("building_interior")
	if existing is BuildingInterior:
		return existing
	if tree.current_scene == null:
		return null
	var manager := BuildingInterior.new()
	tree.current_scene.add_child(manager)
	return manager


## Step `player` into the building behind `door`. The player's return point is
## captured from the door's live transform now (not stored at build time) so a
## floating-origin shift before entry can't leave a stale coordinate behind.
## No-op while a transition is mid-flight or an interior is already open.
func enter(player: Node3D, door: BuildingDoor) -> void:
	if _busy or _room != null or player == null or door == null:
		return
	_busy = true
	_return_pos = _return_point(door)
	await _fade.to_black()
	var centre := BuildingEntry.centroid(door.footprint)
	_build_room(door.footprint, centre, door.door_local)
	var entry2d := BuildingEntry.entry_offset(door.door_local - centre, ENTRY_INSET)
	_move_player(player, STAGE_ORIGIN + Vector3(entry2d.x, DROP_HEIGHT, entry2d.y))
	await _fade.from_black()
	_busy = false


## Send `player` back outside and tear the interior down.
func leave(player: Node3D) -> void:
	if _busy or _room == null or player == null:
		return
	_busy = true
	await _fade.to_black()
	_move_player(player, _return_pos)
	_room.queue_free()
	_room = null
	await _fade.from_black()
	_busy = false


## The street point just outside `door`, in world space, from its current
## transform so it tracks any floating-origin shift up to entry time.
func _return_point(door: BuildingDoor) -> Vector3:
	var parent := door.get_parent()
	if not (parent is Node3D):
		return door.global_position
	var centre := BuildingEntry.centroid(door.footprint)
	var outward := door.door_local - centre
	outward = outward.normalized() if outward.length() > 0.001 else Vector2(0.0, 1.0)
	var local := Vector3(
		door.door_local.x + outward.x * EXIT_NUDGE,
		door.position.y,
		door.door_local.y + outward.y * EXIT_NUDGE
	)
	return (parent as Node3D).to_global(local)


func _build_room(footprint: PackedVector2Array, centre: Vector2, door_local: Vector2) -> void:
	var centred := BuildingEntry.recenter(footprint, centre)
	var data := InteriorBuilder.room(centred, CEILING_HEIGHT)
	_room = Node3D.new()
	_room.position = STAGE_ORIGIN
	add_child(_room)
	if data.is_empty():
		return

	var shell := MeshInstance3D.new()
	shell.mesh = _array_mesh(data)
	shell.material_override = _interior_material()
	_room.add_child(shell)
	shell.create_trimesh_collision()

	var light := OmniLight3D.new()
	light.position = Vector3(0.0, CEILING_HEIGHT - 0.5, 0.0)
	light.omni_range = 60.0
	light.light_energy = 3.0
	_room.add_child(light)

	var exit := BuildingDoor.new()
	exit.is_exit = true
	exit.position = Vector3((door_local - centre).x, DROP_HEIGHT, (door_local - centre).y)
	_room.add_child(exit)


func _move_player(player: Node3D, pos: Vector3) -> void:
	if player.has_method("eject"):
		player.eject()
	player.global_position = pos
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


func _array_mesh(data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _interior_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.76, 0.72)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
