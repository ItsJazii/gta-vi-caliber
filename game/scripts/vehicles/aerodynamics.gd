class_name Aerodynamics
extends RefCounted
## Pure aerodynamic-force math for vehicles.
##
## Static functions only, no scene access — same testable-core pattern as
## Powertrain / VehicleMotion (docs/ARCHITECTURE.md). Models the two forces that
## matter at road speed: drag, which grows with the square of speed and is what
## actually caps a car's top speed once the gearbox runs out of pull, and
## downforce, which presses the car into the road so grip climbs with speed.
## Both take a pre-multiplied area term (drag_area = Cd·A, lift_area = Cl·A) so
## the caller tunes one number per axis. Covered by tests/unit/test_aerodynamics.gd.

## Sea-level air density (kg/m³) at ~15 °C — the default medium.
const AIR_DENSITY: float = 1.225


## Drag force magnitude (N), always ≥ 0, from the standard ½·ρ·Cd·A·v² relation.
## drag_area is Cd·A (m²); air_density lets callers thin the air for altitude or
## thicken it for tests. Speed is unsigned — the caller applies this opposite the
## velocity vector.
static func drag_force(speed: float, drag_area: float, air_density: float = AIR_DENSITY) -> float:
	if drag_area <= 0.0 or air_density <= 0.0:
		return 0.0
	var v := absf(speed)
	return 0.5 * air_density * drag_area * v * v


## Downforce magnitude (N), always ≥ 0, same ½·ρ·Cl·A·v² form. lift_area is the
## Cl·A term; the caller applies the result straight down (into the road) so that
## available tyre grip rises with speed. Returns 0 at a standstill.
static func downforce(speed: float, lift_area: float, air_density: float = AIR_DENSITY) -> float:
	if lift_area <= 0.0 or air_density <= 0.0:
		return 0.0
	var v := absf(speed)
	return 0.5 * air_density * lift_area * v * v


## Speed (m/s) at which drag exactly balances a steady drive force — the
## drag-limited top speed for that much thrust. Inverts drag_force:
## v = sqrt(2·F / (ρ·Cd·A)). Returns 0 for non-physical inputs (no thrust, no
## drag, no air) so callers never take a sqrt of a negative or divide by zero.
static func terminal_speed(
	drive_force: float, drag_area: float, air_density: float = AIR_DENSITY
) -> float:
	if drive_force <= 0.0 or drag_area <= 0.0 or air_density <= 0.0:
		return 0.0
	return sqrt(2.0 * drive_force / (air_density * drag_area))
