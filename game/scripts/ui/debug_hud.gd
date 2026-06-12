class_name DebugHud
extends CanvasLayer
## Always-on development HUD: FPS plus control hints.
##
## UI observes and emits — it must never drive gameplay (docs/ARCHITECTURE.md).

const HINTS: String = (
	"WASD move · Shift sprint · Space jump/brake · E enter/exit car"
	+ " · C look behind · mouse look · Esc cursor"
)

@onready var _label: Label = $InfoLabel


func _process(_delta: float) -> void:
	var text := "%d FPS\n%s" % [Engine.get_frames_per_second(), HINTS]
	# Duck-typed: the streamer is optional and its class may not be registered
	# in every headless boot order, so probe for the method instead of casting.
	var streamer := get_tree().get_first_node_in_group("tile_streamer")
	if streamer != null and streamer.has_method("stats"):
		var stats: Dictionary = streamer.stats()
		text += (
			"\ntiles: %d resident · %d loading · VRAM %.0f MB · frame %.1f ms"
			% [
				stats["resident"],
				stats["loading"],
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			]
		)
	_label.text = text
