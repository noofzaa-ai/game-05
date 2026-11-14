extends HBoxContainer
## Friends and invitations are separate, independently scrollable lists.
signal join_friend(id: String)
signal invite_friend(id: String)
signal accepted(entry: Dictionary)
signal message(text: String)
const InkUi := preload("res://client/ink_ui.gd")
const CarvedLook := preload("res://client/carved_look.gd")
const Words := preload("res://client/online/online_text.gd")
var account
var social = preload("res://client/online/social_client.gd").new()
var _friends: VBoxContainer
var _invites: VBoxContainer
var _friend_title: Label
var _invite_title: Label
var _refreshing := false
var _cursor := ""
var _inbox_cursor := ""
var _people: Array = []
var _entries: Array = []

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_friend_title = Label.new(); _friend_title.text = "เพื่อน"
	_invite_title = Label.new(); _invite_title.text = "คำเชิญ"
	_friends = _column(_friend_title)
	_invites = _column(_invite_title)

func _column(title: Label) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", CarvedLook.dialog_theme().get_stylebox("panel", "PanelContainer"))  # parchment inset
	add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 14); panel.add_child(box)
	title.add_theme_font_size_override("font_size", 24); title.add_theme_color_override("font_color", CarvedLook.CardTokens.HUB_INK); box.add_child(title)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS; box.add_child(scroll)
	InkUi.inventory_scrollbar(scroll.get_v_scroll_bar(), true)
	scroll.get_v_scroll_bar().custom_minimum_size.x = 18
	var margin := MarginContainer.new(); margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; margin.add_theme_constant_override("margin_right", 28); scroll.add_child(margin)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 10); margin.add_child(list)
	return list

func _button(parent: Control, caption: String, action: Callable, disabled: bool = false) -> Button:
	var button := Button.new(); button.text = caption; button.custom_minimum_size = Vector2(96, 44); button.disabled = disabled; button.pressed.connect(action); parent.add_child(button); return button

func _card(list: Control) -> VBoxContainer:
	var card := PanelContainer.new(); card.add_theme_stylebox_override("panel", CarvedLook.dialog_theme().get_stylebox("panel", "PanelContainer")); list.add_child(card)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 8); card.add_child(box); return box

func _label(parent: Control, text: String, small: bool = false) -> Label:
	var label := Label.new(); label.text = text; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 15 if small else 19); parent.add_child(label); return label

func refresh(more_friends: bool = false, more_invites: bool = false) -> void:
	if _refreshing or account == null: return
	_refreshing = true
	var result: Dictionary = await social.call_rpc(account, "list", {"cursor": _cursor} if more_friends else {})
	if not is_inside_tree(): return
	var inbox: Dictionary = await social.call_rpc(account, "inbox", {"cursor": _inbox_cursor} if more_invites else {})
	_refreshing = false
	if not is_inside_tree(): return
	if not result.get("ok", false): message.emit(Words.message(str(result.get("error", "unavailable")))); return
	if not inbox.get("ok", false): message.emit(Words.message(str(inbox.get("error", "unavailable")))); return
	if more_friends: _people.append_array(result.get("friends", []))
	elif not more_invites: _people = result.get("friends", [])
	if more_invites: _entries.append_array(inbox.get("invites", []))
	elif not more_friends: _entries = inbox.get("invites", [])
	if not more_invites: _cursor = str(result.get("cursor", ""))
	if not more_friends: _inbox_cursor = str(inbox.get("cursor", ""))
	_render()

func _render() -> void:
	for list in [_friends, _invites]:
		for child in list.get_children(): list.remove_child(child); child.queue_free()
	var online := 0
	for friend in _people:
		if int(friend.get("state", 0)) == 0 and friend.get("online", false): online += 1
		var box := _card(_friends); var row := HBoxContainer.new(); box.add_child(row)
		var details := VBoxContainer.new(); details.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(details)
		_label(details, str(friend.get("name", "Player")))
		var state := int(friend.get("state", 0)); var room = friend.get("room")
		var status := "ออฟไลน์"
		if state == 2: status = "ขอเป็นเพื่อน"
		elif state == 1: status = "รอตอบรับคำขอเป็นเพื่อน"
		elif room is Dictionary: status = ("กำลังผจญภัย" if room.get("started", false) else "อยู่ในห้อง") + " · %d/%d" % [int(room.get("count", 0)), int(room.get("capacity", 4))]
		elif friend.get("online", false): status = "อยู่ที่ Camp"
		_label(details, status, true)
		if state == 2: _button(row, "รับเพื่อน", _friend_action.bind("accept", {"target": friend.id}))
		elif state == 0:
			if room is Dictionary:
				var can_join: bool = room.get("joinable", false)
				_button(row, "เข้าร่วม" if can_join else "ยังเข้าไม่ได้", func(): join_friend.emit(str(friend.id)), not can_join)
			elif friend.get("online", false): _button(row, "ชวนเล่น", func(): invite_friend.emit(str(friend.id)))
	_friend_title.text = "เพื่อน · %d Online" % online
	_invite_title.text = "คำเชิญ · %d รายการ" % _entries.size()
	if _people.is_empty(): _label(_friends, "ยังไม่มีเพื่อน · กดจัดการเพื่อนเพื่อเพิ่ม", true)
	for entry in _entries:
		var box := _card(_invites); _label(box, str(entry.get("name", "Player")))
		if DisplayServer.window_get_size().y > 520: _label(box, "ชวนเข้าร่วมทีม", true)
		var row := HBoxContainer.new(); box.add_child(row)
		var yes := _button(row, "ยอมรับ", func(): accepted.emit(entry)); yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var no := _button(row, "ปฏิเสธ", _friend_action.bind("ack", {"id": entry.id})); no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _entries.is_empty(): _label(_invites, "คำเชิญใหม่จะแสดงที่นี่", true)
	if not _cursor.is_empty(): _button(_friends, "เพื่อนเพิ่มเติม", refresh.bind(true, false))
	if not _inbox_cursor.is_empty(): _button(_invites, "คำเชิญเพิ่มเติม", refresh.bind(false, true))

func _friend_action(operation: String, values: Dictionary) -> void:
	if _refreshing: return
	_refreshing = true
	var result: Dictionary = await social.call_rpc(account, operation, values)
	_refreshing = false
	if not is_inside_tree(): return
	if not result.get("ok", false): message.emit(Words.message(str(result.get("error", "unavailable"))))
	else: refresh()
