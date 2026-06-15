class_name TestSaveManagerPlayerSkills
extends GdUnitTestSuite
## SaveManager persists live PlayerSkills under a distinct `player_skills` key.


class SkillsStub:
	extends Node

	var restored: Dictionary = {}

	func serialize() -> Dictionary:
		return {"skills": {"driving": 18.0, "shooting": 7.0}}

	func restore(data: Dictionary) -> void:
		restored = data


func test_gather_writes_player_skills_key() -> void:
	var manager: SaveManager = auto_free(SaveManager.new())
	add_child(manager)
	var skills: SkillsStub = auto_free(SkillsStub.new())
	skills.add_to_group("player_skills")
	add_child(skills)

	var snapshot: Dictionary = manager.call("_gather")
	var saved: Dictionary = snapshot["player_skills"]
	var values: Dictionary = saved["skills"]

	assert_dict(snapshot).contains_keys("player_skills")
	assert_float(values["driving"]).is_equal(18.0)
	assert_float(values["shooting"]).is_equal(7.0)


func test_apply_restores_player_skills_key() -> void:
	var manager: SaveManager = auto_free(SaveManager.new())
	add_child(manager)
	var skills: SkillsStub = auto_free(SkillsStub.new())
	skills.add_to_group("player_skills")
	add_child(skills)

	manager.call("_apply", {"player_skills": {"skills": {"stamina": 11.0}}})
	var values: Dictionary = skills.restored["skills"]

	assert_float(values["stamina"]).is_equal(11.0)
