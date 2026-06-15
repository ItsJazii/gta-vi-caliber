extends RefCounted
## Behavioural regression tests for the driving-feel tuning pass (feat/vehicle-feel).
## These exercise the pure helpers (Powertrain / Traction / WeightTransfer /
## Aerodynamics / VehicleMotion / VehicleHandling / VehicleDamage / CameraShake /
## BoatMotion) with the TUNED car/bike/boat numbers and assert the end-to-end
## feel targets — launch bite, on-the-boil shifts, preserved drag-limited top
## speed, usable lock at speed, controllable handbrake slides, weighty crashes,
## a no-longer-chronic-wheelie bike, and a planing/steerable boat. Runner contract
## (tests/run_legacy_tests.gd): test_* methods return true to pass. Assertions are
## grouped so the suite stays under the project's max-public-methods limit.
##
## Owned-elsewhere values are referenced as known constants, never asserted to be
## tunable here: peak_torque 420, tire_friction 1.6, max_brake 55, max_health 100.

# --- Tuned CAR parameters (car.gd defaults + car_physics.tscn) ---------------
const PEAK_TORQUE := 420.0
const IDLE := 950.0
const PEAK_RPM := 3600.0
const REDLINE := 6800.0
const FIRST := 3.10
const SECOND := 1.95
const TOP_GEAR := 0.82
const FINAL := 3.90
const RADIUS := 0.35
const EFF := 0.92
const UPSHIFT := 5900.0
const MASS := 1200.0
const GRAV := 9.81
const DRIVE_SHARE := 0.58
const MU := 1.6
const CG := 0.3
const WB := 2.9
const TRACK := 1.7
const MARGIN := 1.0
const MAX_STEER := 0.60
const FALLOFF := 26.0
const DRAG := 0.62
const LIFT := 0.9
const MAX_EBRAKE := 14.0
const MAX_BRAKE := 55.0
const IMPACT_THR := 7.0
const IMPACT_SCALE := 6.0
const FULL_DV := 16.0
const MAX_TRAUMA := 1.0
const FRONT_SLIP := 3.7
const REAR_SLIP := 3.5
const HB_CUT := 0.90
const HB_MIN_SLIP := 0.7

# --- Tuned BIKE parameters ----------------------------------------------------
const B_MAX_STEER := 0.7
const B_FALLOFF := 16.0
const WHEELIE_THR := 16.0
const WHEELIE_SCALE := 5.0
const WHEELIE_MAX := 60.0
const LEAN := 0.85
const UP_STIFF := 90.0
const UP_DAMP := 16.0

# --- Tuned BOAT parameters ----------------------------------------------------
const B_THRUST := 13000.0
const B_RUDDER := 2400.0
const BUOY := 45.0
const B_MASS := 420.0
const LIN_DAMP := 1.3
const ANG_DAMP := 4.0

# --- Acceleration / gearing ---------------------------------------------------


func test_idle_launch_bite_is_firm() -> bool:
	# Off-the-line accel in 1st at the (raised) idle clamp. Old baseline was
	# ~5.09 m/s^2; the tuning must beat it and land in a sporty band.
	var torque := Powertrain.engine_torque(IDLE, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
	var force := Powertrain.wheel_force(torque, 1.0, FIRST, FINAL, RADIUS, EFF)
	var accel := force / MASS
	return accel > 5.5 and accel < 6.6


func test_upshift_rpm_torque_stays_fat() -> bool:
	# After flattening the curve the engine must still make >=76% of peak at the
	# upshift point, so revving to the shift is rewarded rather than wasted.
	var torque := Powertrain.engine_torque(UPSHIFT, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
	return torque >= 0.76 * PEAK_TORQUE


func test_first_to_second_shift_lands_on_the_boil() -> bool:
	# The 1st->2nd shift (the most-used, formerly the softest) must drop the
	# engine to AT OR ABOVE peak_rpm so the car keeps pulling, not deflate.
	var v_shift := UPSHIFT * RADIUS * TAU / (60.0 * FIRST * FINAL)
	var rpm_after := Powertrain.engine_rpm(v_shift, SECOND, FINAL, RADIUS, IDLE, REDLINE)
	return rpm_after >= PEAK_RPM


func test_launch_briefly_lights_the_rears() -> bool:
	# At peak rpm, 1st-gear demand must exceed the straight-line rear grip budget
	# (incl. weight transfer) so the car chirps the rears instead of hooking flat.
	var demand := Powertrain.wheel_force(PEAK_TORQUE, 1.0, FIRST, FINAL, RADIUS, EFF)
	var static_load := MASS * GRAV * DRIVE_SHARE
	var transfer := WeightTransfer.longitudinal_shift(MASS, 11.0, CG, WB)
	var load := WeightTransfer.axle_load(static_load, transfer)
	var grip := Traction.grip_limit(load, MU)
	var available := Traction.longitudinal_grip(grip, 0.0)
	return Traction.traction_scale(demand, available) < 1.0


# --- Top speed / aero ---------------------------------------------------------


func test_top_speed_preserved_and_drag_limited() -> bool:
	# At 70 m/s (252 km/h) the car still out-pulls drag (top end >= old ~254 km/h),
	# and at 75 m/s the engine is still below redline -> drag-limited, not rev-limited.
	var rpm70 := Powertrain.engine_rpm(70.0, TOP_GEAR, FINAL, RADIUS, IDLE, REDLINE)
	var torque70 := Powertrain.engine_torque(rpm70, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
	var force70 := Powertrain.wheel_force(torque70, 1.0, TOP_GEAR, FINAL, RADIUS, EFF)
	var has_margin := force70 > Aerodynamics.drag_force(70.0, DRAG)
	var rpm75 := Powertrain.engine_rpm(75.0, TOP_GEAR, FINAL, RADIUS, IDLE, REDLINE)
	return has_margin and rpm75 < REDLINE


func test_downforce_meaningful_at_speed() -> bool:
	# The raised downforce area more than doubles high-speed downforce vs the old
	# 0.4, so fast sweepers feel planted.
	return Aerodynamics.downforce(40.0, LIFT) >= 2.0 * Aerodynamics.downforce(40.0, 0.4)


# --- Cornering balance --------------------------------------------------------


func test_more_usable_lock_at_speed_and_clamp_still_protects() -> bool:
	# Effective lock at 30 m/s (the tighter of falloff and rollover clamp) beats the
	# old config (less numb at speed), and the anti-flip lateral-g ceiling is still a
	# bounded 2-3 g (tyres slide via wheel grip well before this).
	var new_lock := minf(
		VehicleMotion.steer_limit(30.0, MAX_STEER, FALLOFF),
		VehicleMotion.rollover_steer_limit(30.0, TRACK, CG, WB, MARGIN)
	)
	var old_lock := minf(
		VehicleMotion.steer_limit(30.0, 0.55, 18.0),
		VehicleMotion.rollover_steer_limit(30.0, TRACK, CG, WB, 0.8)
	)
	var cap_g := (TRACK * 0.5) / CG * MARGIN
	return new_lock > old_lock and cap_g > 2.0 and cap_g < 3.2


# --- Handbrake-drift ----------------------------------------------------------


func test_handbrake_breaks_rear_loose_controllably() -> bool:
	# Full handbrake at cruising speed cuts rear grip to ~0.10, which maps to a
	# real, controllable rear slide floor (loose but not zero) far below front grip.
	var fwd := Vector3(0.0, 0.0, -1.0)
	var grip := VehicleHandling.lateral_grip(Vector3(0.0, 0.0, -10.0), fwd, 1.0, 1.0, HB_CUT)
	var slip := VehicleHandling.slip_for_grip(grip, HB_MIN_SLIP, REAR_SLIP)
	return is_equal_approx(grip, 0.10) and slip > 0.6 and slip < 1.2 and slip < FRONT_SLIP * 0.5


func test_handbrake_ramp_speed_and_parked_guard() -> bool:
	# At 1 m/s the faster (/2.0) ramp gives grip 0.55 (the old /3.0 gave 0.70) so
	# tight low-speed handbrake turns bite sooner; a parked car keeps full grip.
	var fwd := Vector3(0.0, 0.0, -1.0)
	var moving := VehicleHandling.lateral_grip(Vector3(0.0, 0.0, -1.0), fwd, 1.0, 1.0, HB_CUT)
	var parked := VehicleHandling.lateral_grip(Vector3.ZERO, fwd, 1.0, 1.0, HB_CUT)
	return is_equal_approx(moving, 0.55) and is_equal_approx(parked, 1.0)


func test_drift_score_only_on_genuine_slide() -> bool:
	# The default DriftScorer engage threshold (0.45) means an ordinary hard
	# corner (drift 0.4) does not score, while a real slide (0.5) does.
	var below := VehicleHandling.DriftScorer.new()
	below.tick(0.4, 1.0)
	var above := VehicleHandling.DriftScorer.new()
	above.tick(0.5, 1.0)
	return is_equal_approx(below.score, 0.0) and above.score > 0.0


func test_drift_factor_reserves_intensity_for_real_slides() -> bool:
	# A ~16 deg slip with the widened full_slip (0.70) reads below the 0.45 engage
	# threshold (no smoke/score), while a full 90 deg slide saturates to 1.0.
	var fwd := Vector3(0.0, 0.0, -1.0)
	var v16 := Vector3(sin(deg_to_rad(16.0)), 0.0, -cos(deg_to_rad(16.0))) * 10.0
	var mild := VehicleHandling.drift_factor(v16, fwd)
	var full := VehicleHandling.drift_factor(Vector3(10.0, 0.0, 0.0), fwd)
	return mild < 0.45 and is_equal_approx(full, 1.0)


# --- Braking ------------------------------------------------------------------


func test_engine_braking_is_perceptible_bounded_and_monotonic() -> bool:
	# Caps at max_engine_brake in 1st at redline, rises with revs, floors at 0, and
	# stays well under the service brake (max_brake) so it never feels like stopping.
	var capped := Powertrain.engine_brake(REDLINE, REDLINE, FIRST, FIRST, MAX_EBRAKE)
	var lo := Powertrain.engine_brake(2000.0, REDLINE, SECOND, FIRST, MAX_EBRAKE)
	var hi := Powertrain.engine_brake(5000.0, REDLINE, SECOND, FIRST, MAX_EBRAKE)
	var zero := Powertrain.engine_brake(0.0, REDLINE, FIRST, FIRST, MAX_EBRAKE)
	return (
		is_equal_approx(capped, MAX_EBRAKE)
		and hi > lo
		and is_equal_approx(zero, 0.0)
		and capped < MAX_BRAKE
	)


# --- Crash / impact feel ------------------------------------------------------


func test_crash_damage_scales_fairly() -> bool:
	# Clean landing (dv 6.5) free; ~50 km/h prang (dv 12) costs 30 hp but survivable;
	# ~100 km/h head-on (dv 24) deals 102 hp and totals the 100 hp car.
	var landing := VehicleDamage.impact_damage(6.5, IMPACT_THR, IMPACT_SCALE)
	var prang := VehicleDamage.impact_damage(12.0, IMPACT_THR, IMPACT_SCALE)
	var headon := VehicleDamage.impact_damage(24.0, IMPACT_THR, IMPACT_SCALE)
	return (
		is_equal_approx(landing, 0.0)
		and is_equal_approx(prang, 30.0)
		and VehicleDamage.health_after(100.0, prang) > 0.0
		and is_equal_approx(headon, 102.0)
		and is_equal_approx(VehicleDamage.health_after(100.0, headon), 0.0)
	)


func test_crash_shake_is_felt_and_bounded() -> bool:
	# No shake at/below the damage floor; a ~50 km/h prang is clearly felt (~0.31,
	# vs an imperceptible ~0.08 under the old full_dv=25); a big hit saturates to 1.
	var silent := CameraShake.trauma_from_impact(IMPACT_THR, IMPACT_THR, FULL_DV, MAX_TRAUMA)
	var prang_trauma := CameraShake.trauma_from_impact(12.0, IMPACT_THR, FULL_DV, MAX_TRAUMA)
	var big := CameraShake.trauma_from_impact(FULL_DV, IMPACT_THR, FULL_DV, MAX_TRAUMA)
	return (
		is_equal_approx(silent, 0.0)
		and CameraShake.shake_amount(prang_trauma, 2.0) > 0.25
		and is_equal_approx(big, 1.0)
	)


# --- Bike ---------------------------------------------------------------------


func test_bike_no_chronic_wheelie() -> bool:
	# The bike's steady traction-limited launch (~16 m/s^2 with the lower CG) no
	# longer auto-pops a wheelie at every part-throttle launch.
	return is_equal_approx(
		VehicleMotion.wheelie_torque(8.6, WHEELIE_THR, WHEELIE_SCALE, WHEELIE_MAX), 0.0
	)


func test_bike_hard_launch_pops_bounded_wheelie() -> bool:
	# A genuine hard launch (18 m/s^2) still lifts the front, proportionally and
	# well under the cap.
	var wheelie := VehicleMotion.wheelie_torque(18.0, WHEELIE_THR, WHEELIE_SCALE, WHEELIE_MAX)
	return is_equal_approx(wheelie, 10.0) and wheelie < WHEELIE_MAX


func test_bike_lean_is_committed() -> bool:
	# Max lean target at 20 m/s is clearly committed (~15 deg) rather than upright.
	var lean_target := LEAN * VehicleMotion.steer_limit(20.0, B_MAX_STEER, B_FALLOFF)
	return lean_target > 0.20


func test_bike_upright_is_near_critically_damped() -> bool:
	var zeta := UP_DAMP / (2.0 * sqrt(UP_STIFF))
	return zeta > 0.8 and zeta < 0.95


# --- Boat ---------------------------------------------------------------------


func test_boat_floats_at_planing_waterline() -> bool:
	# Level-hull equilibrium depth = g/buoyancy_strength; the 4 corner points then
	# exactly balance weight, and the hull sits ~22 cm deep (planing, not wallowing).
	var depth_eq := GRAV / BUOY
	var point_strength := BUOY * B_MASS / 4.0
	var lift := 4.0 * BoatMotion.buoyancy_force(depth_eq, point_strength)
	return is_equal_approx(lift, B_MASS * GRAV) and depth_eq > 0.18 and depth_eq < 0.26


func test_boat_top_speed_and_launch_punch() -> bool:
	# Terminal v = thrust/(mass*linear_damp); launch a0 = thrust/mass.
	var top := B_THRUST / (B_MASS * LIN_DAMP)
	var launch := B_THRUST / B_MASS
	return absf(top - 23.81) < 0.2 and absf(launch - 30.95) < 0.2 and top > 22.5


func test_boat_yaw_is_controllable() -> bool:
	# Steady yaw rate = rudder/(I_yaw*angular_damp) is a deliberate ~66 deg/s,
	# not the old top-like ~348 deg/s.
	var i_yaw := B_MASS / 12.0 * (1.8 * 1.8 + 3.4 * 3.4)
	var yaw_rate := B_RUDDER / (i_yaw * ANG_DAMP)
	return yaw_rate < 2.0 and yaw_rate > 0.5


func test_boat_thrust_and_rudder_gating() -> bool:
	return (
		is_equal_approx(BoatMotion.thrust(0.5, B_THRUST, true), 6500.0)
		and is_equal_approx(BoatMotion.thrust(1.0, B_THRUST, false), 0.0)
		and is_equal_approx(BoatMotion.rudder_torque(-1.0, B_RUDDER, true), -2400.0)
		and is_equal_approx(BoatMotion.rudder_torque(1.0, B_RUDDER, false), 0.0)
	)
