class_name GameHud
extends CanvasLayer
## The in-world GTA-style HUD: minimap, health/armor, weapon + ammo, money,
## clock, wanted stars and the objective tracker, plus the aiming crosshair.
##
## Pure observer. It locates every source by group and reads it — never writes
## gameplay state:
##   * HP        ← "player_health"  (changed signal + fraction()/is_dead())
##   * Armor/$/  ← "player_stats"   (PlayerStats signals)
##   * Stars     ← "wanted"         (WantedTracker.stars_changed)
##   * Weapon    ← "weapon_controller" (hud_state(), hit_confirmed)
##   * Time      ← "sky"            (SkyController.time_of_day)
##   * Position  ← "player"         (global_position, for objective distance)
## Anything absent simply renders blank, so the HUD degrades gracefully in
## partial scenes. The weapon switch wheel and phone are sibling overlays.

## Crosshair gap (px) at zero spread, and spread→px scale (mirrors WeaponHud).
@export var base_gap: float = 5.0
@export var spread_to_px: float = 1500.0
@export var hit_marker_decay: float = 3.0

var _weapons: Node = null
var _grenades: Node = null
var _health: Node = null
var _stats: Node = null
var _wanted: Node = null
var _sky: Node = null
var _player: Node3D = null

@onready var _crosshair: Crosshair = $Crosshair
@onready var _vitals: StatBars = $Vitals
@onready var _stars: WantedStars = $WantedStars
@onready var _money: Label = $TopRight/Money
@onready var _clock: Label = $TopRight/Clock
@onready var _phase: Label = $TopRight/Phase
@onready var _weapon_name: Label = $Weapon/Name
@onready var _ammo: Label = $Weapon/Ammo
@onready var _grenade_label: Label = $Weapon/Grenades
@onready var _objective_title: Label = $Quest/Margin/VBox/Title
@onready var _objective_dist: Label = $Quest/Margin/VBox/Distance
@onready var _quest_panel: Panel = $Quest
@onready var _wasted: Label = $Wasted


func _ready() -> void:
	add_to_group("game_hud")
	_crosshair.visible = false
	_ammo.text = ""
	_weapon_name.text = ""
	_grenade_label.text = ""
	_wasted.visible = false
	call_deferred("_bind")


func _bind() -> void:
	_weapons = _first("weapon_controller")
	_grenades = _first("grenade_thrower")
	_health = _first("player_health")
	_stats = _first("player_stats")
	_wanted = _first("wanted")
	_sky = _first("sky")
	_player = _first("player") as Node3D

	if _weapons != null and _weapons.has_signal("hit_confirmed"):
		_weapons.hit_confirmed.connect(_on_hit)
	if _health != null and _health.has_signal("changed"):
		_health.changed.connect(_on_health)
		_vitals.health = _health.fraction()
	if _stats != null:
		_stats.armor_changed.connect(_on_armor)
		_stats.money_changed.connect(_on_money)
		_stats.objective_changed.connect(func(_t, _w): _refresh_objective())
		_vitals.armor = PlayerStats.fraction(_stats.armor, _stats.max_armor)
		_on_money(_stats.money)
		_refresh_objective()
	else:
		_on_money(0)
		_refresh_objective()
	if _wanted != null and _wanted.has_signal("stars_changed"):
		_wanted.stars_changed.connect(_on_stars)
		_stars.stars = _wanted.stars()
	queue_redraw_widgets()


func _process(delta: float) -> void:
	_update_weapon(delta)
	_update_grenades()
	_update_clock()
	_update_objective_distance()
	_update_wasted()


# --- weapon + crosshair ---------------------------------------------------


func _update_weapon(delta: float) -> void:
	if _crosshair.hit_flash > 0.0:
		_crosshair.hit_flash = maxf(_crosshair.hit_flash - hit_marker_decay * delta, 0.0)
		_crosshair.queue_redraw()
	if _weapons == null:
		return
	var state: Dictionary = _weapons.hud_state()
	var armed: bool = state.get("armed", false)
	_crosshair.visible = armed
	if not armed:
		_ammo.text = ""
		_weapon_name.text = ""
		return
	_weapon_name.text = str(state.get("name", ""))
	_ammo.text = "%d / %d" % [int(state.get("ammo", 0)), int(state.get("reserve", 0))]
	_crosshair.gap = base_gap + float(state.get("spread", 0.0)) * spread_to_px
	_crosshair.queue_redraw()


func _on_hit(killed: bool) -> void:
	_crosshair.hit_flash = 1.0
	_crosshair.hit_kill = killed


# --- grenades -------------------------------------------------------------


func _update_grenades() -> void:
	if _grenades == null or not _grenades.has_method("grenade_count"):
		_grenade_label.text = ""
		return
	var count: int = _grenades.grenade_count()
	var maximum: int = _grenades.max_count() if _grenades.has_method("max_count") else count
	_grenade_label.text = "GRENADES  %d/%d" % [count, maximum]
	# Dim the line when the pouch is empty so it reads as unavailable.
	_grenade_label.modulate.a = 0.4 if count <= 0 else 0.92


# --- vitals / money / stars ----------------------------------------------


func _on_health(fraction: float) -> void:
	_vitals.health = fraction
	_vitals.queue_redraw()


func _on_armor(armor: float, max_armor: float) -> void:
	_vitals.armor = PlayerStats.fraction(armor, max_armor)
	_vitals.queue_redraw()


func _on_money(amount: int) -> void:
	_money.text = HudFormat.format_money(amount)


func _on_stars(count: int) -> void:
	_stars.stars = count
	_stars.queue_redraw()


# --- clock ----------------------------------------------------------------


func _update_clock() -> void:
	if _sky == null:
		return
	var tod: float = _sky.time_of_day
	_clock.text = HudFormat.format_clock(tod)
	_phase.text = HudFormat.day_phase(tod)


# --- objective ------------------------------------------------------------


func _refresh_objective() -> void:
	if _stats == null or _stats.objective_title == "":
		_quest_panel.visible = false
		return
	_quest_panel.visible = true
	_objective_title.text = _stats.objective_title


func _update_objective_distance() -> void:
	if (
		_stats == null
		or _player == null
		or not _stats.has_method("has_waypoint")
		or not _stats.has_waypoint()
	):
		_objective_dist.text = ""
		return
	var d := _player.global_position.distance_to(_stats.objective_waypoint)
	_objective_dist.text = HudFormat.format_distance(d)


# --- death overlay --------------------------------------------------------


func _update_wasted() -> void:
	var dead: bool = _health != null and _health.has_method("is_dead") and _health.is_dead()
	_wasted.visible = dead


# --- helpers --------------------------------------------------------------


func queue_redraw_widgets() -> void:
	_vitals.queue_redraw()
	_stars.queue_redraw()


func _first(group: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null
