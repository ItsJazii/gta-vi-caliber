class_name Traction
extends RefCounted
## Pure tyre-grip math for vehicles.
##
## Static functions only, no scene access — same testable-core pattern as
## Powertrain / Aerodynamics (docs/ARCHITECTURE.md). Models the hard ceiling a
## tyre puts on how much force it can pass to the road: grip is proportional to
## the load pressing the contact patch down (so downforce buys grip at speed),
## and the longitudinal and lateral demands share that one budget through a
## friction circle — flooring the throttle mid-corner leaves less grip for
## driving, which is what makes a car push wide or light its wheels up exiting a
## bend. Covered by tests/unit/test_traction.gd.


## Downward load (N) on the contact patch: static weight plus the share of
## aerodynamic downforce carried here. Clamped at zero so a freak negative input
## can't invert grip. Pass the per-axle share of mass and downforce if you only
## care about the driven wheels.
static func normal_load(mass: float, gravity: float, downforce: float) -> float:
	return maxf(mass * gravity + downforce, 0.0)


## Peak force (N) the tyre can pass to the road before it slides: the classic
## friction_coefficient · normal_load. Both inputs are floored at zero.
static func grip_limit(normal_load_n: float, friction_coefficient: float) -> float:
	return maxf(friction_coefficient, 0.0) * maxf(normal_load_n, 0.0)


## Longitudinal grip (N) still available once cornering has spent some of the
## budget — the forward leg of the friction circle, sqrt(grip² − lateral²). Once
## lateral demand alone reaches the limit there is nothing left to drive or brake
## with, so this returns 0 rather than a negative root.
static func longitudinal_grip(grip_limit_n: float, lateral_force: float) -> float:
	var budget := maxf(grip_limit_n, 0.0)
	var spent := absf(lateral_force)
	if spent >= budget:
		return 0.0
	return sqrt(budget * budget - spent * spent)


## Scale in [0, 1] to apply to a demanded drive/brake force so it never exceeds
## the grip available: 1.0 while the tyre can cope, tapering to grip/demand once
## the request would break traction. A zero demand needs no limiting, so returns
## 1.0. This is the core of a simple traction-control / wheelspin limiter.
static func traction_scale(demanded_force: float, available_grip: float) -> float:
	var demand := absf(demanded_force)
	if demand <= 0.0:
		return 1.0
	return clampf(maxf(available_grip, 0.0) / demand, 0.0, 1.0)


## Lateral (cornering) force (N) the DRIVEN axle must hold: its share of the
## car's mass times the lateral acceleration (≈ speed · yaw_rate). This MUST be
## charged against the same per-axle grip budget grip_limit() is built from —
## using the whole car's mass against a rear-axle budget spuriously eats ~half
## the drive grip in an ordinary corner (and zeroes it past a moderate yaw rate).
## mass floored at 0, share clamped to [0, 1].
static func cornering_force(mass: float, axle_share: float, speed: float, yaw_rate: float) -> float:
	return maxf(mass, 0.0) * clampf(axle_share, 0.0, 1.0) * absf(speed * yaw_rate)
