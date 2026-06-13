extends SceneTree
## Grand integration probe — boots several gameplay systems together in one mock
## tree and proves they react COHERENTLY to shared state, which the per-system
## probes don't cover. One wanted spike should, in a single beat, rally the stock
## market (MarketEventCoordinator), file a news headline + heat the district
## (CrimeReactionDirector), and let the score escalate (MusicDirector); then a
## completed HitContract should move the market. Scene-free (mock wanted/stats), so
## it's independent of miami.tscn. Run headless:
##   godot --headless --path game --script res://tests/systems_integration_probe.gd

const SETTLE_FRAMES: int = 3

var _market: MarketEventCoordinator = null
var _crime: CrimeReactionDirector = null
var _music: MusicDirector = null
var _hits: HitContract = null
var _mock: MockWanted = null
var _frames: int = 0


class MockWanted:
	extends Node
	signal stars_changed(stars: int)
	var _stars: int = 0

	func _ready() -> void:
		add_to_group("wanted")

	func stars() -> int:
		return _stars

	func escalate(to_stars: int) -> void:
		_stars = to_stars
		stars_changed.emit(to_stars)


func _initialize() -> void:
	_mock = MockWanted.new()
	root.add_child(_mock)
	_market = MarketEventCoordinator.new()
	root.add_child(_market)
	_crime = CrimeReactionDirector.new()
	root.add_child(_crime)
	_music = MusicDirector.new()
	_hits = HitContract.new()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	return _run()


func _run() -> bool:
	var reactions := _check_wanted_reactions()
	if reactions != "":
		return _fail(reactions)
	var hit := _check_hit_loop()
	if hit != "":
		return _fail(hit)
	return _pass()


# One wanted spike drives the market, the news/district, and the score together.
func _check_wanted_reactions() -> String:
	var base_defense := _market.market.price("merryweather")
	var base_heat := _crime.districts.heat_in(_crime.active_district)
	_mock.escalate(4)
	_music.update({"stars": 4, "in_combat": true}, 0.1)
	if _market.market.price("merryweather") <= base_defense:
		return "market did not rally defense stock on the wanted spike"
	if not _crime.news.has_pending():
		return "no news headline filed on the wanted spike"
	if _crime.districts.heat_in(_crime.active_district) <= base_heat:
		return "district did not heat on the wanted spike"
	if not _music.is_intense():
		return "score did not escalate on the wanted spike"
	return ""


# A completed assassination contract moves the live market.
func _check_hit_loop() -> String:
	var base_rival := _market.market.price("augury_air")
	_hits.accept("airline_war")
	var effect: Dictionary = _hits.complete()["market_effect"]
	_market.apply_hit_effect(effect)
	if _market.market.price("augury_air") <= base_rival:
		return "completed hit did not move the rival stock"
	return ""


func _pass() -> bool:
	print("systems integration probe: OK (market + news + district + score + hit react together)")
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("systems integration probe FAIL: %s" % reason)
	quit(1)
	return true
