class_name BuildingUse
extends RefCounted
## Classifies a building's OSM kind into how the player interacts with it. This
## is the seam between "what a building is" and "what geometry represents it":
## OSM footprints today and real 3D building assets later both carry a kind, so
## the same classifier drives interaction wiring straight across the asset swap.
## Pure and headless-tested (tests/unit/test_building_use.gd).

## Public-facing kinds that read as storefronts: the player shops at them rather
## than walking into an empty interior.
const SHOP_KINDS := {
	"retail": true,
	"commercial": true,
	"supermarket": true,
}


## True when a building of this kind should host a street-level shop.
static func is_shop(kind: String) -> bool:
	return SHOP_KINDS.has(kind)


## The shop stock for a kind, as a ShopModel catalogue Array. For now every shop
## carries the general-store stock; when assets distinguish gun stores, clothing,
## food, vary the catalogue by kind here and nothing downstream changes.
static func catalogue_for(_kind: String) -> Array:
	return ShopModel.default_catalogue()
