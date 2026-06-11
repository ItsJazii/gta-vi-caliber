class_name WorldQuality
extends WorldEnvironment
## Applies a GPU-budget-gated cinematic grade to this scene's WorldEnvironment at
## runtime, so the gameplay scene gets premium lighting without baking the
## expensive GI passes into the .tscn (which would force the cost on every GPU,
## the regression LOOP_HANDOFF flagged). The tier resolves from $GTA_QUALITY or
## defaults to MEDIUM — see CinematicEnvironment.apply_quality / resolved_tier.
##
## The scene keeps its own sky/background; only the grade + AO/reflections/GI
## layers are touched, so SkyController/DayNight tinting still drives the sky.


func _ready() -> void:
	if environment == null:
		environment = Environment.new()
	CinematicEnvironment.apply_quality(environment, CinematicEnvironment.resolved_tier())
