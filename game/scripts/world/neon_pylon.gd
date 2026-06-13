class_name NeonPylon
extends Node3D
## A tall vintage roadside neon sign — the ANIMATED night landmark the static
## neon work was missing. A pylon carries a panel whose border tubes chase
## around like a marquee, a headline that gently pulses, and a "VACANCY"
## sub-sign that blinks. Pure emissive + per-frame energy animation, so it lives
## at night with no shared-env dependency. Built in populate() for headless
## tests; animated in _process. Placed via FloridaBackdrop.

@export var headline: String = "SEA BREEZE"
@export var subtitle: String = "MOTEL"
@export var neon: Color = Color(1.0, 0.2, 0.55)
@export var accent: Color = Color(0.15, 0.95, 1.0)
@export var pole_h: float = 9.0
@export var panel_w: float = 7.0
@export var panel_h: float = 9.0
@export var chase_speed: float = 6.0
@export var blink_period: float = 1.1

var _time: float = 0.0
var _segments: Array[StandardMaterial3D] = []
var _seg_energy: float = 3.0
var _headline_mat: StandardMaterial3D
var _vacancy: Node3D
var _vacancy_mat: StandardMaterial3D


func _ready() -> void:
	populate()


func populate() -> int:
	if not _segments.is_empty():
		return _segments.size()
	_build_pole()
	_build_panel()
	_build_border()
	_build_text()
	_build_vacancy()
	return _segments.size()


func _process(delta: float) -> void:
	_time += delta
	# Chase: a bright spot sweeps around the border ring.
	var n := _segments.size()
	if n > 0:
		var head := fmod(_time * chase_speed, float(n))
		for i in n:
			var d: float = fmod(float(i) - head + float(n), float(n))
			var lead: float = minf(d, float(n) - d)  # ring distance to the moving head
			var glow: float = clampf(1.6 - lead * 0.5, 0.25, 1.6)
			_segments[i].emission_energy_multiplier = _seg_energy * glow
	# Headline breathes.
	if _headline_mat != null:
		_headline_mat.emission_energy_multiplier = 1.4 + 0.5 * sin(_time * 2.0)
	# VACANCY blinks on/off.
	if _vacancy != null:
		var on := fmod(_time, blink_period) < blink_period * 0.6
		_vacancy.visible = on


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _build_pole() -> void:
	var pole := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(0.7, pole_h, 0.7)
	pole.mesh = pmesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.12)
	mat.metallic = 0.6
	mat.roughness = 0.5
	pole.material_override = mat
	pole.position = Vector3(0.0, pole_h * 0.5, 0.0)
	add_child(pole)


func _build_panel() -> void:
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(panel_w, panel_h, 0.4)
	panel.mesh = mesh
	panel.name = "Panel"
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.07)
	dark.roughness = 0.6
	panel.material_override = dark
	panel.position = Vector3(0.0, pole_h + panel_h * 0.5, 0.0)
	add_child(panel)


## A ring of individually-lit border segments (so the chase can sweep them).
func _build_border() -> void:
	var ring := Node3D.new()
	ring.name = "Border"
	add_child(ring)
	var cy := pole_h + panel_h * 0.5
	var hw := panel_w * 0.5
	var hh := panel_h * 0.5
	var per_side := 5
	var seg := BoxMesh.new()
	seg.size = Vector3(0.3, 0.3, 0.3)
	# Walk the rectangle clockwise so the chase reads as continuous.
	var pts: Array[Vector2] = []
	for i in per_side:
		pts.append(Vector2(lerpf(-hw, hw, float(i) / float(per_side)), hh))
	for i in per_side:
		pts.append(Vector2(hw, lerpf(hh, -hh, float(i) / float(per_side))))
	for i in per_side:
		pts.append(Vector2(lerpf(hw, -hw, float(i) / float(per_side)), -hh))
	for i in per_side:
		pts.append(Vector2(-hw, lerpf(-hh, hh, float(i) / float(per_side))))
	for p in pts:
		var m := _emissive(neon, _seg_energy)
		_segments.append(m)
		var dot := MeshInstance3D.new()
		dot.mesh = seg
		dot.material_override = m
		dot.position = Vector3(p.x, cy + p.y, 0.3)
		ring.add_child(dot)


func _build_text() -> void:
	var cy := pole_h + panel_h * 0.5
	_headline_mat = _emissive(neon, 1.6)
	var head := Label3D.new()
	head.name = "Headline"
	head.text = headline
	head.font_size = 130
	head.pixel_size = 0.013
	head.modulate = neon
	head.outline_size = 16
	head.outline_modulate = Color(0.2, 0.0, 0.08)
	head.position = Vector3(0.0, cy + panel_h * 0.22, 0.35)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Label3D can't take a material that animates energy, so a backing bar does
	# the breathing glow; the text rides on top at fixed brightness.
	add_child(head)
	var glow := MeshInstance3D.new()
	var gmesh := BoxMesh.new()
	gmesh.size = Vector3(panel_w - 1.0, 1.6, 0.1)
	glow.mesh = gmesh
	glow.material_override = _headline_mat
	glow.position = Vector3(0.0, cy + panel_h * 0.22, 0.28)
	add_child(glow)

	var sub := Label3D.new()
	sub.name = "Subtitle"
	sub.text = subtitle
	sub.font_size = 150
	sub.pixel_size = 0.013
	sub.modulate = accent
	sub.outline_size = 18
	sub.outline_modulate = Color(0.0, 0.18, 0.22)
	sub.position = Vector3(0.0, cy - panel_h * 0.08, 0.35)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)


func _build_vacancy() -> void:
	var cy := pole_h + panel_h * 0.5
	_vacancy = Node3D.new()
	_vacancy.name = "Vacancy"
	add_child(_vacancy)
	_vacancy_mat = _emissive(accent, 2.4)
	var bar := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(panel_w - 1.6, 1.2, 0.1)
	bar.mesh = bmesh
	bar.material_override = _vacancy_mat
	bar.position = Vector3(0.0, cy - panel_h * 0.34, 0.28)
	_vacancy.add_child(bar)
	var label := Label3D.new()
	label.text = "VACANCY"
	label.font_size = 90
	label.pixel_size = 0.011
	label.modulate = Color(0.02, 0.04, 0.05)
	label.position = Vector3(0.0, cy - panel_h * 0.34, 0.35)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vacancy.add_child(label)
