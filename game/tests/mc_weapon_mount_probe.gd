extends SceneTree
## Probe: the player's carried GunMount is moved onto the MC right-hand bone at
## world scale. The MC model's skeleton is authored at 0.01 scale, so a naive
## BoneAttachment shrinks the gun ~100x (invisible) and leaves it reading as
## "floating behind the player". Guards McPlayerRig._attach_weapon_to_hand against
## regressing that: the gun must end up under a hand BoneAttachment, at ~unit scale.

const MC_RIG_PATH := "res://scenes/player/mc_rig.tscn"
const WARMUP_FRAMES: int = 6

var _rig: Node3D = null
var _frames: int = 0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_rig = (load(MC_RIG_PATH) as PackedScene).instantiate() as Node3D
	# Mimic player.tscn parenting a GunMount under the rig before it enters the tree.
	var mount := Node3D.new()
	mount.name = "GunMount"
	mount.add_child(MeshInstance3D.new())
	_rig.add_child(mount)
	world.add_child(_rig)


func _process(_delta: float) -> bool:
	if _rig == null:
		push_error("mc weapon mount probe FAIL :: mc_rig is not a Node3D")
		quit(1)
		return true
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false

	var failures := PackedStringArray()
	var hand := _rig.find_child("WeaponHand", true, false) as BoneAttachment3D
	if hand == null:
		failures.append("no WeaponHand bone attachment (gun never moved onto the hand)")
	var mount := _rig.find_child("GunMount", true, false) as Node3D
	if mount == null:
		failures.append("GunMount disappeared")
	else:
		if hand != null and not _is_descendant_of(mount, hand):
			failures.append("GunMount is not parented under the hand attachment")
		var scale := mount.global_transform.basis.get_scale()
		if absf(scale.x - 1.0) > 0.1 or absf(scale.y - 1.0) > 0.1:
			failures.append("gun world scale is %.3v (skeleton 0.01 scale not cancelled)" % scale)

	if not failures.is_empty():
		for failure in failures:
			push_error("mc weapon mount probe FAIL :: %s" % failure)
		quit(1)
		return true
	print("mc weapon mount probe: OK (gun on hand bone at unit scale)")
	quit(0)
	return true


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var cur := node.get_parent()
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false
