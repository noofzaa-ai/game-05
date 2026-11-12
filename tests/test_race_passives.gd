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
const SimInput := preload("res://logic/sim_input.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]


## A squad fight of the goblin wave journey with these races (one per card of CARDS).
static func squad(races: Array, cards: Array = CARDS) -> Dictionary:
	var f := F.make()
	for i in cards.size():
		Deck.set_race(f.profile.card_deck, cards[i], races[i])
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
	_inert_cells(ctx)
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
		counts.append(procs(react(sim, {"type": "hit", "attacker": 3, "target": foe, "damage": 10, "move": "light_1"}), 3).size())
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
	react(msim, {"type": "skill_hit", "attacker": 1, "target": enemy_of(msim), "damage": 100})
	ctx.check("Bloomcaster: a skill hit heals the most-hurt ally 25% of the damage", is_equal_approx(msim.fighters[3].hp - before, 25.0 * msim.fighters[3].heal_factor()))
	for id in [1, 2, 3]: msim.fighters[id].hp = msim.fighters[id].max_hp()
	ctx.check("nobody hurt: Bloomcaster does not proc", procs(react(msim, {"type": "skill_hit", "attacker": 1, "target": enemy_of(msim), "damage": 100}), 1).is_empty())


## Cells that need phase-4 features load but do nothing yet (no shield, burst, skill_mod, charges, scaling).
func _inert_cells(ctx) -> void:
	var f := squad(["runeborn", "runeborn", "viking"])
	var sim = f.sim
	RacePassives.step(sim)
	var foe := enemy_of(sim)
	var hp_before: float = sim.fighters[foe].hp
	var out: Array = []
	for i in 6:
		out.append_array(react(sim, {"type": "hit", "attacker": 2, "target": foe, "damage": 10, "move": "heavy"}))
		out.append_array(react(sim, {"type": "hit", "attacker": foe, "target": 1, "damage": 10, "move": "light_1"}))
	ctx.check("inert: Runeborn rune cells fire nothing yet", procs(out, 1).is_empty() and procs(out, 2).is_empty() and sim.fighters[foe].hp == hp_before)
	var g := squad(["human", "viking", "elf"])
	var gsim = g.sim
	gsim.fighters[2].hp = gsim.fighters[2].max_hp() * 0.2
	ctx.check("inert: Berserker low-HP ATK scaling is not applied yet", is_equal_approx(gsim.fighters[2].stat("ATK"), float(gsim.fighters[2].stats["ATK"])))


func _synergy(ctx) -> void:
	var trio := squad(["elf", "elf", "elf"])
	ctx.check("run synergy: AAA -> Trio", trio.journey.synergy()["kind"] == "trio" and trio.journey.synergy()["race"] == "elf")
	ctx.check("run synergy: AAB -> Pair(A)", squad(["viking", "elf", "viking"]).journey.synergy()["race"] == "viking" and squad(["viking", "elf", "viking"]).journey.synergy()["kind"] == "pair")
	var alliance := squad(["human", "viking", "elf"])
	ctx.check("run synergy: ABC -> Alliance", alliance.journey.synergy()["kind"] == "alliance")
	ctx.check("run synergy: solo -> none", squad(["elf"], ["longbow"]).journey.synergy()["kind"] == "none")
	ctx.check("run synergy: duo AA -> Pair", squad(["elf", "elf"], ["sword_shield", "greatsword"]).journey.synergy()["kind"] == "pair")
	# Alliance stat_mod: +8% max HP and ATK on every member, on top of the same card without a synergy.
	var plain := squad(["elf"], ["sword_shield"])
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
