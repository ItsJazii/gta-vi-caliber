class_name SaveGame
extends RefCounted
## Versioned save/load of world + player state. Serialization is pure JSON over
## plain data (so it unit-tests headless and stays engine-version stable); the
## read/write helpers persist to user:// . State is a plain Dictionary owned by
## the caller — e.g. {player_pos:[x,y,z], time_of_day:float, wanted_heat:float,
## missions:{...}} — keeping this layer agnostic to what the game stores.

const VERSION := 1
const DEFAULT_PATH := "user://savegame.json"


static func serialize(state: Dictionary) -> String:
	return JSON.stringify({"version": VERSION, "state": state})


static func deserialize(text: String) -> Dictionary:
	# Use an instance JSON.parse (returns an error code) rather than the static
	# JSON.parse_string, which pushes a global ERROR to the log on any malformed
	# or empty input — and "no save yet / empty file" is the normal first-run
	# path, so that was spamming hard errors that mask real ones. Behaviour is
	# identical: anything that isn't a versioned object yields {}.
	var json := JSON.new()
	if text.strip_edges().is_empty() or json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION and parsed.has("state"):
		return parsed["state"]
	return {}


static func write(state: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(serialize(state))
	return true


static func read(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return deserialize(FileAccess.get_file_as_string(path))


static func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)
