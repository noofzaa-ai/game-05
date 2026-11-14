extends CanvasLayer
## Explicit online room entry. Solo and party share the same server-owned account profile.
signal closed
const Words := preload("res://client/online/online_text.gd")
const Link := preload("res://client/online/invite_link.gd")
const TEXT := {"friends": "เพื่อน/คำเชิญ", "copied": "คัดลอกลิงก์เชิญแล้ว", "connecting": "กำลังเข้าแคมป์ปาร์ตี้…"}
const InkUi := preload("res://client/ink_ui.gd")
const CarvedLook := preload("res://client/carved_look.gd")
var service
var companion := ""
var companion_seed := ""
var invite_target := ""
var invite_match := ""
var incoming_invite := {}
var _companion_started := false
var names = preload("res://client/online/name_client.gd").new()
var profiles = preload("res://client/online/profile_client.gd").new()
var rooms = preload("res://client/online/room_client.gd").new()
var name_field: LineEdit
var room_field: LineEdit
var capacity: OptionButton
var note: Label
var _busy := false
var _room := ""
var _notification := ""

var _roster
var _tools: HBoxContainer
var _tools_open := false
var _more_button: Button
var _connection: Label
var _connect_button: Button
var _panel: PanelContainer
var _center: CenterContainer

func _ready() -> void:
	layer = 30
	service = get_node("/root/Online")
	var dim := ColorRect.new(); dim.color = InkUi.SCRIM; dim.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(dim)
	_center = CenterContainer.new(); dim.add_child(_center)
	_panel = PanelContainer.new(); _panel.custom_minimum_size = Vector2(1060, 540); InkUi.panel(_panel, CarvedLook.board_box()); _center.add_child(_panel)
	_panel.theme = CarvedLook.dialog_theme()  # carved look (Boss 2026-11-14)
	var box := VBoxContainer.new(); InkUi.gap(box, 10); _panel.add_child(box)
	var heading := HBoxContainer.new(); box.add_child(heading)
	var title := InkUi.brush_title("เล่นออนไลน์", 28); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.add_child(title)
	capacity = OptionButton.new()
	for count in range(1, 5): capacity.add_item("%d คน" % count)
	capacity.select(3); capacity.custom_minimum_size = Vector2(90, 44); heading.add_child(capacity)
	button(heading, "+ สร้างห้อง", _create)
	InkUi.add_close(heading, _close)
	note = Label.new(); note.custom_minimum_size.y = 32; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(note)
	var tools := HBoxContainer.new(); _tools = tools; box.add_child(tools)
	button(tools, "จัดการเพื่อน", _friends)
	button(tools, "รีเฟรช", _refresh_roster)
	button(tools, "กลับห้องเดิม", _resume)
	var advanced := VBoxContainer.new()
	var toggle := Button.new(); toggle.text = "ชื่อ / รหัสเชิญ"; toggle.custom_minimum_size.y = 44
	toggle.pressed.connect(func(): advanced.visible = not advanced.visible; _fit.call_deferred(_center))
	tools.add_child(toggle); box.add_child(advanced)
	name_field = LineEdit.new(); name_field.placeholder_text = "ชื่อตัวละครออนไลน์"; name_field.custom_minimum_size.y = 44; name_field.virtual_keyboard_enabled = true; advanced.add_child(name_field)
	var codes := HBoxContainer.new(); advanced.add_child(codes)
	room_field = LineEdit.new(); room_field.placeholder_text = "วางรหัสห้องที่เพื่อนส่งมา"; room_field.custom_minimum_size.y = 44; room_field.virtual_keyboard_enabled = true; room_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; codes.add_child(room_field)
	button(codes, "เข้าห้อง", _join)
	button(codes, "คัดลอกรหัส", _copy)
	var pending := Link.consume()
	advanced.visible = not pending.is_empty()
	if not pending.is_empty(): room_field.text = pending.room + ":" + pending.invite
	_roster = preload("res://client/online/online_roster.gd").new(); _roster.account = service; _roster.custom_minimum_size.y = 240; _roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster.join_friend.connect(_join_friend); _roster.invite_friend.connect(_invite_friend); _roster.accepted.connect(_accept_invite)
	_roster.message.connect(func(text): note.text = text); box.add_child(_roster)
	var footer := HBoxContainer.new(); box.add_child(footer)
	_connection = Label.new(); footer.add_child(_connection)
	_connect_button = button(footer, "เชื่อมต่อ", _connect)
	_more_button = button(footer, "เพิ่มเติม", func(): _tools_open = not _tools_open; _fit.call_deferred(_center))
	service.changed.connect(_status_changed)
	_status_changed()
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(spacer)

	get_viewport().size_changed.connect(_fit.bind(_center)); _fit.call_deferred(_center)
	var timer := Timer.new(); timer.wait_time = 15; timer.timeout.connect(_refresh_roster); add_child(timer); timer.start()
	if service.status == service.Status.AUTHENTICATED: _load_name()
	else: note.text = "เชื่อมต่อบัญชีก่อน · โหมดนี้ใช้ไอเทมที่เซิร์ฟเวอร์บันทึกไว้"

func _fit(center: Control) -> void:
	var size := get_viewport().get_visible_rect().size
	var small := DisplayServer.window_get_size().y <= 520 or size.y < 500
	_tools.visible = not small or _tools_open
	_more_button.visible = small
	_panel.custom_minimum_size = Vector2(800, 340) if small else Vector2(1060, 540)
	_roster.custom_minimum_size.y = 150 if small else 240
	note.custom_minimum_size.y = 24 if small else 32
	var minimum := _panel.get_combined_minimum_size().max(_panel.custom_minimum_size)
	var factor := maxf(0.1, minf((size.x - 24) / minimum.x, (size.y - 24) / minimum.y))
	center.scale = Vector2.ONE * factor
	center.size = size / factor
	center.set_deferred("size", size / factor)

func _refresh_roster() -> void:
	if _busy or _roster == null or not is_inside_tree(): return
	_roster.refresh()

func _join_friend(id: String) -> void:
	if _busy or not _room.is_empty(): return
	_busy = true
	if not await _prepare(): _busy = false; return
	var result: Dictionary = await rooms.join_friend(service, id)
	_busy = false
	if not is_inside_tree(): return
	if not result.get("ok", false): note.text = Words.message(str(result.get("error", "unavailable"))); _refresh_roster(); return
	room_field.text = ""
	_enter(result)

func _invite_friend(id: String) -> void:
	if _busy or not _room.is_empty(): return
	_busy = true
	if not await _prepare(): _busy = false; return
	var result: Dictionary = await rooms.create(service, maxi(2,capacity.selected+1), true)
	if not result.get("ok", false): _busy = false; note.text = Words.message(str(result.get("error", "unavailable"))); return
	room_field.text = result.room + ":" + str(result.get("invite", ""))
	var values := {"target":id,"room":result.room,"invite":result.invite}
	if not invite_match.is_empty() and not id.begins_with("companion:"): values.match = invite_match
	var invitation: Dictionary = await preload("res://client/online/social_client.gd").new().call_rpc(service,"invite",values)
	_busy = false
	if not is_inside_tree(): return
	if not invitation.get("ok", false):
		await rooms.cancel(service, result.room)
		note.text = "ส่งคำเชิญไม่สำเร็จ: " + Words.message(str(invitation.get("error", "unavailable")))
		return
	if invitation.get("pending",false): result["companion_pending"] = true
	_enter(result)

func _status_changed() -> void:
	var connected: bool = service.status == service.Status.AUTHENTICATED
	_connection.text = "● Connected" if connected else "○ ยังไม่เชื่อมต่อ"
	_connection.modulate = Color(0.3, 0.85, 0.6) if connected else Color.WHITE
	_connect_button.visible = not connected

func button(parent: Control, label: String, callback: Callable) -> Button:
	var item := Button.new(); item.text = label; item.custom_minimum_size = Vector2(120, 42); item.pressed.connect(callback); parent.add_child(item)
	return item

func _load_name() -> void:
	var result: Dictionary = await names.get_name(service)
	if not is_inside_tree(): return
	if result.get("ok", false): name_field.text = result.name if not result.name.is_empty() else GameState.profile.name
	note.text = "เล่นผจญภัยกับเพื่อนของคุณ"
	if not _companion_started:
		_companion_started = true
		if not incoming_invite.is_empty(): _accept_invite.call_deferred(incoming_invite)
		elif not invite_target.is_empty(): _invite_friend.call_deferred(invite_target)
	_refresh_roster()
	var response = await service.client.rpc_async(service.session, "zorx_online_status_v1", JSON.stringify({"v": 1}))
	if not is_inside_tree(): return
	if not response.is_exception():
		var status = JSON.parse_string(response.payload)
		if status is Dictionary and status.get("maintenance", false): note.text = Words.message("maintenance")

func _connect() -> void:
	if _busy: return
	_busy = true; note.text = "กำลังเชื่อมต่อบัญชี…"
	await service.connect_account()
	_busy = false
	if service.status == service.Status.AUTHENTICATED: _load_name()
	else: note.text = "ยังเชื่อมต่อไม่ได้ กรุณาลองใหม่"

func _prepare() -> bool:
	note.text = "กำลังโหลดตัวละครออนไลน์…"
	var result: Dictionary = await names.claim(service, name_field.text)
	if not result.get("ok", false): note.text = "ตรวจชื่อไม่สำเร็จ: " + Words.message(str(result.get("error", "unavailable"))); return false
	result = await profiles.fetch(service)
	if not result.get("ok", false): note.text = "ยังโหลดข้อมูลไม่ได้ กรุณาลองใหม่"; return false
	return true

func _create() -> void:
	if _busy or not _room.is_empty(): return
	_busy = true
	if not await _prepare(): _busy = false; return
	var result: Dictionary = await rooms.create(service, maxi(2, capacity.selected + 1) if not companion.is_empty() else capacity.selected + 1, true, "", false, companion, companion_seed)
	_busy = false
	if not result.get("ok", false): note.text = "สร้างห้องไม่สำเร็จ: " + Words.message(str(result.get("error", "unavailable"))); return
	room_field.text = result.room + ":" + str(result.get("invite", ""))
	_enter(result)

func _join() -> void:
	if _busy or not _room.is_empty(): return
	var code := Link.parse(room_field.text)
	if code.is_empty(): note.text = "วางรหัสห้องให้ครบตามที่เพื่อนส่งมา"; return
	_busy = true
	if not await _prepare(): _busy = false; return
	var result: Dictionary = await rooms.join(service, code.room, code.invite)
	_busy = false
	if not result.get("ok", false): note.text = "เข้าห้องไม่สำเร็จ: " + Words.message(str(result.get("error", "unavailable"))); return
	if not _notification.is_empty():
		_busy = true
		await preload("res://client/online/social_client.gd").new().call_rpc(service, "ack", {"id": _notification})
		_busy = false; _notification = ""
	_enter(result)

func _enter(ticket: Dictionary) -> void:
	_room = ticket.room
	var code := Link.parse(room_field.text)
	GameState.party_invite = str(ticket.get("invite", code.get("invite", "")))
	if GameState.attach_online_room(service, ticket) == null: _room = ""; note.text = "ยังเชื่อมต่อห้องไม่ได้"; return
	note.text = TEXT.connecting

func _copy() -> void:
	var code := Link.parse(room_field.text)
	if not code.is_empty(): DisplayServer.clipboard_set(Link.create(code.room, code.invite)); note.text = TEXT.copied

func _close() -> void:
	if _busy: return
	if not _room.is_empty():
		_busy = true
		var result: Dictionary = await rooms.cancel(service, _room)
		_busy = false
		if not result.get("ok", false): note.text = "รอบเริ่มแล้ว กรุณากลับเข้าห้องเดิม"; return
		GameState.stop_online_room()
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _resume() -> void:
	if _busy: return
	_busy = true
	var result: Dictionary = await rooms.resume(service)
	_busy = false
	if result.get("ok", false): _enter(result)
	else: note.text = "ยังกลับห้องเดิมไม่ได้ หรือห้องจบแล้ว"

func _friends() -> void:
	if _busy: return
	_busy = true
	if not await _prepare(): _busy = false; return
	_busy = false
	var panel = preload("res://client/online/social_panel.gd").new()
	panel.account = service; panel.room = _room; panel.invite = GameState.party_invite
	panel.accepted.connect(_accept_invite)
	add_child(panel)

func _accept_invite(value: Dictionary) -> void:
	_notification = str(value.get("id", ""))
	room_field.text = str(value.room) + ":" + str(value.invite)
	_join()
