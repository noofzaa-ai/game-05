extends Control
## Bounded, plain-text chat for the current plaza channel; no persistent history.
signal submitted(text: String)
const InkUi := preload("res://client/ink_ui.gd")
var panel: PanelContainer
var toggle: Button
var history: RichTextLabel
var field: LineEdit
var send: Button
var notice: Label
var heading: HBoxContainer
var title: Label
var close: Button
var lines: Array[String] = []
var expanded := true
var connected := false
var ui_scale := 1.0
var layout_key := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = InkUi.make_theme()
	panel = PanelContainer.new(); add_child(panel); InkUi.panel(panel, InkUi.panel_style())
	var box := VBoxContainer.new(); panel.add_child(box)
	heading = HBoxContainer.new(); box.add_child(heading)
	title = Label.new(); title.text = "แชทลานรวมพล"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.add_child(title)
	close = Button.new(); close.text = "×"; close.tooltip_text = "ย่อแชท"; heading.add_child(close)
	close.pressed.connect(func(): expanded = false; field.release_focus(); _layout())
	history = RichTextLabel.new(); history.bbcode_enabled = false; history.scroll_following = true
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL; history.selection_enabled = true; box.add_child(history)
	notice = Label.new(); notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; notice.text = "กำลังเชื่อมต่อ…"; box.add_child(notice)
	var row := HBoxContainer.new(); box.add_child(row)
	field = LineEdit.new(); field.max_length = 160; field.placeholder_text = "พิมพ์ข้อความ…"; field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(field)
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	field.text_submitted.connect(func(_text): _submit())
	field.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			field.release_focus(); accept_event())
	send = Button.new(); send.text = "ส่ง"; row.add_child(send); send.pressed.connect(_submit)
	toggle = Button.new(); toggle.text = "แชทลานรวมพล"; add_child(toggle)
	toggle.pressed.connect(func(): expanded = true; _layout(); field.grab_focus())
	set_connected(false)

func _process(_delta: float) -> void:
	_layout()

func set_connected(value: bool) -> void:
	connected = value
	if field == null: return
	field.editable = value; send.disabled = not value
	notice.text = "เฉพาะลานนี้ · ไม่เกิน 160 ตัวอักษร" if value else "กำลังเชื่อมต่อ…"

func add_message(sender: String, text: String) -> void:
	lines.append(sender.left(64) + ": " + text.left(160))
	while lines.size() > 40: lines.pop_front()
	history.text = "\n".join(lines)

func clear_channel() -> void:
	lines.clear()
	if history != null: history.text = ""
	if field != null: field.release_focus()
	set_connected(false)

func show_error(text: String) -> void:
	notice.text = text

func _submit() -> void:
	var text := field.text.strip_edges()
	if not connected or text.is_empty(): return
	submitted.emit(text)
	field.clear()
	field.release_focus()

func _layout() -> void:
	if panel == null: return
	var view := get_viewport().get_visible_rect().size
	var s := maxf(0.5, ui_scale)
	var keyboard := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	var key := "%s|%s|%s|%s" % [view, s, keyboard, expanded]
	if key == layout_key: return
	layout_key = key
	var screen_height := float(DisplayServer.window_get_size().y)
	var lift := keyboard * view.y / maxf(1.0, screen_height)
	var width := minf(370.0 * s, view.x * 0.48)
	panel.visible = expanded; toggle.visible = not expanded
	var available := maxf(60.0, view.y - lift - 16.0)
	var height := minf(210.0 * s, available)
	history.visible = available > 230.0 * s
	heading.visible = available > 150.0 * s
	notice.visible = available > 150.0 * s
	panel.position = Vector2(view.x - width - 12.0 * s, maxf(8.0, view.y - lift - height - 8.0))
	panel.size = Vector2(width, height)
	title.add_theme_font_size_override("font_size", maxi(12, roundi(15.0 * s)))
	close.custom_minimum_size = Vector2(44, 44) * s
	close.add_theme_font_size_override("font_size", roundi(22 * s))
	field.custom_minimum_size = Vector2(0, maxf(44.0, 44.0 * s))
	send.custom_minimum_size = Vector2(maxf(48.0, 56.0 * s), maxf(44.0, 44.0 * s))
	history.custom_minimum_size.y = 65.0 * s
	for control in [field, send, notice]: control.add_theme_font_size_override("font_size", maxi(12, roundi(15.0 * s)))
	history.add_theme_font_size_override("normal_font_size", maxi(12, roundi(15.0 * s)))
	toggle.position = Vector2(view.x - 170.0 * s - 12.0 * s, view.y - 48.0 * s - 12.0 * s)
	toggle.size = Vector2(170.0 * s, 48.0 * s)
