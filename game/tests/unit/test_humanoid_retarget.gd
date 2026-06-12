extends RefCounted
## Pure bone-map checks for the runtime character retarget bridge.


func test_maps_core_body_chain() -> bool:
	return (
		HumanoidRetarget.source_name(&"Hips") == &"pelvis"
		and HumanoidRetarget.source_name(&"UpperChest") == &"spine_03"
		and HumanoidRetarget.source_name(&"Head") == &"Head"
	)


func test_maps_limbs_and_toes() -> bool:
	return (
		HumanoidRetarget.source_name(&"LeftUpperArm") == &"upperarm_l"
		and HumanoidRetarget.source_name(&"RightLowerLeg") == &"calf_r"
		and HumanoidRetarget.source_name(&"LeftToes") == &"ball_l"
	)


func test_maps_all_three_finger_segments() -> bool:
	return (
		HumanoidRetarget.source_name(&"RightIndexProximal") == &"index_01_r"
		and HumanoidRetarget.source_name(&"RightIndexIntermediate") == &"index_02_r"
		and HumanoidRetarget.source_name(&"RightIndexDistal") == &"index_03_r"
	)


func test_unknown_bone_is_unmapped() -> bool:
	return HumanoidRetarget.source_name(&"Tail") == &""


func test_profile_has_unique_source_names() -> bool:
	var names := HumanoidRetarget.source_bone_names()
	var unique := {}
	for bone_name in names:
		unique[bone_name] = true
	return names.size() == unique.size() and names.size() == 52
