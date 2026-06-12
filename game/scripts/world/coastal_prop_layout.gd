class_name CoastalPropLayout
extends RefCounted
## Pure placement data for the imported coastal prop set.

const PALM_PLANTER: StringName = &"palm_planter"
const PALM_TREE: StringName = &"palm_tree"
const STREET_LAMP: StringName = &"street_lamp"
const GROUND_Y: float = 0.4


static func placements() -> Array[Dictionary]:
	return [
		_spec(&"PalmTree01", PALM_TREE, Vector3(-16.0, GROUND_Y, -10.0), 18.0, 12.0),
		_spec(&"PalmTree02", PALM_TREE, Vector3(13.0, GROUND_Y, -15.0), -24.0, 12.0),
		_spec(&"PalmTree03", PALM_TREE, Vector3(27.0, GROUND_Y, 3.0), 41.0, 12.0),
		_spec(&"PalmTree04", PALM_TREE, Vector3(-25.0, GROUND_Y, 18.0), -38.0, 12.0),
		_spec(&"StreetLamp01", STREET_LAMP, Vector3(-9.0, GROUND_Y, 11.0), 15.0, 3.2),
		_spec(&"StreetLamp02", STREET_LAMP, Vector3(7.0, GROUND_Y, -10.0), 195.0, 3.2),
		_spec(&"StreetLamp03", STREET_LAMP, Vector3(23.0, GROUND_Y, 15.0), 72.0, 3.2),
		_spec(&"StreetLamp04", STREET_LAMP, Vector3(-21.0, GROUND_Y, -18.0), -72.0, 3.2),
		_spec(&"PalmPlanter01", PALM_PLANTER, Vector3(-5.0, GROUND_Y, -7.0), 12.0, 3.5),
		_spec(&"PalmPlanter02", PALM_PLANTER, Vector3(4.0, GROUND_Y, -8.0), -18.0, 3.5),
		_spec(&"PalmPlanter03", PALM_PLANTER, Vector3(-10.0, GROUND_Y, 4.0), 28.0, 3.5),
		_spec(&"PalmPlanter04", PALM_PLANTER, Vector3(18.0, GROUND_Y, -5.0), -31.0, 3.5),
	]


static func _spec(
	node_name: StringName,
	kind: StringName,
	position: Vector3,
	yaw_degrees: float,
	uniform_scale: float
) -> Dictionary:
	return {
		"name": node_name,
		"kind": kind,
		"position": position,
		"yaw_degrees": yaw_degrees,
		"scale": uniform_scale,
	}
