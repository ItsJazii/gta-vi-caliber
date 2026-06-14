extends SceneTree
## Runtime probe for the live LootDropDirector in miami.tscn. Boots the map, asserts
## the director wired itself to the player's WeaponController.crime_committed and has
## its pickup scenes assigned, then simulates kills and asserts loot pickups drop.
## Self-contained (no miami_wiring_probe touch).
##   godot --headless --path game --script res://tests/loot_drop_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 120
const KILLS: int = 24

var _scene: Node = null
var _frames: int = 0
var _drops: int = 0


func _on_dropped(_kind: String, _at: Vector3) -> void:
	_drops += 1


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("loot drop probe: scene failed to load")
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
		print("loot drop probe: OK (%d drops from %d kills)" % [_drops, KILLS])
		quit(0)
	else:
		push_error("loot drop probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var director := _scene.find_child("LootDropDirector", true, false) as LootDropDirector
	if director == null:
		return "LootDropDirector not present in miami.tscn"
	if director.medkit_scene == null or director.armor_scene == null:
		return "LootDropDirector pickup scenes (medkit/armor) not assigned"
	var weapon := get_first_node_in_group("weapon_controller")
	if weapon == null:
		return "no live weapon_controller (loot would never drop on a kill)"
	if not weapon.crime_committed.is_connected(Callable(director, "_on_crime")):
		return "director not wired to weapon_controller.crime_committed"
	# Force kills and confirm pickups drop (health+armor are 6/9 of the table, so
	# 24 kills practically always drops something; drop_chance forced to 1.0).
	director.drop_chance = 1.0
	director.loot_dropped.connect(_on_dropped)
	for _i in range(KILLS):
		director._on_crime(true, Vector3(150, 0, 150))
	if _drops <= 0:
		return "no loot dropped after %d kills" % KILLS
	return ""
