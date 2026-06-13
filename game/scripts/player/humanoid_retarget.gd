class_name HumanoidRetarget
extends RefCounted
## Bone-name bridge from the Tripo humanoid rig to the Quaternius animation rig.
##
## RetargetModifier3D matches bones by name. The imported target skeleton and
## its private skin bind names are renamed together, while the source rig keeps
## the names referenced by the existing animation tracks.

const TARGET_TO_SOURCE: Dictionary = {
	&"Hips": &"pelvis",
	&"Spine": &"spine_01",
	&"Chest": &"spine_02",
	&"UpperChest": &"spine_03",
	&"Neck": &"neck_01",
	&"Head": &"Head",
	&"LeftShoulder": &"clavicle_l",
	&"LeftUpperArm": &"upperarm_l",
	&"LeftLowerArm": &"lowerarm_l",
	&"LeftHand": &"hand_l",
	&"LeftThumbMetacarpal": &"thumb_01_l",
	&"LeftThumbProximal": &"thumb_02_l",
	&"LeftThumbDistal": &"thumb_03_l",
	&"LeftIndexProximal": &"index_01_l",
	&"LeftIndexIntermediate": &"index_02_l",
	&"LeftIndexDistal": &"index_03_l",
	&"LeftMiddleProximal": &"middle_01_l",
	&"LeftMiddleIntermediate": &"middle_02_l",
	&"LeftMiddleDistal": &"middle_03_l",
	&"LeftRingProximal": &"ring_01_l",
	&"LeftRingIntermediate": &"ring_02_l",
	&"LeftRingDistal": &"ring_03_l",
	&"LeftLittleProximal": &"pinky_01_l",
	&"LeftLittleIntermediate": &"pinky_02_l",
	&"LeftLittleDistal": &"pinky_03_l",
	&"RightShoulder": &"clavicle_r",
	&"RightUpperArm": &"upperarm_r",
	&"RightLowerArm": &"lowerarm_r",
	&"RightHand": &"hand_r",
	&"RightThumbMetacarpal": &"thumb_01_r",
	&"RightThumbProximal": &"thumb_02_r",
	&"RightThumbDistal": &"thumb_03_r",
	&"RightIndexProximal": &"index_01_r",
	&"RightIndexIntermediate": &"index_02_r",
	&"RightIndexDistal": &"index_03_r",
	&"RightMiddleProximal": &"middle_01_r",
	&"RightMiddleIntermediate": &"middle_02_r",
	&"RightMiddleDistal": &"middle_03_r",
	&"RightRingProximal": &"ring_01_r",
	&"RightRingIntermediate": &"ring_02_r",
	&"RightRingDistal": &"ring_03_r",
	&"RightLittleProximal": &"pinky_01_r",
	&"RightLittleIntermediate": &"pinky_02_r",
	&"RightLittleDistal": &"pinky_03_r",
	&"LeftUpperLeg": &"thigh_l",
	&"LeftLowerLeg": &"calf_l",
	&"LeftFoot": &"foot_l",
	&"LeftToes": &"ball_l",
	&"RightUpperLeg": &"thigh_r",
	&"RightLowerLeg": &"calf_r",
	&"RightFoot": &"foot_r",
	&"RightToes": &"ball_r",
}


static func source_name(target_name: StringName) -> StringName:
	return TARGET_TO_SOURCE.get(target_name, &"")


static func source_bone_names() -> PackedStringArray:
	var names := PackedStringArray()
	for target_name: StringName in TARGET_TO_SOURCE:
		names.append(TARGET_TO_SOURCE[target_name])
	return names


static func rename_target_skeleton(skeleton: Skeleton3D) -> PackedStringArray:
	var missing := PackedStringArray()
	_rename_skin_binds(skeleton)
	for target_name: StringName in TARGET_TO_SOURCE:
		var bone_idx := skeleton.find_bone(target_name)
		if bone_idx < 0:
			missing.append(target_name)
			continue
		skeleton.set_bone_name(bone_idx, TARGET_TO_SOURCE[target_name])
	return missing


static func _rename_skin_binds(skeleton: Skeleton3D) -> void:
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.skin == null:
			continue
		var renamed_skin := mesh_instance.skin.duplicate() as Skin
		for bind_idx in renamed_skin.get_bind_count():
			var mapped_name := source_name(renamed_skin.get_bind_name(bind_idx))
			if not mapped_name.is_empty():
				renamed_skin.set_bind_name(bind_idx, mapped_name)
		mesh_instance.skin = renamed_skin


static func build_profile() -> SkeletonProfile:
	var names := source_bone_names()
	var profile := SkeletonProfile.new()
	profile.bone_size = names.size()
	for bone_idx in names.size():
		profile.set_bone_name(bone_idx, names[bone_idx])
	return profile
