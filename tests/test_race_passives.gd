extends RefCounted
## Race passives in the fight and squad synergies (design/gdd/races-and-classes.md 3.4-3.6, 4.2; phases 2 and 5).
## The squad is the starter S&S/GS/Bow, races set per test with Deck.set_race before the squad is built.
const F := preload("res://tests/online_fixture.gd")
const Party := preload("res://logic/coop_journey.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const Codec := preload("res://logic/state_codec.gd")
const Fighter := preload("res://logic/fighter.gd")
const Map := preload("res://logic/map_loader.gd")
const Deck := preload("res://logic/card_deck.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const RaceData := preload("res://logic/race_data.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]


## A squad fight of the goblin wave journey with these races (one per card of CARDS).
static func squad(races: Array, cards: Array = CARDS, keep_race_gear: bool = false) -> Dictionary:
	var f := F.make()
	for i in cards.size():
		Deck.set_race(f.profile.card_deck, cards[i], races[i])
	if not keep_race_gear:
		plain_gear(f, cards)
	f.data = preload("res://logic/journey_data.gd").load_by_id("goblin_waves", f.combat.enemies.keys())
	var members: Array = SquadMember.make_squad(f.run, cards)
	var trips := {}
	for i in members.size():
		trips[i + 1] = members[i]
	f.journey = Party.start_party(f.data, trips, f.rules, f.loot, f.combat.weapon_ids, 77) if members.size() > 1 else preload("res://logic/journey.gd").start(f.data, members[0], f.rules, f.loot, f.combat.weapon_ids, 77)
	while f.journey.state != f.journey.IN_STAGE:
		if f.journey.state == f.journey.CHOOSING: f.journey.choose(0)
		else: f.journey.leave_node()
	var map = Map.load_by_id(str(f.journey.current["map"]))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var sim := Sim.new(world, f.combat, F.rng(12345))
	if members.size() == 1:
		sim.add_player(1, map.spawn)
		sim.attach_run(1, f.journey.run, f.rules, f.loot)
	f.journey.populate(sim, map, 1, 100)
	f.sim = sim
	return f


## Swaps every worn race set piece (the starter race outfit, race-gear-sets.md) for the set-free class kit piece of the
## same slot and tier, so the passives here are the base ones (tests/test_race_sets.gd covers the set option).
static func plain_gear(f: Dictionary, cards: Array) -> void:
	var kits: Dictionary = preload("res://logic/profile.gd").starter_kits().get("kits", {})
	for card in cards:
		var worn = f.profile.loadout_of(card)
		for item in worn.items():
			if f.rules.catalog.race_set_of(item.item_id).is_empty():
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(item.id)
			worn.unequip(item.slot, 0)
			worn.equip(preload("res://logic/item_system.gd").create_item(f.rules, item.id, item.slot, item.tier, rng, "", str(kits[card][item.slot])))


static func enemy_of(sim) -> int:
	var ids: Array = sim.fighters.keys().filter(func(id): return sim.fighters[id].team == "enemy" and sim.fighters[id].is_alive())
	ids.sort()
	return ids[0]


## Runs RacePassives on one fake sim event (as if it happened this tick) and returns the events it added.
static func react(sim, event: Dictionary) -> Array:
	sim.events.clear()
	sim.events.append(event)
	RacePassives.step(sim)
	return sim.events.slice(1)


static func procs(events: Array, player: int) -> Array:
	return events.filter(func(e): return e["type"] == "race_proc" and int(e["player"]) == player)


func run(ctx) -> void:
	_attach(ctx)
	_headhunter(ctx)
	_living_bark(ctx)
	_rallying_drill(ctx)
	_moonlit_and_bloom(ctx)
	_shield(ctx)
	_low_hp_scaling(ctx)
	_skill_mod(ctx)
	_charges_and_burst(ctx)
	_aggro(ctx)
	_synergy(ctx)
	_checkpoint_and_determinism(ctx)


func _attach(ctx) -> void:
	var f := squad(["human", "viking", "elf"])
	var sim = f.sim
	ctx.check("each squad fighter carries its card's race and passive", sim.fighters[1].race_state["race"] == "human" and sim.fighters[1].race_state["passive"] == "Rallying Drill"
		and sim.fighters[2].race_state["passive"] == "Berserker" and sim.fighters[3].race_state["passive"] == "Moonlit Arrow")
	ctx.check("enemies carry no race", sim.fighters[enemy_of(sim)].race_state.is_empty())


## Viking longbow, Headhunter: a kill grants rage 8 s and haste 4 s (doc 3.4), once per kill.
func _headhunter(ctx) -> void:
	var f := squad(["human", "elf", "viking"])
	var sim = f.sim
	RacePassives.step(sim)  # wave_start of wave 1
	var foe := enemy_of(sim)
	sim.fighters[foe].hp = 0
	sim.fighters[foe].state = Fighter.State.DEAD
	var out := react(sim, {"type": "killed", "target": foe, "by": 3})
	ctx.check("Headhunter: a kill fires once", procs(out, 3).size() == 1)
	ctx.check("Headhunter: rage 480 ticks and haste 240 ticks", int(sim.fighters[3].effects.get("rage", {}).get("left", 0)) == 480 and int(sim.fighters[3].effects.get("haste", {}).get("left", 0)) == 240)
	ctx.check("Headhunter: rage really raises ATK +30%", is_equal_approx(sim.fighters[3].stat("ATK"), float(sim.fighters[3].stats["ATK"]) * 1.3))
	ctx.check("Headhunter: someone else's kill does nothing", procs(react(sim, {"type": "killed", "target": foe, "by": 1}), 3).is_empty())
	ctx.check("Headhunter: a hit is not a kill", procs(react(sim, {"type": "hit", "attacker": 3, "target": foe, "damage": 10, "move": "light_1"}), 3).is_empty())


## Elf greatsword, Living Bark: regen at wave start, refreshed by each kill.
func _living_bark(ctx) -> void:
	var f := squad(["human", "elf", "viking"])
	var sim = f.sim
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("Living Bark: regen at wave start, exactly once", sim.fighters[2].effects.has("regen") and procs(sim.events, 2).size() == 1)
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("Living Bark: no second wave_start in the same wave", procs(sim.events, 2).is_empty())
	sim.fighters[2].effects["regen"]["left"] = 5
	var foe := enemy_of(sim)
	react(sim, {"type": "killed", "target": foe, "by": 2})
	ctx.check("Living Bark: a kill refreshes regen", int(sim.fighters[2].effects["regen"]["left"]) == 480)
	sim._waves_released += 1  # the next wave arrived
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("Living Bark: the next wave starts it again", procs(sim.events, 2).size() == 1)


## Human sword & shield, Rallying Drill: a skill cast gives fortify 3 s to all allies, then a 10 s cooldown.
func _rallying_drill(ctx) -> void:
	var f := squad(["human", "viking", "elf"])
	var sim = f.sim
	RacePassives.step(sim)
	var out := react(sim, {"type": "skill_cast", "player": 1})
	ctx.check("Rallying Drill: a cast fires once", procs(out, 1).size() == 1)
	ctx.check("Rallying Drill: fortify 180 ticks on all three allies", [1, 2, 3].all(func(id): return int(sim.fighters[id].effects.get("fortify", {}).get("left", 0)) == 180))
	ctx.check("Rallying Drill: no enemy is fortified", not sim.fighters[enemy_of(sim)].effects.has("fortify"))
	sim.tick_count += 599
	ctx.check("Rallying Drill: still on cooldown at 599 ticks", procs(react(sim, {"type": "skill_cast", "player": 1}), 1).is_empty())
	sim.tick_count += 1
	ctx.check("Rallying Drill: ready again at 600 ticks", procs(react(sim, {"type": "skill_cast", "player": 1}), 1).size() == 1)
	ctx.check("Rallying Drill: another card's cast does nothing", procs(react(sim, {"type": "skill_cast", "player": 2}), 1).is_empty())


## Elf longbow, Moonlit Arrow: every 5th hit heals the most-hurt ally 6% max HP. Elf magic, Bloomcaster (4.2 example).
func _moonlit_and_bloom(ctx) -> void:
	var f := squad(["human", "viking", "elf"])
	var sim = f.sim
	RacePassives.step(sim)
	var foe := enemy_of(sim)
	var hurt = sim.fighters[2]
	hurt.hp = hurt.max_hp() * 0.5
	var counts := []
	for i in 5:
		counts.append(procs(react(sim, {"type": "hit", "attacker": 3, "target": foe, "damage": 10, "move": "light_1"}), 3).filter(func(e): return e["source"] == "passive").size())  # (not the class signature Hunter's Mark)
	ctx.check("Moonlit Arrow: only the 5th hit heals (%s)" % [counts], counts == [0, 0, 0, 0, 1])
	ctx.check("Moonlit Arrow: the most-hurt ally gets 6% max HP", is_equal_approx(hurt.hp, hurt.max_hp() * 0.56))
	# Formula 4.2 (Bloomcaster): 300 damage, ally max 1000 -> min(0.25 x 300, 0.08 x 1000) = 75; and the cap: 2000 -> 80.
	var ally := Fighter.new()
	ally.stats = {"HP": 1000.0}
	var action := {"action": "heal", "target": "ally_most_hurt", "fraction_of": "damage", "fraction": 0.25, "cap_max_hp": 0.08}
	ctx.check("formula 4.2: Bloomcaster 300 damage -> 75 heal", is_equal_approx(RacePassives.heal_amount(action, ally, ally, 300.0), 75.0))
	ctx.check("formula 4.2: capped at 8% of the ally's max HP", is_equal_approx(RacePassives.heal_amount(action, ally, ally, 2000.0), 80.0))
	var magic := squad(["elf", "elf", "elf"], ["magic", "greatsword", "longbow"])
	var msim = magic.sim
	RacePassives.step(msim)
	msim.fighters[3].hp = msim.fighters[3].max_hp() * 0.5
	var before: float = msim.fighters[3].hp
	react(msim, {"type": "skill_hit", "attacker": 1, "target": enemy_of(msim), "damage": 10})  # HP scale 100: a 10 hit on a ~100-HP squad (below the 8% cap)
	ctx.check("Bloomcaster: a skill hit heals the most-hurt ally 25% of the damage", is_equal_approx(msim.fighters[3].hp - before, 2.5 * msim.fighters[3].heal_factor()))
	for id in [1, 2, 3]: msim.fighters[id].hp = msim.fighters[id].max_hp()
	ctx.check("nobody hurt: Bloomcaster does not proc", procs(react(msim, {"type": "skill_hit", "attacker": 1, "target": enemy_of(msim), "damage": 100}), 1).is_empty())


## Fighter shield (GDD 4.3, phase 4 step 1): an absorb pool capped at 30% max HP, absorbs before HP, lasts
## duration_ticks, cleared at wave end, saved in checkpoints, announced with a race_shield event.
func _shield(ctx) -> void:
	# Formula 4.3: Runeweaver, mage max HP 750 -> 0.10 x 750 = 75 per ally per discharge.
	var mage := Fighter.new()
	mage.stats = {"HP": 750.0}
	var runeweaver := {"action": "shield", "target": "allies_all", "fraction_of": "source_max_hp", "fraction": 0.10, "duration_ticks": 600}
	ctx.check("formula 4.3: Runeweaver 750 max HP -> 75 shield", is_equal_approx(RacePassives.shield_amount(runeweaver, mage, 0.0), 75.0))
	var pool := Fighter.new()
	pool.stats = {"HP": 1000.0}
	pool.hp = 1000.0
	ctx.check("shield: a 200 gain on 1000 max HP adds 200", is_equal_approx(pool.add_shield(200.0, 600, 0, 0.30), 200.0) and is_equal_approx(pool.shield, 200.0))
	ctx.check("shield: capped at 30% max HP (only 100 more of 250 fits)", is_equal_approx(pool.add_shield(250.0, 600, 0, 0.30), 100.0) and is_equal_approx(pool.shield, 300.0))
	ctx.check("shield: absorbs before HP (120 hit -> 120 absorbed)", is_equal_approx(pool.absorb(120.0), 120.0) and is_equal_approx(pool.shield, 180.0))
	ctx.check("shield: the rest goes to HP (500 hit -> 180 absorbed)", is_equal_approx(pool.absorb(500.0), 180.0) and pool.shield == 0.0)
	# Runeborn Pair: every ally gets 8% of their own max HP at wave start.
	var f := squad(["runeborn", "runeborn", "human"])
	var sim = f.sim
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("Runeborn Pair: 8%% max HP shield on every ally at wave start (%s)" % [[1, 2, 3].map(func(id): return snappedf(sim.fighters[id].shield / sim.fighters[id].max_hp(), 0.001))],
		[1, 2, 3].all(func(id): return is_equal_approx(sim.fighters[id].shield, sim.fighters[id].max_hp() * 0.08)))
	ctx.check("shield: a race_shield event for the client", sim.events.any(func(e): return e["type"] == "race_shield" and int(e["target"]) == 1 and float(e["amount"]) > 0.0))
	# A real enemy hit is absorbed by the shield before HP.
	var foe := enemy_of(sim)
	var tank = sim.fighters[1]
	tank.add_shield(tank.max_hp(), 600, sim.tick_count, 0.30)  # top up to the cap so one goblin blow fits in it
	var hp_before: float = tank.hp
	var shield_before: float = tank.shield
	sim.events.clear()
	sim.fighters[foe].direction = Vector2i(1, 0)
	var move: String = sim.combat.styles[sim.fighters[foe].style]["ground_light"]
	preload("res://logic/combat.gd").apply_hit(foe, 1, move, sim.fighters, sim.bodies, sim.combat, sim.rng, sim.events)
	var hit: Array = sim.events.filter(func(e): return e["type"] in ["hit", "blocked"] and int(e["target"]) == 1)
	ctx.check("shield: an enemy hit is absorbed before HP (hp %.1f -> %.1f, shield %.1f -> %.1f)" % [hp_before, tank.hp, shield_before, tank.shield],
		tank.hp == hp_before and tank.shield < shield_before and not hit.is_empty() and float(hit[0].get("absorbed", 0.0)) > 0.0)
	# Saved in checkpoints.
	var copy = Sim.new(World.new(), f.combat, F.rng(1))
	copy.item_rules = f.rules
	copy.loot_data = f.loot
	copy.restore({"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(sim.snapshot()["checkpoint"]))}, f.camp)
	ctx.check("shield: saved in the checkpoint", is_equal_approx(copy.fighters[1].shield, tank.shield) and int(copy.fighters[1].shield_until) == int(tank.shield_until))
	# Expires after duration_ticks; cleared at wave end.
	sim.tick_count = int(tank.shield_until)
	RacePassives.step(sim)
	ctx.check("shield: gone after its duration", tank.shield == 0.0)
	var g := squad(["runeborn", "runeborn", "runeborn"])
	RacePassives.step(g.sim)
	ctx.check("Runeborn Trio: 12% max HP shield at wave start", is_equal_approx(g.sim.fighters[2].shield, g.sim.fighters[2].max_hp() * 0.12))
	g.sim.fighters[2].shield_until = g.sim.tick_count + 100000
	g.sim._waves_released += 1
	g.sim.fighters[2].shield = 1.0
	RacePassives.step(g.sim)
	ctx.check("shield: cleared at wave end (the new wave regrants only 12%)", is_equal_approx(g.sim.fighters[2].shield, g.sim.fighters[2].max_hp() * 0.12))
	# Viking sword & shield, Unbroken: first drop below 35% HP each wave -> shield 25% max HP.
	var v := squad(["viking", "human", "elf"])
	var vsim = v.sim
	RacePassives.step(vsim)
	var viking = vsim.fighters[1]
	viking.hp = viking.max_hp() * 0.30
	vsim.events.clear()
	RacePassives.step(vsim)
	ctx.check("Unbroken: below 35% HP -> shield 25% max HP, one proc", is_equal_approx(viking.shield, viking.max_hp() * 0.25) and procs(vsim.events, 1).size() == 1)
	viking.hp = viking.max_hp()
	RacePassives.step(vsim)
	viking.hp = viking.max_hp() * 0.30
	vsim.events.clear()
	RacePassives.step(vsim)
	ctx.check("Unbroken: once per wave", procs(vsim.events, 1).is_empty())


## low_hp_scaling (GDD 4.1, phase 4 step 2): bonus = max_mul x clamp((from_hp - h) / (from_hp - full_at_hp), 0, 1);
## a `below` gate makes it a step (0 above, max_mul below). Read live through Fighter.stat, so damage follows HP.
func _low_hp_scaling(ctx) -> void:
	var berserker := {"type": "low_hp_scaling", "stat": "ATK", "max_mul": 0.4, "from_hp": 1.0, "full_at_hp": 0.2}
	var got := []
	for h in [1.0, 0.6, 0.5, 0.2, 0.1]:
		got.append(snappedf(RacePassives.low_hp_bonus(berserker, h), 0.0001))
	ctx.check("formula 4.1: Berserker at h=1.0/0.6/0.5/0.2/0.1 -> 0/0.20/0.25/0.40/0.40 (%s)" % [got], got == [0.0, 0.2, 0.25, 0.4, 0.4])
	var pair := {"type": "low_hp_scaling", "stat": "ATK", "max_mul": 0.15, "below": 0.5}
	ctx.check("formula 4.1: Viking Pair gate -> 0 at 50%, 0.15 at 49%",
		RacePassives.low_hp_bonus(pair, 0.5) == 0.0 and is_equal_approx(RacePassives.low_hp_bonus(pair, 0.49), 0.15))
	# Viking greatsword (Berserker) in an Alliance squad: ATK follows HP, live.
	var f := squad(["human", "viking", "elf"])
	var gs = f.sim.fighters[2]
	var base: float = gs.stat("ATK")
	gs.hp = gs.max_hp() * 0.6
	ctx.check("Berserker: ATK +20%% at 60%% HP (%.2f vs %.2f)" % [gs.stat("ATK"), base], is_equal_approx(gs.stat("ATK"), base * 1.2))
	gs.hp = gs.max_hp() * 0.1
	ctx.check("Berserker: ATK +40% at 10% HP", is_equal_approx(gs.stat("ATK"), base * 1.4))
	var low_def: float = gs.stat("DEF")
	gs.hp = gs.max_hp()
	ctx.check("Berserker: DEF does not scale", is_equal_approx(gs.stat("DEF"), low_def))
	ctx.check("Berserker: no bonus at full HP", is_equal_approx(gs.stat("ATK"), base))
	# Viking magic (Blood Rite, no scaling) in a Viking Pair: only the Pair's step bonus.
	var v := squad(["viking", "viking", "elf"], ["magic", "sword_shield", "longbow"])
	var mage = v.sim.fighters[1]
	var mbase: float = mage.stat("ATK")
	mage.hp = mage.max_hp() * 0.51
	ctx.check("Viking Pair: nothing at 51% HP", is_equal_approx(mage.stat("ATK"), mbase))
	mage.hp = mage.max_hp() * 0.4
	ctx.check("Viking Pair: ATK +15%% below 50%% (%.2f vs %.2f)" % [mage.stat("ATK"), mbase], is_equal_approx(mage.stat("ATK"), mbase * 1.15))
	# Viking default_class (every current class has a Viking cell, so a class without one is faked): +20% below 50%,
	# stacking additively with the Pair's +15%.
	var default_effects: Array = RaceData.load_default().races["viking"]["default_class"]["passive"]["effects"]
	mage.race_state["scaling"] = mage.race_state["scaling"] + default_effects.filter(func(e): return e["type"] == "low_hp_scaling")
	ctx.check("Viking default + Pair: ATK x(1 + 0.20 + 0.15) below 50%", is_equal_approx(mage.stat("ATK"), mbase * 1.35))
	var bow = v.sim.fighters[3]
	var bbase: float = bow.stat("ATK")
	bow.hp = bow.max_hp() * 0.4
	ctx.check("Viking Pair: the Elf member gets +15% below 50% too", is_equal_approx(bow.stat("ATK"), bbase * 1.15))
	var t := squad(["viking", "viking", "viking"])
	var tank = t.sim.fighters[1]
	var tbase: float = tank.stat("ATK")
	tank.hp = tank.max_hp() * 0.3
	ctx.check("Viking Trio: ATK +20% below 50% (sword & shield has no scaling cell)", is_equal_approx(tank.stat("ATK"), tbase * 1.2))


## Casts skill slot 0 of squad member `id` through the real skill-build path; returns the release job's stats
## and the cooldown it set ({} if the cast was refused, with "refused").
static func cast_slot0(sim, id: int) -> Dictionary:
	var fighter = sim.fighters[id]
	var class_id := str(fighter.race_state["class"])
	sim.set_class_style(id, str(Deck.class_data(class_id).get("weapon", "")))  # as the client and class_sim do
	fighter.energy = fighter.max_energy()
	var Skills = preload("res://logic/class_skills/engine.gd")
	var skill: String = fighter.skill_state["skills"][0]
	fighter.skill_state["cd"][skill] = 0
	var problem: String = Skills.cast(sim, id, skill, {"target": enemy_of(sim)})
	if not problem.is_empty():
		return {"refused": problem}
	return {"stats": fighter.skill_state["cast"]["stats"], "cooldown": float(fighter.skill_state["cast"]["stats"]["cooldown"])}


## skill_mod (GDD 4.4, phase 4 step 3): the hook where a class-skill cast resolves (logic/class_skills/engine.gd cast_stats()).
func _skill_mod(ctx) -> void:
	# Formula 4.4 on plain stats: Human magic + Human Trio -> cooldown x0.85 x0.90 = 0.765, damage x1.30 x1.20.
	var mage := Fighter.new()
	mage.stats = {"HP": 750.0}
	mage.hp = 750.0
	mage.race_state = {"effects": [{"src": "passive", "effect": {"type": "skill_mod", "damage_mul": 1.3, "cooldown_mul": 0.85}},
		{"src": "synergy", "effect": {"type": "skill_mod", "damage_mul": 1.2, "cooldown_mul": 0.9}}], "pseudo": {}}
	var stats := {"damage": 100.0, "cooldown": 10.0, "radius": 2.0, "crit_chance": 0.1}
	RacePassives.modify_skill_stats(mage, stats)
	ctx.check("formula 4.4: Human magic + Trio cooldown 10 -> 7.65 (%.3f)" % stats["cooldown"], is_equal_approx(stats["cooldown"], 7.65))
	ctx.check("formula 4.4: Human magic + Trio damage 100 -> 156 (%.2f)" % stats["damage"], is_equal_approx(stats["damage"], 156.0))
	mage.race_state["pseudo"] = {"SKILL_DMG": {"add": 0.0, "mul": 0.3}}  # recital (+30% SKILL_DMG): 1.30 x 1.20 x 1.30 = 2.028
	stats = {"damage": 100.0, "cooldown": 10.0}
	RacePassives.modify_skill_stats(mage, stats)
	ctx.check("formula 4.4: with SKILL_DMG +30%% -> 2.028x (%.3f)" % (stats["damage"] / 100.0), is_equal_approx(stats["damage"], 202.8))
	mage.race_state["effects"].append({"src": "passive", "effect": {"type": "skill_mod", "cooldown_mul": 0.5}})
	stats = {"damage": 100.0, "cooldown": 10.0}
	RacePassives.modify_skill_stats(mage, stats)
	ctx.check("formula 4.4: cooldown floored at x0.60 (%.2f)" % stats["cooldown"], is_equal_approx(stats["cooldown"], 6.0))
	var gs := Fighter.new()
	gs.stats = {"HP": 1000.0}
	gs.race_state = {"effects": [{"src": "passive", "effect": {"type": "skill_mod", "radius_mul": 1.25, "damage_mul": 1.1}},
		{"src": "passive", "effect": {"type": "skill_mod", "crit_add": 20.0}}], "pseudo": {}}
	stats = {"damage": 100.0, "radius": 2.0, "crit_chance": 0.1}
	RacePassives.modify_skill_stats(gs, stats)
	ctx.check("Wide Arcs: radius x1.25, damage x1.1; Trained Eye: crit +20", is_equal_approx(stats["radius"], 2.5) and is_equal_approx(stats["damage"], 110.0) and is_equal_approx(stats["crit_chance"], 0.3))
	# Real casts. Human magic (Archmage) vs Elf magic (no skill_mod), same squad shape otherwise (Alliance both).
	var human := squad(["human", "viking", "elf"], ["magic", "greatsword", "longbow"])
	var elf := squad(["elf", "viking", "human"], ["magic", "greatsword", "longbow"])
	if not preload("res://logic/class_skills/engine.gd").has_skills(human.sim.fighters[1]):
		ctx.check("skill_mod: squad cards have their class skills", false)
		return
	var h := cast_slot0(human.sim, 1)
	var e := cast_slot0(elf.sim, 1)
	ctx.check("Archmage: a real cast is accepted (%s / %s)" % [h.get("refused", ""), e.get("refused", "")], h.has("stats") and e.has("stats"))
	if h.has("stats") and e.has("stats"):
		ctx.check("Archmage: real cast damage x1.30 (%.2f vs %.2f)" % [float(h["stats"]["damage"]), float(e["stats"]["damage"])], is_equal_approx(float(h["stats"]["damage"]), float(e["stats"]["damage"]) * 1.3))
		ctx.check("Archmage: real cast cooldown x0.85 (%.2f vs %.2f)" % [h["cooldown"], e["cooldown"]], is_equal_approx(float(h["cooldown"]), float(e["cooldown"]) * 0.85))
	# Viking magic (Blood Rite): +40% damage, costs 5% of current HP, refused below 10% HP; the cost is not a hurt.
	var viking := squad(["viking", "human", "elf"], ["magic", "greatsword", "longbow"])
	var vm = viking.sim.fighters[1]
	vm.hp = vm.max_hp() * 0.8
	var before: float = vm.hp
	viking.sim.events.clear()
	var v := cast_slot0(viking.sim, 1)
	ctx.check("Blood Rite: real cast damage x1.40", v.has("stats") and e.has("stats") and is_equal_approx(float(v["stats"]["damage"]), float(e["stats"]["damage"]) * 1.4))
	ctx.check("Blood Rite: pays 5%% of current HP (%.2f -> %.2f)" % [before, vm.hp], is_equal_approx(vm.hp, before * 0.95))
	ctx.check("Blood Rite: the price is not damage (no hit/hurt event)", not viking.sim.events.any(func(ev): return ev["type"] in ["hit", "skill_hit"] and int(ev.get("target", -1)) == 1))
	var low := squad(["viking", "human", "elf"], ["magic", "greatsword", "longbow"])
	low.sim.fighters[1].hp = low.sim.fighters[1].max_hp() * 0.09
	ctx.check("Blood Rite: cannot cast below 10% HP", cast_slot0(low.sim, 1).get("refused", "") == "race_min_hp")


## charges + burst (phase 4 step 4): the 4 Runeborn cells and the Runeborn Trio's RUNE_GAIN.
func _charges_and_burst(ctx) -> void:
	# Rune Aegis (Runeborn sword & shield): +1 per hit taken or blocked, at 5 -> shield 20% max HP + fortify 4 s, reset.
	var f := squad(["runeborn", "human", "elf"])
	var sim = f.sim
	RacePassives.step(sim)
	var foe := enemy_of(sim)
	var tank = sim.fighters[1]
	var discharges := []
	for i in 5:
		var event := {"type": "hit", "attacker": foe, "target": 1, "damage": 10, "move": "light_1"} if i % 2 == 0 else {"type": "blocked", "attacker": foe, "target": 1, "damage": 3}
		discharges.append(procs(react(sim, event), 1).size())
	ctx.check("Rune Aegis: discharges on the 5th hit/block only (%s)" % [discharges], discharges == [0, 0, 0, 0, 1])
	ctx.check("Rune Aegis: shield 20% max HP + fortify 240 ticks", is_equal_approx(tank.shield, tank.max_hp() * 0.2) and int(tank.effects.get("fortify", {}).get("left", 0)) == 240)
	ctx.check("Rune Aegis: runes reset to 0", int(tank.race_state["fx"]["0"]["charges"]) == 0)
	var pips: Array = react(sim, {"type": "hit", "attacker": foe, "target": 1, "damage": 10, "move": "light_1"}).filter(func(e): return e["type"] == "race_runes")
	ctx.check("Rune Aegis: a race_runes event for the pips (1/5)", pips.size() == 1 and int(pips[0]["runes"]) == 1 and int(pips[0]["max"]) == 5)
	ctx.check("Rune Aegis: dealing a hit gains nothing", procs(react(sim, {"type": "hit", "attacker": 1, "target": foe, "damage": 10, "move": "light_1"}), 1).is_empty() and int(tank.race_state["fx"]["0"]["charges"]) == 1)
	# Runic Edge (Runeborn greatsword): +1 per heavy hit, at 4 -> burst 80% ATK within 3 m + shock.
	var g := squad(["human", "runeborn", "elf"])
	var gsim = g.sim
	RacePassives.step(gsim)
	var enemies: Array = gsim.fighters.keys().filter(func(id): return gsim.fighters[id].team == "enemy" and gsim.fighters[id].is_alive())
	enemies.sort()
	var at: Vector3 = gsim.bodies[2].position
	for other in enemies:
		gsim.bodies[other].position = at + Vector3(20.0, 0, 20.0)  # everyone else far away
	gsim.bodies[enemies[0]].position = at + Vector3(2.0, 0, 0)  # inside 3 m
	gsim.bodies[enemies[1]].position = at + Vector3(0, 0, 2.9)  # inside
	gsim.bodies[enemies[2]].position = at + Vector3(3.5, 0, 0)  # outside
	var near = gsim.fighters[enemies[0]]
	near.stats["HP"] = 100000.0
	near.hp = 100000.0
	var gs = gsim.fighters[2]
	var defense: float = near.stat("DEF")
	var expected := roundf(gs.stat("ATK") * 0.8 * (1.0 - defense / (defense + float(gsim.combat.rules["defense_constant"]))))
	var hp_far: float = gsim.fighters[enemies[2]].hp
	var counts := []
	var out := []
	for i in 4:
		out = react(gsim, {"type": "hit", "attacker": 2, "target": enemies[0], "damage": 10, "move": "heavy"})
		counts.append(procs(out, 2).size())
	react(gsim, {"type": "hit", "attacker": 2, "target": enemies[0], "damage": 10, "move": "light_1"})  # a light hit is not a rune
	ctx.check("Runic Edge: bursts on the 4th heavy only (%s)" % [counts], counts == [0, 0, 0, 1] and int(gs.race_state["fx"]["0"]["charges"]) == 0)
	var hits: Array = out.filter(func(e): return e["type"] == "race_burst_hit")
	ctx.check("Runic Edge: hits the 2 enemies within 3 m, not the one at 3.5 m", hits.map(func(e): return int(e["target"])) == [enemies[0], enemies[1]] and gsim.fighters[enemies[2]].hp == hp_far)
	ctx.check("Runic Edge: 80%% ATK vs DEF (%.0f, expected %.0f)" % [float(hits[0]["damage"]) if not hits.is_empty() else -1.0, expected],
		not hits.is_empty() and is_equal_approx(float(hits[0]["damage"]), expected) and is_equal_approx(near.hp, 100000.0 - expected))
	ctx.check("Runic Edge: shock on the enemies hit (applied or resisted by the normal rule)", out.any(func(e): return e["type"] in ["effect_applied", "effect_resisted"] and e.get("effect", "") == "shock" and int(e["target"]) == enemies[0]))
	ctx.check("Runic Edge: a race_burst event for the client", out.any(func(e): return e["type"] == "race_burst" and is_equal_approx(float(e["radius"]), 3.0)))
	# A burst kill is a normal kill (loot, waves).
	var weak = gsim.fighters[enemies[1]]
	weak.hp = 1.0
	for i in 4:
		out = react(gsim, {"type": "hit", "attacker": 2, "target": enemies[0], "damage": 10, "move": "heavy"})
	ctx.check("Runic Edge: a burst kill is a killed event by the caster", not weak.is_alive() and out.any(func(e): return e["type"] == "killed" and int(e["target"]) == enemies[1] and int(e["by"]) == 2))
	# Glyph Shot (Runeborn longbow): +1 per basic hit, at 6 -> focus 8 s + shield 8% max HP.
	var b := squad(["human", "elf", "runeborn"])
	var bsim = b.sim
	RacePassives.step(bsim)
	var bfoe := enemy_of(bsim)
	counts = []
	for i in 6:
		counts.append(procs(react(bsim, {"type": "hit", "attacker": 3, "target": bfoe, "damage": 10, "move": "light_1"}), 3).filter(func(e): return e["source"] == "passive").size())  # (not Hunter's Mark)
	var bow = bsim.fighters[3]
	ctx.check("Glyph Shot: discharges on the 6th hit (%s)" % [counts], counts == [0, 0, 0, 0, 0, 1])
	ctx.check("Glyph Shot: focus 480 ticks + shield 8% max HP", int(bow.effects.get("focus", {}).get("left", 0)) == 480 and is_equal_approx(bow.shield, bow.max_hp() * 0.08))
	# Runeweaver (Runeborn magic): +1 per skill cast, at 3 -> shield every ally 10% of the caster's max HP (4.3).
	var m := squad(["runeborn", "human", "elf"], ["magic", "greatsword", "longbow"])
	var msim = m.sim
	RacePassives.step(msim)
	counts = []
	for i in 3:
		counts.append(procs(react(msim, {"type": "skill_cast", "player": 1}), 1).size())
	var mage_hp: float = msim.fighters[1].max_hp()
	ctx.check("Runeweaver: discharges on the 3rd cast (%s)" % [counts], counts == [0, 0, 1])
	ctx.check("Runeweaver: every ally gets 10%% of the caster's max HP (%s)" % [[1, 2, 3].map(func(id): return snappedf(msim.fighters[id].shield, 0.01))],
		[1, 2, 3].all(func(id): return is_equal_approx(msim.fighters[id].shield, minf(mage_hp * 0.1, msim.fighters[id].max_hp() * 0.3))))
	# Runes carry across waves.
	react(msim, {"type": "skill_cast", "player": 1})
	msim._waves_released += 1
	msim.events.clear()
	RacePassives.step(msim)
	ctx.check("runes carry across waves", int(msim.fighters[1].race_state["fx"]["0"]["charges"]) == 1)
	# ultimate_cast (gain "max"): fills and discharges once, even with runes already near max (GDD 5).
	msim.events.clear()
	RacePassives.fire(msim, 1, "ultimate_cast", {})
	ctx.check("ultimate_cast fills the runes and discharges exactly once", procs(msim.events, 1).size() == 1 and int(msim.fighters[1].race_state["fx"]["0"]["charges"]) == 0)
	# Runeborn Trio: RUNE_GAIN +1 -> Rune Aegis gains 2 per hit: 2, 4, 5 (capped) -> discharges on the 3rd hit.
	var t := squad(["runeborn", "runeborn", "runeborn"])
	var tsim = t.sim
	RacePassives.step(tsim)
	var tfoe := enemy_of(tsim)
	counts = []
	for i in 3:
		counts.append(procs(react(tsim, {"type": "hit", "attacker": tfoe, "target": 1, "damage": 10, "move": "light_1"}), 1).filter(func(e): return e.get("discharge", false)).size())
	ctx.check("Runeborn Trio: rune gains +1 (Rune Aegis on the 3rd hit) (%s)" % [counts], counts == [0, 0, 1])
	# Charges are in the checkpoint.
	react(tsim, {"type": "hit", "attacker": tfoe, "target": 1, "damage": 10, "move": "light_1"})
	var copy = Sim.new(World.new(), t.combat, F.rng(1))
	copy.item_rules = t.rules
	copy.loot_data = t.loot
	copy.restore({"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(tsim.snapshot()["checkpoint"]))}, t.camp)
	ctx.check("runes are saved in the checkpoint", int(copy.fighters[1].race_state["fx"]["0"]["charges"]) == 2)


## aggro / pulse_aggro (phase 4 step 5): Bulwark, the sword & shield signature (GDD 3.2), any race; the enemy AI
## target override (logic/enemy_ai.gd taunt) that the race engine sets through GameSim.taunt_enemy.
func _aggro(ctx) -> void:
	var f := squad(["elf", "elf", "human"])  # Elf S&S: no taunt in its passive, so only the class signature taunts
	var sim = f.sim
	var enemies: Array = sim.fighters.keys().filter(func(id): return sim.fighters[id].team == "enemy" and sim.fighters[id].is_alive())
	enemies.sort()
	var tank_at: Vector3 = sim.bodies[1].position
	for other in enemies:
		sim.bodies[other].position = tank_at + Vector3(30.0, 0, 30.0)
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("Bulwark: no pulse while no enemy is within 5 m", sim.events.filter(func(e): return e["type"] == "race_taunt").is_empty())
	# Enemy A at 4 m from the tank but 1 m from the bow: without a taunt it targets the bow (nearest).
	sim.bodies[3].position = tank_at + Vector3(5.0, 0, 0)
	sim.bodies[2].position = tank_at + Vector3(-20.0, 0, 0)
	sim.bodies[enemies[0]].position = tank_at + Vector3(4.0, 0, 0)
	sim.bodies[enemies[1]].position = tank_at + Vector3(5.5, 0, 0)  # outside 5 m of the tank
	var brain = sim._ai[enemies[0]]
	ctx.check("enemy AI: no taunt -> attacks the nearest player", brain.taunted_by(sim.fighters[enemies[0]], sim.fighters) == -1)
	sim.events.clear()
	RacePassives.step(sim)
	var taunts: Array = sim.events.filter(func(e): return e["type"] == "race_taunt")
	ctx.check("Bulwark: pulses once an enemy is within 5 m, taunting only those (%s)" % [taunts], taunts.size() == 1 and taunts[0]["enemies"] == [enemies[0]] and int(taunts[0]["ticks"]) == 180)
	ctx.check("Bulwark: a signature race_proc", procs(sim.events, 1).any(func(e): return e["source"] == "signature" and e["name"] == "Bulwark"))
	ctx.check("enemy AI: taunted -> attacks the tank, not the nearer bow", brain.taunted_by(sim.fighters[enemies[0]], sim.fighters) == 1 and int(brain.taunt_left) == 180)
	ctx.check("enemy AI: the one outside 5 m is not taunted", int(sim._ai[enemies[1]].taunt_left) == 0)
	# The override really steers the brain: it walks toward the tank (left), not the bow (right).
	sim.fighters[enemies[0]].state = Fighter.State.IDLE
	var input = brain.think(sim.fighters[enemies[0]], sim.bodies[enemies[0]], sim.bodies, sim.fighters, sim.rng, true)
	ctx.check("enemy AI: a taunted monster moves toward the tank (move.x %.2f < 0)" % input.move.x, input.move.x < 0.0)
	# Every 8 s: not again at 479 ticks, again at 480.
	sim.tick_count += 479
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("Bulwark: no second pulse at 479 ticks", sim.events.filter(func(e): return e["type"] == "race_taunt").is_empty())
	sim.tick_count += 1
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("Bulwark: pulses again at 480 ticks", sim.events.filter(func(e): return e["type"] == "race_taunt").size() == 1)
	# The taunt runs out after 180 AI ticks, then the nearest rule is back.
	for i in 180:
		brain.think(sim.fighters[enemies[0]], sim.bodies[enemies[0]], sim.bodies, sim.fighters, sim.rng, true)
	ctx.check("enemy AI: the taunt ends after 180 ticks", int(brain.taunt_left) == 0 and brain.taunted_by(sim.fighters[enemies[0]], sim.fighters) == -1)
	# Overlap: the longer remaining taunt wins; a shorter one from someone else does not take over.
	ctx.check("taunt: a fresh taunt lands", sim.taunt_enemy(enemies[0], 1, 180))
	ctx.check("taunt: a shorter one by another card does not override", not sim.taunt_enemy(enemies[0], 3, 60) and int(brain.taunt_target) == 1 and int(brain.taunt_left) == 180)
	ctx.check("taunt: the same card does not stack duration", sim.taunt_enemy(enemies[0], 1, 180) and int(brain.taunt_left) == 180)
	# A downed or dead taunter releases the monster at once.
	sim.fighters[1].state = Fighter.State.DEAD
	ctx.check("taunt: a dead taunter releases the monster", brain.taunted_by(sim.fighters[enemies[0]], sim.fighters) == -1)
	sim.fighters[1].state = Fighter.State.IDLE
	# Taunt is not a control effect: control immunity does not block it (the boss, GDD 5).
	sim.fighters[enemies[0]].control_immune_left = 300
	brain.taunt_left = 0
	ctx.check("taunt ignores control immunity", sim.taunt_enemy(enemies[0], 1, 180))
	# Saved in checkpoints (AI state is checkpointed).
	var copy = Sim.new(World.new(), f.combat, F.rng(1))
	copy.item_rules = f.rules
	copy.loot_data = f.loot
	copy.restore({"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(sim.snapshot()["checkpoint"]))}, f.camp)
	ctx.check("taunt is saved in the checkpoint", int(copy._ai[enemies[0]].taunt_target) == 1 and int(copy._ai[enemies[0]].taunt_left) == int(brain.taunt_left))
	ctx.check("Bulwark timer is saved in the checkpoint", copy.fighters[1].race_state["fx"] == sim.fighters[1].race_state["fx"])
	# Other classes have no signature taunt.
	ctx.check("only sword & shield carries Bulwark", sim.fighters[2].race_state["effects"].all(func(e): return e["effect"]["type"] != "aggro")
		and sim.fighters[1].race_state["effects"].any(func(e): return e["effect"]["type"] == "aggro"))
	# Viking S&S Unbroken: below 35% HP -> shield AND an immediate Bulwark pulse (pulse_aggro), even off its timer.
	var v := squad(["viking", "human", "elf"])
	var vsim = v.sim
	var ven: Array = vsim.fighters.keys().filter(func(id): return vsim.fighters[id].team == "enemy" and vsim.fighters[id].is_alive())
	ven.sort()
	for other in ven:
		vsim.bodies[other].position = vsim.bodies[1].position + Vector3(30.0, 0, 30.0)
	vsim.bodies[ven[0]].position = vsim.bodies[1].position + Vector3(3.0, 0, 0)
	RacePassives.step(vsim)  # wave start + the first Bulwark pulse
	vsim.tick_count += 60
	vsim._ai[ven[0]].taunt_left = 0
	var viking = vsim.fighters[1]
	viking.hp = viking.max_hp() * 0.3
	vsim.events.clear()
	RacePassives.step(vsim)
	ctx.check("Unbroken: shield + an immediate taunt pulse (Bulwark still on cooldown)",
		viking.shield > 0.0 and vsim.events.any(func(e): return e["type"] == "race_taunt") and int(vsim._ai[ven[0]].taunt_target) == 1 and int(vsim._ai[ven[0]].taunt_left) == 180)


func _synergy(ctx) -> void:
	var trio := squad(["elf", "elf", "elf"])
	ctx.check("run synergy: AAA -> Trio", trio.journey.synergy()["kind"] == "trio" and trio.journey.synergy()["race"] == "elf")
	ctx.check("run synergy: AAB -> Pair(A)", squad(["viking", "elf", "viking"]).journey.synergy()["race"] == "viking" and squad(["viking", "elf", "viking"]).journey.synergy()["kind"] == "pair")
	var alliance := squad(["human", "viking", "elf"])
	ctx.check("run synergy: ABC -> Alliance", alliance.journey.synergy()["kind"] == "alliance")
	ctx.check("run synergy: solo -> none", squad(["elf"], ["longbow"]).journey.synergy()["kind"] == "none")
	ctx.check("run synergy: duo AA -> Pair", squad(["elf", "elf"], ["sword_shield", "greatsword"]).journey.synergy()["kind"] == "pair")
	# Alliance stat_mod: +8% max HP and ATK on every member, on top of the same card without a synergy (a mixed duo:
	# no synergy, and not a lone card, which would get its class's solo block, data/classes/<id>.json "solo").
	var plain := squad(["elf", "human"], ["sword_shield", "greatsword"])
	ctx.check("a mixed duo has no synergy and its cards do not fight alone", plain.journey.synergy()["kind"] == "none" and not plain.sim.fighters[1].race_state["effects"].any(func(e): return e["src"] == "solo"))
	# Class solo block (data/classes/sword_shield.json "solo", PO Option A 2026-11-13): only a card with no allies gets it.
	var lone := squad(["elf"], ["sword_shield"])
	var solo_block: Array = preload("res://logic/card_deck.gd").class_data("sword_shield").get("solo", [])
	ctx.check("solo block: a lone sword_shield card gets its class's solo effects", not solo_block.is_empty() and lone.sim.fighters[1].race_state["effects"].filter(func(e): return e["src"] == "solo").size() == solo_block.size())
	ctx.check("solo block: no member of a squad of 3 gets it", [1, 2, 3].all(func(id): return not alliance.sim.fighters[id].race_state["effects"].any(func(e): return e["src"] == "solo")))
	var grouped: Array = SquadMember.make_squad(lone.run, ["sword_shield"], {}, "p1")
	ctx.check("solo block: a squad of one inside a party (synergy group) is not alone", not RacePassives.fights_alone(grouped[0]) and RacePassives.fights_alone(SquadMember.make_squad(lone.run, ["sword_shield"])[0]))
	var a1 = alliance.sim.fighters[1]
	var p1 = plain.sim.fighters[1]
	ctx.check("Alliance: max HP +8%% (%.1f vs %.1f)" % [a1.max_hp(), p1.max_hp()], is_equal_approx(a1.max_hp(), p1.max_hp() * 1.08))
	ctx.check("Alliance: ATK +8%", is_equal_approx(float(a1.stats["ATK"]), float(p1.stats["ATK"]) * 1.08))
	ctx.check("Alliance: starts at full (bigger) HP", is_equal_approx(a1.hp, a1.max_hp()))
	# Elf Trio: healing received +30% (stat_mod HEALING) and regen at wave start on every member.
	var t1 = trio.sim.fighters[1]
	ctx.check("Elf Trio: healing received x1.3", is_equal_approx(t1.heal_factor(), 1.3))
	trio.sim.events.clear()
	RacePassives.step(trio.sim)
	ctx.check("Elf Trio: regen on every ally at wave start", [1, 2, 3].all(func(id): return trio.sim.fighters[id].effects.has("regen")))
	# Fixed for the whole run: a death or a race change mid-run does not switch it.
	trio.sim.fighters[2].state = Fighter.State.DEAD
	Deck.set_race(trio.profile.card_deck, "greatsword", "human")
	ctx.check("synergy fixed for the run (death, race change)", trio.journey.synergy()["kind"] == "trio")
	var copy = Party.from_dict(JSON.parse_string(JSON.stringify(trio.journey.to_dict())), trio.data, trio.rules, trio.camp, trio.loot, trio.combat.weapon_ids)
	ctx.check("synergy survives journey save/load", copy != null and copy.synergy()["kind"] == "trio")


## Race state is in the checkpoint: 300 ticks + restore + 300 ticks == 600 uninterrupted; same seed = same run.
func _checkpoint_and_determinism(ctx) -> void:
	var digests := []
	for attempt in 2:
		var f := squad(["human", "elf", "viking"])
		var sim = f.sim
		var memories := {}
		for id in [1, 2, 3]: memories[id] = Pilot.new_memory(id * 7919 + 1)
		var copy = null
		for tick in 600:
			if tick == 300:
				var saved: Dictionary = sim.snapshot()
				copy = Sim.new(World.new(), f.combat, F.rng(1))
				copy.item_rules = f.rules
				copy.loot_data = f.loot
				ctx.check("race checkpoint restores", copy.restore({"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(saved["checkpoint"]))}, f.camp))
				ctx.check("race state is in the checkpoint", copy.fighters[3].race_state.get("passive", "") == "Headhunter")
			for id in [1, 2, 3]:
				var input: SimInput = SimInput.decode(Pilot.decide(sim, f.combat, id, memories[id], tick).encode())
				sim.set_input(id, input)
				if copy != null: copy.set_input(id, input)
			sim.tick()
			if copy != null: copy.tick()
		ctx.check("race checkpoint: 300+restore+300 equals uninterrupted 600", Codec.digest(copy.snapshot()) == Codec.digest(sim.snapshot()))
		digests.append(Codec.digest(sim.snapshot()))
	ctx.check("same seed, same race fight", digests[0] == digests[1])
