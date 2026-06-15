class_name Powertrain
extends RefCounted
## Pure engine + transmission math for Car.
##
## Static functions only, no scene access — same testable-core pattern as
## VehicleMotion (docs/ARCHITECTURE.md). Turns road speed and a gear into an
## engine RPM, an RPM into crankshaft torque off a peaked torque curve, and that
## torque into a driving force at the contact patch. A small auto-shift selector
## walks the gearbox up and down with hysteresis so the engine stays in its
## powerband. This replaces the old flat "force tapers to top speed" model with
## something that actually has gears you can hear and feel. Covered by
## tests/unit/test_powertrain.gd.

## Fraction of peak torque lost at the extreme ends of the rev range (idle and
## redline). 0.0 = flat curve, 1.0 = torque falls to zero at the edges. 0.45
## keeps the curve fat through the working range so the engine stays on the boil
## across a shift instead of deflating, while still rewarding revs near peak.
const CURVE_FALLOFF: float = 0.45
## Torque never drops below this fraction of peak, so a lugging or over-revving
## engine still produces usable force instead of stalling to nothing. 0.45 also
## firms up the off-the-line bite (the idle clamp sits on this floor).
const MIN_TORQUE_FRACTION: float = 0.45


## Crankshaft RPM implied by road speed in the given gear. Drivetrain runs
## backwards from the wheels: wheel angular speed (v / r) is multiplied up by the
## gear and final-drive ratios. Clamped to [idle, redline] — the clutch/torque
## converter is assumed to absorb the difference at a standstill rather than
## stalling. wheel_radius and the ratios must be positive.
static func engine_rpm(
	road_speed: float,
	gear_ratio: float,
	final_drive: float,
	wheel_radius: float,
	idle_rpm: float,
	redline_rpm: float
) -> float:
	if wheel_radius <= 0.0:
		return idle_rpm
	var wheel_rad_per_sec := absf(road_speed) / wheel_radius
	var engine_rad_per_sec := wheel_rad_per_sec * absf(gear_ratio) * absf(final_drive)
	var rpm := engine_rad_per_sec * 60.0 / TAU
	return clampf(rpm, idle_rpm, redline_rpm)


## Crankshaft torque (N·m) at a given RPM, read off a parabola that peaks at
## peak_rpm and falls toward the idle and redline ends by CURVE_FALLOFF. The two
## sides use independent spans so a low peak_rpm (lots of low-end grunt) doesn't
## force a symmetric high-end. Result is floored at MIN_TORQUE_FRACTION of peak.
static func engine_torque(
	rpm: float, peak_torque: float, idle_rpm: float, peak_rpm: float, redline_rpm: float
) -> float:
	var clamped := clampf(rpm, idle_rpm, redline_rpm)
	var span := (peak_rpm - idle_rpm) if clamped < peak_rpm else (redline_rpm - peak_rpm)
	if span <= 0.0:
		return peak_torque
	var offset := (clamped - peak_rpm) / span
	var factor := 1.0 - CURVE_FALLOFF * offset * offset
	return peak_torque * clampf(factor, MIN_TORQUE_FRACTION, 1.0)


## Driving force (N) delivered at the contact patch. Crankshaft torque is
## multiplied by the gear and final-drive ratios, scaled by drivetrain
## efficiency, and divided by wheel radius to convert torque into linear force.
## throttle is the pedal in [0, 1]; gear_ratio carries the sign, so a negative
## (reverse) ratio yields a backward force without the caller special-casing it.
static func wheel_force(
	engine_torque_nm: float,
	throttle: float,
	gear_ratio: float,
	final_drive: float,
	wheel_radius: float,
	efficiency: float
) -> float:
	if wheel_radius <= 0.0:
		return 0.0
	var pedal := clampf(throttle, 0.0, 1.0)
	return pedal * engine_torque_nm * gear_ratio * final_drive * efficiency / wheel_radius


## Retarding brake force from engine drag when coasting off-throttle — the
## deceleration you feel lifting off in gear. Grows with revs (pumping and
## friction losses climb with RPM) and with how tall the current gear is (a low
## gear multiplies that drag to the wheels), normalised so first gear at the
## redline returns max_engine_brake. Returned as a positive amount for the caller
## to add to the service brake; never negative.
static func engine_brake(
	rpm: float,
	redline_rpm: float,
	gear_ratio: float,
	first_gear_ratio: float,
	max_engine_brake: float
) -> float:
	if redline_rpm <= 0.0 or first_gear_ratio <= 0.0:
		return 0.0
	var rev := clampf(rpm / redline_rpm, 0.0, 1.0)
	var gear_factor := clampf(absf(gear_ratio) / first_gear_ratio, 0.0, 1.0)
	return maxf(max_engine_brake, 0.0) * rev * gear_factor


## Pick the forward gear (1..top_gear) for the current RPM. Upshifts when the
## engine climbs past upshift_rpm, downshifts when it drops below downshift_rpm,
## and otherwise holds. Keep upshift_rpm well above downshift_rpm: the gap is the
## hysteresis band that stops the box hunting between two gears at a steady
## cruise. At most one gear per call, mirroring a real shift taking a moment.
static func select_gear(
	current_gear: int, rpm: float, upshift_rpm: float, downshift_rpm: float, top_gear: int
) -> int:
	if rpm > upshift_rpm and current_gear < top_gear:
		return current_gear + 1
	if rpm < downshift_rpm and current_gear > 1:
		return current_gear - 1
	return current_gear
