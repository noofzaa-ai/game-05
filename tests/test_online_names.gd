extends RefCounted
const Rules := preload("res://server/names/name_rules.gd")
const NameClient := preload("res://client/online/name_client.gd")
const OnlineAccount := preload("res://client/online/online_account.gd")
const Profile := preload("res://logic/profile.gd")


func run(ctx) -> void:
	for value in ["Hero", " ตัวละคร ", "หมาป่า-แดง", "A_B 7", "ชื่อ", "éclair", "東京", "x", "", "abcdefghijklmnopq", "a  b", "<script>", "name\nline", "🔥🔥"]:
		var result := Rules.validate({"v": 1, "name": value})
		var problem := Profile.name_problem(value)
		ctx.check("server reuses Profile name rule for vector %d" % value.hash(), result.ok == problem.is_empty() and (result.get("name", "") == value.strip_edges() if result.ok else result.error == problem))
	for request in [null, [], "Hero", {"v": true, "name": "Hero"}, {"v": 2, "name": "Hero"}, {"v": 1, "name": 42}, {"v": 1, "name": "Hero", "user_id": "forged"}, {"v": 1}]:
		var result := Rules.validate(request)
		ctx.check("server name wire contract rejects malformed or identity-bearing payload", not result.ok and result.error == "invalid_payload")

	ctx.check("case-only variants share the same server canonical name", Rules.validate({"v": 1, "name": "Hero"}).canonical == Rules.validate({"v": 1, "name": "hero"}).canonical)
	await _check_client(ctx)
	await _check_creator(ctx)

class FakeAccount:
	extends RefCounted
	var status := OnlineAccount.Status.AUTHENTICATED
	var session = {"user_id": "test-user"}
	var client
	func use_offline():
		status = OnlineAccount.Status.OFFLINE
		session = null

class FakeRpc:
	extends RefCounted
	signal released
	var hold := false
	var calls := 0
	var response := '{"v":1,"ok":true,"name":"Hero"}'
	var last_payload := {}
	var last_rpc := ""
	func rpc_async(_session, rpc, payload):
		calls += 1
		last_payload = JSON.parse_string(payload)
		last_rpc = rpc
		var captured := response
		if hold:
			await released
		return RpcResult.new(captured)

class RpcResult:
	extends RefCounted
	var payload: String
	func _init(text):
		payload = text
	func is_exception():
		return false


func _check_client(ctx) -> void:
	var account := FakeAccount.new()
	account.client = FakeRpc.new()
	var names := NameClient.new()
	var result := await names.claim(account, "Hero")
	ctx.check("name client uses authenticated RPC and never sends a user ID", result.ok and account.client.last_payload.size() == 2 and int(account.client.last_payload.get("v", 0)) == 1 and account.client.last_payload.get("name") == "Hero" and account.client.last_rpc == NameClient.CLAIM_RPC)
	result = await names.claim(account, "x")
	ctx.check("invalid local name never sends a request", not result.ok and result.error == "too_short" and account.client.calls == 1)
	account.client.response = '{"v":1,"ok":false,"error":"name_taken"}'
	result = await names.claim(account, "Hero")
	ctx.check("duplicate name is a server result", not result.ok and result.error == "name_taken")
	account.client.response = '{"v":1,"ok":false,"error":"raw-private-diagnostic"}'
	result = await names.claim(account, "Hero")
	ctx.check("unrecognized server diagnostics stay out of UI", not result.ok and result.error == "unavailable")
	account.client.response = '{"v":1,"ok":false,"error":"rate_limited"}'
	result = await names.claim(account, "Hero")
	ctx.check("rate-limited naming returns a friendly UI code", not result.ok and result.error == "rate_limited")
	account.client.response = '{"v":1,"ok":true,"name":null}'
	result = await names.get_name(account)
	ctx.check("account without a name returns an empty prefill", result.ok and result.name == "")
	account.status = OnlineAccount.Status.OFFLINE
	var calls: int = account.client.calls
	result = await names.claim(account, "Hero")
	ctx.check("offline naming does not call backend", not result.ok and result.error == "not_online" and account.client.calls == calls)


func _check_creator(ctx) -> void:
	var rules = load("res://logic/item_rules_loader.gd").load_default()
	var camp = load("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var combat = load("res://logic/combat_data_loader.gd").load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var fresh = Profile.new_player(rules, camp, rng)
	var account := FakeAccount.new()
	account.client = FakeRpc.new()
	var creator = load("res://client/character_creator.gd").new()
	creator.online_account_override = account
	ctx.root.add_child(creator)
	creator.setup(fresh, rules, combat)
	await ctx.process_frame
	await ctx.process_frame
	ctx.check("creator pre-fills existing account name without making a character", creator.name_field.text == "Hero" and not fresh.created)
	account.client.response = '{"v":1,"ok":false,"error":"name_taken"}'
	creator._start()
	ctx.check("server duplicate leaves local profile uncreated and shows friendly error", not fresh.created and creator._problem.text == creator.TEXT.name_taken and not creator._offline_button.visible)
	var saved_size: Vector2i = ctx.root.size
	for phone in [Vector2i(844, 390), Vector2i(667, 375)]:
		ctx.root.size = phone
		creator._apply_layout()
		await ctx.process_frame
		await ctx.process_frame
		var bounds: Rect2 = ctx.root.get_visible_rect()
		ctx.check("online name footer and offline choice fit phone %s" % phone, bounds.encloses(creator.start_button.get_global_rect()) and bounds.encloses(creator._offline_button.get_global_rect()) and bounds.encloses(creator.name_field.get_global_rect()))
	ctx.root.size = saved_size
	creator._apply_layout()
	account.client.hold = true
	account.client.response = '{"v":1,"ok":true,"name":"Hero"}'
	creator._start()
	var calls: int = account.client.calls
	creator._start()
	ctx.check("pending online name disables edits and duplicate submission", creator._name_pending and not creator.name_field.editable and not fresh.created and account.client.calls == calls)
	creator._choose_offline()
	await ctx.process_frame
	ctx.check("explicit offline choice creates local character immediately", fresh.created and fresh.name == "Hero" and account.status == OnlineAccount.Status.OFFLINE)
	account.client.released.emit()
	await ctx.process_frame
	ctx.check("late server reply after leaving creator is harmless", not is_instance_valid(creator))
	# A separate successful online creator commits only after server confirmation.
	fresh = Profile.new_player(rules, camp, rng)
	account = FakeAccount.new()
	account.client = FakeRpc.new()
	creator = load("res://client/character_creator.gd").new()
	creator.online_account_override = account
	ctx.root.add_child(creator)
	creator.setup(fresh, rules, combat)
	await ctx.process_frame
	await ctx.process_frame
	creator._start()
	await ctx.process_frame
	ctx.check("confirmed server name then commits through LocalSession", fresh.created and fresh.name == "Hero" and not is_instance_valid(creator))
