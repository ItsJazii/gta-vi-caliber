extends SceneTree
## Generator for the Tier-A NPC variant scenes (run headless, output is
## committed): for each variant, instance the base character model, override
## the body surface material with a duplicate that swaps in the variant
## albedo (keeping the imported normal/ORM wiring exactly), optionally graft a
## hair mesh under the skeleton, and save the result as a PackedScene.
## Overrides are baked as editable-instance diffs ON the skeleton subtree, so
## they survive AnimatedRig's visual extraction (it keeps only the skeleton).
##   godot --headless --path game --script res://tests/build_npc_variants.gd

const OUT_DIR := "res://scenes/props/npc"
const VAR_DIR := "res://assets/characters/npc_variants"
const CR := "res://assets/characters/coastal_residents"
const HAIR := "res://assets/characters/player_male_01/Hair_SimpleParted.gltf"

## variant id -> [base scene path, albedo ext, material keyword, hair?]
const SPECS := {
	"npc_man_v1": [CR + "/npc_man.glb", "jpg", "", false],
	"npc_man_v2": [CR + "/npc_man.glb", "jpg", "", false],
	"npc_man_v3": [CR + "/npc_man.glb", "jpg", "", false],
	"npc_woman_v1": [CR + "/npc_woman.glb", "jpg", "", false],
	"npc_woman_v2": [CR + "/npc_woman.glb", "jpg", "", false],
	"npc_woman_v3": [CR + "/npc_woman.glb", "jpg", "", false],
	"npc_player_v1": [CR + "/player.glb", "jpg", "", false],
	"npc_player_v2": [CR + "/player.glb", "jpg", "", false],
	"npc_ubc_male_v1":
	[
		"res://assets/characters/player_male_01/Superhero_Male_FullBody.gltf",
		"png",
		"Superhero",
		false
	],
	"npc_ubc_male_v2":
	[
		"res://assets/characters/player_male_01/Superhero_Male_FullBody.gltf",
		"png",
		"Superhero",
		false
	],
	"npc_ubc_female_v1":
	[
		"res://assets/characters/npc_female_01/Superhero_Female_FullBody.gltf",
		"png",
		"Superhero",
		false
	],
	"npc_ubc_female_v2":
	[
		"res://assets/characters/npc_female_01/Superhero_Female_FullBody.gltf",
		"png",
		"Superhero",
		false
	],
	"candidate_01": [CR + "/player.glb", "jpg", "", false],
	"candidate_02": [CR + "/player.glb", "jpg", "", false],
	"candidate_03": [CR + "/npc_man.glb", "jpg", "", false],
	"candidate_04":
	[
		"res://assets/characters/player_male_01/Superhero_Male_FullBody.gltf",
		"png",
		"Superhero",
		true
	],
	"candidate_05": [CR + "/npc_woman.glb", "jpg", "", false],
}


func _initialize() -> void:
	var failures := 0
	for vid: String in SPECS:
		if not _build(vid):
			failures += 1
	print("variant build: %d/%d ok" % [SPECS.size() - failures, SPECS.size()])
	quit(1 if failures > 0 else 0)


func _build(vid: String) -> bool:
	var spec: Array = SPECS[vid]
	var base := load(spec[0]) as PackedScene
	var albedo := load("%s/%s_albedo.%s" % [VAR_DIR, vid, spec[1]]) as Texture2D
	if base == null or albedo == null:
		push_error("variant %s: missing base or albedo" % vid)
		return false

	var root := Node3D.new()
	root.name = vid.to_pascal_case()
	var model := base.instantiate() as Node3D
	model.name = "Model"
	root.add_child(model)
	model.owner = root
	root.set_editable_instance(model, true)

	var overridden := 0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			if spec[2] != "" and not mat.resource_name.contains(spec[2]):
				continue
			var dup := mat.duplicate() as StandardMaterial3D
			dup.resource_name = mat.resource_name + "_" + vid
			dup.albedo_texture = albedo
			mi.set_surface_override_material(s, dup)
			overridden += 1
	if overridden == 0:
		push_error("variant %s: no surface matched" % vid)
		return false

	if spec[3]:
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		var hair := (load(HAIR) as PackedScene).instantiate()
		for mesh in hair.find_children("*", "MeshInstance3D", true, false):
			var grafted := (mesh as MeshInstance3D).duplicate() as MeshInstance3D
			(skeletons[0] as Skeleton3D).add_child(grafted)
			grafted.owner = root
		hair.free()

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("variant %s: pack failed" % vid)
		return false
	var err := ResourceSaver.save(packed, "%s/%s.tscn" % [OUT_DIR, vid])
	root.free()
	print("built %s (%d surfaces overridden)" % [vid, overridden])
	return err == OK
