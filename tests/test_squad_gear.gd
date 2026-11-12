extends RefCounted
## Per-card gear in the fight (docs/tech/per_card_gear_plan.md steps 4-5, Boss answers 2026-11-11): the squad is
## the account's own class cards; each fights in its card's gear and build; ONE shared bag gets one drop per
## kill; the trip ends only when every member is down; checkpoints keep the members.
const F := preload("res://tests/online_fixture.gd")
const Party := preload("res://logic/coop_journey.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Run := preload("res://logic/run.gd")
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const Codec := preload("res://logic/state_codec.gd")
const Fighter := preload("res://logic/fighter.gd")
const Map := preload("res://logic/map_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Session := preload("res://client/session/local_session.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]


static func squad_fixture() -> Dictionary:
	var f := F.make()
	var members: Array = SquadMember.make_squad(f.run, CARDS)
	var trips := {}
	for i in members.size():
		trips[i + 1] = members[i]
	f.members = members
	f.journey = Party.start_party(f.data, trips, f.rules, f.loot, f.combat.weapon_ids, 77)
	f.run = f.journey.run
	return f


static func squad_sim(f: Dictionary):
	var journey = f.journey
	journey.choose(0)
	var map = Map.load_by_id(journey.current["map"])
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var sim := Sim.new(world, f.combat, F.rng(12345))
	sim.add_player(1, map.spawn)
	sim.attach_run(1, f.run, f.rules, f.loot)
	journey.populate(sim, map, 1, 100)
	return sim


static func kill_enemy(sim, enemy_id: int, by: int) -> void:
	sim.fighters[enemy_id].hp = 0
	sim.fighters[enemy_id].state = Fighter.State.DEAD
	sim.events.clear()
	sim.events.append({"type": "killed", "target": enemy_id, "by": by})
	sim._process_economy()


func run(ctx) -> void:
	_party_accepts_squad(ctx)
	_member_gear_and_build(ctx)
	_one_drop_per_kill(ctx)
	_death_rules(ctx)
	_checkpoint(ctx)
	_session_wiring(ctx)


func _party_accepts_squad(ctx) -> void:
	var f := squad_fixture()
	ctx.check("squad: one account's cards form a party sharing one bag", f.journey != null and f.members.all(func(m): return m.bag == f.members[0].bag and m.profile == f.profile))
	var stranger = F.make(91).run
	var mixed = Party.start_party(f.data, {1: f.members[0], 2: f.members[1], 3: stranger}, f.rules, f.loot, f.combat.weapon_ids, 77)
	ctx.check("squad: a squad mixed with an outside run is refused", mixed == null)
	var plain = F.make(92).run
	ctx.check("squad: separate runs still may not share a profile", Party.start_party(f.data, {1: plain, 2: Run.start(plain.profile, f.camp)}, f.rules, f.loot, f.combat.weapon_ids, 77) == null)


func _member_gear_and_build(ctx) -> void:
	var f := squad_fixture()
	var ring = ItemSystem.create_item(f.rules, "squad-test-ring", "ring", 3, F.rng(5))
	f.profile.loadout_of("greatsword").equip(ring)
	var sim = squad_sim(f)
	ctx.check("squad: each fighter wears its own card's gear", sim.runs[2].loadout() == f.profile.loadout_of("greatsword") and sim.runs[1].loadout() == f.profile.loadout_of("sword_shield"))
	ctx.check("squad: fighter stats differ when card loadouts differ", sim.runs[2].stats(f.rules) != sim.runs[1].stats(f.rules) and sim.runs[2].stats(f.rules).get("EFFECT_RES", 0.0) > sim.runs[1].stats(f.rules).get("EFFECT_RES", 0.0))
	# Forcing a style must not swap in that style's default build: the card's own build stays.
	sim.set_class_style(3, "blade")
	ctx.check("squad: a member keeps its card's class skills (not the forced style's)", sim.fighters[3].skill_state.get("skills", []) == preload("res://logic/class_skills/skill_data.gd").load_default().class_skills("longbow"))


func _one_drop_per_kill(ctx) -> void:
	var f := squad_fixture()
	var sim = squad_sim(f)
	var enemy := -1
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy" and sim.fighters[id].is_alive():
			enemy = id
			break
	kill_enemy(sim, enemy, 2)
	var loot_events: Array = sim.events.filter(func(e): return e["type"] == "loot")
	ctx.check("squad: a kill drops once into the shared bag (not once per fighter)", loot_events.size() == 1)


func _death_rules(ctx) -> void:
	var f := squad_fixture()
	f.run.bag.gold = 50
	var gold_before: int = f.profile.stash.gold
	f.members[0].death()
	ctx.check("squad: one member down does not end the trip", f.members[0].died and not f.members[0].shared.died and f.run.bag.gold == 50)
	f.members[1].death()
	f.members[2].death()
	ctx.check("squad: all members down secures the shared bag once", f.members[0].shared.died and f.profile.stash.gold == gold_before + 50 and f.run.bag.gold == 0)


func _checkpoint(ctx) -> void:
	var f := squad_fixture()
	var sim = squad_sim(f)
	for tick in 30:
		sim.tick()
	sim.runs[2].died = true
	sim.runs[3].skill_cooldowns["x"] = 2.5
	var saved: Dictionary = sim.snapshot()
	var copy := Sim.new(World.new(), f.combat, F.rng(1))
	copy.item_rules = f.rules
	copy.loot_data = f.loot
	var json_saved := {"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(saved["checkpoint"]))}
	ctx.check("squad checkpoint: restores", copy.restore(json_saved, f.camp))
	var members: Array = [copy.runs.get(1), copy.runs.get(2), copy.runs.get(3)]
	ctx.check("squad checkpoint: members restore around ONE profile and bag", members.all(func(m): return m is SquadMember) and members.all(func(m): return m.profile == members[0].profile and m.bag == members[0].bag))
	ctx.check("squad checkpoint: cards, deaths and cooldowns per member", members.map(func(m): return m.card_id) == CARDS and members[1].died and not members[0].died and float(members[2].skill_cooldowns.get("x", 0)) == 2.5)
	ctx.check("squad checkpoint: full state equals original", Codec.digest(copy.snapshot()) == Codec.digest(saved))
	var future: Dictionary = Codec.unpack(saved["checkpoint"])
	future["checkpoint_v"] = 99
	ctx.check("squad checkpoint: a newer version is rejected", not Sim.new(World.new(), f.combat).restore({"v": 1, "checkpoint": Codec.pack(future)}, f.camp))
	var journey_copy = Party.from_dict(JSON.parse_string(JSON.stringify(f.journey.to_dict())), f.data, f.rules, f.camp, f.loot, f.combat.weapon_ids)
	ctx.check("squad journey: save/load keeps one shared run", journey_copy != null and journey_copy.runs_by_player.values().all(func(m): return m is SquadMember and m.bag == journey_copy.run.bag) and journey_copy.runs_by_player[2].card_id == "greatsword" and journey_copy.runs_by_player[2].died)


func _session_wiring(ctx) -> void:
	var f := F.make()
	var session = Session.new(f.profile, f.rules, f.camp, f.loot)
	var data = preload("res://logic/journey_data.gd").load_by_id("goblin_waves", f.combat.enemies.keys())
	session.start_journey(data, f.combat.weapon_ids, 5, {}, CARDS)
	ctx.check("squad session: the journey's fighters are the squad cards", session.is_coop() and session.journey.player_ids() == [1, 2, 3] and session.journey.runs_by_player.values().map(func(m): return m.card_id) == CARDS)
	ctx.check("squad session: no guest profiles (all fighters are this account)", session.journey.runs_by_player.values().all(func(m): return m.profile == f.profile))
