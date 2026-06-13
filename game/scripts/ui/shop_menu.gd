class_name ShopMenu
extends CanvasLayer
## Code-built shop UI (no .tscn). Lazily spawned and reused, like the other
## interaction overlays. Lists a catalogue with prices and the player's balance;
## buying resolves through ShopModel.purchase and applies the spend via
## PlayerStats.spend_money. Pauses the game while open (mouse freed) like a
## standard store menu and restores on close, so it needs no coupling to the
## player controller. Interactive, so not unit-tested; the purchase math it
## drives (ShopModel) is.

var _model: ShopModel
var _stats: PlayerStats
var _money_label: Label
var _rows: VBoxContainer
var _title_label: Label
var _buy_buttons: Array[Button] = []


func _ready() -> void:
	add_to_group("shop_menu")
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


## The one shop menu under the current scene, created on first use.
static func instance(tree: SceneTree) -> ShopMenu:
	var existing := tree.get_first_node_in_group("shop_menu")
	if existing is ShopMenu:
		return existing
	if tree.current_scene == null:
		return null
	var menu := ShopMenu.new()
	tree.current_scene.add_child(menu)
	return menu


## Open the store for `items` (each {id, name, price, category}), charging
## against `stats`. Pauses the game and frees the mouse until closed.
func open(model: ShopModel, stats: PlayerStats, title: String, items: Array) -> void:
	_model = model
	_stats = stats
	_title_label.text = title
	_populate(items)
	_refresh()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420.0, 480.0)
	dim.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	column.add_child(_title_label)

	_money_label = Label.new()
	column.add_child(_money_label)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	column.add_child(close_button)


func _populate(items: Array) -> void:
	for child in _rows.get_children():
		child.queue_free()
	_buy_buttons.clear()
	for entry in items:
		if not (entry is Dictionary) or not entry.has("id"):
			continue
		var id := String(entry["id"])
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "%s  $%d" % [entry.get("name", id), int(entry.get("price", 0))]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var buy := Button.new()
		buy.text = "Buy"
		buy.pressed.connect(_on_buy.bind(id))
		row.add_child(buy)
		_buy_buttons.append(buy)
		buy.set_meta("item_id", id)
		_rows.add_child(row)


func _on_buy(id: String) -> void:
	if _model == null or _stats == null:
		return
	var result := _model.purchase(id, _stats.money)
	if result.get("success", false):
		_stats.spend_money(int(result.get("cost", 0)))
	_refresh()


## Update the balance and grey out anything the player can no longer afford.
func _refresh() -> void:
	if _stats == null or _model == null:
		return
	_money_label.text = "Cash: $%d" % _stats.money
	for buy in _buy_buttons:
		var id := String(buy.get_meta("item_id", ""))
		buy.disabled = not _model.can_afford(id, _stats.money)
