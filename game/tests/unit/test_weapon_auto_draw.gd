extends RefCounted
## Unit tests for WeaponController.should_auto_draw — the draw-on-first-click
## rule that makes shooting responsive (see tests/run_tests.gd: test_* methods
## return true to pass). Pure truth table, no scene or input plumbing.


func test_fire_while_holstered_draws() -> bool:
	return WeaponController.should_auto_draw(false, true, true, false)


func test_aim_while_holstered_draws() -> bool:
	return WeaponController.should_auto_draw(false, true, false, true)


func test_no_input_keeps_holstered() -> bool:
	return not WeaponController.should_auto_draw(false, true, false, false)


func test_already_armed_does_not_redraw() -> bool:
	# When already armed the normal fire/aim path runs; auto-draw stays out of it.
	return not WeaponController.should_auto_draw(true, true, true, true)


func test_no_weapon_never_draws() -> bool:
	return not WeaponController.should_auto_draw(false, false, true, true)
