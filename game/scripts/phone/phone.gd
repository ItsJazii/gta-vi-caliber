class_name Phone
extends CanvasLayer
## The player's in-world smartphone: raise it, scroll social feeds, and call NPC
## friends — all drawn procedurally (no UI assets), animated, and mouse-driven.
##
## State lives here; the *decisions* (scroll inertia, call progression, layout
## maths) are delegated to PhoneModel / SocialFeed / PhoneContacts (pure, tested).
## The device is added in code by the Player (like FootstepAudio) so it stays
## self-contained and doesn't collide with parallel edits to player.tscn. A child
## Control does the drawing via its `draw` signal so this CanvasLayer can own all
## the state in one place.
##
## Controls: the "phone" action raises/lowers it; while up the mouse is freed so
## the look-camera (which gates on a captured mouse) holds still. Mouse wheel or
## click-drag scrolls with kinetic momentum; click an app to open it, a contact
## to call, the red button to hang up; Esc backs out an app or pockets the phone.

## Emitted when the phone is raised (true) or pocketed (false). Player listens to
## drive the holding pose, the hand prop, and the walk-only speed clamp.
signal active_changed(active: bool)
## Emitted the moment a call connects to a friend, with their display name. Lets
## a Pedestrian of the same name in the world react (wave, stop) if one is near.
signal friend_called(name: String)
## Emitted when a connected service contact successfully takes a paid request.
## Player handles the immediate effect; future systems can listen for drops/spawns.
signal service_requested(id: String, kind: String, contact: String, cost: int)

## Fixed seeds so the generated feeds are stable across a session/run.
const PHOTO_SEED: int = 20260610
const CHIRP_SEED: int = 77

## Design-space device size (px); scaled to fit the viewport height at runtime.
const BODY_W: float = 380.0
const BODY_H: float = 760.0

## How long the raise/lower slide takes (s) and the app-open slide (s).
const OPEN_TIME: float = 0.26
const APP_TIME: float = 0.22

## Decorative-only home tiles (no app behind them) rounding out the launcher.
const DECOR_APPS: Array[Dictionary] = [
	{"label": "Camera", "hue": 0.58},
	{"label": "Maps", "hue": 0.32},
	{"label": "Music", "hue": 0.85},
	{"label": "Weather", "hue": 0.55},
	{"label": "Clock", "hue": 0.0},
	{"label": "Settings", "hue": 0.62},
]

var _view: Control
var _font: Font
var _active: bool = false
var _open: float = 0.0

var _app: int = PhoneModel.App.HOME
var _app_anim: float = 1.0

var _photos: Array[Dictionary] = []
var _chirps: Array[Dictionary] = []
var _stories: Array[Dictionary] = []

var _scroll_offset: float = 0.0
var _scroll_velocity: float = 0.0
var _content_h: float = 0.0
var _view_h: float = 1.0

var _dragging: bool = false
var _press_screen: Vector2 = Vector2.ZERO
var _press_offset: float = 0.0
var _moved: bool = false

var _call_state: int = PhoneModel.Call.IDLE
var _call_elapsed: float = 0.0
var _call_contact: Dictionary = {}
var _call_service_id: String = ""
var _service_fired_for_call: bool = false
var _service_message: String = ""
var _service_message_ok: bool = false
var _anim_clock: float = 0.0
var _shake: float = 0.0
var _services: ContactServices

# Layout, recomputed each frame so draw and hit-testing share one geometry.
var _screen_rect: Rect2 = Rect2()
var _content_rect: Rect2 = Rect2()
var _scale: float = 1.0
var _hotspots: Array[Dictionary] = []


func _ready() -> void:
	layer = 30
	_services = ContactServices.new()
	_font = ThemeDB.fallback_font
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_render)
	add_child(_view)
	_generate_feeds()
	_view.visible = false


## True while the phone is raised. Player polls/observes this to gate sprint etc.
func is_active() -> bool:
	return _active


func _generate_feeds() -> void:
	var handles := PhoneContacts.handles()
	_photos = SocialFeed.photo_posts(handles, PHOTO_SEED, 14)
	_chirps = SocialFeed.chirp_posts(handles, CHIRP_SEED, 16)
	_stories = SocialFeed.stories(handles, PHOTO_SEED)


# ---------------------------------------------------------------- input -------


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _active:
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		if _press_screen.distance_to(_view.get_global_mouse_position()) > 8.0:
			_moved = true
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_active = not _active
	if _active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_view.visible = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_end_call()
		_app = PhoneModel.App.HOME
	active_changed.emit(_active)


# Esc / right-equivalent: back out of an open app, or pocket the phone at home.
func _back() -> void:
	if _app == PhoneModel.App.CALL:
		_end_call()
		_open_app(PhoneModel.App.CONTACTS)
	elif _app != PhoneModel.App.HOME:
		_open_app(PhoneModel.App.HOME)
	else:
		_toggle()


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_scroll_velocity -= 900.0
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_scroll_velocity += 900.0
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
			_moved = false
			_press_screen = _view.get_global_mouse_position()
			_press_offset = _scroll_offset
		else:
			if not _moved:
				_tap(_view.get_global_mouse_position())
			_dragging = false


# A tap (press+release without dragging) dispatches the hotspot under it.
func _tap(pos: Vector2) -> void:
	for h in _hotspots:
		if (h["rect"] as Rect2).has_point(pos):
			_dispatch(h)
			return


func _dispatch(hot: Dictionary) -> void:
	match hot["kind"]:
		"app":
			_open_app(hot["i"])
		"home":
			_open_app(PhoneModel.App.HOME)
		"contact":
			_start_call(hot["i"])
		"endcall":
			_back()
		"like":
			_photos[hot["i"]]["liked"] = not _photos[hot["i"]]["liked"]


func _open_app(app: int) -> void:
	_app = app
	_app_anim = 0.0
	_scroll_offset = 0.0
	_scroll_velocity = 0.0


# ----------------------------------------------------------------- calls ------


func _start_call(roster_index: int) -> void:
	var roster := PhoneContacts.roster()
	if roster_index < 0 or roster_index >= roster.size():
		return
	_call_contact = roster[roster_index]
	_call_service_id = _services.id_for_contact(String(_call_contact.get("name", "")))
	_service_fired_for_call = false
	_service_message = ""
	_service_message_ok = false
	_call_state = PhoneModel.Call.DIALING
	_call_elapsed = 0.0
	_shake = 0.6
	_open_app(PhoneModel.App.CALL)


func _end_call() -> void:
	_call_state = PhoneModel.Call.IDLE
	_call_elapsed = 0.0
	_call_service_id = ""
	_service_fired_for_call = false
	_service_message = ""


func _advance_call(delta: float) -> void:
	if _call_state == PhoneModel.Call.IDLE or _call_state == PhoneModel.Call.ENDED:
		return
	_call_elapsed += delta
	var ring := PhoneContacts.ring_seconds(_call_contact)
	var answers := PhoneContacts.will_answer(_call_contact)
	var next := PhoneModel.advance_call(_call_state, _call_elapsed, answers, ring)
	if next != _call_state:
		_call_state = next
		_call_elapsed = 0.0
		_shake = 0.5
		if next == PhoneModel.Call.CONNECTED:
			_on_call_connected()


func _on_call_connected() -> void:
	friend_called.emit(_call_contact.get("name", ""))
	_try_request_service()


func _try_request_service() -> void:
	if _call_service_id.is_empty() or _service_fired_for_call:
		return
	_service_fired_for_call = true
	var stats := _player_stats()
	var balance := int(stats.money) if stats != null and ("money" in stats) else 0
	var result := _services.request(_call_service_id, _service_now(), balance, true)
	if not bool(result.get("success", false)):
		_service_message = String(result.get("reason", "service unavailable"))
		_service_message_ok = false
		return
	var cost := int(result.get("cost", 0))
	if stats == null or not stats.has_method("spend_money") or not stats.spend_money(cost):
		_service_message = "wallet unavailable"
		_service_message_ok = false
		return
	var kind := String(result.get("kind", ""))
	var contact := String(_call_contact.get("name", ""))
	_apply_service_effect(kind)
	service_requested.emit(_call_service_id, kind, contact, cost)
	_service_message = _service_success_line(kind, contact, cost)
	_service_message_ok = true


func _player_stats() -> Node:
	return get_tree().get_first_node_in_group("player_stats")


func _service_now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _apply_service_effect(kind: String) -> void:
	match kind:
		"heat":
			var tracker := get_tree().get_first_node_in_group("wanted")
			if tracker != null and tracker.has_method("clear"):
				tracker.clear()


func _service_success_line(kind: String, contact: String, cost: int) -> String:
	match kind:
		"heat":
			return "%s cooled the heat ($%d)." % [contact, cost]
		"vehicle":
			return "%s patched up your ride ($%d)." % [contact, cost]
		"weapons":
			return "%s marked a drop ($%d)." % [contact, cost]
		"transport":
			return "%s is lining up transport ($%d)." % [contact, cost]
		"combat":
			return "%s is calling backup ($%d)." % [contact, cost]
		_:
			return "%s is handling it ($%d)." % [contact, cost]


# ---------------------------------------------------------------- process -----


func _process(delta: float) -> void:
	_open = move_toward(_open, 1.0 if _active else 0.0, delta / OPEN_TIME)
	if _open <= 0.0 and not _active:
		_view.visible = false
		return
	_view.visible = true
	_anim_clock += delta
	_app_anim = minf(_app_anim + delta / APP_TIME, 1.0)
	_shake = maxf(_shake - delta * 2.5, 0.0)

	if _app == PhoneModel.App.CALL:
		_advance_call(delta)

	_update_scroll(delta)
	_view.queue_redraw()


func _update_scroll(delta: float) -> void:
	if _dragging:
		var prev := _scroll_offset
		var pointer_dy := _press_screen.y - _view.get_global_mouse_position().y
		_scroll_offset = PhoneModel.clamp_offset(_press_offset + pointer_dy, _content_h, _view_h)
		_scroll_velocity = (_scroll_offset - prev) / maxf(delta, 0.0001)
	else:
		var r := PhoneModel.integrate_scroll(
			_scroll_offset, _scroll_velocity, _content_h, _view_h, delta
		)
		_scroll_offset = r["offset"]
		_scroll_velocity = r["velocity"]


# ----------------------------------------------------------------- render -----


# Eased open with a small overshoot so the phone pops into the hand.
func _eased_open() -> float:
	var t := clampf(_open, 0.0, 1.0)
	var s := 1.70158
	var u := t - 1.0
	return 1.0 + (s + 1.0) * u * u * u + s * u * u


func _layout() -> void:
	var vp := _view.size
	_scale = clampf(vp.y * 0.94 / BODY_H, 0.45, 1.25)
	var bw := BODY_W * _scale
	var bh := BODY_H * _scale
	var rest_y := vp.y - bh - 8.0 * _scale
	var hidden_y := vp.y + 30.0
	var y := lerpf(hidden_y, rest_y, _eased_open())
	y += sin(_anim_clock * 1.3) * 3.0 * _scale * _open  # idle hand bob
	var x := (vp.x - bw) * 0.5 + sin(_shake * 40.0) * _shake * 8.0
	var bezel := 13.0 * _scale
	var body := Rect2(x, y, bw, bh)
	_screen_rect = Rect2(
		body.position + Vector2(bezel, bezel), body.size - Vector2(bezel, bezel) * 2.0
	)
	var topbar := 40.0 * _scale
	var botbar := 30.0 * _scale
	_content_rect = Rect2(
		_screen_rect.position + Vector2(0.0, topbar),
		Vector2(_screen_rect.size.x, _screen_rect.size.y - topbar - botbar)
	)
	_view_h = _content_rect.size.y


func _render() -> void:
	_layout()
	_hotspots = []
	var body := _screen_rect.grow(13.0 * _scale)
	# Drop shadow + aluminium body.
	_round_rect(body.grow(6.0 * _scale), Color(0, 0, 0, 0.35 * _open), 44.0 * _scale)
	_round_rect(body, Color(0.04, 0.04, 0.05), 40.0 * _scale, 2.0 * _scale, Color(0.2, 0.2, 0.24))
	_round_rect(_screen_rect, Color(0.07, 0.07, 0.09), 28.0 * _scale)

	match _app:
		PhoneModel.App.PHOTOS:
			_render_scrollable(Callable(self, "_build_photos"))
		PhoneModel.App.CHIRP:
			_render_scrollable(Callable(self, "_build_chirp"))
		PhoneModel.App.CONTACTS:
			_render_scrollable(Callable(self, "_build_contacts"))
		PhoneModel.App.CALL:
			_render_call()
		_:
			_render_home()
	_render_chrome()


# Status bar (top) + home indicator (bottom). Drawn last so feed overflow at the
# screen's rounded edges is masked behind the device chrome.
func _render_chrome() -> void:
	var top := Rect2(_screen_rect.position, Vector2(_screen_rect.size.x, 40.0 * _scale))
	_round_rect(top, Color(0.07, 0.07, 0.09), 0.0)
	var clock := "9:41"
	_text(top.position + Vector2(18.0 * _scale, 26.0 * _scale), clock, 15, Color(1, 1, 1, 0.9))
	# Battery pill, top-right.
	var bat := Rect2(
		top.end - Vector2(40.0 * _scale, 26.0 * _scale), Vector2(22.0 * _scale, 11.0 * _scale)
	)
	_round_rect(bat, Color(1, 1, 1, 0.85), 3.0 * _scale)
	# Home indicator bar.
	var hb_w := _screen_rect.size.x * 0.32
	var hb := Rect2(
		Vector2(
			_screen_rect.position.x + (_screen_rect.size.x - hb_w) * 0.5,
			_screen_rect.end.y - 16.0 * _scale
		),
		Vector2(hb_w, 5.0 * _scale)
	)
	_round_rect(hb, Color(1, 1, 1, 0.5), 3.0 * _scale)


# ------------------------------------------------------------------ home ------


func _render_home() -> void:
	# Wallpaper gradient.
	for i in 8:
		var f := float(i) / 7.0
		var band := Rect2(
			_screen_rect.position + Vector2(0.0, _screen_rect.size.y * f / 1.0),
			Vector2(_screen_rect.size.x, _screen_rect.size.y / 7.0 + 1.0)
		)
		_view.draw_rect(band, Color.from_hsv(0.62 - f * 0.15, 0.55, lerpf(0.32, 0.08, f)))
	# Big clock.
	_text(
		_content_rect.position + Vector2(0.0, 70.0 * _scale),
		"9:41",
		int(58 * _scale),
		Color(1, 1, 1, 0.95),
		HORIZONTAL_ALIGNMENT_CENTER,
		_content_rect.size.x
	)
	_text(
		_content_rect.position + Vector2(0.0, 100.0 * _scale),
		"Tuesday, June 10",
		int(15 * _scale),
		Color(1, 1, 1, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER,
		_content_rect.size.x
	)
	_render_app_grid()


func _render_app_grid() -> void:
	var cols := 4
	var area := _content_rect
	var gap := 16.0 * _scale
	var icon := (area.size.x - gap * float(cols + 1)) / float(cols)
	var top := area.position.y + 150.0 * _scale
	var apps := _all_home_apps()
	for idx in apps.size():
		var col := idx % cols
		var row := idx / cols
		var pos := Vector2(
			area.position.x + gap + float(col) * (icon + gap),
			top + float(row) * (icon + 34.0 * _scale)
		)
		var rect := Rect2(pos, Vector2(icon, icon))
		var app: Dictionary = apps[idx]
		_draw_app_icon(rect, app)
		if app.has("app"):
			_hotspots.append({"rect": rect, "kind": "app", "i": app["app"]})
	# Dock strip.
	var dock := Rect2(
		Vector2(area.position.x + gap, area.end.y - icon - gap),
		Vector2(area.size.x - gap * 2.0, icon + gap * 0.5)
	)
	_round_rect(dock, Color(1, 1, 1, 0.08), 26.0 * _scale)


func _all_home_apps() -> Array[Dictionary]:
	# Functional apps first, then decorative tiles to fill the launcher out.
	var out: Array[Dictionary] = PhoneModel.HOME_APPS.duplicate(true)
	out.append_array(DECOR_APPS)
	return out


func _draw_app_icon(rect: Rect2, app: Dictionary) -> void:
	var hue: float = app["hue"]
	var top := Color.from_hsv(hue, 0.65, 0.95)
	var bot := Color.from_hsv(fmod(hue + 0.07, 1.0), 0.8, 0.7)
	_gradient_rect(rect, top, bot, 16.0 * _scale)
	var label: String = app["label"]
	_text(
		rect.position + Vector2(0.0, rect.size.y * 0.62),
		label.substr(0, 1).to_upper(),
		int(rect.size.y * 0.5),
		Color(1, 1, 1, 0.95),
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x
	)
	_text(
		Vector2(rect.position.x, rect.end.y + 15.0 * _scale),
		label,
		int(12 * _scale),
		Color(1, 1, 1, 0.85),
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x
	)


# ------------------------------------------------------- scrollable apps ------


# Shared scaffold for the scrolling apps: title bar, a clipped content pass
# (slid in on app-open and offset by the live scroll), and the back chevron.
# `builder` is a Callable(top_y: float) -> float returning total content height.
func _render_scrollable(builder: Callable) -> void:
	var slide := (1.0 - _ease_app()) * 36.0 * _scale
	_view.draw_set_transform(Vector2(slide, 0.0), 0.0, Vector2.ONE)
	var start_y := _content_rect.position.y - _scroll_offset
	_content_h = builder.call(start_y)
	_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_title_bar(_app_title())


func _app_title() -> String:
	match _app:
		PhoneModel.App.PHOTOS:
			return "Instasnap"
		PhoneModel.App.CHIRP:
			return "Chirp"
		PhoneModel.App.CONTACTS:
			return "Contacts"
		_:
			return ""


func _draw_title_bar(title: String) -> void:
	var bar := Rect2(
		_screen_rect.position + Vector2(0.0, 40.0 * _scale),
		Vector2(_screen_rect.size.x, 38.0 * _scale)
	)
	_round_rect(bar, Color(0.1, 0.1, 0.13), 0.0)
	_view.draw_line(bar.position + Vector2(0.0, bar.size.y), bar.end, Color(1, 1, 1, 0.08), 1.0)
	_text(
		bar.position + Vector2(0.0, 26.0 * _scale),
		title,
		int(17 * _scale),
		Color(1, 1, 1, 0.95),
		HORIZONTAL_ALIGNMENT_CENTER,
		bar.size.x
	)
	# Back chevron hotspot, top-left.
	var back := Rect2(
		bar.position + Vector2(6.0 * _scale, 4.0 * _scale), Vector2(34.0 * _scale, 30.0 * _scale)
	)
	_text(
		back.position + Vector2(10.0 * _scale, 22.0 * _scale),
		"<",
		int(20 * _scale),
		Color(0.6, 0.8, 1.0)
	)
	_hotspots.append({"rect": back, "kind": "home", "i": 0})


func _ease_app() -> float:
	var t := clampf(_app_anim, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


# Returns true if a row at [y, y+h] is at all visible in the content window.
func _row_visible(y: float, h: float) -> bool:
	return y + h >= _content_rect.position.y and y <= _content_rect.end.y


func _build_photos(start_y: float) -> float:
	var x := _content_rect.position.x
	var w := _content_rect.size.x
	var y := start_y + 8.0 * _scale
	y = _draw_stories(x, y, w)
	for i in _photos.size():
		var card_h := w + 78.0 * _scale  # square photo + header + actions
		if _row_visible(y, card_h):
			_draw_photo_card(Rect2(Vector2(x, y), Vector2(w, card_h)), i)
		y += card_h + 8.0 * _scale
	return y - start_y


func _draw_stories(x: float, y: float, w: float) -> float:
	var d := 54.0 * _scale
	var pad := 12.0 * _scale
	var cx := x + pad + d * 0.5
	for s in _stories:
		if cx < x + w:
			var center := Vector2(cx, y + pad + d * 0.5)
			var ring: Color = (
				Color.from_hsv(s["hue"], 0.8, 1.0) if s["unseen"] else Color(0.3, 0.3, 0.34)
			)
			_view.draw_arc(center, d * 0.5 + 3.0 * _scale, 0.0, TAU, 32, ring, 2.5 * _scale)
			_view.draw_circle(center, d * 0.5, Color.from_hsv(s["hue"], 0.55, 0.55))
			_text(
				Vector2(cx - d * 0.5, y + d + pad + 12.0 * _scale),
				String(s["handle"]).substr(0, 7),
				int(10 * _scale),
				Color(1, 1, 1, 0.7),
				HORIZONTAL_ALIGNMENT_CENTER,
				d
			)
		cx += d + pad
	return y + d + pad * 2.0 + 8.0 * _scale


func _draw_photo_card(rect: Rect2, index: int) -> void:
	var post := _photos[index]
	var hdr := 42.0 * _scale
	# Header: avatar + handle.
	_view.draw_circle(
		rect.position + Vector2(22.0 * _scale, hdr * 0.5),
		13.0 * _scale,
		Color.from_hsv(post["hue"], 0.6, 0.7)
	)
	_text(
		rect.position + Vector2(42.0 * _scale, hdr * 0.62),
		String(post["handle"]),
		int(13 * _scale),
		Color(1, 1, 1, 0.95)
	)
	# Photo (procedural diagonal gradient).
	var photo := Rect2(rect.position + Vector2(0.0, hdr), Vector2(rect.size.x, rect.size.x))
	_gradient_rect(
		photo, Color.from_hsv(post["hue"], 0.7, 0.95), Color.from_hsv(post["hue2"], 0.8, 0.5), 0.0
	)
	# Actions row: heart + like count.
	var ay := photo.end.y + 22.0 * _scale
	var heart := Rect2(
		rect.position + Vector2(12.0 * _scale, ay - 16.0 * _scale),
		Vector2(28.0 * _scale, 28.0 * _scale)
	)
	var liked: bool = post["liked"]
	_view.draw_circle(
		heart.get_center(), 9.0 * _scale, Color(0.95, 0.2, 0.3) if liked else Color(1, 1, 1, 0.85)
	)
	_hotspots.append({"rect": heart, "kind": "like", "i": index})
	var likes: int = post["likes"] + (1 if liked else 0)
	_text(
		rect.position + Vector2(46.0 * _scale, ay + 4.0 * _scale),
		"%s likes" % SocialFeed.format_count(likes),
		int(12 * _scale),
		Color(1, 1, 1, 0.85)
	)
	_text(
		rect.position + Vector2(12.0 * _scale, ay + 26.0 * _scale),
		"%s  %s" % [String(post["handle"]), String(post["caption"])],
		int(12 * _scale),
		Color(1, 1, 1, 0.75),
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 24.0 * _scale
	)


func _build_chirp(start_y: float) -> float:
	var x := _content_rect.position.x
	var w := _content_rect.size.x
	var y := start_y + 6.0 * _scale
	for post in _chirps:
		var h := 92.0 * _scale
		if _row_visible(y, h):
			_draw_chirp_row(Rect2(Vector2(x, y), Vector2(w, h)), post)
		y += h
	return y - start_y


func _draw_chirp_row(rect: Rect2, post: Dictionary) -> void:
	_view.draw_line(rect.position + Vector2(0.0, rect.size.y), rect.end, Color(1, 1, 1, 0.07), 1.0)
	_view.draw_circle(
		rect.position + Vector2(28.0 * _scale, 26.0 * _scale),
		15.0 * _scale,
		Color.from_hsv(SocialFeed.format_count(post["likes"]).length() / 6.0, 0.5, 0.65)
	)
	_text(
		rect.position + Vector2(52.0 * _scale, 24.0 * _scale),
		"@%s" % String(post["handle"]),
		int(13 * _scale),
		Color(1, 1, 1, 0.95)
	)
	_text(
		rect.position + Vector2(52.0 * _scale, 46.0 * _scale),
		String(post["text"]),
		int(13 * _scale),
		Color(1, 1, 1, 0.82),
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 64.0 * _scale
	)
	_text(
		rect.position + Vector2(52.0 * _scale, rect.size.y - 12.0 * _scale),
		(
			"♡ %s   ⇄ %s"
			% [SocialFeed.format_count(post["likes"]), SocialFeed.format_count(post["reposts"])]
		),
		int(11 * _scale),
		Color(1, 1, 1, 0.5)
	)


func _build_contacts(start_y: float) -> float:
	var x := _content_rect.position.x
	var w := _content_rect.size.x
	var y := start_y + 6.0 * _scale
	var roster := PhoneContacts.roster()
	for i in roster.size():
		var h := 64.0 * _scale
		var rect := Rect2(Vector2(x, y), Vector2(w, h))
		if _row_visible(y, h):
			_draw_contact_row(rect, roster[i])
		_hotspots.append({"rect": rect, "kind": "contact", "i": i})
		y += h
	return y - start_y


func _draw_contact_row(rect: Rect2, contact: Dictionary) -> void:
	_view.draw_line(rect.position + Vector2(0.0, rect.size.y), rect.end, Color(1, 1, 1, 0.07), 1.0)
	var center := rect.position + Vector2(34.0 * _scale, rect.size.y * 0.5)
	_view.draw_circle(center, 18.0 * _scale, Color.from_hsv(contact["hue"], 0.6, 0.7))
	_text(
		center + Vector2(-9.0 * _scale, 6.0 * _scale),
		String(contact["name"]).substr(0, 1),
		int(16 * _scale),
		Color(1, 1, 1, 0.95)
	)
	_text(
		rect.position + Vector2(64.0 * _scale, rect.size.y * 0.45),
		String(contact["name"]),
		int(15 * _scale),
		Color(1, 1, 1, 0.95)
	)
	var online: bool = contact["status"] == PhoneContacts.ONLINE
	_text(
		rect.position + Vector2(64.0 * _scale, rect.size.y * 0.72),
		_contact_subtitle(contact),
		int(11 * _scale),
		Color(0.4, 0.85, 0.45) if online else Color(1, 1, 1, 0.45)
	)
	# Green call glyph on the right.
	var dial := rect.position + Vector2(rect.size.x - 28.0 * _scale, rect.size.y * 0.5)
	_view.draw_circle(dial, 14.0 * _scale, Color(0.2, 0.75, 0.35))
	_text(dial + Vector2(-5.0 * _scale, 5.0 * _scale), "☎", int(13 * _scale), Color(1, 1, 1, 0.95))


func _contact_subtitle(contact: Dictionary) -> String:
	var label := PhoneContacts.presence_label(contact)
	if _services == null:
		return label
	var id := _services.id_for_contact(String(contact.get("name", "")))
	if id.is_empty():
		return label
	return "%s · %s $%d" % [label, _service_label(_services.kind_of(id)), _services.cost_of(id)]


func _service_label(kind: String) -> String:
	match kind:
		"heat":
			return "clear heat"
		"vehicle":
			return "mechanic"
		"weapons":
			return "drop"
		"transport":
			return "ride"
		"combat":
			return "backup"
		_:
			return "favor"


# ------------------------------------------------------------------ call ------


func _render_call() -> void:
	_content_h = 0.0
	var area := _screen_rect
	# Vignette over the screen.
	_round_rect(
		Rect2(
			area.position + Vector2(0.0, 40.0 * _scale),
			Vector2(area.size.x, area.size.y - 40.0 * _scale)
		),
		Color.from_hsv(_call_contact.get("hue", 0.6), 0.35, 0.16),
		0.0
	)
	var center := Vector2(area.position.x + area.size.x * 0.5, area.position.y + area.size.y * 0.34)
	var base_r := 52.0 * _scale
	# Expanding rings while connecting/ringing.
	if _call_state == PhoneModel.Call.DIALING or _call_state == PhoneModel.Call.RINGING:
		for k in 3:
			var phase := fmod(_anim_clock * 0.8 + float(k) / 3.0, 1.0)
			_view.draw_arc(
				center,
				base_r + phase * 70.0 * _scale,
				0.0,
				TAU,
				48,
				Color(1, 1, 1, (1.0 - phase) * 0.4),
				2.0 * _scale
			)
	var pulse := 1.0 + 0.04 * sin(_anim_clock * 5.0)
	_view.draw_circle(
		center, base_r * pulse, Color.from_hsv(_call_contact.get("hue", 0.6), 0.6, 0.7)
	)
	_text(
		center + Vector2(-base_r, base_r * 0.35),
		String(_call_contact.get("name", "?")).substr(0, 1),
		int(48 * _scale),
		Color(1, 1, 1, 0.95),
		HORIZONTAL_ALIGNMENT_CENTER,
		base_r * 2.0
	)
	_text(
		Vector2(area.position.x, center.y + base_r + 44.0 * _scale),
		String(_call_contact.get("name", "Unknown")),
		int(26 * _scale),
		Color(1, 1, 1, 0.97),
		HORIZONTAL_ALIGNMENT_CENTER,
		area.size.x
	)
	_text(
		Vector2(area.position.x, center.y + base_r + 74.0 * _scale),
		PhoneModel.call_status_text(_call_state, _call_elapsed),
		int(15 * _scale),
		Color(1, 1, 1, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER,
		area.size.x
	)
	if not _service_message.is_empty():
		_text(
			Vector2(area.position.x + 24.0 * _scale, center.y + base_r + 104.0 * _scale),
			_service_message,
			int(12 * _scale),
			Color(0.45, 1.0, 0.62, 0.9) if _service_message_ok else Color(1.0, 0.72, 0.58, 0.9),
			HORIZONTAL_ALIGNMENT_CENTER,
			area.size.x - 48.0 * _scale
		)
	# Red hang-up button.
	var hang := Vector2(area.position.x + area.size.x * 0.5, area.end.y - 70.0 * _scale)
	var hang_rect := Rect2(
		hang - Vector2(30.0 * _scale, 30.0 * _scale), Vector2(60.0 * _scale, 60.0 * _scale)
	)
	_view.draw_circle(hang, 30.0 * _scale, Color(0.85, 0.2, 0.2))
	_text(hang + Vector2(-9.0 * _scale, 8.0 * _scale), "☎", int(22 * _scale), Color(1, 1, 1, 0.95))
	_hotspots.append({"rect": hang_rect, "kind": "endcall", "i": 0})


# --------------------------------------------------------------- drawing ------


func _round_rect(
	rect: Rect2,
	color: Color,
	radius: float,
	border_w: float = 0.0,
	border_color: Color = Color(0, 0, 0, 0)
) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(maxf(radius, 0.0)))
	if border_w > 0.0:
		sb.set_border_width_all(int(border_w))
		sb.border_color = border_color
	sb.draw(_view.get_canvas_item(), rect)


# A vertical two-stop gradient, approximated by horizontal bands (StyleBoxFlat
# has no gradient and we keep zero shader/material assets).
func _gradient_rect(rect: Rect2, top: Color, bottom: Color, radius: float) -> void:
	var bands := 16
	for i in bands:
		var f := float(i) / float(bands - 1)
		var band := Rect2(
			rect.position + Vector2(0.0, rect.size.y * float(i) / float(bands)),
			Vector2(rect.size.x, rect.size.y / float(bands) + 1.0)
		)
		var r := radius if (i == 0 or i == bands - 1) else 0.0
		_round_rect(band, top.lerp(bottom, f), r)


func _text(
	pos: Vector2,
	content: String,
	size_px: int,
	color: Color,
	align: int = HORIZONTAL_ALIGNMENT_LEFT,
	width: float = -1.0
) -> void:
	_view.draw_string(_font, pos, content, align, width, maxi(size_px, 1), color)
