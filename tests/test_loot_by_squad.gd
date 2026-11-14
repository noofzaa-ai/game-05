extends RefCounted
## Loot by squad size (Boss 2026-11-12): a smaller squad is easier but pays less. goblin_waves.json
## loot_by_squad (index 0 = 1 fighter) scales every loot source in a fight: per-kill chances, gold and
## materials, challenge rewards and treasure. Same seed = same loot; the factor never
## changes how many random numbers are drawn.
const F := preload("res://tests/online_fixture.gd")
const Party := preload("res://logic/coop_journey.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Loot := preload("res://logic/loot.gd")
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const Map := preload("res://logic/map_loader.gd")
const Fighter := preload("res://logic/fighter.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]


func run(ctx) -> void:
	_data_shape(ctx)
	_roll_scaling(ctx)
	_sim_factor(ctx)
	_journey_rewards(ctx)


func _data_shape(ctx) -> void:
	var combat = F.Combat.load_default()
	var waves = JourneyData.load_by_id("goblin_waves", combat.enemies.keys())
	ctx.check("loot by squad: goblin_waves loads %s" % [waves.errors], waves.is_valid())
	ctx.check("loot by squad: goblin_waves has [0.33, 0.67, 1.0]", waves.loot_by_squad.size() == 3 and is_equal_approx(waves.loot_by_squad[0], 0.33) and is_equal_approx(waves.loot_by_squad[1], 0.67) and is_equal_approx(waves.loot_by_squad[2], 1.0))
	ctx.check("loot by squad: 1/2/3 fighters -> 0.33/0.67/1.0", is_equal_approx(waves.loot_for(1), 0.33) and is_equal_approx(waves.loot_for(2), 0.67) and is_equal_approx(waves.loot_for(3), 1.0))
	ctx.check("loot by squad: a bigger squad uses the last entry", is_equal_approx(waves.loot_for(4), 1.0))
	var road = JourneyData.load_by_id("ink_road", combat.enemies.keys())
	ctx.check("loot by squad: a journey without the list pays full loot", road.loot_by_squad.is_empty() and is_equal_approx(road.loot_for(1), 1.0))
	var broken = JourneyData.parse(JSON.stringify({"version": 1, "loot_by_squad": [-1.0, 0.5]}))
	ctx.check("loot by squad: negative factors are clamped to 0", is_equal_approx(broken.loot_for(1), 0.0) and is_equal_approx(broken.loot_for(2), 0.5))


func _roll_scaling(ctx) -> void:
	var f := F.make()
	var same := true
	var same_draws := true
	var empty := true
	var full := {"gold": 0, "items": 0, "materials": 0}
	var third := {"gold": 0, "items": 0, "materials": 0}
	for seed in range(1, 801):
		var a := F.rng(seed)
		var b := F.rng(seed)
		var c := F.rng(seed)
		var d := F.rng(seed)
		var plain := Loot.roll(f.rules, f.loot, "brute", 4, f.combat.weapon_ids, a)
		var one := Loot.roll(f.rules, f.loot, "brute", 4, f.combat.weapon_ids, b, 1.0)
		var low := Loot.roll(f.rules, f.loot, "brute", 4, f.combat.weapon_ids, c, 0.33)
		var none := Loot.roll(f.rules, f.loot, "brute", 4, f.combat.weapon_ids, d, 0.0)
		same = same and plain.gold == one.gold and plain.materials == one.materials and plain.items.map(func(i): return i.to_dict()) == one.items.map(func(i): return i.to_dict())
		same_draws = same_draws and a.state == b.state and b.state == c.state and c.state == d.state
		empty = empty and none.gold == 0 and none.items.is_empty() and none.materials.is_empty()
		for pair in [[full, one], [third, low]]:
			pair[0].gold += int(pair[1].gold)
			pair[0].items += pair[1].items.size()
			for m in pair[1].materials:
				pair[0].materials += int(pair[1].materials[m])
	ctx.check("loot by squad: factor 1.0 rolls exactly the old drop", same)
	ctx.check("loot by squad: the factor never changes how many random numbers are drawn", same_draws)
	ctx.check("loot by squad: factor 0 drops nothing", empty)
	for key in full:
		var ratio := float(third[key]) / maxf(1.0, float(full[key]))
		ctx.check("loot by squad: factor 0.33 pays about a third of the %s (%.2f)" % [key, ratio], ratio > 0.26 and ratio < 0.40)


## A goblin_waves fight with `cards` (1 = solo through Journey.start).
func _wave_sim(f: Dictionary, cards: Array):
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var journey
	if cards.size() == 1:
		journey = Journey.start(data, f.run, f.rules, f.loot, f.combat.weapon_ids, 77)
	else:
		var members: Array = SquadMember.make_squad(f.run, cards)
		var trips := {}
		for i in members.size():
			trips[i + 1] = members[i]
		journey = Party.start_party(data, trips, f.rules, f.loot, f.combat.weapon_ids, 77)
	journey.choose(0)
	var map = Map.load_by_id(journey.current["map"])
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var sim := Sim.new(world, f.combat, F.rng(12345))
	sim.add_player(1, map.spawn)
	sim.attach_run(1, journey.run, f.rules, f.loot)
	journey.populate(sim, map, 1, 100)
	return sim


func _sim_factor(ctx) -> void:
	var factors := []
	for size in [1, 2, 3]:
		factors.append(_wave_sim(F.make(), CARDS.slice(0, size)).loot_factor)
	ctx.check("loot by squad: the fight's loot factor follows the squad size %s" % [factors], is_equal_approx(factors[0], 0.33) and is_equal_approx(factors[1], 0.67) and is_equal_approx(factors[2], 1.0))
	var f := F.make()
	var sim = _wave_sim(f, CARDS)
	sim.loot_factor = 0.0
	var enemy := -1
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy" and sim.fighters[id].is_alive():
			enemy = id
			break
	sim.fighters[enemy].hp = 0
	sim.fighters[enemy].state = Fighter.State.DEAD
	sim.events.clear()
	sim.events.append({"type": "killed", "target": enemy, "by": 2})
	sim._process_economy()
	var drops: Array = sim.events.filter(func(e): return e["type"] == "loot")
	ctx.check("loot by squad: the kill drop uses the fight's factor", drops.size() == 1 and int(drops[0].gold) == 0 and drops[0].items.is_empty() and drops[0].materials.is_empty())
	sim.loot_factor = 0.67
	var saved: Dictionary = sim.snapshot()
	var copy := Sim.new(World.new(), f.combat, F.rng(1))
	copy.item_rules = f.rules
	copy.loot_data = f.loot
	var restored: bool = copy.restore({"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(saved["checkpoint"]))}, f.camp)
	ctx.check("loot by squad: a checkpoint keeps the loot factor", restored and is_equal_approx(copy.loot_factor, 0.67))


func _journey_rewards(ctx) -> void:
	# Challenge and treasure (road mode stages) use the same factor.
	var paid := 0
	var full_gold := 0
	var low_gold := 0
	for seed in range(1, 121):
		var f := F.make(seed)
		var j = f.journey
		j.completed = 3
		j.nodes[3] = [{"stage": 4, "kind": "challenge", "map": "ink_garden"}]
		j.choose(0)
		full_gold += int(j.challenge_reward(F.rng(seed)).gold)
		j.data.loot_by_squad.assign([0.33])
		low_gold += int(j.challenge_reward(F.rng(seed)).gold)
		var t = F.make(seed)
		t.journey.data.loot_by_squad.assign([0.33])
		t.journey.nodes[1] = [{"stage": 2, "kind": "treasure", "map": ""}]
		t.journey.completed = 1
		t.journey.choose(0)
		paid += t.journey.open_treasure().get("items", []).size()
	var ratio := float(low_gold) / maxf(1.0, float(full_gold))
	ctx.check("loot by squad: a challenge reward pays about a third for one fighter (%.2f)" % ratio, ratio > 0.26 and ratio < 0.40)
	ctx.check("loot by squad: a treasure pays for one fighter about a third of the time (%d of 120)" % paid, paid > 25 and paid < 55)
	var g := F.make(9)
	g.journey.nodes[1] = [{"stage": 2, "kind": "treasure", "map": ""}]
	g.journey.completed = 1
	g.journey.choose(0)
	ctx.check("loot by squad: full factor: the treasure always pays", g.journey.open_treasure().get("items", []).size() == 1)
	var squad := F.make(10)
	var members: Array = SquadMember.make_squad(squad.run, CARDS.slice(0, 2))
	var party = Party.start_party(squad.data, {1: members[0], 2: members[1]}, squad.rules, squad.loot, squad.combat.weapon_ids, 10)
	party.data.loot_by_squad.assign([0.0, 0.0, 1.0])
	party.nodes[1] = [{"stage": 2, "kind": "treasure", "map": ""}]
	party.completed = 1
	party.choose(0)
	party.open_treasure()
	ctx.check("loot by squad: a squad of 2 uses the 2-fighter factor for its treasure", squad.run.bag.items.is_empty())
