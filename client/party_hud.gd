extends CanvasLayer
## Presentation only: readiness, health and pings come from the authoritative room.
signal request(command: Dictionary)
signal invite_requested
const Ink := preload("res://client/ink_ui.gd")
const Words := preload("res://client/online/online_text.gd")
const Fighter := preload("res://logic/fighter.gd")
const TEXT := {"ready": "พร้อม", "unready": "ยกเลิกพร้อม", "depart": "ออกเดินทาง", "invite": "เชิญเพื่อน", "leave": "ออกปาร์ตี้", "revive": "กดค้างช่วยเพื่อน", "here": "ตรงนี้", "danger": "ระวัง", "help": "ช่วยด้วย", "yes": "ตกลง", "leader": "หัวหน้า", "down": "ล้ม", "out": "ออกจากการต่อสู้", "wait": "รอเพื่อนพร้อม", "offline": "ขาดการเชื่อมต่อ", "communicate": "สื่อสาร"}
var session
var revive_held := false
var _root: Control
var _roster: VBoxContainer
var _actions: HBoxContainer
var _ready_button: Button
var _depart: Button
var _revive: Button
var _note: Label
var _ping_toggle: Button
var _key := ""
var _refresh_left := 0.0
var _presence := {}

func _ready() -> void:
	layer = 12
	_root = Control.new(); _root.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_root)
	_root.theme = Ink.make_theme()
	_roster = VBoxContainer.new(); _roster.mouse_filter = Control.MOUSE_FILTER_IGNORE; _roster.position = Vector2(16, 150); _roster.custom_minimum_size.x = 220; _root.add_child(_roster)
	_actions = HBoxContainer.new(); _root.add_child(_actions)
	_ready_button = _button(_actions, TEXT.ready, _toggle_ready)
	_depart = _button(_actions, TEXT.depart, func(): request.emit({"type": "party_depart"}))
	_button(_actions, TEXT.invite, func(): invite_requested.emit())
	_button(_actions, TEXT.leave, func(): request.emit({"type": "party_leave"}))
	var pings := HBoxContainer.new(); pings.name = "Pings"; _root.add_child(pings)
	pings.visible = false
	_ping_toggle = _button(_root, TEXT.communicate, func(): pings.visible = not pings.visible)
	for kind in ["here", "danger", "help", "yes"]: _button(pings, TEXT[kind], func(): request.emit({"type": "party_ping", "kind": kind}); pings.hide())
	_revive = _button(_root, TEXT.revive, func(): pass)
	_revive.button_down.connect(func(): revive_held = true)
	_revive.button_up.connect(func(): revive_held = false)
	_note = Label.new(); _root.add_child(_note)
	get_viewport().size_changed.connect(_fit); _fit()
	set_process(true)

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new(); button.text = caption; button.custom_minimum_size = Vector2(100, 46); button.pressed.connect(action); parent.add_child(button); return button

func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	var factor := minf(size.x / 1000.0, size.y / 600.0)
	_root.scale = Vector2.ONE * factor; _root.size = size / factor
	var press_height := 70.0 if DisplayServer.window_get_size().y <= 520 or DisplayServer.is_touchscreen_available() else 46.0
	for control in _root.find_children("*", "Button", true, false): control.custom_minimum_size.y = press_height
	_actions.position = Vector2((_root.size.x - 440) / 2 - 70, _root.size.y - press_height - 20)
	_root.get_node("Pings").position = Vector2((_root.size.x - 420) / 2, _root.size.y - 210)
	_ping_toggle.position = Vector2(16, 260)
	_revive.position = Vector2((_root.size.x - 180) / 2, _root.size.y - 120)
	_note.position = Vector2((_root.size.x - 440) / 2, _root.size.y - 150)

func _toggle_ready() -> void:
	for member in session.party_view().get("members", []):
		if int(member.id) == session.player_id(): request.emit({"type": "party_ready", "ready": not member.ready})

func show_result(result: Dictionary) -> void:
	_note.text = "" if result.get("ok", false) else Words.message(str(result.get("error", "unavailable")))

func _process(delta: float) -> void:
	if session == null or not session.ready: return
	_refresh_left -= delta
	if _refresh_left > 0: return
	_refresh_left = 0.1
	if not session.connected: _note.text = Words.message(session.error)
	var party: Dictionary = session.party_view()
	_actions.visible = session.is_lobby()
	var next_presence := {}
	for member in party.get("members", []):
		next_presence[int(member.id)] = {"name": member.name, "connected": member.connected}
		if _presence.has(int(member.id)) and _presence[int(member.id)].connected != member.connected: _note.text = Words.message("friend_reconnected" if member.connected else "friend_disconnected") % member.name
	for id in _presence:
		if not next_presence.has(id): _note.text = Words.message("friend_left") % _presence[id].name
	_presence = next_presence
	var all_ready := true
	var signature := ""
	var nearby := false
	for member in party.get("members", []):
		var id := int(member.id)
		all_ready = all_ready and member.ready and member.connected
		if id == session.player_id(): _ready_button.text = TEXT.unready if member.ready else TEXT.ready
		if not session.fighters.has(id): continue
		var fighter = session.fighters[id]
		var suffix := "✓" if member.ready else ""
		if not member.connected: suffix = TEXT.offline
		elif fighter.eliminated: suffix = TEXT.out
		elif fighter.state == Fighter.State.DOWNED:
			suffix = "%s %.1fs · %d%%" % [TEXT.down, fighter.bleedout_left / 60.0, fighter.revive_progress * 100 / maxi(1, int(session.combat.coop.revive_ticks))]
			if id != session.player_id() and session.bodies.has(session.player_id()): nearby = nearby or session.bodies[id].position.distance_to(session.bodies[session.player_id()].position) <= 1.6
		signature += "%s%s %.0f/%.0f %s\n" % ["◆ " if id == int(party.get("leader", -1)) else "", member.name, fighter.hp, fighter.max_hp(), suffix]
	if signature != _key:
		_key = signature
		for child in _roster.get_children(): child.free()
		for line in signature.strip_edges().split("\n"):
			var label := Ink.label(line, Ink.PAPER, 16); _roster.add_child(label)
	_depart.disabled = not all_ready or session.player_id() != int(party.get("leader", -1)) or party.get("departing", false)
	_revive.visible = nearby and not session.is_lobby()
	if not _revive.visible: revive_held = false
