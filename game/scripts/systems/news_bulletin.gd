class_name NewsBulletin
extends RefCounted
## Pure reactive-news model — turns the player's notable deeds (crimes, rampages,
## heists, clean escapes, stunts) into radio/TV headlines, so the world talks about
## YOU. A controller calls report() when something newsworthy happens; the radio's
## NEWS slot (RadioScheduler) pulls next_bulletin() for the anchor to read. Headline
## wording escalates with severity (a petty theft vs a city-wide manhunt).
##
## No nodes, no scene access, deterministic (templates chosen by severity, not RNG):
## a controller owns one and drains it, so the headline queue stays unit-tested
## headless (tests/unit/test_news_bulletin.gd).
##
## report(kind, severity, context): `severity` is 1..5 (clamped) and picks the
## wording tier; `context` fills {place} and {count} placeholders (defaults supplied).

## kind -> headline templates, ascending by severity. Index = min(severity-1, last).
const HEADLINES: Dictionary = {
	"crime":
	[
		"Petty crime reported in {place}.",
		"Armed robbery rocks {place}.",
		"Crime wave grips {place}.",
		"{place} on edge after a violent spree.",
		"City-wide manhunt underway across {place}.",
	],
	"rampage":
	[
		"Reports of gunfire in {place}.",
		"Streets clear as chaos erupts in {place}.",
		"{place} locked down amid a violent rampage.",
	],
	"heist":
	[
		"Bank alarm tripped in {place}.",
		"Daring daylight heist nets thousands in {place}.",
		"Brazen vault robbery stuns {place}.",
		"Record-breaking heist baffles {place} police.",
		"The heist of the century leaves {place} reeling.",
	],
	"spree":
	[
		"Police link a suspect to {count} incident(s).",
		"Crime spree: {count} offences and counting.",
		"A {count}-crime rampage shocks the city.",
	],
	"escape":
	[
		"A suspect slips the police cordon.",
		"Wanted fugitive vanishes into the night.",
		"Manhunt called off — suspect still at large.",
	],
	"stunt":
	[
		"Daredevil stunt caught on camera in {place}.",
		"A wild jump stuns onlookers in {place}.",
	],
}

## Generic line for the news slot when nothing newsworthy is queued.
const FILLER: String = "And now the weather: another sunny day on the coast."

## How many pending bulletins to hold before dropping the oldest.
const MAX_QUEUE: int = 12

## FIFO of pending {kind, severity, text} bulletins.
var _queue: Array = []


## Every recognised event kind.
func kinds() -> Array:
	return HEADLINES.keys()


## Report a newsworthy event, enqueuing a headline. severity is clamped to 1..5;
## context may carry "place" (default "the city") and "count" (default 0). Returns
## the headline text, or "" for an unknown kind.
func report(kind: String, severity: int, context: Dictionary = {}) -> String:
	if not HEADLINES.has(kind):
		return ""
	var templates: Array = HEADLINES[kind]
	var idx := clampi(severity - 1, 0, templates.size() - 1)
	var text: String = (
		String(templates[idx])
		. format(
			{
				"place": str(context.get("place", "the city")),
				"count": int(context.get("count", 0)),
			}
		)
	)
	_queue.append({"kind": kind, "severity": clampi(severity, 1, 5), "text": text})
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	return text


func has_pending() -> bool:
	return not _queue.is_empty()


func pending_count() -> int:
	return _queue.size()


## Pull the next headline for the news anchor (FIFO). Returns FILLER when nothing is
## queued, so the slot always has something to read.
func next_bulletin() -> String:
	if _queue.is_empty():
		return FILLER
	var item: Dictionary = _queue.pop_front()
	return item["text"]


## The most recently reported headline still in the queue, or "" if empty.
func peek_latest() -> String:
	if _queue.is_empty():
		return ""
	return _queue.back()["text"]


## Up to `limit` of the most recent queued headlines (newest first).
func recent(limit: int) -> Array:
	var out: Array = []
	var i := _queue.size() - 1
	while i >= 0 and out.size() < limit:
		out.append(_queue[i]["text"])
		i -= 1
	return out


## Drop all pending bulletins.
func clear() -> void:
	_queue.clear()
