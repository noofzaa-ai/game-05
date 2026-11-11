extends "res://client/session/local_session.gd"
## Shared online account/lifecycle views; gameplay networking is exclusively Netfox.
signal party_left
signal route_changed
signal ownership_changed
signal state_ready
signal stage_changed
signal command_completed(id: int, result: Dictionary)
signal connection_changed
const Wire := preload("res://logic/net_wire.gd")
var admission := {}
var account
var room_client = preload("res://client/online/room_client.gd").new()
var connected := false
var connecting := false
var error := ""
var server_state := {}
var event_ack := 0
var bytes_in := 0
var bytes_out := 0
var rtt_ms := 0.0
var corrections := 0
var saved := false
var ready := false
var _snapshot_combat
var _pending_events: Array = []
var _epoch := 0
var _received_at := 0
var _last_ping := 0
var _last_pong := -1
var _disconnected_at := 0
var _retry_at := 0
var _reconnecting := false
var _deliberate_close := false
var _terminal := false
var _leave_requested := false
var _left_emitted := false
var _connection_generation := 0
var _command_id := 0
var _pending_commands := {}
var _presented_epoch := 0
var _last_scene_ack := -1000
var _ping_nonce := -1
var lag_poll_us := 0
var lag_step_us := 0
var lag_states := 0
var lag_reconciles := 0
var lag_scene_build_us := 0
var lag_scene_present_us := 0
var lag_decode_us := 0
var lag_reconcile_us := 0
var lag_packets := 0
var lag_replay_ticks := 0
var lag_max_queue := 0
var disconnect_count := 0
var close_history: Array = []
var input_trace=preload("res://client/session/input_trace.gd").new()
var _collision_map_id := ""
var _collision_world: SimWorld

func _init(player = null, item_rules = null, camp_data = null, loot_data = null) -> void:
	super(player, item_rules, camp_data, loot_data)
	journey = preload("res://client/session/remote_journey.gd").new()

func _open_socket() -> bool:
	push_error("Online session requires Netfox implementation")
	return false

func _send(_kind: int, _value: Dictionary) -> void: pass
func _finish_leave(_confirmed: bool) -> void: pass

func scene_presented(scene_epoch: int) -> void:
	if scene_epoch != _epoch or _presented_epoch == scene_epoch: return
	_presented_epoch = scene_epoch
	_last_scene_ack = -1000
	_reset_ping()

func _reset_ping() -> void:
	rtt_ms = 0.0; _last_pong = -1; _ping_nonce = -1; _last_ping = 0

func scene_epoch() -> int:
	return _epoch


func connect_room(service, ticket: Dictionary) -> bool:
	account = service; admission = ticket.duplicate(true); _player_id = int(ticket.player_id)
	room_client.last_room = ticket.room
	return _open_socket()

func can_return_to_hub() -> bool:
	return saved or _terminal or error == "reconnect_expired"

func _handle_reconnect_result(result: Dictionary) -> void:
	if not result.get("ok", false):
		error = str(result.get("error", "unavailable"))
		if error in ["room_expired", "not_invited", "account_disabled", "google_login_required", "character_required"]:
			_terminal = true; connected = false; connecting = false
			if _leave_requested: _finish_leave(false)
			else: connection_changed.emit()
		return
	admission = result
	_open_socket()

func _reconnect() -> void:
	var generation := _connection_generation
	var result: Dictionary = await room_client.join(account, admission.room)
	_reconnecting = false
	if _deliberate_close or generation != _connection_generation: return
	_handle_reconnect_result(result)

func make_sim(state: Dictionary, map):
	# SimWorld is immutable collision data during prediction. Keep it across snapshots of this map.
	if _collision_world == null or _collision_map_id != str(map.id):
		_collision_world=SimWorld.new()
		_collision_world.half_width=map.half_width
		_collision_world.half_depth=map.half_depth
		for solid in map.solids: _collision_world.add_solid(solid.box)
		_collision_map_id=str(map.id)
	var world := _collision_world
	if _snapshot_combat == null:
		_snapshot_combat = preload("res://logic/combat_data_loader.gd").load_default()
	var result := GameSim.new(world, _snapshot_combat, RandomNumberGenerator.new())
	apply_entities(result, state)
	return result

func apply_entities(target, state: Dictionary) -> void:
	for id in target.bodies.keys():
		if not state.entities.has(id): target.bodies.erase(id); target.fighters.erase(id); target._inputs.erase(id)
	for id in state.entities:
		var row: Array = state.entities[id]
		if not target.bodies.has(id): target.add_player(id, Vector3.ZERO)
		for index in range(Wire.BODY_FIELDS.size()): target.bodies[id].set(Wire.BODY_FIELDS[index], row[0][index])
		for index in range(Wire.FIGHTER_FIELDS.size()):
			var field: String = Wire.FIGHTER_FIELDS[index]
			var old = target.fighters[id].get(field)
			if old is Array: old.assign(row[1][index])
			else: target.fighters[id].set(field, row[1][index])
	target.projectiles = state.projectiles.duplicate(true); target.areas = state.areas.duplicate(true)
	target._ranged.projectiles = target.projectiles; target._ranged.areas = target.areas
	target.tick_count = int(state.tick)

static func copy_fields(source, target, fields: Array) -> void:
	for field in fields:
		var value = source.get(field)
		var old = target.get(field)
		if old is Array: old.assign(value)
		else: target.set(field, value.duplicate(true) if value is Dictionary else value)

func command(request: Dictionary) -> Dictionary:
	if not connected: return {"ok": false, "error": "not_connected"}
	if request.get("type") == "party_leave" and _leave_requested: return {"ok": false, "pending": true, "error": "pending"}
	if _pending_commands.size() >= 32: return {"ok": false, "error": "busy"}
	if request.get("type") == "party_leave": _leave_requested = true
	_command_id += 1
	_pending_commands[_command_id] = {"request": request.duplicate(true), "epoch": _epoch, "sent": Time.get_ticks_msec()}
	_send(Wire.CONTROL, {"id": _command_id, "epoch": _epoch, "request": request})
	return {"ok": false, "pending": true, "id": _command_id, "error": "pending"}

func begin_stage(_map_data, _combat_data, _trip = null, _player = 1, _enemy = 100, _random = null) -> Dictionary:
	var enemies := {}; var bosses := []
	for id in fighters:
		if fighters[id].team == "enemy":
			enemies[id] = fighters[id].enemy_type
			if str(fighters[id].enemy_type).contains("chief"): bosses.append(id)
	return {"enemy_types": enemies, "bosses": bosses}
func is_remote() -> bool: return true
func player_id() -> int: return _player_id
func is_coop() -> bool: return server_state.get("meta", {}).get("players", []).size() > 1
func profile_for(id: int): return Profile.from_dict(server_state.meta.profiles[id], rules, camp) if server_state.get("meta", {}).get("profiles", {}).has(id) else profile
func run_for(id: int): return run if id == _player_id else Run.start(profile_for(id), camp)
func local_defeated() -> bool: return ready and (journey.state == "lost" or fighters[_player_id].eliminated)
func capture_gauge() -> void: pass
func mark_camp_rest(_point: String) -> void: pass
func open_rest(_point: String) -> bool: return ready and journey.is_at_camp()
func close_menu() -> void: pass
func use_rest() -> bool: return false # Journey camp heal already applied by server choice.
func open_route_camp(_point: String) -> bool: return ready and journey.is_at_camp()
func party_view() -> Dictionary: return server_state.get("meta", {}).get("party", {})
func is_lobby() -> bool: return bool(party_view().get("lobby", false))
func player_name(id: int) -> String:
	return str(server_state.get("meta", {}).get("profiles", {}).get(id, {}).get("name", "P%d" % id))
func boss_presentation() -> Dictionary: return server_state.get("meta", {}).get("boss_intro", {})
func _receive(bytes: PackedByteArray, _now: int) -> void:
	var message := Wire.parse(bytes)
	if message.is_empty() or message.kind not in [Wire.EVENTS, Wire.PONG, Wire.CONTROL]: return
	var decoded := Wire.decode(message.body)
	if decoded.is_empty() or not decoded.value is Dictionary: return
	var value: Dictionary = decoded.value
	lag_packets += 1
	match message.kind:
		Wire.EVENTS:
			if not value.get("events") is Array: return
			for record in value.events:
				if not record is Dictionary or not record.get("sequence") is int or record.sequence <= event_ack: continue
				event_ack = record.sequence
				var event: Dictionary = record.event
				_pending_events.append(event)
				if _pending_events.size() > 512: _pending_events.pop_front()
		Wire.PONG:
			if value.get("nonce") is int and value.nonce == _ping_nonce:
				_last_pong = Time.get_ticks_msec()
				# Latest application echo RTT, including browser scheduling; no loading EWMA tail.
				rtt_ms = float(maxi(0, _last_pong - value.nonce))
				_ping_nonce = -1
		Wire.CONTROL:
			if value.get("id") is int and value.get("result") is Dictionary and _pending_commands.has(value.id):
				var was_leave: bool = _pending_commands[value.id].request.get("type") == "party_leave"
				_pending_commands.erase(value.id)
				if was_leave and not value.result.get("ok", false): _leave_requested = false
				if was_leave and value.result.get("left", false):
					_finish_leave(true)
				command_completed.emit(value.id, value.result)

