extends CanvasLayer
## The Bag window of the class card screen: the character, the worn-gear slots, the stash grid and
## details (gear_panel.gd) in a full-screen ink frame. (The camp, look, repair, rest and shop tabs of the
## old campfire were cut with the auto-battler, Boss 2026-11-11.)
## It shows and changes the player's profile through the rules in logic/; it decides nothing.

const LocalSession := preload("res://client/session/local_session.gd")
const GearPanel := preload("res://client/gear_panel.gd")
const InkUi := preload("res://client/ink_ui.gd")

signal closed

## Kept for the caller (card_deck_screen.gd): this window is the backpack.
var backpack_mode := true
var session
var profile
var camp
var rules
var combat
var gear  ## the GearPanel
var layout: Dictionary = {}  ## the current InkUi.layout_for() result
var density_override := 0.0  ## > 0: use this screen density instead of the display's (screenshots)

var _root: Control  ## everything, scaled to the screen
var _margin: MarginContainer
var _status: Label


## Builds the window over the player's profile.
func setup(player_profile, camp_data, item_rules, combat_data, _trip = null, _point_id: String = "", _trip_journey = null, command_session = null) -> void:
	profile = player_profile
	camp = camp_data
	rules = item_rules
	combat = combat_data
	session = command_session if command_session != null else LocalSession.for_menu(profile, rules, camp, null, null)
	if session.has_signal("ownership_changed") and not session.ownership_changed.is_connected(_refresh): session.ownership_changed.connect(_refresh)
	layer = 20
	_build_frame()
	_apply_layout()
	if not get_viewport().size_changed.is_connected(_apply_layout):
		get_viewport().size_changed.connect(_apply_layout)


## Kept for the caller: there is a single page.
func show_tab(_index: int) -> void:
	pass


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _build_frame() -> void:
	var dim := ColorRect.new()
	dim.color = InkUi.SCRIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_root = Control.new()
	_root.name = "Menu"
	_root.theme = InkUi.make_theme()
	add_child(_root)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	var panel := PanelContainer.new()
	InkUi.panel(panel, InkUi.window_style())
	_margin.add_child(panel)
	var column := VBoxContainer.new()
	InkUi.gap(column, InkUi.GAP_S)
	panel.add_child(column)
	var header := HBoxContainer.new()
	InkUi.gap(header, InkUi.GAP_XL)
	column.add_child(header)
	var title := Label.new()
	title.text = "Backpack"
	InkUi.style_text(title, InkUi.PAPER, InkUi.FONT_TITLE)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.name = "Close"
	close_button.custom_minimum_size = Vector2(96.0, 44.0)
	close_button.pressed.connect(_close)
	InkUi.close_button(close_button)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(close_button)
	gear = GearPanel.new()
	gear.name = "Inventory"
	gear.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gear.store_label_override = "Bag"
	column.add_child(gear)
	gear.setup(profile, null, rules, camp, combat, session)
	gear.message.connect(_say)
	_status = Label.new()
	InkUi.style_text(_status, InkUi.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_status.visible = false  # takes no room until there is something to say


func _apply_layout() -> void:
	if _root == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	var logical: Vector2 = viewport.get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var density := DisplayServer.screen_get_scale()
	if window.x <= 0.0 or window.y <= 0.0:
		window = logical
	if density_override > 0.0:
		density = density_override
	layout = InkUi.layout_for(window, logical, density)
	_root.scale = Vector2.ONE * float(layout["scale"])
	_root.size = layout["size"]
	InkUi.margins(_margin, InkUi.edge_for(layout["mode"]))
	if gear != null: gear.set_mode(layout["mode"])


func _refresh(_refresh_gear: bool = true) -> void:
	if gear != null:
		gear.refresh()


func _say(text: String) -> void:
	_status.text = text
	_status.visible = text != ""
