extends CanvasLayer
## The character creator, shown when the game starts with a character not made yet: the player names
## the character and picks its looks (the same Look panel as at camp, plus a dice button), then Start.
## It changes the profile only through LocalSession.command(); it decides nothing.
## Scaled per screen like the camp screens (InkUi.layout_for).

signal created  ## the character is made (the profile has its name and looks)

const LocalSession := preload("res://client/session/local_session.gd")
var session

const InkUi := preload("res://client/ink_ui.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const LookPanel := preload("res://client/look_panel.gd")
const NameClient := preload("res://client/online/name_client.gd")
const OnlineAccount := preload("res://client/online/online_account.gd")
const Profile := preload("res://logic/profile.gd")

## Words the player sees (one place, for translation).
const TEXT := {
	"rate_limited": "ส่งคำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่",
	"title": "Create your character",
	"name_hint": "Name",
	"random": "Random look",
	"start": "Start",
	"too_short": "The name needs at least %d letters.",
	"too_long": "The name can be at most %d letters.",
	"bad_characters": "Use letters, numbers, spaces, _ or - in the name.",
	"checking": "กำลังตรวจและจองชื่อ…",
	"invalid_payload": "ข้อมูลชื่อไม่ถูกต้อง กรุณาลองใหม่",
	"name_taken": "ชื่อนี้ถูกใช้แล้ว กรุณาเลือกชื่ออื่น (ตัวพิมพ์ใหญ่/เล็กถือว่าซ้ำกัน)",
	"conflict": "มีคำขอเปลี่ยนชื่อพร้อมกัน กรุณาลองอีกครั้ง",
	"unavailable": "ยังยืนยันชื่อออนไลน์ไม่ได้ กรุณาลองใหม่",
	"not_online": "บัญชีไม่ได้เชื่อมต่อ กรุณาเชื่อมต่อใหม่",
	"connection_changed": "การเชื่อมต่อเปลี่ยนไป กรุณาลองอีกครั้ง",
	"offline": "เล่นออฟไลน์",
}

var profile
var look  ## LookPanel
var name_field: LineEdit
var start_button: Button
var _problem: Label
var _root: Control
var _margin: MarginContainer
var _layout_mode := InkUi.WIDE
var online_account_override  ## Fake account for isolated UI tests only.
var _names := NameClient.new()
var _name_ticket := 0
var _name_pending := false
var _require_online_name := false
var _prefill_text := ""
var _offline_button: Button
var _finish_id := -1


func setup(player_profile, item_rules, combat_data, command_session = null) -> void:
	session = command_session if command_session != null else LocalSession.for_menu(player_profile, item_rules)
	profile = player_profile
	if session.has_signal("command_completed"): session.command_completed.connect(_server_created)
	layer = 25
	var dim := ColorRect.new()
	dim.color = InkUi.SCRIM_STRONG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_root = Control.new()
	_root.name = "Creator"
	_root.theme = InkUi.make_theme()
	add_child(_root)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	var panel := PanelContainer.new()
	InkUi.panel(panel, InkUi.window_style())
	_margin.add_child(panel)
	var column := VBoxContainer.new()
	InkUi.gap(column, InkUi.GAP_L)
	panel.add_child(column)
	var title := Label.new()
	title.text = TEXT["title"]
	InkUi.style_text(title, InkUi.PAPER, InkUi.FONT_TITLE)
	var header := HBoxContainer.new()
	header.add_child(title)
	InkUi.add_close(header, func():
		if _name_pending: return
		get_tree().change_scene_to_file("res://scenes/card_deck_screen.tscn")  # the hub (no title screen, Boss 2026-11-13)
		queue_free())
	column.add_child(header)

	look = LookPanel.new()
	look.fit_preview_height = true
	look.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(look)
	look.setup(profile, item_rules, combat_data, session)

	var row := HFlowContainer.new()
	InkUi.gap(row, InkUi.GAP_L, InkUi.GAP_M)
	column.add_child(row)
	name_field = LineEdit.new()
	name_field.virtual_keyboard_enabled = true
	name_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	name_field.placeholder_text = TEXT["name_hint"]
	name_field.max_length = Profile.NAME_MAX
	name_field.custom_minimum_size = Vector2(260.0, 48.0)
	name_field.text = profile.name
	name_field.text_changed.connect(func(_text: String) -> void: _check_name())
	name_field.text_submitted.connect(func(_text: String) -> void: _start())
	row.add_child(name_field)
	row.add_child(_button(TEXT["random"], randomize_look))
	start_button = _button(TEXT["start"], _start)
	InkUi.make_primary(start_button)
	row.add_child(start_button)
	_offline_button = _button(TEXT["offline"], _choose_offline)
	row.add_child(_offline_button)
	var account = _online_account()
	_require_online_name = account != null and account.status == OnlineAccount.Status.AUTHENTICATED
	_offline_button.visible = false
	_names.completed.connect(_on_name_response)
	_problem = Label.new()
	InkUi.style_text(_problem, InkUi.BAD)
	_problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_problem)
	_check_name()
	_apply_layout()
	if not get_viewport().size_changed.is_connected(_apply_layout):
		get_viewport().size_changed.connect(_apply_layout)
	# Do not summon a phone keyboard before the player taps the name.
	if _layout_mode == InkUi.WIDE:
		name_field.grab_focus()
	if _require_online_name:
		_prefill_online_name.call_deferred()


## The dice: a random pick for every part of the look.
func randomize_look() -> void:
	if not session.command({"type": "randomize_appearance"})["ok"]:
		return
	look.refresh()
	look.changed.emit()


## What is wrong with the typed name ("" = fine). Shows it once something has been typed.
func _check_name() -> String:
	var problem := Profile.name_problem(name_field.text)
	start_button.disabled = _name_pending or not problem.is_empty()
	_problem.text = "" if problem.is_empty() or name_field.text.is_empty() else _problem_text(problem)
	_problem.visible = not _problem.text.is_empty()
	return problem


func _problem_text(problem: String) -> String:
	match problem:
		"too_short":
			return TEXT[problem] % Profile.NAME_MIN
		"too_long":
			return TEXT[problem] % Profile.NAME_MAX
	return TEXT.get(problem, problem)


func _start() -> void:
	if _name_pending or not _check_name().is_empty():
		return
	if _require_online_name:
		var account = _online_account()
		if account == null or account.status != OnlineAccount.Status.AUTHENTICATED:
			_show_name_error("not_online")
			return
		_name_ticket += 1
		_name_pending = true
		name_field.editable = false
		start_button.disabled = true
		_problem.text = TEXT["checking"]
		InkUi.style_text(_problem, InkUi.MUTED)
		_problem.show()
		_names.begin_claim(account, name_field.text, _name_ticket)
		return
	_finish_local_name(name_field.text)


func _finish_local_name(value: String) -> void:
	var result: Dictionary = session.command({"type": "set_name", "name": value})
	if result.get("pending", false):
		_finish_id = result.id
		_name_pending = true
		name_field.editable = false
		_check_name()
		return
	if not result["ok"]:
		_show_name_error(str(result["error"]))
		return
	created.emit()
	queue_free()


func _online_account():
	return online_account_override if online_account_override != null else get_node_or_null("/root/Online")


func _prefill_online_name() -> void:
	if _name_pending or not is_inside_tree():
		return
	_prefill_text = name_field.text
	_name_ticket += 1
	_names.begin_get(_online_account(), _name_ticket)


func _on_name_response(operation: String, ticket: int, result: Dictionary) -> void:
	if ticket != _name_ticket or not is_inside_tree():
		return
	if operation == "get":
		if result.ok and not result.name.is_empty() and name_field.text == _prefill_text:
			name_field.text = result.name
			_check_name()
		return
	_name_pending = false
	name_field.editable = true
	_check_name()
	if not result.ok:
		_show_name_error(str(result.error))
		return
	_finish_local_name(str(result.name))


func _show_name_error(problem: String) -> void:
	_problem.text = _problem_text(problem)
	InkUi.style_text(_problem, InkUi.BAD)
	_problem.show()


func _choose_offline() -> void:
	_name_ticket += 1
	_name_pending = false
	_require_online_name = false
	var account = _online_account()
	if account != null:
		account.use_offline()
	name_field.editable = true
	_start()


func _apply_layout() -> void:
	if _root == null or not is_inside_tree():
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		window = logical
	var layout: Dictionary = InkUi.layout_for(window, logical, DisplayServer.screen_get_scale())
	_root.scale = Vector2.ONE * float(layout["scale"])
	_root.size = layout["size"]
	InkUi.margins(_margin, InkUi.edge_for(layout["mode"]))
	look.set_mode(layout["mode"])
	_layout_mode = layout["mode"]
	var height := 48.0 if layout["mode"] == InkUi.WIDE else 58.0
	for child in name_field.get_parent().get_children():
		if child is Control:
			child.custom_minimum_size.y = height


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(140.0, 48.0)
	button.pressed.connect(callback)
	return button

func _server_created(id: int, result: Dictionary) -> void:
	if id != _finish_id: return
	_name_pending = false; _finish_id = -1
	name_field.editable = true
	if not result.get("ok", false):
		_show_name_error(str(result.get("error", "unavailable")))
		_check_name()
		return
	created.emit()
	queue_free()
