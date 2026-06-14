class_name Savepoint
extends Node3D
## A walk-up save spot (safehouse-style): face it and press the interact key to
## save the game. Mirrors the storefront interactable shape (self-wires into the
## "interactables" group, answers interact_prompt()/interact()), but instead of
## owning any state it just drives the existing SaveManager.
##
## SaveManager is a plain Node in the scene (not in any group), so we can't look
## it up by group like the shops look up player_stats. Instead we locate it by
## capability — the live node that has a save_game() method — searching the scene
## we belong to and caching the result. One press = one save: save_game() runs and
## game_saved fires. No-op (quiet) if no SaveManager is present.

## Fired after a successful save (SaveManager located and save_game() invoked).
signal game_saved

var _save_manager: Node = null


func _ready() -> void:
	add_to_group("interactables")


## Interact-contract: the on-screen prompt.
func interact_prompt() -> String:
	return "Save game"


## Interact-contract: locate the SaveManager and save the game. No-op if absent.
func interact(_player: Node) -> void:
	var manager := _find_save_manager()
	if manager == null:
		return
	manager.save_game()
	game_saved.emit()


## Resolve the live SaveManager by capability (has save_game()), caching the hit
## and re-resolving if the cached node has since been freed. Searches the scene we
## belong to: `owner` is the scene root under both real play and a manual-instantiate
## probe, so (unlike `current_scene`, which is null under manual instantiation) it
## resolves in either context; `get_tree().root` is the last-ditch fallback.
func _find_save_manager() -> Node:
	if is_instance_valid(_save_manager):
		return _save_manager
	for root in [get_owner(), get_tree().current_scene, get_tree().root]:
		if root == null:
			continue
		if root.has_method("save_game"):
			_save_manager = root
			return _save_manager
		for node in root.find_children("*", "", true, false):
			if node.has_method("save_game"):
				_save_manager = node
				return _save_manager
	return null
