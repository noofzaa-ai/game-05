extends BoxContainer
## The camp's Look tab: the player picks the character's face, hair style, hair color and skin tone (free, any time
## at camp) and sees it at once on the live doll. Choices go into Profile.appearance through
## LocalSession.command(); the stage shows them on the next trip. Side by side on wide screens,
## the doll above the choices on a phone held upright (set_mode()). Face/Hair/Colors have separate scroll pages.
## EXTENDING: a new part is one more entry in CosmeticOptions.PARTS and a title in TEXT.

signal changed  ## the player picked something (the inventory's doll should show it too)

const LocalSession := preload("res://client/session/local_session.gd")
var session

const InkUi := preload("res://client/ink_ui.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const PaperDoll := preload("res://client/paper_doll.gd")

const TEXT := {"face": "Face", "hair_style": "Hair", "hair_color": "Hair color", "skin": "Skin", "natural": "Own", "eye_color": "Eye color", "blink_mode": "กระพริบตา"}
const COLOR_BUTTON := 40.0

var profile
var rules  ## ItemRules (the doll shows the worn items too)
var combat  ## CombatData (the weapon's stance)
var doll  ## PaperDoll
var _color_pickers: Dictionary = {}
var _buttons: Dictionary = {}  ## part -> {id: Button}
## Creator reserves its footer; let its preview shrink with the remaining height.
var fit_preview_height := false
var _doll_holder: Control
var _pages := {}
var _tabs := {}
var selected_tab := "face"
const TAB_NAMES := {"face": "Eyes"}  ## the Mall, old face and old hair-style tabs went with the old model (Boss 2026-11-13)


func setup(player_profile, item_rules, combat_data, command_session = null) -> void:
	session = command_session if command_session != null else LocalSession.for_menu(player_profile, item_rules)
	if session.has_signal("ownership_changed") and not session.ownership_changed.is_connected(_server_look_changed): session.ownership_changed.connect(_server_look_changed)
	profile = player_profile
	rules = item_rules
	combat = combat_data
	InkUi.gap(self, InkUi.GAP_HUGE)
	_doll_holder = PanelContainer.new()
	InkUi.panel(_doll_holder, InkUi.doll_frame_style())
	add_child(_doll_holder)
	doll = PaperDoll.new()
	doll.name = "PaperDoll"
	_doll_holder.add_child(doll)
	var choices_box := VBoxContainer.new()
	choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(choices_box)
	var tabs := HBoxContainer.new()
	InkUi.gap(tabs, InkUi.GAP_M)
	choices_box.add_child(tabs)
	var tab_group := ButtonGroup.new()
	for key in TAB_NAMES:
		var tab := Button.new()
		tab.text = TAB_NAMES[key]
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(90.0, 44.0)
		tab.pressed.connect(show_tab.bind(key))
		tabs.add_child(tab)
		_tabs[key] = tab
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		choices_box.add_child(scroll)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		InkUi.gap(column, InkUi.GAP_L)
		scroll.add_child(column)
		_pages[key] = column
	var options = ItemAssets.cosmetics()
	for part in ["eye_color"]:
		if options.choices.get(part, []).is_empty():
			continue
		var column: VBoxContainer = _pages["face"]
		column.add_child(InkUi.brush_title(TEXT.get(part, part)))
		var row := HFlowContainer.new()
		InkUi.gap(row, InkUi.GAP_M, InkUi.GAP_M)
		column.add_child(row)
		if part in ["skin", "eye_color"]:
			var picker := ColorPickerButton.new()
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(44,44)
			picker.color = Color(options.resolve(profile.appearance).get(part, {}).get("color", "#ddbfae"))
			picker.popup_closed.connect(func(): pick(part, "#" + picker.color.to_html(false)))
			_color_pickers[part]=picker
			row.add_child(picker)
			var reset := Button.new()
			reset.text = "คืนสีเดิม"
			reset.pressed.connect(func(): pick(part, str(options.defaults[part])))
			row.add_child(reset)
		var group := ButtonGroup.new()
		_buttons[part] = {}
		for choice in options.choices[part]:
			var button := _color_button(choice)
			button.toggle_mode = true
			button.button_group = group
			button.tooltip_text = choice["name"]
			button.pressed.connect(pick.bind(part,choice["id"]))
			row.add_child(button)
			_buttons[part][choice["id"]] = button
	show_tab(selected_tab)
	set_mode(InkUi.WIDE)
	refresh()


## Keep each category independently scrollable; switching tabs preserves its position.
func show_tab(key: String) -> void:
	if not _pages.has(key):
		return
	selected_tab = key
	if is_instance_valid(doll):refresh()
	for page in _pages:
		_pages[page].get_parent().visible = page == key
		_tabs[page].set_pressed_no_signal(page == key)


## Picks `id` for `part` (as a press of its button does). Returns false for an unknown choice.
func pick(part: String, id: String) -> bool:
	if not session.command({"type": "appearance", "part": part, "choice": id})["ok"]:
		return false
	refresh()
	changed.emit()
	return true


## Shows the current choices: the pressed buttons and the doll.
func refresh() -> void:
	var preview: Dictionary = profile.appearance
	var picked: Dictionary = ItemAssets.cosmetics().resolve(preview)
	for part in _color_pickers:
		_color_pickers[part].color=Color(picked.get(part,{}).get("color","#ddbfae"))
	for part in _buttons:
		var id: String = picked.get(part, {}).get("id", "")
		for choice_id in _buttons[part]:
			_buttons[part][choice_id].set_pressed_no_signal(choice_id == id)
	doll.dress(profile.loadout, profile.loadout.weapon_style(combat.styles.keys()), rules.catalog, preview)


## The id picked for `part` now (its default if nothing was picked).
func picked_id(part: String) -> String:
	return ItemAssets.cosmetics().resolve(profile.appearance).get(part, {}).get("id", "")


## InkUi.WIDE / COMPACT: the doll beside the choices; PORTRAIT: above them.
func set_mode(mode: String) -> void:
	vertical = mode == InkUi.PORTRAIT
	_doll_holder.custom_minimum_size = Vector2(0.0, 260.0) if vertical else Vector2(300.0, 0.0 if fit_preview_height or mode == InkUi.COMPACT else 420.0)
	_doll_holder.size_flags_vertical = Control.SIZE_FILL if vertical else Control.SIZE_EXPAND_FILL


## The picture of a choice that is a model. The old face / hair-style pictures went with the old model (Boss
## 2026-11-13), so no choice has one now ("" = a text button).
static func icon_file(_part: String, _choice: Dictionary) -> String:
	return ""

func _color_button(choice: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(COLOR_BUTTON, COLOR_BUTTON)
	if choice.get("natural", false):  # each hair style's own colors: a word, not a swatch
		button.text = TEXT["natural"]
		button.custom_minimum_size.x = COLOR_BUTTON * 1.5
		_style(button, InkUi.PANEL_LIGHT)
		return button
	_style(button, Color(choice["color"]))
	return button


## Its own color as the face of the button; a vermilion frame when picked, a light one under the pointer.
func _style(button: Button, color: Color) -> void:
	InkUi.make_swatch(button, color)

func _server_look_changed() -> void:
	refresh()
	changed.emit()
