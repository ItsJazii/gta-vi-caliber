class_name CameraPath
extends RefCounted
## A Catmull-Rom spline through control points — the math behind cinematic
## camera flythroughs (roadmap M6: "Cinematic camera tooling for capture", which
## feeds the project's acceptance test, a 90-second in-engine trailer). Sample a
## smooth position at t∈[0,1] over the whole path; the camera also samples a
## little ahead to know which way to look.
##
## Pure and deterministic (points + t → position), so it unit-tests headless
## (tests/unit/test_camera_path.gd). The curve passes through every control point
## and is C¹-continuous, so the camera never kinks at a waypoint.


## Catmull-Rom interpolation of the segment p1→p2 (p0,p3 are the neighbours that
## shape the tangents), at local parameter u∈[0,1].
static func segment(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return (
		0.5
		* (
			2.0 * p1
			+ (p2 - p0) * u
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3
		)
	)


## Sample the whole path at t∈[0,1]. Passes exactly through points[0] at t=0 and
## points[-1] at t=1. Degenerate inputs are handled: empty → ZERO, single → that
## point.
static func sample(points: Array, t: float) -> Vector3:
	var n := points.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return points[0]
	var segments := n - 1
	var ft := clampf(t, 0.0, 1.0) * float(segments)
	var i := clampi(int(floor(ft)), 0, segments - 1)
	var u := ft - float(i)
	var p0: Vector3 = points[maxi(i - 1, 0)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(i + 2, n - 1)]
	return segment(p0, p1, p2, p3, u)
