extends RefCounted
## Front-door route checks: boot intro -> main menu -> Miami world.

const INTRO_SCENE_PATH := "res://scenes/ui/intro_video.tscn"
const MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const WORLD_SCENE_PATH := "res://scenes/world/miami.tscn"

const INTRO_SCENE := preload("res://scenes/ui/intro_video.tscn")
const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const WORLD_SCENE := preload("res://scenes/world/miami.tscn")


func test_project_boots_intro_video() -> bool:
	return ProjectSettings.get_setting("application/run/main_scene") == INTRO_SCENE_PATH


func test_intro_hands_off_to_main_menu() -> bool:
	return IntroVideo.MENU_SCENE == MENU_SCENE_PATH


func test_main_menu_play_opens_miami() -> bool:
	return MainMenu.PLAY_SCENE == WORLD_SCENE_PATH


func test_front_door_scenes_load() -> bool:
	return INTRO_SCENE != null and MENU_SCENE != null and WORLD_SCENE != null


func test_front_door_ui_scene_scripts_match_route() -> bool:
	var intro := INTRO_SCENE.instantiate()
	var menu := MENU_SCENE.instantiate()
	var ok := intro is IntroVideo and menu is MainMenu
	intro.free()
	menu.free()
	return ok
