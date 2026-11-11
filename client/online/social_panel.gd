extends CanvasLayer
signal accepted(invite: Dictionary)
const InkUi := preload("res://client/ink_ui.gd")
const Words := preload("res://client/online/online_text.gd")
const TEXT := {"title": "เพื่อนและคำเชิญ", "add": "ขอเป็นเพื่อน", "refresh": "รีเฟรช", "close": "กลับ", "accept": "รับเป็นเพื่อน", "invite": "เชิญเข้าแคมป์", "join": "เข้าปาร์ตี้", "remove": "ลบ", "more": "โหลดเพิ่ม", "done": "สำเร็จ", "empty": "ยังไม่มีเพื่อนหรือคำเชิญ", "name": "ชื่อตัวละครของเพื่อน", "dismiss": "ปฏิเสธ", "more_invites": "คำเชิญเพิ่มเติม", "copy": "คัดลอกลิงก์เชิญ", "copied": "คัดลอกลิงก์แล้ว"}
var account
var room := ""
var invite := ""
var social = preload("res://client/online/social_client.gd").new()
var _box: VBoxContainer
var _list: VBoxContainer
var _note: Label
var _field: LineEdit
var _busy := false
var _cursor := ""
var _friends: Array = []
var _entries: Array = []
var _inbox_cursor := ""

func _ready() -> void:
	layer = 40
	var dim := ColorRect.new(); dim.color = InkUi.SCRIM; dim.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(dim)
	var center := CenterContainer.new(); dim.add_child(center)
	var panel := PanelContainer.new(); panel.theme = InkUi.make_theme(); InkUi.panel(panel, InkUi.window_style()); center.add_child(panel)
	_box = VBoxContainer.new(); _box.custom_minimum_size = Vector2(540, 300); InkUi.gap(_box, 8); panel.add_child(_box)
	var header := HBoxContainer.new()
	header.add_child(InkUi.brush_title(TEXT.title, 26))
	InkUi.add_close(header, queue_free)
	_box.add_child(header)
	_note = Label.new(); _note.custom_minimum_size.y = 28; _box.add_child(_note)
	var row := HBoxContainer.new(); _box.add_child(row)
	_field = LineEdit.new(); _field.placeholder_text = TEXT.name; _field.virtual_keyboard_enabled = true; _field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _field.custom_minimum_size.y = 44; row.add_child(_field)
	_button(row, TEXT.add, _request)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(540, 140); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; _box.add_child(scroll)
	_list = VBoxContainer.new(); _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_list)
	var actions := HBoxContainer.new(); _box.add_child(actions)
	_button(actions, TEXT.refresh, _refresh)
	if not room.is_empty() and not invite.is_empty(): _button(actions, TEXT.copy, func(): DisplayServer.clipboard_set(preload("res://client/online/invite_link.gd").create(room, invite)); _note.text = TEXT.copied)

	get_viewport().size_changed.connect(_fit.bind(center)); _fit(center)
	_refresh()

func _fit(center: Control) -> void:
	var size := get_viewport().get_visible_rect().size
	var pixels := Vector2(DisplayServer.window_get_size())
	var layout := InkUi.layout_for(pixels, size)
	var factor: float = minf(layout.scale, minf(size.x / 580, size.y / 350))
	if DisplayServer.is_touchscreen_available() or pixels.y <= 520: factor = minf(size.x / 580, size.y / 350)
	center.scale = Vector2.ONE * factor; center.size = size / factor; center.set_deferred("size", size / factor)

func _button(parent: Control, caption: String, action: Callable) -> void:
	var button := Button.new(); button.text = caption; button.custom_minimum_size = Vector2(105, 44); button.pressed.connect(action); parent.add_child(button)

func _request() -> void:
	await _action("request", {"name": _field.text})

func _action(operation: String, values: Dictionary) -> void:
	if _busy: return
	_busy = true
	var result: Dictionary = await social.call_rpc(account, operation, values)
	_busy = false
	if not is_inside_tree(): return
	_note.text = TEXT.done if result.get("ok", false) else Words.message(str(result.get("error", "unavailable")))
	if result.get("ok", false): _refresh()

func _refresh() -> void:
	if _busy: return
	_busy = true
	var result: Dictionary = await social.call_rpc(account, "list")
	var inbox: Dictionary = await social.call_rpc(account, "inbox")
	_busy = false
	if not is_inside_tree(): return
	if not result.get("ok", false): _note.text = Words.message(str(result.get("error", "unavailable"))); return
	_friends = social.friends; _cursor = str(result.get("cursor", ""))
	_entries = inbox.get("invites", []); _inbox_cursor = str(inbox.get("cursor", ""))
	_render(_entries)

func _render(inbox: Array) -> void:
	for child in _list.get_children(): child.queue_free()
	if _friends.is_empty() and inbox.is_empty():
		var label := Label.new(); label.text = TEXT.empty; _list.add_child(label)
	for friend in _friends:
		var row := HBoxContainer.new(); _list.add_child(row)
		var label := Label.new(); label.text = str(friend.name); label.custom_minimum_size.x = 180; label.clip_text = true; row.add_child(label)
		if int(friend.state) == 2: _button(row, TEXT.accept, _action.bind("accept", {"target": friend.id}))
		elif int(friend.state) == 0 and not room.is_empty() and not invite.is_empty(): _button(row, TEXT.invite, _action.bind("invite", {"target": friend.id, "room": room, "invite": invite}))
		_button(row, TEXT.remove, _action.bind("remove", {"target": friend.id}))
	for entry in inbox:
		var row := HBoxContainer.new(); _list.add_child(row)
		var label := Label.new(); label.text = str(entry.name); label.custom_minimum_size.x = 180; label.clip_text = true; row.add_child(label)
		_button(row, TEXT.join, _accept.bind(entry))
		_button(row, TEXT.dismiss, _action.bind("ack", {"id": entry.id}))
	if not _cursor.is_empty(): _button(_list, TEXT.more, _more)
	if not _inbox_cursor.is_empty(): _button(_list, TEXT.more_invites, _more_invites)

func _more() -> void:
	if _busy: return
	_busy = true
	var result: Dictionary = await social.call_rpc(account, "list", {"cursor": _cursor})
	_busy = false
	if not is_inside_tree(): return
	if result.get("ok", false):
		_friends.append_array(result.friends); _cursor = str(result.get("cursor", "")); _render(_entries)
	else: _note.text = Words.message(str(result.get("error", "unavailable")))

func _accept(entry: Dictionary) -> void:
	accepted.emit(entry)
	queue_free()

func _more_invites() -> void:
	if _busy: return
	_busy = true
	var result: Dictionary = await social.call_rpc(account, "inbox", {"cursor": _inbox_cursor})
	_busy = false
	if not is_inside_tree(): return
	if result.get("ok", false):
		_entries.append_array(result.invites); _inbox_cursor = str(result.get("cursor", "")); _render(_entries)
	else: _note.text = Words.message(str(result.get("error", "unavailable")))
