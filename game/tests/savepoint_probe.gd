extends SceneTree
## Runtime wiring probe for the live Savepoint in miami.tscn. Boots the real map,
## asserts the savepoint is present and registered as an interactable (so the
## player can walk up and press to save), then drives interact() once. interact()
## emits game_saved only after it has located the live SaveManager (a plain,
## group-less Node) and invoked save_game(); the probe connects to game_saved and
## asserts it fired — proving the capability lookup + save call wired up with no
## error. save_game() may write user://savegame.json in headless; that's fine,
## we don't assert on the file, only that the save ran. Self-contained.
##   godot --headless --path game --script res://tests/savepoint_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90

var _scene: Node = null
var _frames: int = 0
var _saved: bool = false


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("savepoint probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var err := _verify()
	if err.is_empty():
		print("savepoint probe: OK (located SaveManager, save ran, game_saved fired)")
		quit(0)
	else:
		push_error("savepoint probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var savepoint := _scene.find_child("Savepoint", true, false) as Savepoint
	if savepoint == null:
		return "Savepoint not present in miami.tscn"
	if not savepoint.is_in_group("interactables") or not savepoint.has_method("interact"):
		return "Savepoint is not a live interactable (group/contract missing)"
	if _find_save_manager() == null:
		return "no live SaveManager (save_game) node in scene"

	savepoint.game_saved.connect(_on_saved)
	savepoint.interact(get_first_node_in_group("player"))
	if not _saved:
		return "interact did not emit game_saved (SaveManager not found / save errored)"
	return ""


func _find_save_manager() -> Node:
	for node in _scene.find_children("*", "", true, false):
		if node.has_method("save_game"):
			return node
	return null


func _on_saved() -> void:
	_saved = true
