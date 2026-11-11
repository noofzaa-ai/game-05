extends SceneTree
const Account := preload("res://client/online/online_account.gd")
const Names := preload("res://client/online/name_client.gd")
const Profiles := preload("res://client/online/profile_client.gd")
const Rooms := preload("res://client/online/room_client.gd")
const Remote := preload("res://client/session/netfox_session.gd")
const Social := preload("res://client/online/social_client.gd")
const FrameInput := preload("res://logic/sim_input.gd")
var accounts := []
var clients := []
var failed := 0
var withheld_scene_slot := 0
func check(label: String, good: bool) -> void:
	print("PASS " if good else "FAIL ",label)
	if not good: failed += 1
func pump(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds*1000)
	while Time.get_ticks_msec() < until:
		for client in clients:
			client.poll(1.0/60)
			if client.ready and client.connected:
				if client.player_id() != withheld_scene_slot:
					client.scene_presented(client.scene_epoch()) # Explicit mock render completion.
				client.step(FrameInput.new())
		await process_frame
func _initialize() -> void:
	Engine.max_fps = 60
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size()<2: quit(2); return
	var config = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var names := []
	for index in range(4):
		var account := Account.new(); root.add_child(account); account.store.path = args[1]+".party%d.cache"%index
		await account.connect_account(config); accounts.append(account)
		var name_value := "Party%d"%index+Crypto.new().generate_random_bytes(3).hex_encode(); names.append(name_value)
		var named := await Names.new().claim(account,name_value)
		var profile := await Profiles.new().fetch(account)
		check("server creates participant%d"%index,account.status == Account.Status.AUTHENTICATED and named.get("ok",false) and profile.get("ok",false))
	var social := Social.new()
	var sent := await social.call_rpc(accounts[0],"request",{"name":names[1]})
	var received := await social.call_rpc(accounts[1],"list")
	check("actual Nakama Friends delivers request",sent.get("ok",false) and received.get("friends",[]).size()==1 and int(received.friends[0].state)==2)
	var accepted := await social.call_rpc(accounts[1],"accept",{"target":accounts[0].session.user_id})
	check("actual Nakama friend acceptance",accepted.get("ok",false))
	var rooms := Rooms.new()
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var loot = preload("res://logic/loot_data_loader.gd").load_default(camp.materials.keys(),rules.tiers.size())
	# Last-member leave: reproduce a throttled tab and an intentionally lost final ACK.
	for lose_ack in [false, true]:
		var single := await rooms.create(accounts[0], 1, true)
		check("single-owner camp admission", single.get("ok", false))
		if not single.get("ok", false): finish(); return
		var single_client := Remote.new(null, rules, camp, loot)
		var left_once := [0]
		single_client.party_left.connect(func(): left_once[0] += 1)
		clients.append(single_client); single_client.connect_room(accounts[0], single)
		await pump(2)
		check("single-owner camp ready", single_client.ready and single_client.is_lobby())
		single_client.command({"type": "party_leave"})
		if lose_ack: single_client._pending_commands.clear()
		await create_timer(1.2).timeout # server closes while this client does not poll
		await pump(3)
		check("last member leaves after stalled polling / lost ACK %s" % lose_ack, left_once[0] == 1 and not single_client.connected and single_client._deliberate_close)
		clients.erase(single_client); single_client.enter_camp()
	var created := await rooms.create(accounts[0],4,true)
	check("camp admission",created.get("ok",false))
	if not created.get("ok",false): finish(); return
	var invite := await social.call_rpc(accounts[0],"invite",{"target":accounts[1].session.user_id,"room":created.room,"invite":created.invite})
	var inbox := await social.call_rpc(accounts[1],"inbox")
	check("persistent friend invite contains room capability",invite.get("ok",false) and inbox.get("invites",[]).size()==1 and inbox.invites[0].get("room")==created.room)
	var friends := await social.call_rpc(accounts[1], "list")
	check("friend list advertises waiting owner camp without invite secret", friends.get("ok", false) and friends.friends[0].get("room", {}).get("joinable", false) and not JSON.stringify(friends).contains(str(created.invite)))
	var outsider := await rooms.join_friend(accounts[2], accounts[0].session.user_id)
	check("nonfriend cannot join owner camp", outsider.get("error") == "not_friends")
	for index in range(4):
		var ticket: Dictionary = created
		if index == 1: ticket = await rooms.join_friend(accounts[index], accounts[0].session.user_id)
		elif index > 1: ticket = await rooms.join(accounts[index],created.room,created.invite)
		check("party ticket%d"%index,ticket.get("ok",false))
		if not ticket.get("ok",false): finish(); return
		var client := Remote.new(null,rules,camp,loot); clients.append(client); client.connect_room(accounts[index],ticket)
		await pump(2)
		check("camp opens before full and grows roster%d"%index,client.ready and client.is_lobby() and client.party_view().get("members",[]).size()==index+1)
	await pump(1)
	check("four players share camp",clients.all(func(c):return c.party_view().members.size()==4))
	if not inbox.get("invites",[]).is_empty():
		var refused := await social.call_rpc(accounts[0],"ack",{"id":inbox.invites[0].id})
		var acked := await social.call_rpc(accounts[1],"ack",{"id":inbox.invites[0].id})
		check("notification ack is owner scoped",refused.get("error")=="request_expired" and acked.get("ok",false))
	# Leaving must save/unlock before a slot can be reused; leader handoff is authoritative.
	clients[0].command({"type":"party_leave"}); await pump(3)
	check("leader leaves without killing camp",not clients[0].connected and clients[1].party_view().leader==2 and clients[1].party_view().members.size()==3)
	var unlocked := await Profiles.new().fetch(accounts[0])
	check("camp leave unlocks persisted profile",unlocked.get("ok",false) and not unlocked.get("in_match",false))
	var again := await rooms.join(accounts[0],created.room,created.invite)
	check("leaving account can rejoin a fresh membership",again.get("ok",false) and again.get("player_id")==1)
	if not again.get("ok",false): finish(); return
	clients[0].enter_camp(); clients[0] = Remote.new(null,rules,camp,loot); clients[0].connect_room(accounts[0],again)
	await pump(3)
	check("reused slot receives current roster",clients[0].ready and clients[0].party_view().members.size()==4)
	var results := {}
	for index in range(4):
		clients[index].command_completed.connect(func(id,result):results[str(index)+":"+str(id)]=result)
	var denied: Dictionary = clients[1].command({"type":"party_depart"})
	await pump(1)
	check("nonleader cannot depart",results.get("1:"+str(denied.get("id",0)),{}).get("error")=="leader_only")
	for client in clients: client.command({"type":"party_ready","ready":true})
	await pump(2)
	check("ready replicated to all",clients[0].party_view().members.all(func(m):return m.ready))
	withheld_scene_slot = clients[3].player_id()
	clients[0].command({"type":"party_depart"}); await pump(3)
	check("scene barrier waits for slow fourth client", clients.all(func(c): return c.server_state.meta.get("scene_loading", false)))
	var held_tick: int = clients[0].server_state.tick
	await pump(2)
	check("server sim remains frozen while fourth client loads", clients.all(func(c): return c.server_state.tick == held_tick))
	withheld_scene_slot = 0
	await pump(2)
	check("scene barrier releases after fourth render ACK", clients.all(func(c): return not c.server_state.meta.get("scene_loading", true) and c.server_state.tick > held_tick))
	check("leader departs all four into Journey",clients.all(func(c):return not c.is_lobby() and c.server_state.entities.has(4)))
	clients[1].command({"type":"party_ping","kind":"help"}); await pump(1)
	check("party remains connected after ping",clients.all(func(c):return c.connected))
	# Explicitly close clients; server's existing disconnect settlement owns final persistence.
	finish()
func finish() -> void:
	for client in clients: client.enter_camp()
	for account in accounts: account.queue_free()
	await process_frame
	print("ROOM_SDK_FAILED=",failed)
	quit(0 if failed==0 else 1)
