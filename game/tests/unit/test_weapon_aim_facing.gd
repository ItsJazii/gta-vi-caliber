extends RefCounted
## Unit tests for WeaponController.aim_yaw_for — the armed-facing yaw. Guards the
## convention that the model's forward (+Z / Vector3.BACK) ends up pointing along
## the camera forward, so aiming faces the character downrange instead of spinning
## 180° to face the camera (see tests/run_tests.gd: test_* return true to pass).


func _faces_along(forward: Vector3) -> bool:
	var yaw := WeaponController.aim_yaw_for(forward)
	var model_forward := Basis(Vector3.UP, yaw) * Vector3.BACK
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	return model_forward.dot(flat) > 0.999


func test_faces_along_minus_z() -> bool:
	return _faces_along(Vector3(0.0, 0.0, -1.0))


func test_faces_along_plus_x() -> bool:
	return _faces_along(Vector3(1.0, 0.0, 0.0))


func test_faces_along_diagonal_ignoring_pitch() -> bool:
	# A downward-tilted look still yaws the body along the planar heading only.
	return _faces_along(Vector3(2.0, -1.5, -3.0))
