extends SceneTree
## Probe: a downed NPC topples over and rests flat on the floor instead of freezing
## upright and floating. The only death clip lays the body down through root motion
## that the retarget strips, so AnimatedRig freezes the skinned pose on death and
## topples the visual about its feet, clamping the lowest posed bone to the floor.
## Guards that fall+settle against regressing back to the "standing corpse in the
## air" / "floating upside-down" bug.

const CIVILIAN_RIG_PATH := "res://scenes/npc/civilian_rig.tscn"
const WARMUP_FRAMES: int = 6
const SETTLE_FRAMES: int = 16

var _world: Node3D = null
var _rig: AnimatedRig = null
var _frames: int = 0
var _killed: bool = false


func _initialize() -> void:
	# Parent under a Node3D so the rig's owning-body floor reference resolves,
	# exactly like the real Pedestrian body the rig normally hangs under.
	_world = Node3D.new()
	root.add_child(_world)
	_rig = (load(CIVILIAN_RIG_PATH) as PackedScene).instantiate() as AnimatedRig
	if _rig != null:
		_world.add_child(_rig)


func _process(_delta: float) -> bool:
	if _rig == null:
		push_error("corpse settle probe FAIL :: civilian rig is not an AnimatedRig")
		quit(1)
		return true
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	if not _killed:
		_rig.play_death()
		_force_death_pose()
		_killed = true
		return false
	if _frames < WARMUP_FRAMES + SETTLE_FRAMES:
		return false
	_report()
	return true


# play_death freezes the skinned pose, so the body lies down purely from the rig
# topple. Headless frame deltas are too small to advance the timed topple, so push
# it past death_fall_time with one large manual step; real frames afterward let the
# ground clamp converge on the frozen pose.
func _force_death_pose() -> void:
	_rig.call("_process", 1.0)


func _report() -> void:
	var failures := PackedStringArray()
	var extent := _vertical_extent()
	var pitch := rad_to_deg(_rig.rotation.x)
	if is_nan(extent.x):
		failures.append("no RetargetedSkeleton to measure")
	else:
		if absf(pitch) < 60.0:
			failures.append("body did not topple over (pitch=%.1f deg)" % pitch)
		if extent.y > 1.0:
			failures.append("body still upright (highest bone y=%.2f)" % extent.y)
		if absf(extent.x) > 0.2:
			failures.append("body not resting on floor (lowest bone y=%.3f)" % extent.x)
	if not failures.is_empty():
		for failure in failures:
			push_error("corpse settle probe FAIL :: %s" % failure)
		quit(1)
		return
	print(
		(
			"corpse settle probe: OK (toppled %.0f deg, lies flat low=%.2f high=%.2f)"
			% [pitch, extent.x, extent.y]
		)
	)
	quit(0)


# Lowest and highest posed bone world Y of the visible (retargeted) skeleton.
func _vertical_extent() -> Vector2:
	var skeleton := _rig.find_child("RetargetedSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		return Vector2(NAN, NAN)
	var skel_xform := skeleton.global_transform
	var low := INF
	var high := -INF
	for i in skeleton.get_bone_count():
		var bone_y: float = (skel_xform * skeleton.get_bone_global_pose(i).origin).y
		low = minf(low, bone_y)
		high = maxf(high, bone_y)
	return Vector2(low, high)
