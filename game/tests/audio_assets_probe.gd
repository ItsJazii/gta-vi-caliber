extends SceneTree
## Probe: every CC0 sample the audio nodes reference actually resolves (a renamed
## or missing asset fails CI), each loads as an AudioStream, and the nodes voice
## known / fallback / bogus events without error. Guards WeaponAudio and
## FootstepAudio against silently losing their samples.

const WARMUP_FRAMES: int = 4

var _frames: int = 0
var _weapon_audio: WeaponAudio = null
var _footstep_audio: FootstepAudio = null


func _initialize() -> void:
	_weapon_audio = WeaponAudio.new()
	root.add_child(_weapon_audio)
	_footstep_audio = FootstepAudio.new()
	root.add_child(_footstep_audio)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var failures := PackedStringArray()
	_check_weapon_assets(failures)
	_check_footstep_assets(failures)
	_exercise()
	if not failures.is_empty():
		for failure in failures:
			push_error("audio assets probe FAIL :: %s" % failure)
		quit(1)
		return true
	print(
		(
			"audio assets probe: OK (%d weapon samples, %d footstep banks)"
			% [WeaponAudio.STREAMS.size(), FootstepAudio.SURFACE_DIRS.size()]
		)
	)
	quit(0)
	return true


func _check_weapon_assets(failures: PackedStringArray) -> void:
	for key: String in WeaponAudio.STREAMS:
		var path: String = WeaponAudio.STREAMS[key]
		if not ResourceLoader.exists(path):
			failures.append("weapon '%s' sample missing: %s" % [key, path])
		elif not (load(path) is AudioStream):
			failures.append("weapon '%s' is not an AudioStream: %s" % [key, path])


func _check_footstep_assets(failures: PackedStringArray) -> void:
	if not FootstepAudio.SURFACE_DIRS.has(FootstepAudio.FALLBACK_SURFACE):
		failures.append(
			"footstep fallback surface '%s' has no bank" % FootstepAudio.FALLBACK_SURFACE
		)
	for surface: String in FootstepAudio.SURFACE_DIRS:
		var dir_path: String = FootstepAudio.SURFACE_DIRS[surface]
		var prefix: String = dir_path.get_file()
		var found: int = 0
		for i in range(1, FootstepAudio.VARIATIONS + 1):
			var path := "%s/%s_%d.ogg" % [dir_path, prefix, i]
			if ResourceLoader.exists(path) and load(path) is AudioStream:
				found += 1
			else:
				failures.append("footstep '%s' sample missing: %s" % [surface, path])
		if found == 0:
			failures.append("footstep '%s' bank is empty" % surface)


## Smoke-fire known, fallback, and bogus events; any error surfaces in CI output.
func _exercise() -> void:
	for surface in ["concrete", "grass", "sand", "metal", "wood", "water", "__none__"]:
		_footstep_audio.on_footstep(surface, true)
		_footstep_audio.on_footstep(surface, false)
	for key in ["pistol", "smg", "rifle", "shotgun", "__none__"]:
		_weapon_audio.fire(key, Vector3.ZERO)
