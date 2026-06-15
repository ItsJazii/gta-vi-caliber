class_name ParkedCarLayer
extends Node3D
## A street's worth of parked cars, all one model: drawn as a single MultiMesh
## (cheap, a couple of draw calls) but made SOLID — a StaticBody with one box per
## car — and JACKABLE. The player can take any car in the layer: that hides the
## parked instance and hands back where it stood and which model it was, so a real
## drivable Car can be dropped in its place and driven off. district_loader builds
## one layer per model (coupe / sedan) per streamed tile.
##
## All maths that needs world space goes through `to_global`, since the instance
## transforms are stored in the layer's (tile-local) frame like the MultiMesh.

## World collision layer (matches BuildingCollision.WORLD_LAYER) — the solid layer
## the player, NPCs and vehicles all collide against.
const SOLID_LAYER := 1
## Fallback car box if the mesh has no AABB to size colliders from.
const FALLBACK_BOX := Vector3(1.9, 1.4, 4.4)

var _variant: int = 0
var _transforms: Array[Transform3D] = []
var _taken: Array[bool] = []
var _mm: MultiMesh = null
var _shapes: Array[CollisionShape3D] = []


## Build the visual MultiMesh (named `mm_name` so the vehicle-visual probe still
## finds it), one solid collider box per car, and the jackable registry. Every car
## here is model `variant`, so a jacked one drives off as that car.
func build(mesh: Mesh, transforms: Array[Transform3D], variant: int, mm_name: String) -> void:
	_variant = variant
	_transforms = transforms
	add_to_group("parked_cars")
	var box := TrafficCar.solid_box(mesh.get_aabb(), 0.0) if mesh != null else {}
	var box_size: Vector3 = box.get("size", FALLBACK_BOX)
	var box_center: Vector3 = box.get("center", Vector3(0.0, FALLBACK_BOX.y * 0.5, 0.0))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = transforms.size()
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	for i in transforms.size():
		_mm.set_instance_transform(i, transforms[i])
		_taken.append(false)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		cs.shape = shape
		cs.transform = transforms[i] * Transform3D(Basis(), box_center)
		body.add_child(cs)
		_shapes.append(cs)
	add_child(body)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = _mm
	mmi.visibility_range_end = 300.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)


## Nearest still-parked car (world space) to `world_pos` within `reach`, or -1.
func nearest(world_pos: Vector3, reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in _transforms.size():
		if _taken[i]:
			continue
		var d := world_pos.distance_to(to_global(_transforms[i].origin))
		if d <= best_d:
			best_d = d
			best = i
	return best


## World position of parked car `index` (for the caller's reach check).
func car_position(index: int) -> Vector3:
	return to_global(_transforms[index].origin)


## Take parked car `index`: hide its visual + collider and return its WORLD
## {transform, variant}, so the caller can drop a real drivable Car there. Empty
## dictionary if the index is invalid or already taken.
func take(index: int) -> Dictionary:
	if index < 0 or index >= _transforms.size() or _taken[index]:
		return {}
	_taken[index] = true
	_shapes[index].disabled = true
	# Collapse the parked instance to nothing so only the drivable car is left.
	_mm.set_instance_transform(
		index, Transform3D(Basis().scaled(Vector3.ZERO), _transforms[index].origin)
	)
	return {"transform": global_transform * _transforms[index], "variant": _variant}
