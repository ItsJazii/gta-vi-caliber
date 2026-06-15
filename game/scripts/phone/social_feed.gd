class_name SocialFeed
extends RefCounted
## Procedural content for the phone's two social apps — "Instasnap" (photo grid
## feed + stories) and "Chirp" (short text posts).
##
## Everything is generated deterministically from a seed and the friend handles,
## so the same seed always yields the same scroll of posts — no text/image assets
## in the repo, and the feeds are unit-testable headless (pure data, no scene
## access). The Phone node owns presentation; this only produces plain data
## dictionaries. Covered by tests/unit/test_social_feed.gd.

## Caption fragments for photo posts, combined deterministically per post.
const CAPTIONS: PackedStringArray = [
	"golden hour downtown",
	"no notes ☀️",
	"found the best taco truck",
	"beach day with the crew",
	"sunset never misses",
	"new kicks who dis",
	"3am thoughts",
	"caught in 4k",
	"vibes immaculate",
	"touch grass they said",
	"city lights hit different",
	"weekend reset",
]

## Whole short text posts for Chirp.
const CHIRPS: PackedStringArray = [
	"why is the highway already packed at 6am",
	"hot take: pineapple belongs on pizza",
	"just saw someone parallel park in one move. legend.",
	"someone tell my neighbor it's not concert hour",
	"manifesting a quiet weekend",
	"the seagulls have unionized and they want my fries",
	"day 4 of pretending i'll go to the gym",
	"this city runs on iced coffee and bad decisions",
	"reminder that you are doing great. probably.",
	"who keeps moving my traffic cone",
	"the sunset tax in this town is unreal and worth it",
	"brb buying a boat i cannot afford",
]


## A deterministic generator keyed to (seed, index) so a given feed position is
## always the same post. Reused for every per-post random choice below.
static func _rng(seed_value: int, index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 100003 + index * 31 + 7
	return rng


## Stories rail: one bubble per handle, each with an avatar hue and a deterministic
## "unseen" flag (about half are fresh). Order follows the handles given.
static func stories(handles: PackedStringArray, seed_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in handles.size():
		var rng := _rng(seed_value, i)
		out.append({"handle": handles[i], "hue": rng.randf(), "unseen": rng.randf() > 0.45})
	return out


## `count` photo posts. Each: author handle, caption, like count, an image hue +
## a second hue so the node can draw a procedural gradient "photo", and a `liked`
## flag the UI toggles on a double-tap. Authors cycle through the handles.
static func photo_posts(
	handles: PackedStringArray, seed_value: int, count: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if handles.is_empty():
		return out
	for i in count:
		var rng := _rng(seed_value, i)
		var handle := handles[i % handles.size()]
		(
			out
			. append(
				{
					"handle": handle,
					"caption": CAPTIONS[rng.randi() % CAPTIONS.size()],
					"likes": rng.randi_range(3, 4200),
					"hue": rng.randf(),
					"hue2": rng.randf(),
					"liked": false,
				}
			)
		)
	return out


## `count` text posts for Chirp. Each: author handle, body text, like + repost
## counts. Authors cycle through the handles; the body is a deterministic pick.
static func chirp_posts(
	handles: PackedStringArray, seed_value: int, count: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if handles.is_empty():
		return out
	for i in count:
		var rng := _rng(seed_value, i + 500)
		var handle := handles[i % handles.size()]
		(
			out
			. append(
				{
					"handle": handle,
					"text": CHIRPS[rng.randi() % CHIRPS.size()],
					"likes": rng.randi_range(0, 980),
					"reposts": rng.randi_range(0, 210),
				}
			)
		)
	return out


## Abbreviate a count the way social apps do: 1200 → "1.2k", 980 → "980".
static func format_count(n: int) -> String:
	if n < 1000:
		return str(n)
	return "%0.1fk" % (float(n) / 1000.0)
