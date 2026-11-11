extends Control
## Camp feedback composer. Identity/time are assigned by the authenticated server.
const InkUi := preload("res://client/ink_ui.gd")
var _box: PanelContainer
var _text: TextEdit
var _status: Label
var _counter: Label
var _send: Button
var _close: Button
var _busy := false
var _request := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	var shade := ColorRect.new()
	shade.color = InkUi.SCRIM_STRONG
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_box = PanelContainer.new()
	InkUi.panel(_box, InkUi.panel_style())
	add_child(_box)
	var content := VBoxContainer.new()
	InkUi.gap(content, InkUi.GAP_S)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var outer := VBoxContainer.new()
	_box.add_child(outer)
	outer.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var title := InkUi.label("Feedback / แจ้งปัญหา", InkUi.GOLD, InkUi.FONT_SECTION)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var header := HBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	outer.add_child(header)
	outer.move_child(header, 0)
	var help := InkUi.label("ส่งถึงทีมพัฒนา · กรุณาอย่าส่งรหัสผ่านหรือข้อมูลส่วนตัว", InkUi.PAPER, InkUi.FONT_BODY)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(help)
	_text = TextEdit.new()
	_text.placeholder_text = "พบปัญหาอะไร หรืออยากเสนอแนะอะไรบ้าง?"
	_text.custom_minimum_size = Vector2(0, 80)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.virtual_keyboard_enabled = true
	_text.text_changed.connect(_changed)
	content.add_child(_text)
	_counter = InkUi.label("0 / 2000", InkUi.PAPER, InkUi.FONT_BODY)
	content.add_child(_counter)
	_status = InkUi.label("", InkUi.GOLD, InkUi.FONT_BODY)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	_send = Button.new(); _send.text = "ส่ง Feedback"; _send.custom_minimum_size.y = 44
	_send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send.pressed.connect(_submit)
	actions.add_child(_send)
	_close = Button.new(); InkUi.close_button(_close)
	_close.pressed.connect(queue_free)
	header.add_child(_close)
	resized.connect(_fit)
	_box.minimum_size_changed.connect(func(): _fit.call_deferred())
	_fit(); _changed()

func _fit() -> void:
	if _box == null: return
	_box.size = Vector2(minf(640, maxf(240, size.x - 32)), minf(430, maxf(120, size.y - 24)))
	_box.position = (size - _box.size) * 0.5

func _changed() -> void:
	_counter.text = "%d / 2000" % _text.text.length()
	_send.disabled = _busy or _text.text.strip_edges().length() < 3 or _text.text.length() > 2000
	if not _busy and _request.get("message", "") != _text.text.strip_edges(): _request.clear()

func _submit() -> void:
	if _busy or _send.disabled: return
	var account = get_node_or_null("/root/Online")
	if account == null or account.session == null or account.client == null:
		_status.text = "กรุณาเข้าสู่ระบบก่อนส่ง Feedback"; return
	if _request.is_empty():
		var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/build_info.json")) if FileAccess.file_exists("res://data/ui/build_info.json") else {}
		_request = {"v": 1, "request_id": Crypto.new().generate_random_bytes(16).hex_encode(), "message": _text.text.strip_edges(), "platform": "web" if OS.has_feature("web") else "native", "version": str(metadata.get("short_commit", "development")) if metadata is Dictionary else "development"}
	_busy = true; _text.editable = false; _close.disabled = true; _changed()
	_status.text = "กำลังส่ง…"
	var uid: String = account.session.user_id
	var response = await account.client.rpc_async(account.session, "zorx_feedback_v1", JSON.stringify(_request))
	if not is_inside_tree(): return
	_busy = false; _text.editable = true; _close.disabled = false
	var result = null if response == null or response.is_exception() or response.payload.length() > 4096 else JSON.parse_string(response.payload)
	if account.session == null or account.session.user_id != uid: result = null
	if result is Dictionary and result.get("ok") == true:
		_request.clear(); _text.text = ""; _status.text = "ส่ง Feedback แล้ว ขอบคุณครับ"
	elif result is Dictionary and result.get("error") == "rate_limited":
		_status.text = "ส่งได้ครั้งละ 1 นาที กรุณารอสักครู่แล้วลองใหม่"
	else:
		_status.text = "ยังส่งไม่สำเร็จ ข้อความยังอยู่ กดส่งเพื่อลองใหม่ได้"
	_changed()
