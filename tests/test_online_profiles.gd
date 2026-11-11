extends RefCounted
const Runner := preload("res://server/profile/runner.gd")
const Commands := preload("res://logic/commands.gd")
const Profile := preload("res://logic/profile.gd")

func run(ctx) -> void:
	await _client_checks(ctx)
	var runner := Runner.new()
	ctx.check("M3-4 production configuration loads", runner.ready())
	var initial := envelope(null, null)
	var made := runner.execute(initial)
	ctx.check("M3-4 server creates starter profile without test kit", made.ok and int(made.profile.stash.gold) == runner.camp.starter.gold and made.profile.stash.items.is_empty())
	ctx.check("M3-4 reserved name projected into profile", made.profile.name == "Hero" and made.profile.created)
	ctx.check("M3-4 same trusted seed gives same starter", runner.execute(initial) == made)
	var state := {"profile": made.profile, "rng_state": made.rng_state}
	var original := state.duplicate(true)
	var command := {"type": "unequip", "slot": "weapon", "destination": "stash"}
	var applied := runner.execute(envelope(state, command))
	ctx.check("M3-4 camp command executes", applied.ok and applied.profile.stash.items.size() == 1)
	ctx.check("M3-4 borrowed stored state remains unchanged", state == original)
	var profile = Profile.from_dict(state.profile, runner.rules, runner.camp)
	var rng := RandomNumberGenerator.new()
	rng.state = int(state.rng_state)
	var direct := Commands.apply({"profile": profile, "rules": runner.rules, "camp": runner.camp, "cosmetics": runner.cosmetics, "location": "camp"}, command, rng)
	ctx.check("M3-4 same Commands.apply result and serialization", applied.result == direct and applied.profile == profile.to_dict() and applied.rng_state == str(rng.state))
	var reloaded := runner.execute(envelope({"profile": applied.profile, "rng_state": applied.rng_state}, null))
	ctx.check("M3-4 serialized profile reloads without reset", reloaded.profile == applied.profile and reloaded.rng_state == applied.rng_state)
	for attack in [
		{"type": "equip", "item": "someone-elses", "source": "stash"},
		{"type": "upgrade_camp", "gold": 9999999},
		{"type": "appearance", "part": "face", "choice": "nonexistent"},
		{"type": "discard_material", "material": "ore", "count": -10, "source": "stash"},
	]:
		ctx.check("M3-4 invalid command leaves state unchanged", not runner.execute(envelope(state, attack)).ok and state == original)
	for kind in ["journey_finish", "bank_bag", "return_to_camp", "give_gold"]:
		ctx.check("M3-4 no client journey rewards or economy injection", runner.execute(envelope(state, {"type": kind})).error == "not_available_here")
	ctx.check("M3-4 names must use reservation RPC", runner.execute(envelope(state, {"type": "set_name", "name": "Other"})).error == "name_rpc_required")
	ctx.check("M3-4 enhance remains gated by Boss config decision", runner.execute(envelope(state, {"type": "enhance", "item": "starter-weapon"})).error == "not_configured")
	var random_command := {"type": "randomize_appearance"}
	ctx.check("M3-4 command RNG deterministic from persisted state", runner.execute(envelope(state, random_command)) == runner.execute(envelope(state, random_command)))
	var changed_name := envelope(state, null)
	changed_name.name = "New Name"
	ctx.check("M3-4 fresh reserved name wins over stale saved name", runner.execute(changed_name).profile.name == "New Name")
	for invalid in [null, {}, {"v": true}, {"profile": {"gold": 9999}}]:
		ctx.check("M3-4 malformed private envelope rejected", not runner.execute(invalid).ok)
	var extra := envelope(state, command)
	extra.location = "rest"
	ctx.check("M3-4 caller cannot inject context", runner.execute(extra).error == "invalid_payload")

func envelope(state, command) -> Dictionary:
	return {"v": 1, "state": state, "seed": "0123456789abcde", "name": "Hero", "command": command}

func _client_checks(ctx) -> void:
	var fixtures = load("res://tests/test_online_names.gd")
	var account = fixtures.FakeAccount.new()
	account.client = fixtures.FakeRpc.new()
	var client = load("res://client/online/profile_client.gd").new()
	ctx.check("M3-4 client cannot command before fetching revision", client.prepare({"type": "repair_all"}).is_empty())
	account.client.response = '{"v":1,"ok":true,"revision":1,"profile":{"name":"Hero"}}'
	var result: Dictionary = await client.fetch(account)
	ctx.check("M3-4 client tracks fetched revision", result.ok and client.revision == 1)
	var cmd := {"type": "repair_all"}
	var pending: Dictionary = client.prepare(cmd)
	cmd.type = "forged"
	ctx.check("M3-4 request envelope copies command and omits local profile", pending.command.type == "repair_all" and not pending.has("profile") and pending.request_id.length() == 32)
	account.client.response = '{"v":1,"ok":true,"revision":2,"profile":{"name":"Hero"}}'
	result = await client.submit(account, pending)
	ctx.check("M3-4 client advances only on server success", result.ok and client.revision == 2)
	account.client.response = '{"v":1,"ok":false,"error":"revision_conflict"}'
	result = await client.submit(account, pending)
	ctx.check("M3-4 conflict stays explicit without local fallback", not result.ok and result.error == "revision_conflict" and client.revision == 2)
	account.client.response = '{"v":1,"ok":true,"revision":1,"profile":{}}'
	result = await client.fetch(account)
	ctx.check("M3-4 older response cannot roll client revision backward", not result.ok and client.revision == 2)
	account.status = 0
	var calls: int = account.client.calls
	result = await client.submit(account, pending)
	ctx.check("M3-4 offline commands do not reach backend", not result.ok and result.error == "not_online" and account.client.calls == calls)
