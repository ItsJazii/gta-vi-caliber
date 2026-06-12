class_name RadioScheduler
extends RefCounted
## Pure station-programming / scheduler model: decides what plays next so a
## station feels live by interleaving songs, DJ chatter, ads, station IDs and
## occasional news (M5 radio polish). Complements VehicleRadioModel, which owns
## the station list and now-playing cursor; this model owns the *programming*
## brain — the running order. No engine/node deps, fully unit-tested
## (test_radio_scheduler.gd).
##
## Determinism: all randomness flows through a passed-in RandomNumberGenerator,
## so seeding the rng reproduces an exact running order (no global RNG).

enum Segment { SONG, DJ, AD, NEWS, ID }

## Songs are queued between breaks; a break lands after this many songs.
const BREAK_AFTER_SONGS: int = 4
## How many recent songs to remember to avoid immediate repeats.
const RECENT_MEMORY: int = 3
## Chance (0..1) that a break is NEWS instead of DJ/AD/ID.
const NEWS_CHANCE: float = 0.15

var _songs: Array[String] = []
var _ads: Array[String] = []
var _station_id: String = ""

# --- stateful playlist runner ------------------------------------------------
var _songs_since_break: int = 0
var _recent: Array[String] = []
var _now: Dictionary = {}


func _init(songs: Array = [], ads: Array = [], station_id: String = "") -> void:
	for s in songs:
		_songs.append(String(s))
	for a in ads:
		_ads.append(String(a))
	_station_id = station_id


## Decide the next segment kind given how many songs have played since the last
## break. Mostly SONG, but forces a break once BREAK_AFTER_SONGS is reached;
## the break is usually DJ/AD/ID and occasionally NEWS. Deterministic given the
## rng + counter. With no songs available it always returns a break segment so
## an empty pool never deadlocks on "play a song".
func next_segment(songs_since_break: int, rng: RandomNumberGenerator) -> int:
	if _songs.is_empty():
		return _pick_break(rng)
	if songs_since_break < BREAK_AFTER_SONGS:
		return Segment.SONG
	return _pick_break(rng)


## Choose a song id, avoiding any in recently_played. Falls back to the full
## pool when every song is recent, and to "" only when the pool is empty.
func pick_song(rng: RandomNumberGenerator, recently_played: Array = []) -> String:
	if _songs.is_empty():
		return ""
	var fresh: Array[String] = []
	for song in _songs:
		if not recently_played.has(song):
			fresh.append(song)
	var pool := fresh if not fresh.is_empty() else _songs
	return pool[rng.randi_range(0, pool.size() - 1)]


## Choose an advert id, or "" when no ads are configured.
func pick_ad(rng: RandomNumberGenerator) -> String:
	if _ads.is_empty():
		return ""
	return _ads[rng.randi_range(0, _ads.size() - 1)]


## Advance the running order one step and return {"segment", "id"}. Maintains
## the songs-since-break counter (incremented per song, reset on a break) and
## the recent-song history. Becomes the new now_playing().
func advance(rng: RandomNumberGenerator) -> Dictionary:
	var seg := next_segment(_songs_since_break, rng)
	var id := _segment_id(seg, rng)
	if seg == Segment.SONG:
		_songs_since_break += 1
		_remember(id)
	else:
		_songs_since_break = 0
	_now = {"segment": seg, "id": id}
	return _now.duplicate()


## The last segment produced by advance(), or an empty Dictionary before the
## first advance().
func now_playing() -> Dictionary:
	return _now.duplicate()


## How many songs have played since the last break (exposed for HUD/tests).
func songs_since_break() -> int:
	return _songs_since_break


## Human-readable label for a Segment value.
func segment_name(seg: int) -> String:
	match seg:
		Segment.SONG:
			return "SONG"
		Segment.DJ:
			return "DJ"
		Segment.AD:
			return "AD"
		Segment.NEWS:
			return "NEWS"
		Segment.ID:
			return "ID"
		_:
			return "UNKNOWN"


# --- internals ---------------------------------------------------------------


func _pick_break(rng: RandomNumberGenerator) -> int:
	if rng.randf() < NEWS_CHANCE:
		return Segment.NEWS
	var kinds := [Segment.DJ, Segment.AD, Segment.ID]
	return kinds[rng.randi_range(0, kinds.size() - 1)]


func _segment_id(seg: int, rng: RandomNumberGenerator) -> String:
	match seg:
		Segment.SONG:
			return pick_song(rng, _recent)
		Segment.AD:
			return pick_ad(rng)
		Segment.ID:
			return _station_id
		_:
			return ""


func _remember(song_id: String) -> void:
	if song_id.is_empty():
		return
	_recent.append(song_id)
	while _recent.size() > RECENT_MEMORY:
		_recent.pop_front()
