class_name LootDropDirector
extends Node
## On a kill — WeaponController.crime_committed(killed=true) — roll a loot table and
## spawn a real pickup (medkit/armor) at the kill site for the player to grab: the
## combat-reward loop. Self-wiring: it finds the weapon by group `weapon_controller`
## (the same hook WantedTracker / CrowdPanicDirector use), polling until the weapon
## appears, then stops processing. Reuses the existing Pickup scenes, so drops are
## collectibles you walk over, not instant credits. Wiring exercised by
## tests/loot_drop_probe.gd.

## Emitted when a kill drops loot, with the pickup kind and where it landed.
signal loot_dropped(kind: String, at: Vector3)

## Chance a kill drops anything at all (the rest is "nothing").
@export var drop_chance: float = 0.6
## Pickup scenes per loot kind — set in the scene to medkit.tscn / armor.tscn.
@export var medkit_scene: PackedScene
@export var armor_scene: PackedScene

var _loot: LootTable
var _rng: RandomNumberGenerator
var _connected: bool = false


func _init() -> void:
	# Only kinds we actually have a Pickup scene for (pickup.gd grants health/armor).
	_loot = (
		LootTable
		. new(
			[
				{"id": "health", "weight": 4.0, "min": 1, "max": 1},
				{"id": "armor", "weight": 2.0, "min": 1, "max": 1},
				{"id": "", "weight": 3.0, "min": 0, "max": 0},
			]
		)
	)
	_rng = RandomNumberGenerator.new()


func _ready() -> void:
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
	if not _loot.drop_chance_satisfied(_rng, drop_chance):
		return
	var drop: Dictionary = _loot.roll(_rng)
	var scene := _scene_for(str(drop.get("id", "")))
	if scene == null:
		return
	var pickup := scene.instantiate() as Node3D
	if pickup == null:
		return
	# Drop into the world node (group `world`, the map root), falling back to our
	# own parent — robust whether or not the tree has a `current_scene` set.
	var host: Node = get_tree().get_first_node_in_group("world")
	if host == null:
		host = get_parent()
	if host == null:
		pickup.free()
		return
	host.add_child(pickup)
	pickup.global_position = pos + Vector3(0.0, 0.5, 0.0)
	loot_dropped.emit(str(drop["id"]), pickup.global_position)


func _scene_for(kind: String) -> PackedScene:
	match kind:
		"health":
			return medkit_scene
		"armor":
			return armor_scene
	return null
