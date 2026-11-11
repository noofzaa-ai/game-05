extends RefCounted
const Party := preload("res://logic/party_state.gd")
const Manager := preload("res://server/rooms/manager.gd")
const Fixture := preload("res://tests/online_fixture.gd")
const FrameInput := preload("res://logic/sim_input.gd")
const Links := preload("res://client/online/invite_link.gd")
func run(ctx) -> void:
	var party := Party.new()
	ctx.check("M5 empty party cannot depart", not party.can_depart(-1))
	for id in [4, 2, 1, 3]: ctx.check("M5 accepts four slots %d" % id, party.join(id))
	ctx.check("M5 immutable capacity and leader", not party.join(5) and party.leader() == 1)
	for id in [1, 2, 3, 4]: party.set_ready(id, true)
	ctx.check("M5 only ready leader departs", party.can_depart(1) and not party.can_depart(2))
	party.presence(3, false)
	ctx.check("M5 disconnect resets readiness", not party.can_depart(1) and not party.set_ready(3, true))
	party.leave(1)
	ctx.check("M5 leave hands leadership to lowest surviving slot", party.leader() == 2)
	var raw := []
	for id in [1, 2]: raw.append({"id": id, "profile": Fixture.make(id).profile.to_dict()})
	var manager := Manager.new()
	ctx.check("M5 starts safe waiting camp before capacity", manager.create("party-test", 77, [raw[0]], true, 4).ok)
	var room = manager.rooms["party-test"].room
	ctx.check("M5 camp has no enemies", room.lobby and room.sim.living_enemy_count() == 0)
	var action := FrameInput.new(); action.light = true; action.ultimate = true
	room.input(1, 1, action.encode()); room.tick()
	ctx.check("M5 camp rejects combat input on authority", room.sim.fighters[1].move_id.is_empty())
	ctx.check("M5 admission rebuilds party and changes epoch", room.rebuild_lobby(raw) and room.epoch == 2 and room.party.members.size() == 2)
	ctx.check("M5 unready and nonleader depart denied", room.command(1,1,{"type":"party_depart"}).error == "party_not_ready" and room.command(2,1,{"type":"party_depart"}).error == "leader_only")
	room.command(1,2,{"type":"party_ready","ready":true}); room.command(2,2,{"type":"party_ready","ready":true})
	ctx.check("M5 departure waits for private backend confirmation", room.command(1,3,{"type":"party_depart"}).get("action") == "depart" and room.lobby)
	ctx.check("M5 authoritative departure preserves clock", room.depart() and not room.lobby and room.clock_tick == 1 and room.epoch == 3)
	ctx.check("M5 pings are bounded and server positioned", room.command(2,3,{"type":"party_ping","kind":"help"}).ok and room.command(2,4,{"type":"party_ping","kind":"help"}).error == "rate_limited" and room.events[-1].event.pos == room.sim.bodies[2].position)
	var code := "a".repeat(32) + ":" + "b".repeat(32)
	ctx.check("M5 link fragment and plain invite parse identically", Links.parse(code) == Links.parse("https://game.example/#party="+code))
	ctx.check("M5 malformed invites rejected", Links.parse("https://bad/?token=secret").is_empty() and Links.parse(code+":extra").is_empty())
	ctx.check("M5 ally audio attenuated, self/enemy unchanged", preload("res://client/audio/audio_rules.gd").friend_gain_db({"ally":true}) == -6.0 and preload("res://client/audio/audio_rules.gd").friend_gain_db({"enemy":true}) == 0.0)

	var rig := preload("res://client/camera_rig.gd").new()
	var camera := preload("res://client/party_camera.gd").new(); camera.rig = rig
	var boss := Node3D.new()
	var remote = preload("res://client/session/netfox_session.gd").new()
	remote.server_state = {"tick":10,"epoch":2,"meta":{"boss_intro":{"tick":0,"duration":90,"epoch":2,"boss":100}}}
	camera.update(remote,{100:boss},false)
	ctx.check("M5 shared boss intro follows server clock",camera.active and rig.target == boss)
	camera.update(remote,{100:boss},true)
	ctx.check("M5 local ultimate takes camera priority",not camera.active and rig._overrides.is_empty())
	remote.server_state.tick = 91;camera.update(remote,{100:boss},false)
	ctx.check("M5 late boss intro does not restart cinematic",not camera.active)
	camera.free();rig.free();boss.free()
	var wire := preload("res://logic/net_wire.gd")
	var delta := preload("res://logic/net_state.gd")
	var state: Dictionary = room.public_state(1)
	var cache := {}
	var expected: PackedByteArray = wire.encode(state,262144)
	ctx.check("M6 cached entity encoding stays byte identical",wire.encode(state,262144,cache)==expected and wire.encode(state,262144,cache)==expected)
	var large := {"entities":{}}
	for index in 200: large.entities[index]=range(50)
	cache.clear()
	ctx.check("M6 cached bytes still obey node budget and frame bound",not wire.encode(large,262144,cache).is_empty() and wire.encode(large,65524,cache).is_empty() and wire.encode(state,12,{}).is_empty())
	var before := state.duplicate(true);before.tick-=1
	var delta_cache := {}
	ctx.check("M6 shared delta matches independent calculation",delta.difference(state,before,1,1,delta_cache)==delta.difference(state,before,1,1))
	before.entities[1][0][0] += Vector3.ONE
	ctx.check("M6 same-tick distinct baselines cannot collide",delta.difference(state,before,1,1,delta_cache)==delta.difference(state,before,1,1))
	var exported: Dictionary = room.public_state(1)
	exported.meta.profiles[1].name="mutated";exported.entities[1][0][0]=Vector3.INF
	var intact: Dictionary = room.public_state(1)
	ctx.check("M6 cached snapshots preserve caller ownership and private filtering",intact.meta.profiles[1].name!="mutated" and intact.entities[1][0][0].is_finite() and intact.meta.profiles[2].stash.items.is_empty())
	var whole: Dictionary = room.trip_for(1).to_dict();whole.erase("profile")
	ctx.check("M6 public run skips profile serialization without schema change",room.trip_for(1).to_dict(false)==whole)
