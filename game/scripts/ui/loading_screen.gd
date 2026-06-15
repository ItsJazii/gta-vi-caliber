class_name LoadingScreen
extends CanvasLayer
## Full-screen loading cover shown while the spawn district builds on the main
## thread (native streaming module absent, so the build blocks frames). On top of
## a dusk gradient it runs a slideshow of Vice-City key art (assets/ui/loading),
## crossfading slowly between random pieces, with the game title, a real progress
## bar driven by DistrictLoader.build_progress, and rotating flavour lines. A
## dark scrim keeps the text legible over the art. If no art imports (or a cold
## cache), it silently falls back to the gradient-only cover. Dismissed on
## district_built, with a safety timeout so it never traps the player.
##
## UI only, never drives gameplay (docs/ARCHITECTURE.md).

const MAX_WAIT := 30.0
const FADE := 0.6
const TIP_INTERVAL := 2.5
const SLIDE_HOLD := 3.0  ## seconds a piece stays before the next crossfade starts
const SLIDE_FADE := 1.4  ## seconds each crossfade takes
const TIPS: Array[String] = [
	"WASD to move, Shift to sprint",
	"Press E to enter a car",
	"Hold V for weapons, Tab for the phone",
	"C looks behind you",
	"Press F3 for the geometry inspector",
]
## Key-art shown in the loading slideshow. Listed explicitly (not dir-scanned) so
## it works the same in the editor and an exported PCK; missing/uimported files
## are skipped at load time, so editing this list is all it takes to curate it.
const ART_DIR := "res://assets/ui/loading/"
const ART_FILES: Array[String] = [
	"pawn_crew.png",
	"crypto_atm.png",
	"news_anchor.png",
	"sheriff_gator.png",
	"suncoast_flood.png",
	"hurricane_supplies.png",
	"airboat_swamp.png",
	"retirement_scooter.png",
]

var _root: Control
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _status: Label
var _tip: Label
var _progress := 0.0
var _target := 0.0
var _done := false
var _elapsed := 0.0
var _tip_index := 0

var _photos: Array[Texture2D] = []
var _slide_holder: Control
var _slide_a: TextureRect
var _slide_b: TextureRect
var _front_is_a := true
var _order: Array[int] = []
var _order_pos := 0
var _slide_t := 0.0
var _slide_tween: Tween


## Connect to the loader that owns the build, before it starts emitting.
func bind(loader: Object) -> void:
	if loader.has_signal("build_progress"):
		loader.connect("build_progress", _on_progress)
	if loader.has_signal("district_built"):
		loader.connect("district_built", _on_built)


func _ready() -> void:
	layer = 200
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_root.add_child(_make_backdrop())

	_load_photos()
	if not _photos.is_empty():
		_build_slideshow()
		_root.add_child(_make_scrim())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "NEON BAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.86))
	_shadow(title)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "entering the city"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.86, 0.72, 0.72))
	_shadow(sub)
	vbox.add_child(sub)

	_status = _make_bottom_label(-64, -44, Color(0.92, 0.88, 0.88))
	_status.text = "Loading Miami..."
	_root.add_child(_status)

	_tip = _make_bottom_label(-40, -22, Color(0.78, 0.74, 0.80))
	_tip.text = TIPS[0]
	_root.add_child(_tip)

	_build_bar()


func _make_backdrop() -> TextureRect:
	# Dusk gradient (indigo to magenta to warm) from a gradient texture, so the
	# cover reads as Miami at dusk even when no key art imports.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.06, 0.05, 0.13))
	grad.add_point(0.55, Color(0.30, 0.10, 0.32))
	grad.set_color(1, Color(0.85, 0.40, 0.28))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	var bg := TextureRect.new()
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	return bg


func _load_photos() -> void:
	for file in ART_FILES:
		var path := ART_DIR + file
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex != null:
			_photos.append(tex)


func _build_slideshow() -> void:
	_slide_holder = Control.new()
	_slide_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slide_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_slide_holder)

	_slide_a = _make_slide()
	_slide_b = _make_slide()
	_slide_holder.add_child(_slide_a)
	_slide_holder.add_child(_slide_b)

	_reshuffle()
	_slide_a.texture = _photos[_next_index()]
	_slide_a.modulate.a = 1.0


func _make_slide() -> TextureRect:
	var rect := TextureRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	return rect


func _make_scrim() -> TextureRect:
	# Black, transparent in the upper-middle and heavier at top and bottom, so the
	# centred title and the bottom bar/tips stay readable over busy key art.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.45))
	grad.add_point(0.35, Color(0.0, 0.0, 0.0, 0.12))
	grad.add_point(0.7, Color(0.0, 0.0, 0.0, 0.20))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.72))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	var scrim := TextureRect.new()
	scrim.texture = tex
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return scrim


func _reshuffle() -> void:
	_order = []
	for i in _photos.size():
		_order.append(i)
	_order.shuffle()
	_order_pos = 0


func _next_index() -> int:
	if _order_pos >= _order.size():
		var last := _order[-1] if not _order.is_empty() else -1
		_reshuffle()
		# Avoid showing the same piece twice across the reshuffle boundary.
		if _photos.size() > 1 and _order[0] == last:
			_order.append(_order.pop_front())
	var idx := _order[_order_pos]
	_order_pos += 1
	return idx


func _advance_slide() -> void:
	var incoming := _slide_b if _front_is_a else _slide_a
	var outgoing := _slide_a if _front_is_a else _slide_b
	incoming.texture = _photos[_next_index()]
	incoming.modulate.a = 0.0
	_slide_holder.move_child(incoming, _slide_holder.get_child_count() - 1)

	_slide_tween = create_tween()
	_slide_tween.tween_property(incoming, "modulate:a", 1.0, SLIDE_FADE)
	_slide_tween.tween_callback(func() -> void: outgoing.modulate.a = 0.0)
	_front_is_a = not _front_is_a


func _shadow(label: Label) -> void:
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 2)


func _make_bottom_label(top: float, bottom: float, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = top
	label.offset_bottom = bottom
	label.add_theme_color_override("font_color", color)
	_shadow(label)
	return label


func _build_bar() -> void:
	_bar_track = ColorRect.new()
	_bar_track.color = Color(1.0, 1.0, 1.0, 0.12)
	_bar_track.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_track.offset_left = 120
	_bar_track.offset_right = -120
	_bar_track.offset_top = -88
	_bar_track.offset_bottom = -80
	_root.add_child(_bar_track)

	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(1.0, 0.55, 0.30, 1.0)
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_right = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_right = 0.0
	_bar_track.add_child(_bar_fill)


func _on_progress(done: int, total: int) -> void:
	if total > 0:
		_target = clampf(float(done) / float(total), 0.0, 1.0)


func _on_built(_buildings: int, _roads: int) -> void:
	_target = 1.0
	_done = true


func _process(delta: float) -> void:
	_elapsed += delta
	_progress = move_toward(_progress, _target, delta * 1.5)
	if _bar_track != null and _bar_fill != null:
		_bar_fill.offset_right = _bar_track.size.x * _progress
	if _status != null and not _done:
		_status.text = "Loading Miami...  %d%%" % int(_progress * 100.0)

	var wanted_tip := int(_elapsed / TIP_INTERVAL) % TIPS.size()
	if wanted_tip != _tip_index and _tip != null:
		_tip_index = wanted_tip
		_tip.text = TIPS[_tip_index]

	if _photos.size() > 1:
		_slide_t += delta
		var transitioning := _slide_tween != null and _slide_tween.is_running()
		if _slide_t >= SLIDE_HOLD + SLIDE_FADE and not transitioning:
			_slide_t = 0.0
			_advance_slide()

	if (_done and _progress >= 0.999) or _elapsed >= MAX_WAIT:
		_dismiss()


func _dismiss() -> void:
	set_process(false)
	if _status != null:
		_status.text = "Welcome to Miami"
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE)
	tween.tween_callback(queue_free)
