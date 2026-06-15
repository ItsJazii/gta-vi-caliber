class_name VehicleModGarage
extends Area3D
## Drive-in tuning garage: park the car you're driving on the garage floor and the
## next affordable performance upgrade is bought against your wallet and applied
## live to that car. Each vehicle keeps its own upgrade levels (a VehicleModShop
## per car, keyed by node name), so a tuned car stays tuned and a second car starts
## stock. Consumes the tested VehicleModShop model and self-wires by group
## (player_stats); it detects the driven car through the "vehicles" group on body
## entry — the same enter/exit/has_driver contract player.gd uses — so it needs no
## plumbing beyond an Area3D + CollisionShape3D placed over the garage floor.
##
## Cars drive on collision layer 1 (car_physics.tscn) and the player is hidden on
## layer 0 while driving, so the body that trips this zone is the car itself.

signal vehicle_upgraded(vehicle_id: String, category: String, new_level: int, cost: int)

## Buy at most one tier per drive-in (re-enter to keep upgrading). Stops a single
## pass through the zone from draining the wallet across every category at once.
@export var one_purchase_per_visit: bool = true

var _stats: Node = null
## vehicle_id (node name) -> VehicleModShop holding that car's upgrade levels.
var _shops: Dictionary = {}
## vehicle_id -> Dictionary of the car's stock stats, cached before any tuning so
## each upgrade re-derives from the baseline instead of compounding on itself.
var _stock: Dictionary = {}


func _ready() -> void:
	add_to_group("vehicle_mod_shop")
	# Show up on the minimap + full map (M) as a labelled "garage" POI. Both map
	# UIs render any node in a poi_<kind> group whose kind is in Minimap.POI_COLORS.
	add_to_group("poi_garage")
	set_meta("map_label", "Mod Garage")
	# Watch the car's physics layer (1); the driven car, not the player, enters.
	collision_mask |= 1
	body_entered.connect(_on_body_entered)
	_spawn_beacon()


## Drop a glowing holo-beam + floor pad so the (otherwise invisible) trigger zone
## is findable in the world. Built in code so every placed garage gets the same
## marker without per-scene plumbing. The colour tracks the map blip.
func _spawn_beacon() -> void:
	var col: Color = Minimap.POI_COLORS.get("garage", Color(0.1, 0.95, 0.9))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, 0.35)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Tall light beam — visible from across the district.
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 1.0
	beam_mesh.bottom_radius = 1.0
	beam_mesh.height = 8.0
	beam_mesh.material = mat
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, 3.0, 0.0)
	add_child(beam)

	# Flat pad marking the floor you drive onto (sits inside the trigger box).
	var pad := MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 6.0
	pad_mesh.bottom_radius = 6.0
	pad_mesh.height = 0.2
	pad_mesh.material = mat
	pad.mesh = pad_mesh
	pad.position = Vector3(0.0, -0.9, 0.0)
	add_child(pad)

	# A soft glow so the beacon still reads at night.
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 4.0
	light.omni_range = 18.0
	light.position = Vector3(0.0, 2.0, 0.0)
	add_child(light)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("vehicles"):
		return
	# Only tune the car the player is actually driving — parked traffic rolling
	# through the zone shouldn't spend the player's money.
	if not (body.has_method("has_driver") and body.has_driver()):
		return
	_bind()
	if _stats == null or not ("money" in _stats):
		return
	var vehicle_id := String(body.name)
	var shop := _shop_for(vehicle_id)
	var category := _best_affordable(shop, int(_stats.money))
	if category == "":
		return
	var result := shop.upgrade(category, int(_stats.money))
	if not result.get("success", false):
		return
	if _stats.has_method("spend_money"):
		_stats.spend_money(int(result["cost"]))
	_apply_tuning(body, vehicle_id, shop)
	vehicle_upgraded.emit(vehicle_id, category, int(result["new_level"]), int(result["cost"]))


## The next category to upgrade on this drive-in, or "" when nothing is affordable /
## everything is maxed. Picks the LEAST-upgraded affordable category, breaking ties by
## the cheaper next tier. Lowest-level-first genuinely spreads tuning across every stat
## (engine/armor get bought too) instead of the old cheapest-first, which bought tires
## and brakes all the way out before speed or armor ever got a look-in. Static + pure
## (reads only the shop) so the selection policy is unit-tested without a node tree
## (tests/unit/test_vehicle_mod_garage.gd).
static func _best_affordable(shop: VehicleModShop, money: int) -> String:
	var best := ""
	var best_level := -1
	var best_price := -1
	for category: String in shop.categories():
		if not shop.can_upgrade(category):
			continue
		var price := shop.price_for(category, shop.level_of(category) + 1)
		if price < 0 or price > money:
			continue
		var level := shop.level_of(category)
		if best == "" or level < best_level or (level == best_level and price < best_price):
			best = category
			best_level = level
			best_price = price
	return best


func _shop_for(vehicle_id: String) -> VehicleModShop:
	if not _shops.has(vehicle_id):
		_shops[vehicle_id] = VehicleModShop.new()
	return _shops[vehicle_id]


## Re-derive the car's tuned stats from its cached stock baseline times the shop's
## multipliers. Engine torque feeds both acceleration and top speed through the
## powertrain; tyres feed grip, brakes the brake force, armor the health pool.
func _apply_tuning(car: Node, vehicle_id: String, shop: VehicleModShop) -> void:
	var base := _stock_for(car, vehicle_id)
	if "peak_torque" in car:
		car.peak_torque = base["peak_torque"] * shop.acceleration_multiplier()
	if "tire_friction" in car:
		car.tire_friction = base["tire_friction"] * shop.grip_multiplier()
	if "max_brake" in car:
		car.max_brake = base["max_brake"] * shop.brake_multiplier()
	if "max_health" in car:
		car.max_health = base["max_health"] * shop.armor_multiplier()


## Snapshot a car's stock stats the first time it visits, so tuning is always
## baseline * multiplier and never compounds.
func _stock_for(car: Node, vehicle_id: String) -> Dictionary:
	if not _stock.has(vehicle_id):
		_stock[vehicle_id] = {
			"peak_torque": float(car.peak_torque) if "peak_torque" in car else 0.0,
			"tire_friction": float(car.tire_friction) if "tire_friction" in car else 0.0,
			"max_brake": float(car.max_brake) if "max_brake" in car else 0.0,
			"max_health": float(car.max_health) if "max_health" in car else 0.0,
		}
	return _stock[vehicle_id]


func _bind() -> void:
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")


## Total upgrade tiers installed on a vehicle across every category (HUD / probe).
func installed_levels(vehicle_id: String) -> int:
	if not _shops.has(vehicle_id):
		return 0
	var shop: VehicleModShop = _shops[vehicle_id]
	var total := 0
	for category: String in shop.categories():
		total += shop.level_of(category)
	return total


# --- Persistence (SaveManager) ---------------------------------------------


func serialize() -> Dictionary:
	var out: Dictionary = {}
	for vehicle_id: String in _shops:
		out[vehicle_id] = (_shops[vehicle_id] as VehicleModShop).serialize()
	return out


func restore(data: Dictionary) -> void:
	_shops.clear()
	for vehicle_id: Variant in data:
		if not (data[vehicle_id] is Dictionary):
			continue
		var shop := VehicleModShop.new()
		shop.restore(data[vehicle_id])
		_shops[String(vehicle_id)] = shop
	_reapply_all()


## Re-apply restored tuning to any live car whose id we loaded levels for.
func _reapply_all() -> void:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle_id := String(node.name)
		if _shops.has(vehicle_id):
			_apply_tuning(node, vehicle_id, _shops[vehicle_id])
