class_name WeightTransfer
extends RefCounted
## Pure longitudinal weight-transfer math for vehicles.
##
## Static functions only, no scene access — same testable-core pattern as
## Traction / Aerodynamics (docs/ARCHITECTURE.md). When a car accelerates its
## mass pivots about the centre of gravity and load shifts off the front axle
## onto the rear (it squats); braking does the reverse (it dives). That shift is
## why a rear-drive car hooks up on launch — the very thing that adds power also
## presses the driven tyres down. Feeds the load that Traction turns into grip.
## Covered by tests/unit/test_weight_transfer.gd.


## Load (N) moved from the front axle onto the rear under acceleration:
## ΔW = m·a·h / L. Positive longitudinal_accel (speeding up) returns a positive
## shift to add to the rear axle; braking returns negative. Zero wheelbase is
## guarded so a mis-set vehicle can't divide by zero.
static func longitudinal_shift(
	mass: float, longitudinal_accel: float, cg_height: float, wheelbase: float
) -> float:
	if wheelbase <= 0.0:
		return 0.0
	return mass * longitudinal_accel * cg_height / wheelbase


## A static axle load plus its transfer, floored at zero — a wheel can unload
## completely and lift, but it can never pull the chassis down with negative
## load (which would otherwise invert grip in the Traction model).
static func axle_load(static_load: float, transfer: float) -> float:
	return maxf(static_load + transfer, 0.0)
