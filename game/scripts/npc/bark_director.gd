class_name BarkDirector
extends Node
## Drives ambient and reactive NPC barks for a living street.
##
## On a timer it floats an idle one-liner over a pedestrian; when the player
## opens fire (WeaponController.hit_confirmed) the nearest pedestrian shouts a
## panic line. Self-contained: finds pedestrians/player by group and the gunfire
## signal by group, and parents a billboarded Label3D to the speaker — so it
## needs no edits to the (busy) pedestrian script. Lines come from BarkPool
## (pure, tested).
##
## Labels are pooled: at most pool_size Label3Ds ever exist, reparented between
## speakers and reclaimed on expiry, instead of an allocate/free per bark. A
## label dies silently if its speaker despawns mid-bark; the pool just rebuilds.

@export var ambient_interval: float = 5.5
@export var bark_duration: float = 2.3
@export var bark_height: float = 2.15
@export var idle_color: Color = Color(0.9, 0.92, 1.0)
@export var flee_color: Color = Color(1.0, 0.8, 0.5)
@export var react_range: float = 30.0
## Hard cap on live bark labels; the oldest bark is stolen when it overflows.
@export var pool_size: int = 8

var _timer: float = 0.0
var _counter: int = 0
var _pool: Array[Label3D] = []
# Live barks, oldest first: {"label": Label3D, "left": float}.
var _active: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("bark_director")
	call_deferred("_bind")


func _bind() -> void:
	for controller in get_tree().get_nodes_in_group("weapon_controller"):
		if controller.has_signal("hit_confirmed"):
			controller.hit_confirmed.connect(_on_gunfire)


func _process(delta: float) -> void:
	_tick_active(delta)
	_timer += delta
	if _timer >= ambient_interval:
		_timer = 0.0
		_ambient_bark()


func _ambient_bark() -> void:
	var peds := get_tree().get_nodes_in_group("pedestrians")
	if peds.is_empty():
		return
	_counter += 1
	var ped := peds[_counter % peds.size()] as Node3D
	_bark(ped, BarkPool.line(BarkPool.Situation.IDLE, _counter), idle_color)


func _on_gunfire(_killed: bool) -> void:
	var ped := _nearest_pedestrian_to_player()
	if ped == null:
		return
	_counter += 1
	_bark(ped, BarkPool.line(BarkPool.Situation.FLEE, _counter), flee_color)


func _bark(ped: Node3D, text: String, color: Color) -> void:
	if ped == null or text == "":
		return
	var label := _acquire()
	label.text = text
	label.modulate = color
	var parent := label.get_parent()
	if parent != ped:
		if parent != null:
			parent.remove_child(label)
		ped.add_child(label)
	label.position = Vector3.UP * bark_height
	label.visible = true
	_active.append({"label": label, "left": bark_duration})


## Expire live barks and return their labels to the pool. Labels freed with a
## despawned speaker are validity-checked as Variants — a freed instance would
## blow up on a typed parameter before _release could test it.
func _tick_active(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[i]
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) <= 0.0:
			var label: Variant = entry["label"]
			if is_instance_valid(label):
				_release(label)
			_active.remove_at(i)


## A ready-to-use label: pooled if available, stolen from the oldest live bark
## at capacity, freshly built only when the pool has been thinned by despawns.
func _acquire() -> Label3D:
	while not _pool.is_empty():
		var pooled: Label3D = _pool.pop_back()
		if is_instance_valid(pooled):
			return pooled
	if _active.size() >= maxi(pool_size, 1):
		var oldest: Dictionary = _active.pop_front()
		var stolen: Variant = oldest["label"]
		if is_instance_valid(stolen):
			return stolen
	return _make_label()


## Park a label back in the pool (hidden, parented to the director). Labels
## freed with their speaker are simply dropped.
func _release(label: Label3D) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.visible = false
	var parent := label.get_parent()
	if parent != self:
		if parent != null:
			parent.remove_child(label)
		add_child(label)
	_pool.append(label)


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.006
	label.font_size = 32
	label.outline_size = 6
	return label


func _nearest_pedestrian_to_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var origin := (players[0] as Node3D).global_position
	var best: Node3D = null
	var best_distance := react_range
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var ped := node as Node3D
		if ped == null:
			continue
		var distance := origin.distance_to(ped.global_position)
		if distance < best_distance:
			best_distance = distance
			best = ped
	return best
