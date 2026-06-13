class_name GauntletChecks
extends RefCounted
## Pure math behind the asset integration gauntlet
## (tests/asset_gauntlet_capture.gd, docs/ASSET_PIPELINE.md §12): pixel-sanity
## statistics, same-pose flicker metrics, and the camera pose generators for the
## free-look motion arc and the glass angle sweep. Kept headless-testable —
## image sampling and scene wiring stay in the capture script.

## Mean luminance below this reads as a blank/black capture.
const BLANK_MEAN_LUMA := 0.005
## Luminance standard deviation below this reads as a uniform (single-tone)
## capture — a sky-only or wall-only frame that shows nothing of the asset.
const UNIFORM_STDDEV := 0.01
## Per-sample |Δ luminance| above this between two same-pose frames counts as a
## flickering sample (z-fighting, shimmer); TAA jitter stays well below it.
const FLICKER_DELTA := 0.25
## A shot fails the motion pass when more than this fraction of samples flicker.
const FLICKER_MAX_FRACTION := 0.005


## Mean and standard deviation of a luminance sample set.
static func luma_stats(lumas: PackedFloat32Array) -> Dictionary:
	if lumas.is_empty():
		return {"mean": 0.0, "stddev": 0.0}
	var sum := 0.0
	for l in lumas:
		sum += l
	var mean := sum / lumas.size()
	var var_sum := 0.0
	for l in lumas:
		var_sum += (l - mean) * (l - mean)
	return {"mean": mean, "stddev": sqrt(var_sum / lumas.size())}


static func is_blank(mean_luma: float) -> bool:
	return mean_luma < BLANK_MEAN_LUMA


static func is_uniform(stddev_luma: float) -> bool:
	return stddev_luma < UNIFORM_STDDEV


## Fraction of paired samples whose luminance delta exceeds `delta_threshold`.
## Mismatched sample sets cannot be compared and count as total failure.
static func flicker_fraction(
	a: PackedFloat32Array, b: PackedFloat32Array, delta_threshold: float
) -> float:
	if a.size() != b.size() or a.is_empty():
		return 1.0
	var hits := 0
	for i in a.size():
		if absf(a[i] - b[i]) > delta_threshold:
			hits += 1
	return float(hits) / a.size()


## Camera poses for a free-look-style approach: a straight walk from `start` to
## `end` (constant height) while the view swings across `look_center` on a sine
## curve up to `swing_deg` — deliberately NOT a fixed dolly, so grazing angles
## and view-dependent artifacts get sampled. Returns [{pos, look}].
static func arc_poses(
	count: int, start: Vector3, end: Vector3, look_center: Vector3, swing_deg: float
) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	for i in count:
		var t := float(i) / maxf(count - 1, 1.0)
		var pos := start.lerp(end, t)
		var fwd := (look_center - pos).normalized()
		var yaw := deg_to_rad(swing_deg) * sin(t * TAU * 1.5)
		var look_dir := fwd.rotated(Vector3.UP, yaw)
		poses.append({"pos": pos, "look": pos + look_dir * 30.0})
	return poses


## Camera distance that frames a sphere of `radius` filling `fill` (0..1) of the
## vertical field of view.
static func framing_distance(radius: float, fov_deg: float, fill: float) -> float:
	return radius / (tan(deg_to_rad(fov_deg) * 0.5) * maxf(fill, 0.01))


## Poses sweeping view incidence against a (vertical) surface: for each angle in
## `angles_deg` (0 = head-on along the surface normal, ~85 = grazing), a camera
## position `distance` out from `face_center` in the horizontal plane, at
## `height`, looking at the face. Returns [{pos, look}].
static func glass_sweep_poses(
	face_center: Vector3,
	face_normal: Vector3,
	distance: float,
	height: float,
	angles_deg: PackedFloat32Array
) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	var n := Vector3(face_normal.x, 0.0, face_normal.z).normalized()
	for angle in angles_deg:
		var dir := n.rotated(Vector3.UP, deg_to_rad(angle))
		var pos := face_center + dir * distance
		pos.y = height
		poses.append({"pos": pos, "look": face_center})
	return poses
