class_name CrimeReactionDirector
extends Node
## Self-wiring coordinator that makes the city REACT to the player's heat. It owns a
## NewsBulletin and a DistrictEconomy and wires both to the live `wanted` group: a
## rising wanted level files a severity-scaled news headline AND heats up the active
## district (dragging its real-estate desirability down), and that heat bleeds off
## over time. Complements MarketEventCoordinator, which reacts to the same signal on
## the stock side — together they cover news + real-estate + market off one hook,
## with no overlap.
##
## Follows the repo self-wiring pattern (cf. PaySprayShop): drop the node in a scene
## and it finds the wanted tracker by group. The owned models are unit-tested; this
## node's wiring is exercised by tests/crime_reaction_probe.gd.

## Crime heat added to the active district per extra wanted star gained.
@export var heat_per_star: float = 0.15
## Crime heat bled off the whole city per second.
@export var heat_decay_per_sec: float = 0.02
## District that takes the heat (a real scene updates this from player location).
@export var active_district: String = "downtown"
## At/above this many stars a crime reads as a full-blown rampage in the news.
@export var rampage_stars: int = 4

## Reactive radio/TV headlines. Public so a radio NEWS slot can drain it.
var news: NewsBulletin
## Living real-estate model. Public so a property UI can read desirability.
var districts: DistrictEconomy

var _last_stars: int = 0


func _init() -> void:
	news = NewsBulletin.new()
	districts = DistrictEconomy.new()


func _ready() -> void:
	# The wanted node may be added after us; wire on the next idle frame.
	call_deferred("_connect_wanted")


func _process(delta: float) -> void:
	if heat_decay_per_sec > 0.0 and delta > 0.0:
		districts.decay_all_heat(heat_decay_per_sec * delta)


func _connect_wanted() -> void:
	var tracker := get_tree().get_first_node_in_group("wanted")
	if tracker == null or not tracker.has_signal("stars_changed"):
		return
	tracker.connect("stars_changed", _on_stars_changed)
	if tracker.has_method("stars"):
		_last_stars = tracker.stars()


func _on_stars_changed(stars: int) -> void:
	if stars > _last_stars:
		var gained := stars - _last_stars
		districts.add_heat(active_district, heat_per_star * float(gained))
		var kind := "rampage" if stars >= rampage_stars else "crime"
		news.report(kind, stars, {"place": active_district})
	_last_stars = stars
