class_name WeaponWheel
extends Control
## GTA-style radial weapon selector. Hold the "weapon_wheel" action to open: the
## game slows, the cursor frees, and the carried weapons fan out in a ring. The
## slot the cursor points at highlights; releasing equips it. Observes the
## WeaponController via the "weapon_controller" group and only calls its public
## equip()/loadout() — no gameplay state of its own.
##
## Slot geometry and hit-testing come from HudFormat.wheel_slot* so drawing and
## selection agree and are unit-testable.

## Time scale while the wheel is open (slow-mo, like GTA's weapon select).
@export var open_time_scale: float = 0.25
## Cursor distance (px) from centre below which no slot is selected.
@export var dead_zone: float = 36.0
@export var ring_radius: float = 150.0

@export var dim_color: Color = Color(0, 0, 0, 0.45)
@export var slot_color: Color = Color(0.12, 0.14, 0.18, 0.9)
@export var slot_hover: Color = Color(0.95, 0.78, 0.3, 0.95)
@export var text_color: Color = Color(0.92, 0.93, 0.96)

var _controller: Node = null
var _open: bool = false
var _loadout: Array = []
var _hover: int = -1
var _prev_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	call_deferred("_bind")


func _bind() -> void:
	var found := get_tree().get_nodes_in_group("weapon_controller")
	if not found.is_empty():
		_controller = found[0]


func _process(_delta: float) -> void:
	if _controller == null:
		_bind()
		return
	if Input.is_action_just_pressed("weapon_wheel"):
		_open_wheel()
	elif Input.is_action_just_released("weapon_wheel"):
		_close_wheel()
	if _open:
		_hover = HudFormat.wheel_slot(
			get_global_mouse_position() - size * 0.5, _loadout.size(), dead_zone
		)
		queue_redraw()


func _open_wheel() -> void:
	if _controller == null or not _controller.has_method("loadout"):
		return
	_loadout = _controller.loadout()
	if _loadout.is_empty():
		return
	_open = true
	visible = true
	_hover = _controller.current_index() if _controller.has_method("current_index") else -1
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = open_time_scale
	queue_redraw()


func _close_wheel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Engine.time_scale = 1.0
	Input.mouse_mode = _prev_mouse_mode
	if _hover >= 0 and _controller != null and _controller.has_method("equip"):
		_controller.equip(_hover)


func _draw() -> void:
	if not _open:
		return
	var center := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), dim_color)
	var count := _loadout.size()
	draw_arc(center, ring_radius, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 2.0, true)

	var font := ThemeDB.fallback_font
	for i in range(count):
		var angle := HudFormat.wheel_slot_angle(i, count)
		var dir := Vector2(sin(angle), -cos(angle))
		var pos := center + dir * ring_radius
		var hovered := i == _hover
		var col := slot_hover if hovered else slot_color
		draw_circle(pos, 34.0 if hovered else 30.0, col)
		draw_arc(pos, 34.0 if hovered else 30.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 2.0, true)

		var entry: Dictionary = _loadout[i]
		var name_str := str(entry.get("name", "?"))
		var ammo_str := "%d/%d" % [int(entry.get("ammo", 0)), int(entry.get("reserve", 0))]
		var tc := Color(0.05, 0.05, 0.06) if hovered else text_color
		_draw_centered(font, pos + Vector2(0, -2), name_str, 13, tc)
		_draw_centered(font, pos + Vector2(0, 14), ammo_str, 11, tc * Color(1, 1, 1, 0.85))

	# Centre label: the hovered weapon, or a hint.
	var label := "WEAPONS"
	if _hover >= 0 and _hover < count:
		label = str(_loadout[_hover].get("name", ""))
	_draw_centered(font, center, label, 16, Color(0.95, 0.85, 0.4))


func _draw_centered(font: Font, at: Vector2, text: String, font_size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(
		font,
		at - Vector2(w * 0.5, -font_size * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		col
	)
