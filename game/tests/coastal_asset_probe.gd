extends SceneTree
## Runtime integration probe for the imported character and environment set.

const ASSET_PATHS: PackedStringArray = [
	"res://assets/characters/coastal_residents/player.glb",
	"res://assets/characters/coastal_residents/npc_man.glb",
	"res://assets/characters/coastal_residents/npc_woman.glb",
	"res://assets/environment/coastal_props/palm_planter.glb",
	"res://assets/environment/coastal_props/palm_tree.glb",
	"res://assets/environment/coastal_props/street_lamp.glb",
]
const PLAYER_RIG_PATH: String = "res://scenes/player/character_rig.tscn"
const CIVILIAN_RIG_PATH: String = "res://scenes/npc/civilian_rig.tscn"
const PLAYER_VISUAL_PATH: String = "res://assets/characters/coastal_residents/player.glb"
const WARMUP_FRAMES: int = 12

var _player_rig: AnimatedRig = null
var _civilian_rig: AnimatedRig = null
var _props: CoastalPropPlacements = null
var _frames: int = 0


func _initialize() -> void:
	for asset_path in ASSET_PATHS:
		var packed := load(asset_path) as PackedScene
		if packed == null:
			_fail("cannot load %s" % asset_path)
			return
		var instance := packed.instantiate()
		if instance.find_child("*", true, false) == null:
			_fail("%s instantiated empty" % asset_path)
			instance.free()
			return
		instance.free()

	_player_rig = _instantiate_rig(PLAYER_RIG_PATH)
	_civilian_rig = _instantiate_rig(CIVILIAN_RIG_PATH)
	if _player_rig == null or _civilian_rig == null:
		return
	_props = CoastalPropPlacements.new()
	root.add_child(_props)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false

	var failures := PackedStringArray()
	_check_player(failures)
	_check_civilian(failures)
	_check_props(failures)
	if not failures.is_empty():
		for failure in failures:
			push_error("coastal asset probe FAIL :: %s" % failure)
		quit(1)
		return true

	print("coastal asset probe: OK (player, civilian variants, 12 world props)")
	quit(0)
	return true


func _instantiate_rig(path: String) -> AnimatedRig:
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("cannot load %s" % path)
		return null
	var rig := packed.instantiate() as AnimatedRig
	if rig == null:
		_fail("%s root is not AnimatedRig" % path)
		return null
	root.add_child(rig)
	return rig


func _check_player(failures: PackedStringArray) -> void:
	if _player_rig.visual_scene == null:
		failures.append("player visual scene is missing")
	elif _player_rig.visual_scene.resource_path != PLAYER_VISUAL_PATH:
		failures.append("player visual is not player.glb")
	_check_retargeted_rig(_player_rig, "player", failures)


func _check_civilian(failures: PackedStringArray) -> void:
	if _civilian_rig.visual_scene_options.size() != 2:
		failures.append("civilian rig does not expose both imported variants")
	_check_retargeted_rig(_civilian_rig, "civilian", failures)


func _check_retargeted_rig(rig: AnimatedRig, label: String, failures: PackedStringArray) -> void:
	var modifier := rig.find_child("CharacterRetarget", true, false) as RetargetModifier3D
	if modifier == null or modifier.profile == null:
		failures.append("%s retarget modifier is missing" % label)
		return
	var target := modifier.get_node_or_null("RetargetedSkeleton") as Skeleton3D
	if target == null or target.get_bone_count() != 52:
		failures.append("%s target skeleton is not the 52-bone imported rig" % label)
		return
	var travel_velocity := Vector3(2.0, 0.0, -3.0)
	rig.animate(travel_velocity, true, 0.0, false, 1.0)
	var visual_facing := (target.global_basis * Vector3.BACK).normalized()
	if visual_facing.dot(travel_velocity.normalized()) < 0.999:
		failures.append("%s imported visual faces away from travel" % label)
	var target_meshes := 0
	for mesh_node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if target.is_ancestor_of(mesh):
			if mesh.is_visible_in_tree():
				target_meshes += 1
		elif mesh.visible:
			failures.append("%s source animation mesh is still visible" % label)
	if target_meshes == 0:
		failures.append("%s imported mesh is not visible" % label)


func _check_props(failures: PackedStringArray) -> void:
	var expected := CoastalPropLayout.placements().size()
	if _props.get_child_count() != expected:
		failures.append("expected %d props, found %d" % [expected, _props.get_child_count()])
	for kind in [
		CoastalPropLayout.PALM_PLANTER,
		CoastalPropLayout.PALM_TREE,
		CoastalPropLayout.STREET_LAMP,
	]:
		var count := get_nodes_in_group("coastal_prop_%s" % kind).size()
		if count != 4:
			failures.append("expected 4 %s instances, found %d" % [kind, count])


func _fail(message: String) -> void:
	push_error("coastal asset probe FAIL :: %s" % message)
	quit(1)
