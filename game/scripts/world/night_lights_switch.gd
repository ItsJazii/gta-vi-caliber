class_name NightLightsSwitch
extends Node
## Flicks every node in group "night_lights" (the backdrop neon OmniLight3D
## clusters and lit accents) on at night and off by day, reading the shared
## StreetlightSwitch.night_level clock SkyController publishes.
##
## Miami drives its day/night through SkyController, not the legacy DayNightCycle
## that used to own this group, so without this the backdrop neon lights burn at
## noon. Like the old cycle it only touches the group when the on/off state
## actually flips, so it costs nothing on the overwhelming majority of frames.

## Night level at/above which the night lights switch on (dusk).
@export_range(0.0, 1.0) var on_threshold: float = 0.4

var _state: int = -1


func _process(_delta: float) -> void:
	var want := 1 if StreetlightSwitch.night_level >= on_threshold else 0
	if want == _state:
		return
	_state = want
	var on := want == 1
	for node in get_tree().get_nodes_in_group("night_lights"):
		var visual := node as Node3D
		if visual != null:
			visual.visible = on
