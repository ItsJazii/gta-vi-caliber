class_name BuildingShops
extends RefCounted
## Spawns street-level shops on a district's shop-kind buildings (per
## BuildingUse). Static like BuildingDoors so district_loader stays thin. Each
## Shop is a self-contained interactable placed at the storefront door, with its
## catalogue from BuildingUse. When real building assets replace the footprints,
## the same Shop attaches to the asset's storefront marker, unchanged.

## Shops per district and the trigger height above the pavement.
const MAX_SHOPS: int = 10
const SHOP_Y: float = 1.2


## Add a shop under `loader` for each shop-kind building. `proj` projects
## footprints into the loader's local metre frame (the same frame as the meshes).
static func build(loader: Node3D, buildings: Array, proj: GeoProjection) -> void:
	var made := 0
	for b in buildings:
		if made >= MAX_SHOPS:
			break
		var kind := String(b.get("kind", ""))
		if not BuildingUse.is_shop(kind):
			continue
		var ring := _project_ring(b.get("footprint", []), proj)
		if ring.size() < 3:
			continue
		var door := Enterable.door_point(ring)
		var shop := Shop.new()
		shop.catalogue = BuildingUse.catalogue_for(kind)
		shop.position = Vector3(door.x, SHOP_Y, door.y)
		loader.add_child(shop)
		made += 1


static func _project_ring(raw: Array, proj: GeoProjection) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for pair in raw:
		ring.append(proj.to_local_2d(pair[0], pair[1]))
	return ring
