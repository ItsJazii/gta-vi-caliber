class_name LootDropDirector
extends Node
## On a kill or smashed loot crate, roll a loot table and spawn a real pickup
## (medkit/armor) at the reward site for the player to grab: the combat-reward
## loop. Self-wiring: it finds the weapon by group `weapon_controller` (the same
## hook WantedTracker / CrowdPanicDirector use), polling until the weapon appears,
## then stops processing. Reuses the existing Pickup scenes, so drops are
## collectibles you walk over, not instant credits. Wiring exercised by
## tests/loot_drop_probe.gd.

## Emitted when a kill/crate drops loot, with the pickup kind and where it landed.
signal loot_dropped(kind: String, at: Vector3)

## Chance a kill drops anything at all (the rest is "nothing").
@export var drop_chance: float = 0.6
## Chance a smashed loot crate drops a pickup. Crates use an item-only table.
@export var crate_drop_chance: float = 1.0
## Pickup scenes per loot kind — set in the scene to medkit.tscn / armor.tscn.
@export var medkit_scene: PackedScene
@export var armor_scene: PackedScene

var _kill_loot: LootTable
var _crate_loot: LootTable
var _rng: RandomNumberGenerator
var _connected: bool = false


func _init() -> void:
	# Only kinds we actually have a Pickup scene for (pickup.gd grants health/armor).
	_kill_loot = (
		LootTable
		. new(
			[
				{"id": "health", "weight": 4.0, "min": 1, "max": 1},
				{"id": "armor", "weight": 2.0, "min": 1, "max": 1},
				{"id": "", "weight": 3.0, "min": 0, "max": 0},
			]
		)
	)
	_crate_loot = (
		LootTable
		. new(
			[
				{"id": "health", "weight": 3.0, "min": 1, "max": 1},
				{"id": "armor", "weight": 2.0, "min": 1, "max": 1},
			]
		)
	)
	_rng = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("loot_drop")
	_rng.randomize()
	set_process(true)


func _process(_delta: float) -> void:
	if _connected:
		set_process(false)
		return
	var weapon := get_tree().get_first_node_in_group("weapon_controller")
	if weapon == null or not weapon.has_signal("crime_committed"):
		return
	if not weapon.crime_committed.is_connected(_on_crime):
		weapon.crime_committed.connect(_on_crime)
	_connected = true
	set_process(false)


## Seed the drop RNG for deterministic tests/replays.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## A kill at `pos` may drop a pickup there: chance-gated, then a weighted roll for
## which pickup. Spawns the matching Pickup scene into the live world.
func _on_crime(killed: bool, pos: Vector3) -> void:
	if not killed:
		return
	_drop_from_table(_kill_loot, drop_chance, pos)


## A smashed world crate may drop a guaranteed item-table pickup without raising
## wanted heat. Called by LootCrate through the `loot_drop` group.
func drop_from_crate(pos: Vector3) -> bool:
	return _drop_from_table(_crate_loot, crate_drop_chance, pos)


func _drop_from_table(table: LootTable, chance: float, pos: Vector3) -> bool:
	if table == null or not table.drop_chance_satisfied(_rng, chance):
		return false
	var drop: Dictionary = table.roll(_rng)
	var scene := _scene_for(str(drop.get("id", "")))
	if scene == null:
		return false
	var pickup := scene.instantiate() as Node3D
	if pickup == null:
		return false
	# Drop into the world node (group `world`, the map root), falling back to our
	# own parent — robust whether or not the tree has a `current_scene` set.
	var host: Node = get_tree().get_first_node_in_group("world")
	if host == null:
		host = get_parent()
	if host == null:
		pickup.free()
		return false
	host.add_child(pickup)
	pickup.global_position = pos + Vector3(0.0, 0.5, 0.0)
	loot_dropped.emit(str(drop["id"]), pickup.global_position)
	return true


func _scene_for(kind: String) -> PackedScene:
	match kind:
		"health":
			return medkit_scene
		"armor":
			return armor_scene
	return null
