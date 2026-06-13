class_name Shop
extends Node3D
## A storefront the player can use. Self-contained and asset-agnostic: it needs
## only its position and a catalogue, with no dependency on footprints, the
## batched building mesh, or the procedural interior. So when a real 3D building
## asset replaces the placeholder, wiring a shop is just dropping this node at
## the asset's storefront or counter and handing it a catalogue, unchanged.

## ShopModel catalogue (Array of {id, name, price, category}); resolved to the
## ShopModel default stock in _ready if left empty.
var catalogue: Array = []
var shop_name: String = "Shop"

var _model: ShopModel


func _ready() -> void:
	add_to_group("interactables")
	if catalogue.is_empty():
		catalogue = ShopModel.default_catalogue()
	_model = ShopModel.new(catalogue)


func interact_prompt() -> String:
	return shop_name


func interact(_player: Node) -> void:
	var stats := get_tree().get_first_node_in_group("player_stats") as PlayerStats
	if stats == null:
		return
	var menu := ShopMenu.instance(get_tree())
	if menu == null:
		return
	menu.open(_model, stats, shop_name, catalogue)
