extends RefCounted
const F := preload("res://tests/online_fixture.gd")
const Party := preload("res://logic/coop_journey.gd")
const Coop := preload("res://logic/coop.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Codec := preload("res://logic/state_codec.gd")
const Session := preload("res://client/session/local_session.gd")
const Spawns := preload("res://logic/party_spawns.gd")
const Map := preload("res://logic/map_loader.gd")

static func fixture(count: int = 2) -> Dictionary:
	var f := F.make()
	var trips := {1: f.run}
	for id in range(2, count + 1): trips[id] = F.make(77 + id).run
	f.journey = Party.start_party(f.data, trips, f.rules, f.loot, f.combat.weapon_ids, 77)
	return f

static func empty_sim(f):
	var sim = F.simulation(f)
	for id in sim.fighters.keys():
		if sim.fighters[id].team == "enemy":
			sim.fighters.erase(id)
			sim.bodies.erase(id)
			sim._ai.erase(id)
	sim._waves.clear()
	return sim

static func down(sim, id: int) -> void:
	sim.fighters[id].hp = 0
	sim.fighters[id].state = Fighter.State.DEAD
	sim.events.append({"type": "killed", "target": id, "by": 100})
	sim._process_economy()

func run(ctx) -> void:
	var f := fixture()
	ctx.check("M2 party validates two distinct profiles", f.journey != null)
	ctx.check("M2 party refuses a shared profile", Party.start_party(f.data, {1:f.run, 2:f.run},f.rules,f.loot,f.combat.weapon_ids,77) == null)
	var sim = F.simulation(f)
	ctx.check("M2 explicit party enables co-op and independent runs", sim.coop_enabled and sim.runs[1] != sim.runs[2])
	ctx.check("M2 safe spawns separate players", sim.bodies[1].position.distance_to(sim.bodies[2].position) >= .96)
	var solo := F.make()
	var reference = F.simulation(solo)
	ctx.check("M2 solo remains opt-out", not reference.coop_enabled)
	for id in reference.fighters:
		if reference.fighters[id].team == "enemy":
			ctx.check("M2 party HP uses configured multiplier without extra ATK", is_equal_approx(sim.fighters[id].max_hp(), reference.fighters[id].max_hp() * 1.6) and sim.fighters[id].stat("ATK") == reference.fighters[id].stat("ATK"))
	var four := fixture(4)
	var sim4 = F.simulation(four)
	ctx.check("M2 four participants receive safe positions", sim4.runs.size() == 4 and Spawns.points(Map.load_by_id(four.journey.current.map),4,1.2).size() == 4)
	ctx.check("M2 four-player HP multiplier is 2.8", is_equal_approx(sim4.fighters[100].max_hp(), reference.fighters[100].max_hp() * 2.8))
	_revive(ctx)
	_losses(ctx)
	_drops(ctx)
	_session(ctx)
	_data(ctx)
	_carry_and_rewards(ctx)
	for count in [2, 3]:
		var result := preload("res://tests/coop_bot.gd").journey_run(count,77,.7)
		ctx.check("M2 %d starter bots complete all 12 Journey stages" % count, result.won and result.stages == 12 and result.timeouts == 0)

func _revive(ctx):
	var f := fixture()
	var sim = empty_sim(f)
	sim.runs[1].bag.gold = 19
	down(sim,1)
	ctx.check("M2 fatal event becomes downed with bag retained", sim.fighters[1].state == Fighter.State.DOWNED and not sim.runs[1].died and sim.runs[1].bag.gold == 19 and sim.events.any(func(e):return e.type == "downed"))
	sim.bodies[2].position = sim.bodies[1].position + Vector3(1,0,0)
	sim.bodies[1].grounded = true
	sim.bodies[2].grounded = true
	sim.tick_count += 1
	for i in 20: Coop.step(sim)
	ctx.check("M2 idle ally accumulates revive progress", sim.fighters[1].revive_progress == 20)
	var move := SimInput.new()
	move.move = Vector2.RIGHT
	sim.set_input(2, move)
	Coop.step(sim)
	ctx.check("M2 moving interrupts revive", sim.fighters[1].revive_progress == 0)
	sim.set_input(2,SimInput.new())
	for i in 60: Coop.step(sim)
	var saved = sim.snapshot()
	var clone = F.Sim.new(F.World.new(), f.combat, F.rng())
	clone.item_rules = f.rules
	clone.loot_data = f.loot
	ctx.check("M2 mid-revive checkpoint restores", clone.restore(saved, f.camp))
	ctx.check("M2 restored party checkpoint is exact", Codec.digest(saved) == Codec.digest(clone.snapshot()))
	for i in 60:
		Coop.step(sim)
		Coop.step(clone)
	ctx.check("M2 revive completes at configured hold and HP", sim.fighters[1].is_alive() and is_equal_approx(sim.fighters[1].hp,sim.fighters[1].max_hp() * .3) and sim.fighters[1].invulnerable_left == 60)
	ctx.check("M2 replay from mid-revive remains identical", Codec.digest(sim.snapshot()) == Codec.digest(clone.snapshot()))
	f.journey.capture_party(sim)
	var wire: Dictionary = JSON.parse_string(JSON.stringify(f.journey.to_dict()))
	var j = Party.from_dict(wire,f.data,f.rules,f.camp,f.loot,f.combat.weapon_ids)
	ctx.check("M2 JSON Journey roundtrip retains independent player state", j != null and j.to_dict() == f.journey.to_dict() and j.run == j.runs_by_player[1] and j.run != j.runs_by_player[2])

func _losses(ctx):
	var f := fixture()
	var sim = empty_sim(f)
	var stash = sim.runs[1].profile.stash.to_dict()
	sim.runs[1].bag.gold = 23
	down(sim,1)
	sim.tick_count += 1
	sim.fighters[1].bleedout_left = 1
	sim.bodies[2].position += Vector3(10,0,0)
	Coop.step(sim)
	ctx.check("M2 bleedout eliminates and loses only run bag", sim.runs[1].died and sim.runs[1].bag.gold == 0 and sim.runs[1].profile.stash.to_dict() == stash and not sim.runs[2].died)
	sim.runs[2].bag.gold = 31
	down(sim,2)
	Coop.step(sim)
	ctx.check("M2 all down triggers team wipe and remaining bag loss", sim._coop.wiped and sim.runs[2].died and sim.runs[2].bag.gold == 0)
	var events = sim.events.size()
	Coop.step(sim)
	ctx.check("M2 wipe terminal events happen once", sim.events.size() == events)

func _drops(ctx):
	var f := fixture()
	var sim = F.simulation(f)
	sim.events.clear()
	sim._on_killed(100,1)
	var recipients = sim.events.filter(func(e):return e.type == "loot").map(func(e):return e.player)
	ctx.check("M2 enemy kill awards each participant independently", recipients == [1,2])
	var size = sim.events.size()
	sim._on_killed(100,2)
	ctx.check("M2 duplicate kill cannot pay party twice", sim.events.size() == size)
	down(sim,2)
	sim.events.clear()
	sim._on_killed(101,1)
	ctx.check("M2 downed participant remains eligible for loot", sim.events.any(func(e):return e.type == "loot" and e.player == 2))
	sim.runs[2].death()
	sim.events.clear()
	sim._on_killed(102,1)
	ctx.check("M2 eliminated participant receives no new loot", not sim.events.any(func(e):return e.type == "loot" and e.player == 2))

func _session(ctx):
	var f := fixture()
	var s := Session.new(f.profile,f.rules,f.camp,f.loot)
	f.journey.choose(0)
	s.begin_stage(Map.load_by_id(f.journey.current.map),f.combat,f.journey,1,100,F.rng())
	ctx.check("M2 Session exposes both players through read views", s.is_coop() and s.fighters.has(2) and s.profile_for(2) != s.profile_for(1))
	down(s._sim,1)
	s.tick()
	ctx.check("M2 local down does not end party Journey", not s.local_defeated() and not s.journey.is_over())
	down(s._sim,2)
	s.tick()
	ctx.check("M2 Session ends Journey only on team wipe", s.local_defeated() and s.journey.state == s.journey.LOST)

func _data(ctx):
	var loader = preload("res://logic/combat_data_loader.gd")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/combat.json"))
	ctx.check("M2 default co-op rules validate", loader.parse(JSON.stringify(raw)).is_valid())
	raw.coop.revive_ticks = raw.coop.downed_ticks
	ctx.check("M2 rejects impossible revive timing", not loader.parse(JSON.stringify(raw)).is_valid())
	raw.erase("coop")
	ctx.check("M2 older solo combat files remain valid", loader.parse(JSON.stringify(raw)).is_valid())

func _carry_and_rewards(ctx):
	var f := fixture(4)
	var sim = F.simulation(f,true)
	var solo := F.make()
	var base = F.simulation(solo,true)
	var scaled := true
	for i in sim._waves.size():
		for k in sim._waves[i].enemies.size():
			scaled = scaled and is_equal_approx(sim._waves[i].enemies[k].hp_scale,base._waves[i].enemies[k].hp_scale * 2.8)
	ctx.check("M2 boss reinforcements retain party HP scaling", scaled and not sim._waves.is_empty())
	var trip = f.journey
	sim.fighters[2].hp = sim.fighters[2].max_hp() * .45
	sim.fighters[2].gauge = 73.0
	trip.capture_party(sim)
	ctx.check("M2 each participant carries independent HP and gauge", is_equal_approx(trip.health_by_player[2],.45) and trip.gauge_by_player[2] == 73 and trip.gauge_by_player[1] != 73)
	trip.state = trip.CHOOSING
	trip.completed = 0
	trip.nodes[0] = [{"stage":1,"kind":"camp","map":trip.data.camp_map}]
	trip.choose(0)
	ctx.check("M2 camp heals each surviving participant once", is_equal_approx(trip.health_by_player[2],minf(1,.45+trip.data.camp_heal_fraction)))
	var camp_sim := F.Sim.new(F.World.new(),f.combat,F.rng())
	trip.populate(camp_sim,Map.load_by_id(trip.current.map),1,100)
	ctx.check("M2 camp populates party without spawning enemies", camp_sim.coop_enabled and camp_sim.runs.size() == 4 and camp_sim.living_enemy_count() == 0)
	trip.state = trip.AT_NODE
	trip.current.kind = "treasure"
	trip.treasure_pending = true
	trip.open_treasure()
	ctx.check("M2 treasure awards separate Item instances", trip.last_rewards.size() == 4 and trip.last_rewards[1].items[0] != trip.last_rewards[2].items[0])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(trip.to_dict()))
	var restored = Party.from_dict(saved,f.data,f.rules,f.camp,f.loot,f.combat.weapon_ids)
	ctx.check("M2 party reward metadata survives JSON checkpoint", restored.to_dict() == trip.to_dict())
	var full: Dictionary = trip.finish_rewards()
	ctx.check("M2 finish banks every participant independently", full.players.size() == 4 and trip.runs_by_player.values().all(func(r):return r.bag.items.is_empty()))
	var map = Map.load_by_id("sunward_valley")
	map.player_spawns.assign([map.spawn,map.spawn + Vector3(.7,0,.7)])
	var positions := Spawns.points(map,2,1.2)
	ctx.check("M2 custom diagonal spawns cannot overlap body bounds", positions.size()==2 and (absf(positions[0].x-positions[1].x)>=.8 or absf(positions[0].z-positions[1].z)>=.8))
