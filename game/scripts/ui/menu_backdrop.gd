class_name MenuBackdrop
extends Control
## Procedural, zero-asset animated backdrop for the menus.
##
## Draws a dusk gradient sky, a slow sun, drifting haze bands and a parallax
## city skyline of extruded blocks with flickering windows. Pure drawing: it
## owns no gameplay state and is safe to drop into any Control. The silhouette
## is generated once from a fixed seed so it stays stable frame-to-frame while
## only light/animation phases advance.

const _SKY_BANDS: int = 48
const _LAYERS: int = 2

## Palette stops for the sky, top (zenith) to bottom (horizon glow).
@export var sky_top: Color = Color(0.07, 0.09, 0.18)
@export var sky_mid: Color = Color(0.36, 0.20, 0.34)
@export var sky_horizon: Color = Color(0.95, 0.55, 0.32)

## Skyline silhouette colours, far layer to near layer.
@export var city_far: Color = Color(0.12, 0.10, 0.20)
@export var city_near: Color = Color(0.04, 0.03, 0.08)

## Lit-window tint.
@export var window_color: Color = Color(1.0, 0.82, 0.45)

## Random seed for the skyline layout — change for a different city.
@export var seed: int = 60606

var _time: float = 0.0
# Per-layer building rectangles in normalised x (0..1) plus window grids,
# baked once in _ready so the skyline never reshuffles between frames.
var _layers: Array = []


func _ready() -> void:
	_bake_skyline()
	# Redraw continuously for the gentle ambient animation.
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _bake_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_layers.clear()
	for layer in range(_LAYERS):
		var near := float(layer) / float(maxi(_LAYERS - 1, 1))
		var buildings: Array = []
		var x := -0.05
		while x < 1.05:
			var w := rng.randf_range(0.04, 0.10) * (0.7 + near * 0.8)
			# Near layer is taller; far layer hugs the horizon.
			var h := rng.randf_range(0.10, 0.34) * (0.55 + near * 0.95)
			(
				buildings
				. append(
					{
						"x": x,
						"w": w,
						"h": h,
						"lit": rng.randf(),  # phase offset so windows flicker out of sync
					}
				)
			)
			x += w + rng.randf_range(0.004, 0.02)
		_layers.append(buildings)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	_draw_sky(w, h)
	_draw_sun(w, h)
	_draw_haze(w, h)
	_draw_skyline(w, h)


func _draw_sky(w: float, h: float) -> void:
	# Vertical gradient as stacked bands: top->mid over the upper half,
	# mid->horizon over the lower half.
	for i in range(_SKY_BANDS):
		var t := float(i) / float(_SKY_BANDS)
		var col: Color
		if t < 0.5:
			col = sky_top.lerp(sky_mid, t * 2.0)
		else:
			col = sky_mid.lerp(sky_horizon, (t - 0.5) * 2.0)
		draw_rect(Rect2(0.0, t * h, w, h / _SKY_BANDS + 1.0), col)


func _draw_sun(w: float, h: float) -> void:
	# A soft sun that bobs almost imperceptibly above the skyline.
	var cx := w * 0.5
	var cy := h * (0.60 + 0.01 * sin(_time * 0.2))
	var r := h * 0.16
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		var glow := sky_horizon.lerp(Color(1.0, 0.9, 0.7), 1.0 - f)
		glow.a = 0.10 * (1.0 - f) + 0.06
		draw_circle(Vector2(cx, cy), r * (1.0 + f * 2.2), glow)
	draw_circle(Vector2(cx, cy), r, Color(1.0, 0.85, 0.6, 0.95))


func _draw_haze(w: float, h: float) -> void:
	# Two slow horizontal haze bands drifting in opposite directions.
	for i in range(2):
		var y := h * (0.58 + i * 0.06)
		var drift := sin(_time * (0.15 + i * 0.05) + i) * 0.04
		var band := sky_horizon
		band.a = 0.12 - i * 0.04
		draw_rect(Rect2(-w * 0.1 + drift * w, y, w * 1.2, h * 0.05), band)


func _draw_skyline(w: float, h: float) -> void:
	var ground := h * 0.92
	for layer in range(_layers.size()):
		var near := float(layer) / float(maxi(_LAYERS - 1, 1))
		var base := city_far.lerp(city_near, near)
		# Subtle parallax sway per layer.
		var sway := sin(_time * 0.1 + layer) * w * 0.004 * (near + 0.3)
		for b in _layers[layer]:
			var bx: float = float(b["x"]) * w + sway
			var bw: float = float(b["w"]) * w
			var bh: float = float(b["h"]) * h
			var top: float = ground - bh
			draw_rect(Rect2(bx, top, bw, bh), base)
			_draw_windows(bx, top, bw, bh, float(b["lit"]), near)


func _draw_windows(bx: float, top: float, bw: float, bh: float, phase: float, near: float) -> void:
	# Skip the closest layer's interiors when buildings are tiny.
	if bw < 14.0 or bh < 26.0:
		return
	var cell := 7.0 + near * 3.0
	var pad := cell * 0.45
	var win := cell - pad
	var cols := int((bw - pad) / cell)
	var rows := int((bh - pad) / cell)
	var lit := window_color
	for r in range(rows):
		for c in range(cols):
			# Deterministic per-cell flicker: a hash-ish phase fed through sin.
			var k := float(r) * 2.3 + float(c) * 1.7 + phase * 6.28
			var on := sin(_time * 0.8 + k) > 0.35
			if not on:
				continue
			lit.a = 0.5 + 0.35 * (0.5 + 0.5 * sin(_time + k))
			var wx := bx + pad + c * cell
			var wy := top + pad + r * cell
			draw_rect(Rect2(wx, wy, win, win), lit)
