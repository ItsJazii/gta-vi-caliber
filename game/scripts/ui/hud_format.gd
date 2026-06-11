class_name HudFormat
extends RefCounted
## Pure formatting + projection helpers shared by the GTA-style HUD widgets.
##
## Every function here is static and side-effect-free so the GameHud, Minimap
## and WeaponWheel all agree on the same maths and it can be unit-tested without
## a running tree (tests/unit/test_hud_format.gd). World space is Godot's: the
## ground is the XZ plane and north is -Z.

const COMPASS_8: PackedStringArray = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


## "HH:MM" 24-hour clock from a 0..24 time-of-day float (wraps & clamps).
static func format_clock(time_of_day: float) -> String:
	var t := fposmod(time_of_day, 24.0)
	var hours := int(t)
	var minutes := int((t - float(hours)) * 60.0) % 60
	return "%02d:%02d" % [hours, minutes]


## Coarse part-of-day label, matching the sky's mood.
static func day_phase(time_of_day: float) -> String:
	var t := fposmod(time_of_day, 24.0)
	if t < 5.0 or t >= 21.0:
		return "Night"
	if t < 8.0:
		return "Dawn"
	if t < 18.0:
		return "Day"
	return "Dusk"


## "$1,234,567" with thousands separators; negatives keep the sign before the $.
static func format_money(amount: int) -> String:
	var neg := amount < 0
	var digits := str(absi(amount))
	var grouped := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count += 1
		if count % 3 == 0 and i > 0:
			grouped = "," + grouped
	return ("-$" if neg else "$") + grouped


## Human distance: metres under 1 km, otherwise one-decimal km.
static func format_distance(metres: float) -> String:
	if metres < 1000.0:
		return "%dm" % int(roundf(metres))
	return "%.1fkm" % (metres / 1000.0)


## Eight-wind compass label for a world-XZ facing vector (north = -Z).
static func compass_8(forward: Vector2) -> String:
	if forward.length_squared() < 0.0000001:
		return "N"
	var deg := rad_to_deg(atan2(forward.x, -forward.y))
	var idx := int(roundf(fposmod(deg, 360.0) / 45.0)) % 8
	return COMPASS_8[idx]


## Project a world-XZ point (relative to the player) into minimap pixel offsets
## from the map centre, rotated so `forward` points to screen-up (-Y). `forward`
## is the player's facing in world XZ.
static func world_to_map(rel: Vector2, forward: Vector2, pixels_per_meter: float) -> Vector2:
	var f := forward
	if f.length_squared() < 0.0000001:
		f = Vector2(0, 1)
	else:
		f = f.normalized()
	var right := Vector2(f.y, -f.x)  # 90° clockwise → screen +X
	var local_x := rel.dot(right)
	var local_fwd := rel.dot(f)
	return Vector2(local_x, -local_fwd) * pixels_per_meter


## Which radial slot a cursor offset from the wheel centre points at (slot 0 at
## the top, going clockwise). Returns -1 inside the dead-zone so a centred cursor
## keeps the current weapon. `count` is the number of slots.
static func wheel_slot(offset: Vector2, count: int, dead_zone: float) -> int:
	if count <= 0 or offset.length() < dead_zone:
		return -1
	var angle := atan2(offset.x, -offset.y)  # 0 = up, clockwise positive
	var slice := TAU / float(count)
	return int(roundf(fposmod(angle, TAU) / slice)) % count


## Centre angle (radians, 0 = up, clockwise) of a wheel slot — for laying the
## slots out so drawing and hit-testing agree.
static func wheel_slot_angle(slot: int, count: int) -> float:
	if count <= 0:
		return 0.0
	return float(slot) * (TAU / float(count))
