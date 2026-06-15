extends RefCounted
## Unit tests for TrafficCar's pure collision-box sizing. The live body wiring
## (an AnimatableBody3D on the world layer per car) is proven in the running
## scene by tests/miami_traffic_road_probe.gd via TrafficDirector.cars_are_solid().


func test_solid_box_size_matches_aabb() -> bool:
	var aabb := AABB(Vector3(-0.9, 0.0, -2.2), Vector3(1.8, 1.4, 4.4))
	var spec := TrafficCar.solid_box(aabb, 0.03)
	return (spec["size"] as Vector3).is_equal_approx(Vector3(1.8, 1.4, 4.4))


func test_solid_box_center_is_aabb_centre_plus_lift() -> bool:
	# Centre of this AABB is (0, 0.7, 0); the visual's 0.03 lift raises it on Y.
	var aabb := AABB(Vector3(-0.9, 0.0, -2.2), Vector3(1.8, 1.4, 4.4))
	var spec := TrafficCar.solid_box(aabb, 0.03)
	return (spec["center"] as Vector3).is_equal_approx(Vector3(0.0, 0.73, 0.0))


func test_solid_box_handles_an_offset_origin() -> bool:
	# A mesh whose origin sits at its rear: centre shifts forward by half the length.
	var aabb := AABB(Vector3(-0.95, 0.0, 0.0), Vector3(1.9, 1.5, 4.5))
	var spec := TrafficCar.solid_box(aabb, 0.0)
	return (spec["center"] as Vector3).is_equal_approx(Vector3(0.0, 0.75, 2.25))
