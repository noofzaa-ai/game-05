extends SceneTree
## Explicit disposable-backend probe. No test kit, damage boosts or injected kills.
const Account := preload("res://client/online/online_account.gd")
const Names := preload("res://client/online/name_client.gd")
const Profiles := preload("res://client/online/profile_client.gd")
const Rooms := preload("res://client/online/room_client.gd")
const Remote := preload("res://client/session/netfox_session.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Bot := preload("res://tests/journey_bot.gd")
const Fighter := preload("res://logic/fighter.gd")
var failed := 0
var clients := []
var accounts := []
var _last_usec := 0
var _accumulator := 0.0
var _mode := "idle"
var _rngs := []
var _decisions := [{}, {}]
var _route_pending := false
var _config_path := ""

func check(label: String, good: bool) -> void:
	print("PASS " if good else "FAIL ", label)
	if not good: failed += 1

func _initialize() -> void:
	Engine.max_fps = 60
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] != "--config": quit(2); return
	_config_path = args[1]
	var config = JSON.parse_string(FileAccess.get_file_as_string(_config_path))
	if not config is Dictionary: quit(2); return
	for index in range(2):
		var account := Account.new(); account.name = "RoomProbe%d" % index; root.add_child(account)
		account.store.path = _config_path + ".p%d.cache" % index
		await account.connect_account(config)
		accounts.append(account)
		check("room SDK authenticates participant%d" % index, account.status == Account.Status.AUTHENTICATED)
		if account.status != Account.Status.AUTHENTICATED: _finish(); return
		var named := await Names.new().claim(account, "Arena%d" % index + Crypto.new().generate_random_bytes(3).hex_encode())
		var profile := await Profiles.new().fetch(account)
		check("room SDK prepares server-owned profile%d" % index, named.get("ok", false) and profile.get("ok", false))
		var rng := RandomNumberGenerator.new(); rng.seed = 77 * 31 + index; _rngs.append(rng)
	var rooms := Rooms.new()
	var created := await rooms.create(accounts[0], 2)
	check("Nakama allocates room and private invite", created.get("ok", false) and created.get("invite", "").length() == 32)
	if not created.get("ok", false): _finish(); return
	var wrong := await rooms.join(accounts[1], created.room, "0".repeat(32))
	check("uninvited account cannot join", wrong.get("error") == "not_invited")
	# Optional fixture seed is installed by the disposable harness, never accepted by public RPC.
	if config.get("fixture_seed", false):
		var out := FileAccess.open(_config_path + ".room.json", FileAccess.WRITE)
		out.store_string(JSON.stringify({"room": created.room, "users": [accounts[0].session.user_id, accounts[1].session.user_id]})); out.close()
		var deadline := Time.get_ticks_msec() + 15000
		while not FileAccess.file_exists(_config_path + ".seeded") and Time.get_ticks_msec() < deadline: await process_frame
	var joined := await rooms.join(accounts[1], created.room, created.invite)
	check("invited second account gets its own immutable slot", joined.get("ok", false) and joined.player_id == 2)
	if not joined.get("ok", false): _finish(); return
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var loot = preload("res://logic/loot_data_loader.gd").load_default(camp.materials.keys(), rules.tiers.size())
	for index in range(2):
		var client := Remote.new(null, rules, camp, loot)
		clients.append(client)
		check("RemoteSession opens worker%d" % index, client.connect_room(accounts[index], created if index == 0 else joined))
	_last_usec = Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and not (clients[0].ready and clients[1].ready): _frame(); await process_frame
	check("two real clients receive authenticated binary state", clients[0].ready and clients[1].ready)
	if not clients[0].ready or not clients[1].ready: _finish(); return
	for index in range(clients.size()):
		var capture := FileAccess.open(_config_path + ".p%d.state.bin" % index, FileAccess.WRITE)
		capture.store_buffer(preload("res://logic/net_wire.gd").encode(clients[index].server_state, 262144)); capture.close()
	check("peer inventories/RNG are not broadcast", not clients[0].server_state.has("rng_state") and clients[0].server_state.meta.profiles[2].stash.items.is_empty() and clients[0].server_state.meta.profiles[2].stash.gold == "0")
	var locked := Profiles.new()
	await locked.fetch(accounts[0])
	var denied := await locked.submit(accounts[0], locked.prepare({"type": "unequip", "slot": "weapon", "destination": "stash"}))
	check("camp RPC cannot mutate an active room profile", denied.get("error") == "in_match")
	# Replay a consumed ticket: a separate unauthenticated socket cannot steal the slot.
	var replay := WebSocketPeer.new(); replay.connect_to_url(created.url)
	var replay_deadline := Time.get_ticks_msec() + 5000
	var replay_sent := false
	while Time.get_ticks_msec() < replay_deadline and replay.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		replay.poll(); _frame()
		if replay.get_ready_state() == WebSocketPeer.STATE_OPEN and not replay_sent:
			replay.send_text(JSON.stringify({"v": 1, "room": created.room, "ticket": created.ticket})); replay_sent = true
		await process_frame
	check("consumed ticket cannot attach a second socket", replay_sent and replay.get_ready_state() == WebSocketPeer.STATE_CLOSED)
	_mode = "move"
	var start: Vector3 = clients[0].server_state.entities[1][0][0]
	await _run_seconds(1)
	check("server receives client movement", clients[0].server_state.entities[1][0][0].distance_to(start) > .1)
	for client in clients: client.network.configure(75, 10, .02, 77 + client.player_id())
	_mode = "bot"
	await _run_seconds(5)
	check("150ms RTT impairment retains synchronized sessions", clients[0].connected and clients[1].connected and clients[0].ready and clients[1].ready)
	var old_socket = clients[1].socket
	clients[1].socket.close(1000, "probe reconnect")
	deadline = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		_frame(); await process_frame
		if clients[1].socket != old_socket and clients[1].connected and clients[1].last_state_sequence > 0: break
	check("disconnect reconnects same slot with fresh full state", clients[1].socket != old_socket and clients[1].connected and clients[1].player_id() == 2)
	var started_bytes: Array = [clients[0].bytes_in + clients[0].bytes_out, clients[1].bytes_in + clients[1].bytes_out]
	var sample_start := Time.get_ticks_msec()
	if args.has("--long-run"):
		deadline = Time.get_ticks_msec() + 1200000
		while Time.get_ticks_msec() < deadline and not clients[0].saved:
			_frame(); await process_frame
			if Time.get_ticks_msec() - _last_ping_progress > 30000:
				_last_ping_progress = Time.get_ticks_msec()
				var c = clients[0]
				var living := 0
				for id in c.fighters:
					if c.fighters[id].team == "enemy" and c.fighters[id].is_alive(): living += 1
				print("ROOM_PROGRESS stage=", c.journey.stage_number(), " state=", c.journey.state, " enemies=", living, " tick=", c.server_state.tick, " ack=", c.server_state.ack, " lead=", c.prediction_lead, " hp=", c.fighters[1].hp, "/", c.fighters[2].hp, " pos=", c.bodies[1].position)
		check("two impaired clients finish and save a full Journey", clients[0].saved and clients[0].journey.state == "won")
	else: await _run_seconds(8)
	var duration := maxf(.1, float(Time.get_ticks_msec() - sample_start) / 1000)
	var bandwidth := maxf(float(clients[0].bytes_in + clients[0].bytes_out - started_bytes[0]), float(clients[1].bytes_in + clients[1].bytes_out - started_bytes[1])) / duration
	print("ROOM_BANDWIDTH_BYTES_SEC=", roundi(bandwidth))
	print("ROOM_FINAL stage=", clients[0].journey.stage_number(), " state=", clients[0].journey.state, " end_reason=", clients[0].server_state.meta.get("end_reason", ""), " tick=", clients[0].server_state.tick, " ack=", clients[0].server_state.ack, " client_target=", clients[0]._target_tick)
	print("ROOM_METRICS ", JSON.stringify(clients[0].debug_metrics()))
	check("measured send+receive bandwidth below30KiB/s for each participant", bandwidth < 30720)
	if clients[0].saved:
		var loaded := await Profiles.new().fetch(accounts[0])
		check("fresh profile connection sees server-settled equipment", loaded.get("ok", false) and preload("res://logic/profile.gd").from_dict(loaded.profile, rules, camp).to_dict().loadout == clients[0].profile.to_dict().loadout)
	_finish()

var _last_ping_progress := 0
func _frame() -> void:
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_usec) / 1000000.0; _last_usec = now
	for client in clients:
		client.poll(dt)
		if client.ready: client.scene_presented(client.scene_epoch()) # Headless test scene has no assets.
	_accumulator += minf(dt, .1)
	while _accumulator >= 1.0 / 60.0:
		_accumulator -= 1.0 / 60.0
		for index in range(clients.size()):
			var client = clients[index]
			if not client.ready: continue
			var frame := SimInput.new()
			if _mode == "move": frame.move = Vector2(1 if index == 0 else -1, 0)
			elif _mode == "bot":
				var ally := -1
				for id in client.fighters:
					if client.fighters[id].team == "player" and client.fighters[id].state == Fighter.State.DOWNED: ally = id; break
				if ally >= 0:
					var offset: Vector3 = client.bodies[ally].position - client.bodies[client.player_id()].position
					if offset.length() > 1.6: frame.move = Vector2(offset.x, offset.z).normalized()
				elif client.fighters[client.player_id()].is_alive():
					frame = Bot._decide(client._sim, client.combat, 1.0, _rngs[index], _decisions[index], client.tick_count, client.player_id())
					# Exercise legal skill buttons; the server enforces cooldown, stamina and gauge.
					if frame.light:
						frame.special = true
						frame.ultimate = true
			client.step(frame)
	if clients.size() == 2 and clients[0].ready:
		var leader = clients[0]
		if leader.journey.state == "choosing" or (leader.journey.state == "at_node" and not leader.journey.treasure_pending):
			if leader._pending_commands.is_empty():
				var choice := 0; var options: Array = leader.journey.upcoming_choices()
				for i in range(options.size()):
					if options[i].kind in ["camp", "treasure"]: choice = i; break
				leader.command({"type": "journey_choose", "index": choice})
		elif leader.journey.treasure_pending and leader._pending_commands.is_empty(): leader.command({"type": "journey_treasure"})

func _run_seconds(duration: float) -> void:
	var end := Time.get_ticks_msec() + int(duration * 1000)
	while Time.get_ticks_msec() < end: _frame(); await process_frame

func _finish() -> void:
	for client in clients: client.enter_camp()
	for service in accounts: service.use_offline(); service.queue_free()
	await process_frame
	print("ROOM_SDK_FAILED=", failed)
	quit(1 if failed else 0)
