extends RefCounted
const Session := preload("res://client/session/local_session.gd")
const F := preload("res://tests/online_fixture.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Codec := preload("res://logic/state_codec.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")

func run(ctx) -> void:
	_wire_equivalence(ctx)
	_rest_and_gear(ctx)
	_journey_commands(ctx)
	_treasure_wire(ctx)
	_clear_priority(ctx)

func _wire_equivalence(ctx) -> void:
	var f := F.make()
	var reference = F.simulation(f)
	var other := F.make()
	other["journey"].choose(0)
	var session := Session.new(other["profile"], other["rules"], other["camp"], other["loot"])
	var map = MapLoader.load_by_id(other["journey"].current["map"])
	session.begin_stage(map, other["combat"], other["journey"], 1, 100, F.rng(12345))
	var equal := true
	for i in 180:
		var input := SimInput.new()
		input.move = Vector2(.1234567, .9876543)
		input.aim = Vector2(10, .9)
		input.run = i % 60 > 30
		input.jump = i % 50 == 0
		input.light = i % 17 == 0
		reference.set_input(1, SimInput.decode(input.encode()))
		reference.tick()
		session.step(input)
		var snapshot := session.snapshot()
		equal = equal and snapshot.get("journey") == session.journey.to_dict()
		snapshot.erase("journey")
		equal = equal and Codec.digest(reference.snapshot()) == Codec.digest(snapshot)
	ctx.check("M1-6 LocalSession matches direct wire-quantized simulation every tick", equal)
	var held := SimInput.new()
	held.light = true
	session.set_input(1, held)
	held.light = false
	ctx.check("M1-6 queued input is copied through wire boundary", session._sim._inputs[1].light)
	ctx.check("M1-6 stage ownership commands cannot claim rest access", not session.command({"type": "unequip", "slot": "weapon", "destination": "bag"})["ok"])
	ctx.check("M1-6 cannot open an invented rest point", not session.open_rest("invented"))

func _rest_and_gear(ctx) -> void:
	var f := F.make()
	var session := Session.new(f["profile"], f["rules"], f["camp"], f["loot"])
	var map = MapLoader.load_by_id("sunward_valley")
	session.begin_stage(map, f["combat"], null, 1, 100, F.rng())
	var point: Dictionary = map.rest_points[0]
	session.bodies[1].position = point["position"] + Vector3(20, 0, 20)
	ctx.check("M1-6 rest proximity is checked by session", not session.open_rest(point["id"]))
	session.bodies[1].position = point["position"]
	ctx.check("M1-6 real nearby rest point opens", session.open_rest(point["id"]))
	var tick := session.tick_count
	session.step(SimInput.new())
	ctx.check("M1-6 menu pauses fixed simulation ticks", session.tick_count == tick)
	var dagger = ItemSystem.create_item(f["rules"], "session-blade", "weapon", 0, F.rng(), "blade")
	session.run.bag.add_item(dagger)
	ctx.check("M1-6 equip command changes loadout and live fighting style together", session.command({"type": "equip", "item": dagger.id, "source": "bag"})["ok"] and session.fighters[1].style == "blade")
	session.fighters[1].hp = session.fighters[1].max_hp() * .1
	session.fighters[1].energy = 0
	ctx.check("M1-6 rest heals and refills stamina through authority", session.use_rest() and session.fighters[1].energy == session.fighters[1].max_energy())
	ctx.check("M1-6 rest cannot be used twice", not session.use_rest())
	session.close_menu()
	session.step(SimInput.new())
	ctx.check("M1-6 close resumes exactly one tick", session.tick_count == tick + 1)
	ctx.check("M1-6 closed menu loses gear permissions", not session.command({"type": "unequip", "slot": "weapon", "destination": "bag"})["ok"])
	# Farm's existing early-Esc behaviour banks the bag; Journey has a separate restriction.
	session.run.bag.gold = 43
	var before: int = session.profile.stash.gold
	var response := session.command({"type": "return_to_camp"})
	ctx.check("M1-6 free-stage early return keeps the existing bank policy", response["ok"] and session.profile.stash.gold == before + 43 and session.run.bag.gold == 0)
	ctx.check("M1-6 repeated banking cannot duplicate gold", session.command({"type": "return_to_camp"})["result"]["gold"] == 0)

func _journey_commands(ctx) -> void:
	var f := F.make()
	var j = f["journey"]
	var session := Session.new(f["profile"], f["rules"], f["camp"], f["loot"])
	session.journey = j
	session.run = j.run
	ctx.check("M1-6 invalid route choice is rejected", not session.command({"type": "journey_choose", "index": -1})["ok"])
	ctx.check("M1-6 journey cannot use free-stage banking", not session.command({"type": "return_to_camp"})["ok"])
	ctx.check("M1-6 cannot open camp outside a camp node", not session.open_route_camp("journey_camp_1"))
	j.completed = j.first_camp - 1
	ctx.check("M1-6 choice uses authoritative Journey rules", session.command({"type": "journey_choose", "index": 0})["ok"] and j.is_at_camp())
	var point := "journey_camp_%d" % j.stage_number()
	ctx.check("M1-6 route camp can manage equipment", session.open_route_camp(point))
	ctx.check("M1-6 camp's already-applied heal is marked once", session.run.used_rests.count(point) == 1)
	session.open_route_camp(point)
	ctx.check("M1-6 reopening camp does not duplicate consumed rest", session.run.used_rests.count(point) == 1)
	session.run.bag.gold = 52
	var before: int = session.profile.stash.gold
	ctx.check("M1-6 journey bank command transfers once", session.command({"type": "bank_bag"})["ok"] and session.profile.stash.gold == before + 52)
	ctx.check("M1-6 bank command at empty bag does not duplicate", session.command({"type": "bank_bag"})["result"]["gold"] == 0)
	ctx.check("M1-6 invalid command fails with unchanged owned state", not session.command({"type": "equip", "item": "invented", "source": "bag"})["ok"] and session.profile.stash.gold == before + 52)
	ctx.check("M1-6 camp retreat uses same journey and bag", session.command({"type": "journey_retreat"})["ok"] and j.state == j.RETREATED)
	ctx.check("M1-6 unfinished/finished summary respects lifecycle", session.command({"type": "journey_finish"})["ok"])
	session.enter_camp()
	ctx.check("M1-6 leaving stage releases sim, run and journey", session.snapshot().is_empty() and session.run == null and session.journey == null)
	ctx.check("M1-6 cosmetics use Commands on the same profile", session.command({"type": "randomize_appearance"})["ok"] and not session.profile.appearance.is_empty())


func _treasure_wire(ctx) -> void:
	var f := F.make()
	var j = f["journey"]
	j.nodes[0] = [{"stage": 1, "kind": "treasure", "map": ""}]
	j.choose(0)
	var state := {"profile": f["profile"], "rules": f["rules"], "camp": f["camp"], "run": j.run, "journey": j, "location": "stage"}
	var response = load("res://logic/commands.gd").apply(state, {"type": "journey_treasure"}, F.rng())
	var parsed = JSON.parse_string(JSON.stringify(response))
	ctx.check("M1-6 command reward and changed ownership are JSON data, not Item objects", parsed["ok"] and parsed["result"]["items"][0] is Dictionary and parsed["result"]["items"][0]["v"] == 1.0 and parsed["changes"].has("bag") and parsed["changes"].has("journey"))
	var session := Session.new(f["profile"], f["rules"], f["camp"], f["loot"])
	session.journey = j
	session.run = j.run
	var count: int = j.run.bag.items.size()
	ctx.check("M1-6 reopening treasure cannot duplicate a reward", session.command({"type": "journey_treasure"})["result"].is_empty() and j.run.bag.items.size() == count)


func _clear_priority(ctx) -> void:
	var f := F.make()
	f["journey"].choose(0)
	var session := Session.new(f["profile"], f["rules"], f["camp"], f["loot"])
	session.begin_stage(MapLoader.load_by_id(f["journey"].current["map"]), f["combat"], f["journey"], 1, 100, F.rng())
	for fighter in session.fighters.values():
		fighter.hp = 0.0
		fighter.state = fighter.State.DEAD
	session.step(SimInput.new())
	ctx.check("M1-6 preserves old clear-vs-death priority when both occur on the same tick", session.journey.state == session.journey.CHOOSING and session.journey.completed == 1)
