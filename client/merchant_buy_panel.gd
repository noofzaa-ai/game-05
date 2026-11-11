extends CanvasLayer
const Ink = preload("res://client/ink_ui.gd")
var _window: PanelContainer
var _stock: VBoxContainer
var _status: Label
var _profile
var _rules
var _camp
var _session

func setup(profile, rules, camp, authority) -> void:
	layer = 70
	_profile=profile;_rules=rules;_camp=camp;_session=authority
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme=Ink.make_theme()
	add_child(root)
	var shade := ColorRect.new()
	shade.color=Ink.SCRIM
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	_window=PanelContainer.new()
	Ink.panel(_window,Ink.camp_menu_window_style())
	root.add_child(_window)
	var content := VBoxContainer.new()
	_window.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Ink.label("Merchant · ซื้ออาวุธ",Ink.GOLD,Ink.FONT_HEADING)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text="×";close.custom_minimum_size=Vector2(52,48)
	Ink.close_button(close)
	close.pressed.connect(queue_free)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_stock=VBoxContainer.new()
	_stock.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(_stock)
	_status=Ink.label("",Ink.GOLD,Ink.FONT_SMALL)
	_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	if _session.has_signal("ownership_changed"): _session.ownership_changed.connect(_render)
	if _session.has_signal("command_completed"): _session.command_completed.connect(_completed)
	get_viewport().size_changed.connect(_fit)
	_fit();_render()

func _fit() -> void:
	var area := get_viewport().get_visible_rect().size
	_window.position=Vector2(16,16)
	_window.size=area-Vector2(32,32)

func _render() -> void:
	for child in _stock.get_children():
		_stock.remove_child(child);child.queue_free()
	var shop=preload("res://client/shop_panel.gd").new()
	_stock.add_child(shop)
	shop.message.connect(func(text): _status.text=text)
	shop.changed.connect(_render)
	shop.setup(_profile,_rules,_camp,_session)

func _completed(_id: int, result: Dictionary) -> void:
	_status.text="ซื้อแล้ว ของอยู่ในกระเป๋า" if result.get("ok",false) else preload("res://client/online/online_text.gd").command_message(result)
	_render()
