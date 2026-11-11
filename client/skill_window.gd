extends CanvasLayer
signal closed
const Ink = preload("res://client/ink_ui.gd")
var _window: PanelContainer
func setup(profile, session) -> void:
	layer=65
	var root:=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme=Ink.make_theme()
	add_child(root)
	var shade:=ColorRect.new();shade.color=Ink.SCRIM
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(shade)
	_window=PanelContainer.new();Ink.panel(_window,Ink.camp_menu_window_style());root.add_child(_window)
	var content:=VBoxContainer.new();_window.add_child(content)
	var header:=HBoxContainer.new();content.add_child(header)
	var title:=Ink.label("Skill",Ink.GOLD,Ink.FONT_HEADING);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(52,48);Ink.close_button(close)
	close.pressed.connect(func():closed.emit();queue_free());header.add_child(close)
	var panel=preload("res://client/skill_panel.gd").new();content.add_child(panel);panel.setup(profile,session)
	get_viewport().size_changed.connect(_fit);_fit()
	# Wrapped text computes its minimum height only after containers have their width.
	# Refit after layout settles; otherwise the initial narrow measurement can pin a huge window.
	_settle_layout.call_deferred()
func _settle_layout() -> void:
	for i in range(4):
		await get_tree().process_frame
		if not is_inside_tree(): return
		_fit()
func _fit() -> void:
	var content := _window.get_child(0)
	if content.get_child_count()>1:
		var panel := content.get_child(1)
		if panel.get_child_count()>0: panel.get_child(0).visible=get_viewport().get_visible_rect().size.y>=560
	_window.position=Vector2(8,8)
	_window.size=get_viewport().get_visible_rect().size-Vector2(16,16)
