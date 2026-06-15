extends Node3D
## Probe-only world builder for Miami facade audits.
##
## This bypasses the full Miami gameplay scene and the broader district loader so
## the facade/material probe can exercise the district JSON + facade panel pass
## on a clean checkout without unrelated player/UI/NPC dependencies.

const GeoProjection = preload("res://scripts/world/geo_projection.gd")
const DistrictFacadePanels = preload("res://scripts/world/district_facade_panels.gd")

const DISTRICTS: Array[Dictionary] = [
	{"name": "Brickell", "path": "res://assets/world/brickell.json"},
	{"name": "DowntownMiami", "path": "res://assets/world/downtown_miami.json"},
	{"name": "MidBeach", "path": "res://assets/world/mid_beach.json"},
	{"name": "SouthBeach", "path": "res://assets/world/south_beach.json"},
	{"name": "Wynwood", "path": "res://assets/world/wynwood.json"},
]


func _ready() -> void:
	for district in DISTRICTS:
		var data := _load_json(String(district["path"]))
		if data.is_empty():
			push_error("miami_facade_probe_world: missing district %s" % district["path"])
			continue
		var origin_value: Variant = data.get("origin", {})
		if not (origin_value is Dictionary):
			push_error("miami_facade_probe_world: missing origin in %s" % district["path"])
			continue
		var origin := origin_value as Dictionary
		var proj := GeoProjection.new(float(origin["lat"]), float(origin["lon"]))
		var root := Node3D.new()
		root.name = String(district["name"])
		add_child(root)
		DistrictFacadePanels.build(root, data.get("buildings", []), proj)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
