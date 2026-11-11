extends Node3D
## Social presence only; account inventory/economy stays on the existing account session.
const InkUi := preload("res://client/ink_ui.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const Loadout := preload("res://logic/loadout.gd")
var hub
var socket
var match_id := ""
var actors := {}
var descriptions := {}
var joining := false
var retry := 0.0
var send_in := 0.0
var sending := false
var generation := 0
var status: Label
var layout_in := 0.0
var chat: Control
var chat_sending := false

func _ready() -> void:
	status = Label.new()
	status.text = ""
	if GameState.account_session != null:
		GameState.account_session.ownership_changed.connect(_appearance_changed)
	status.theme = InkUi.make_theme()
	status.add_theme_font_override("font", InkUi.font())
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	InkUi.style_text(status, InkUi.GOLD, InkUi.FONT_LABEL, 4)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(status)
	chat = preload("res://client/online/plaza_chat.gd").new()
	layer.add_child(chat)
	chat.submitted.connect(_send_chat)
	chat.hide()

func _process(delta: float) -> void:
	if hub == null: return
	layout_in -= delta
	if layout_in <= 0.0:
		layout_in = .5
		_fit_status()
	var at: Vector3 = hub.player_position()
	var inside := at.z <= -12.2
	status.visible = inside
	chat.visible = inside and not hub.has_open_panel()
	if not chat.visible and chat.field.has_focus(): chat.field.release_focus()
	if not inside:
		if socket != null or joining: _disconnect()
		return
	for uid in actors:
		var actor: Dictionary = actors[uid]
		actor.model.position = actor.model.position.lerp(actor.target, minf(1.0, delta * 12.0))
		actor.model.apply_pose(delta)
	retry -= delta
	if socket == null or not socket.is_connected_to_host():
		chat.set_connected(false)
		status.text = "ลานรวมพล · กำลังเชื่อมต่อ…"
		if not joining and retry <= 0.0: _join()
		return
	if match_id.is_empty(): return
	status.text = "ลานรวมพล · ผู้เล่น %d / 24" % (actors.size() + 1)
	send_in -= delta
	if send_in <= 0.0 and not sending:
		send_in = .2
		_send(at)

func _join() -> void:
	var online = get_node_or_null("/root/Online")
	if online == null or online.session == null or online.client == null:
		retry = 3.0
		return
	joining = true
	generation += 1
	var token := generation
	retry = 5.0
	if socket != null: socket.close()
	var next_socket = get_node("/root/Nakama").create_socket_from(online.client)
	next_socket.logger._level = NakamaLogger.LOG_LEVEL.NONE
	socket = next_socket
	next_socket.received_match_state.connect(_snapshot)
	var connected = await next_socket.connect_async(online.session, true, 5)
	if token != generation: return
	if connected.is_exception():
		_disconnect()
		return
	var response = await online.client.rpc_async(online.session, "zorx_plaza_v1", '{"v":1}')
	if token != generation: return
	if response.is_exception():
		_disconnect()
		return
	var payload = JSON.parse_string(response.payload)
	if not payload is Dictionary or not payload.get("ok", false):
		_disconnect()
		return
	var joined = await next_socket.join_match_async(str(payload.match))
	if token != generation: return
	if joined.is_exception():
		_disconnect()
		return
	match_id = str(payload.match)
	joining = false
	chat.set_connected(true)

func _send(at: Vector3) -> void:
	sending = true
	var token := generation
	var body = hub._sim.bodies[hub.PLAYER_ID]
	var flat := Vector2(body.velocity.x, body.velocity.z)
	await socket.send_match_state_async(match_id, 1, JSON.stringify({"x":at.x,"z":at.z,"fx":hub._facing.x,"fz":hub._facing.y,"speed":flat.length()/3.8}))
	if token == generation: sending = false

func _send_chat(text: String) -> void:
	if chat_sending or socket == null or not socket.is_connected_to_host() or match_id.is_empty(): return
	chat_sending = true
	var token := generation
	await socket.send_match_state_async(match_id, 3, JSON.stringify({"text": text}))
	if token != generation: return
	chat_sending = false

func _snapshot(message) -> void:
	if message.match_id != match_id: return
	if message.op_code == 4:
		var entry = JSON.parse_string(message.data)
		if entry is Dictionary and entry.get("name") is String and entry.get("text") is String:
			chat.add_message(entry.name, entry.text)
		return
	if message.op_code == 5:
		chat.show_error("ส่งถี่เกินไป รอสักครู่แล้วส่งใหม่")
		return
	if message.op_code != 2: return
	var payload = JSON.parse_string(message.data)
	if not payload is Dictionary or not payload.get("actors") is Array: return
	var online = get_node_or_null("/root/Online")
	if online == null or online.session == null: return
	var seen := {}
	var created := 0
	for entry in payload.actors:
		var uid := str(entry.get("id", ""))
		if uid.is_empty() or uid == online.session.user_id: continue
		seen[uid] = true
		if entry.has("loadout"): descriptions[uid] = entry
		if not actors.has(uid):
			if not descriptions.has(uid) or created >= 2: continue
			var description: Dictionary = descriptions[uid]
			created += 1
			var model := CharacterModel.new()
			add_child(model)
			if not model.load_model():
				model.queue_free()
				continue
			var loadout = Loadout.from_dict(description.loadout, GameState.item_rules)
			if loadout == null:
				model.queue_free()
				continue
			var style: String = loadout.weapon_style(hub._combat.styles.keys())
			var looks := ItemAssets.looks(loadout, GameState.item_rules.catalog, style)
			looks["appearance"] = ItemAssets.appearance(description.get("appearance", {}))
			looks["relics"]=description.get("relics",[])
			model.dress(looks)
			var label := preload("res://client/character_foot_name.gd").new()
			label.text = str(description.get("name", "Player"))
			model.add_child(label)
			model.position = Vector3(float(entry.x), 0, float(entry.z))
			actors[uid] = {"model":model,"target":model.position,"style":style}
		var actor: Dictionary = actors[uid]
		if entry.has("loadout"):
			var signature := JSON.stringify([entry.get("appearance", {}), entry.loadout,entry.get("relics",[])])
			if actor.get("look_signature", "") != signature:
				var worn = Loadout.from_dict(entry.loadout, GameState.item_rules)
				if worn != null:
					actor.style = worn.weapon_style(hub._combat.styles.keys())
					var looks := ItemAssets.looks(worn, GameState.item_rules.catalog, actor.style)
					looks["appearance"] = ItemAssets.appearance(entry.get("appearance", {}))
					looks["relics"]=entry.get("relics",[])
					actor.model.dress(looks)
					actor["look_signature"] = signature
		actor.target = Vector3(float(entry.x), 0, float(entry.z))
		var speed := float(entry.get("speed", 0))
		actor.model.set_pose("run" if speed > 1.2 else "walk" if speed > .1 else "idle", 0.0, speed, true, Vector2(float(entry.fx),float(entry.fz)), false, "", "", actor.style)
	for uid in actors.keys():
		if not seen.has(uid):
			actors[uid].model.queue_free()
			actors.erase(uid)
	for uid in descriptions.keys():
		if not seen.has(uid): descriptions.erase(uid)

func _disconnect() -> void:
	generation += 1
	if socket != null: socket.close()
	socket = null
	match_id = ""
	joining = false
	sending = false
	chat_sending = false
	if is_instance_valid(chat): chat.clear_channel()
	retry = 5.0
	for uid in actors: actors[uid].model.queue_free()
	actors.clear()
	descriptions.clear()

func _exit_tree() -> void:
	_disconnect()

func _appearance_changed() -> void:
	if socket != null: _disconnect()

func _fit_status() -> void:
	var logical := get_viewport().get_visible_rect().size
	var scale: float = hub._shortcut_root.scale.x if hub._shortcut_root != null else 1.0
	chat.ui_scale = scale
	status.position = Vector2(16.0 * scale, 42.0 * scale)
	status.size = Vector2(maxf(1.0, logical.x - 32.0 * scale), 30.0 * scale)
	status.add_theme_font_size_override("font_size", maxi(12, roundi(16.0 * scale)))
	status.add_theme_constant_override("outline_size", maxi(2, roundi(3.0 * scale)))
