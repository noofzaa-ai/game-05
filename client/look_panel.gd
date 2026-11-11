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

const TEXT := {"face": "Face", "hair_style": "Hair", "hair_color": "Hair color", "skin": "Skin", "natural": "Own", "eye_color": "Eye color", "fashion": "Outfit overlay", "fashion_display": "แสดงชุดแฟชั่น", "fashion_hat": "หมวก", "fashion_back": "Back accessory", "blink_mode": "กระพริบตา"}
## Pictures of the choices: our own renders first (tools/shots/cosmetic_icons.gd: <part>_<id>.png), then
## the model team's preview of a face (<asset_id>.png).
const ICON_FOLDER := "res://art/cosmetics/icons/"
const FACE_ICON_FOLDER := "res://art/items/faces/"
const FACE_BUTTON := 52.0
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
const TAB_NAMES := {"face": "Face", "hair": "Hair", "fashion": "Mall"}
var _wallet: Button
var _notice: Label
var _mall_labels: Dictionary = {}
var _pending := false
var _mall_sections: Dictionary = {}
var _mall_category := "fashion"
var _preview: Dictionary = {}
var _selection: Dictionary = {}
var _mall_footer: HBoxContainer
var _buy: Button
var _selection_label: Label
var _confirm: CanvasLayer
var _confirmed_selection: Dictionary = {}


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
	_wallet=Button.new();_wallet.icon=load("res://art/ui/diamond.svg");_wallet.add_theme_constant_override("icon_max_width",24);_wallet.expand_icon=true;_wallet.mouse_filter=Control.MOUSE_FILTER_IGNORE
	choices_box.add_child(_wallet)
	_notice=InkUi.label("",InkUi.GOLD,InkUi.FONT_SMALL);choices_box.add_child(_notice)
	if session.has_signal("command_completed"):session.command_completed.connect(_mall_completed)
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
	var categories:=HBoxContainer.new();_pages["fashion"].add_child(categories)
	for part in ["fashion","fashion_hat","fashion_back"]:
		var tab:=Button.new();tab.text={"fashion":"ชุด","fashion_hat":"หมวก","fashion_back":"ของหลัง"}[part];tab.custom_minimum_size=Vector2(80,44);tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL;categories.add_child(tab)
		tab.pressed.connect(_show_mall_category.bind(part))
	var options = ItemAssets.cosmetics()
	for part in ["face","eye_color","hair_style","fashion","fashion_hat","fashion_back"]:
		if options.choices.get(part, []).is_empty():
			continue
		var page_key := "fashion" if part.begins_with("fashion") else ("hair" if part=="hair_style" else "face")
		var column: VBoxContainer = _pages[page_key]
		if part.begins_with("fashion"):
			var section:=VBoxContainer.new();column.add_child(section);column=section;_mall_sections[part]=section;section.visible=part==_mall_category
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
			var button := _color_button(choice) if choice.has("color") else _picture_button(part, choice)
			button.toggle_mode = true
			button.button_group = group
			button.tooltip_text = choice["name"]
			button.pressed.connect(_mall_pick.bind(part, choice["id"]) if part.begins_with("fashion") else pick.bind(part,choice["id"]))
			if part.begins_with("fashion"):
				var cell:=VBoxContainer.new();row.add_child(cell);cell.add_child(button)
				var price:=InkUi.label("",InkUi.GOLD,12);price.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;cell.add_child(price)
				_mall_labels[part+":"+choice["id"]]=price
			else:row.add_child(button)
			_buttons[part][choice["id"]] = button
	_mall_footer=HBoxContainer.new();choices_box.add_child(_mall_footer)
	_selection_label=InkUi.label("เลือกไอเทมเพื่อลองใส่",InkUi.GOLD,InkUi.FONT_SMALL);_selection_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_selection_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_mall_footer.add_child(_selection_label)
	var restore:=Button.new();restore.text="คืนชุดจริง";restore.custom_minimum_size=Vector2(88,44);_mall_footer.add_child(restore);restore.pressed.connect(func():_preview.clear();_selection.clear();refresh())
	_buy=Button.new();_buy.text="Buy";_buy.custom_minimum_size=Vector2(130,44);_mall_footer.add_child(_buy);_buy.pressed.connect(_buy_pressed)
	show_tab(selected_tab)
	set_mode(InkUi.WIDE)
	refresh()


## Keep each category independently scrollable; switching tabs preserves its position.
func show_tab(key: String) -> void:
	if not _pages.has(key):
		return
	selected_tab = key
	if is_instance_valid(_wallet):_wallet.visible=key=="fashion"
	if is_instance_valid(_mall_footer):_mall_footer.visible=key=="fashion"
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
	var preview := _preview_appearance()
	var picked: Dictionary = ItemAssets.cosmetics().resolve(preview)
	_wallet.text="Diamond  %s" % profile.diamonds
	_wallet.visible=selected_tab=="fashion"
	for key in _mall_labels:
		var parts: PackedStringArray=key.split(":")
		var owned:=preload("res://logic/mall.gd").owns(profile,parts[0],parts[1])
		_mall_labels[key].text="มีแล้ว" if owned else "%d Diamond" % int(preload("res://logic/mall.gd").config().prices[parts[0]])
	for part in _color_pickers:
		_color_pickers[part].color=Color(picked.get(part,{}).get("color","#ddbfae"))
	for part in _buttons:
		var id: String = picked.get(part, {}).get("id", "")
		for choice_id in _buttons[part]:
			_buttons[part][choice_id].set_pressed_no_signal(choice_id == id)
	doll.dress(profile.loadout, profile.loadout.weapon_style(combat.styles.keys()), rules.catalog, preview)
	_refresh_buy()


## The id picked for `part` now (its default if nothing was picked).
func picked_id(part: String) -> String:
	return ItemAssets.cosmetics().resolve(profile.appearance).get(part, {}).get("id", "")


## InkUi.WIDE / COMPACT: the doll beside the choices; PORTRAIT: above them.
func set_mode(mode: String) -> void:
	vertical = mode == InkUi.PORTRAIT
	_doll_holder.custom_minimum_size = Vector2(0.0, 260.0) if vertical else Vector2(300.0, 0.0 if fit_preview_height or mode == InkUi.COMPACT else 420.0)
	_doll_holder.size_flags_vertical = Control.SIZE_FILL if vertical else Control.SIZE_EXPAND_FILL


## The picture of a choice that is a model (a face, a hair style), or "" if there is none.
static func icon_file(part: String, choice: Dictionary) -> String:
	var source_kind: String = {"fashion":"outfit","hair_style":"hair","fashion_hat":"hat","fashion_back":"back"}.get(part,"")
	var source_icon := "res://art/fashion/studio_icons/%s-%s.svg" % [source_kind,choice["id"]]
	if not source_kind.is_empty() and ResourceLoader.exists(source_icon): return source_icon
	for file in ["res://art/fashion/icons/%s_%s.png" % [part, choice["id"]], ICON_FOLDER + "%s_%s.png" % [part, choice["id"]], FACE_ICON_FOLDER + str(choice.get("asset_id", "")) + ".png"]:
		if (part == "face" or file.begins_with(ICON_FOLDER) or file.begins_with("res://art/fashion/icons/")) and ResourceLoader.exists(file):
			return file
	return ""


func _picture_button(part: String, choice: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(FACE_BUTTON, FACE_BUTTON)
	var file := icon_file(part, choice)
	if part=="face":
		var atlas:=AtlasTexture.new();atlas.atlas=load("res://art/fashion/eyes/"+str(choice.id)+"_turquoise_atlas.png");atlas.region=Rect2(0,0,256,128)
		InkUi.picture_button(button,atlas,40)
	elif not file.is_empty():
		var texture: Texture2D=load(file)
		if part=="fashion_hat" and str(choice.id).begins_with("fantasy_"):
			var hat_icon:=AtlasTexture.new();hat_icon.atlas=texture
			hat_icon.region=Rect2(texture.get_width()/6.0,0,texture.get_width()*2.0/3.0,texture.get_height()*.27)
			texture=hat_icon
		InkUi.picture_button(button, texture, int(FACE_BUTTON - 16.0))
	else:
		button.text = "ถอด" if choice["id"]=="none" else choice["name"]
	_style(button, InkUi.PANEL_LIGHT)
	return button


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

func _preview_appearance()->Dictionary:
	var result:Dictionary=profile.appearance.duplicate(true)
	if selected_tab=="fashion":
		for part in _preview:result[part]=_preview[part]
		if not _preview.is_empty():result["fashion_display"]="on"
		# A demonstration outfit is local to this doll; it never grants ownership.
		if _preview.has("fashion_hat") and result.get("fashion","none")=="none":result["fashion"]="red"
	return result

func _mall_pick(part:String,id:String)->void:
	if _pending:return
	_preview[part]=id
	_selection={"part":part,"id":id}
	_notice.text="ลองใส่เท่านั้น · ยังไม่ได้ซื้อหรือเปลี่ยนชุดจริง"
	refresh()

func _refresh_buy()->void:
	if not is_instance_valid(_buy):return
	_buy.disabled=_pending or _selection.is_empty()
	if _selection.is_empty():_selection_label.text="เลือกไอเทมเพื่อลองใส่";_buy.text="Buy";return
	var part:String=_selection.part;var id:String=_selection.id
	var choice:Dictionary=ItemAssets.cosmetics().entry(part,id)
	var owned:=preload("res://logic/mall.gd").owns(profile,part,id)
	var price:=int(preload("res://logic/mall.gd").config().prices[part])
	_selection_label.text=str(choice.get("name",id))+(" · มีแล้ว" if owned else " · %d Diamond"%price)
	_buy.text="กำลังซื้อ…" if _pending else "สวมใส่" if owned else "Buy · %d"%price
	if not owned and profile.diamonds<price:_buy.disabled=true

func _buy_pressed()->void:
	if _pending or _selection.is_empty():return
	var part:String=_selection.part;var id:String=_selection.id
	if preload("res://logic/mall.gd").owns(profile,part,id):
		pick(part,id);return
	if is_instance_valid(_confirm):return
	_confirmed_selection=_selection.duplicate()
	_confirm=CanvasLayer.new();_confirm.layer=100;add_child(_confirm)
	var screen:=Control.new();screen.theme=InkUi.make_theme();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_confirm.add_child(screen)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.7);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.add_child(shade)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.add_child(center)
	var frame:=PanelContainer.new();frame.custom_minimum_size=Vector2(minf(410,get_viewport_rect().size.x-24),0);InkUi.panel(frame,InkUi.doll_frame_style());center.add_child(frame)
	var box:=VBoxContainer.new();frame.add_child(box)
	var header:=HBoxContainer.new();box.add_child(header)
	var title:=InkUi.label("ยืนยันการซื้อ",InkUi.GOLD,InkUi.FONT_SMALL);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var close:=Button.new();header.add_child(close);InkUi.close_button(close);close.pressed.connect(_cancel_purchase)
	var choice:Dictionary=ItemAssets.cosmetics().entry(part,id)
	var price:=int(preload("res://logic/mall.gd").config().prices[part])
	var details:=InkUi.label("%s\nราคา %d Diamond\nยอดหลังซื้อ %d"%[choice.name,price,profile.diamonds-price],InkUi.TEXT_PLAIN,InkUi.FONT_SMALL);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(details)
	var buttons:=HBoxContainer.new();box.add_child(buttons)
	for caption in ["ยกเลิก","ยืนยันซื้อ"]:
		var button:=Button.new();button.text=caption;button.custom_minimum_size=Vector2(120,44);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;buttons.add_child(button)
		button.pressed.connect(_confirm_purchase if caption=="ยืนยันซื้อ" else _cancel_purchase)

func _cancel_purchase()->void:
	if is_instance_valid(_confirm):_confirm.queue_free()
	_confirm=null;_confirmed_selection.clear()

func _confirm_purchase()->void:
	if _pending or _confirmed_selection.is_empty():return
	var choice:=_confirmed_selection.duplicate()
	_cancel_purchase()
	var result:Dictionary=session.command({"type":"mall_buy","part":choice.part,"choice":choice.id})
	_pending=bool(result.get("pending",false))
	_notice.text="กำลังซื้อ…" if _pending else ("ซื้อแล้ว · กดสวมใส่เพื่อใช้จริง" if result.get("ok",false) else _mall_error(result))
	refresh()

func _mall_completed(_id:int,result:Dictionary)->void:
	if _pending:
		_pending=false
		_notice.text="ซื้อแล้ว · กดสวมใส่เพื่อใช้จริง" if result.get("ok",false) else _mall_error(result)
	refresh()

func _show_mall_category(part:String)->void:
	_mall_category=part
	for key in _mall_sections:_mall_sections[key].visible=key==part

func _mall_error(result:Dictionary)->String:
	var reason:=str(result.get("reason",result.get("error","unavailable")))
	return {"not_enough_diamonds":"Diamond ไม่พอ", "already_owned":"มีชิ้นนี้แล้ว", "busy":"กำลังบันทึก กรุณารอสักครู่", "not_online":"กรุณาเชื่อมต่อใหม่", "cosmetic_not_owned":"ซื้อชิ้นนี้ใน Mall ก่อน"}.get(reason,"ซื้อไม่สำเร็จ กรุณาลองใหม่")
