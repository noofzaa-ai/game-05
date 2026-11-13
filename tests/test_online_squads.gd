extends RefCounted
## Online squads (design/gdd/online-squads.md section 9). Chunk 1: a party of several squads (one per player),
## synergy per group (AC 3), party_v 3 save/load, v2 still loads, one profile never in two squads.
const F := preload("res://tests/online_fixture.gd")
const Party := preload("res://logic/coop_journey.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Deck := preload("res://logic/card_deck.gd")
const RaceData := preload("res://logic/race_data.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Map := preload("res://logic/map_loader.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]


func run(ctx) -> void:
	_party_of_squads(ctx)
	_synergy_groups(ctx)
	_four_player_group(ctx)
	_save_load(ctx)
	_rejects(ctx)
	_data(ctx)


## One player's squad on its own profile: `races` per card of `cards`.
static func squad_of(seed_value: int, races: Array, cards: Array = CARDS, override: Dictionary = {}, group: String = "") -> Dictionary:
	var f := F.make(seed_value)
	for i in cards.size():
		Deck.set_race(f.profile.card_deck, cards[i], races[i])
	f.members = SquadMember.make_squad(f.run, cards, override, group)
	return f


## A party of squads: `squads` = [fixture...]; player slot = index + 1; fighter ids 1..F in player order.
static func party(squads: Array) -> Dictionary:
	var trips := {}
	var owners := {}
	var next := 1
	for at in squads.size():
		for member in squads[at].members:
			trips[next] = member
			owners[next] = at + 1
			next += 1
	var f: Dictionary = squads[0]
	f.data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	f.journey = Party.start_party(f.data, trips, f.rules, f.loot, f.combat.weapon_ids, 77, 1, owners)
	return f


static func sim_for(f: Dictionary):
	var journey = f.journey
	while journey.state != journey.IN_STAGE:
		if journey.state == journey.CHOOSING: journey.choose(0)
		else: journey.leave_node()
	var map = Map.load_by_id(str(journey.current["map"]))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var sim := Sim.new(world, f.combat, F.rng(12345))
	journey.populate(sim, map, 1, 100)
	return sim


func _party_of_squads(ctx) -> void:
	var f := party([squad_of(77, ["elf", "elf", "human"]), squad_of(78, ["viking", "viking", "viking"])])
	var j = f.journey
	ctx.check("online squads: two squads form one party of 6 fighters", j != null and j.player_ids().size() == 6)
	if j == null: return
	ctx.check("online squads: owners are the player slots", j.owners() == [1, 2] and j.fighters_of(1) == [1, 2, 3] and j.fighters_of(2) == [4, 5, 6])
	ctx.check("online squads: each squad keeps its own bag", j.runs_by_player[1].bag == j.runs_by_player[3].bag and j.runs_by_player[1].bag != j.runs_by_player[4].bag)
	ctx.check("online squads: one payer per bag", j._paying_players() == [1, 4])
	var sim = sim_for(f)
	ctx.check("online squads: populate places all 6 fighters with co-op on", sim.coop_enabled and range(1, 7).all(func(id): return sim.fighters.has(id)))
	ctx.check("online squads: each card casts its own class skills", range(1, 7).all(func(id): return str(sim.fighters[id].skill_state.get("class", "")) == j.runs_by_player[id].card_id))
	ctx.check("online squads: 6 fighters use the 6th hp_multiplier entry", float(f.combat.coop["hp_multiplier"][5]) == 4.0)


func _synergy_groups(ctx) -> void:
	var f := party([squad_of(77, ["elf", "elf", "human"]), squad_of(78, ["viking", "viking", "viking"])])
	var j = f.journey
	if j == null:
		ctx.check("online squads: synergy party built", false)
		return
	var s1: Dictionary = j.runs_by_player[1].synergy()
	var s4: Dictionary = j.runs_by_player[4].synergy()
	ctx.check("online squads AC3: player 1 gets Pair Elf", s1.kind == "pair" and s1.race == "elf")
	ctx.check("online squads AC3: player 2 gets Trio Viking", s4.kind == "trio" and s4.race == "viking")
	ctx.check("online squads: each squad is its own synergy group", s1.get("group") == "p1" and s4.get("group") == "p2")
	var sim = sim_for(f)
	ctx.check("online squads AC3: synergy stays on the owner's cards", sim.fighters[1].race_state.synergy == "pair" and sim.fighters[4].race_state.synergy == "trio" and sim.fighters[1].race_state.group == "p1")
	var group_allies: Array = RacePassives.targets(sim, 1, "allies_all", {"synergy_group": "p1"})
	var all_allies: Array = RacePassives.targets(sim, 1, "allies_all", {})
	ctx.check("online squads: synergy ally targets are the same group only", group_allies == [1, 2, 3])
	ctx.check("online squads: race passive ally targets reach every friendly card", all_allies == [1, 2, 3, 4, 5, 6])


func _four_player_group(ctx) -> void:
	var races := ["human", "elf", "viking", "runeborn"]
	var room_synergy: Dictionary = RaceData.load_default().synergy_for(races)
	ctx.check("online squads AC3: 4 different races = Alliance", room_synergy.kind == "alliance")
	var squads: Array = []
	for i in 4:
		squads.append(squad_of(80 + i, [races[i]], [CARDS[i % CARDS.size()]], room_synergy, "room"))
	var f := party(squads)
	var j = f.journey
	ctx.check("online squads: 4 players x 1 card party", j != null and j.player_ids().size() == 4 and j.owners() == [1, 2, 3, 4])
	if j == null: return
	ctx.check("online squads AC3: Alliance on all 4 cards", range(1, 5).all(func(id): return j.runs_by_player[id].synergy().kind == "alliance" and j.runs_by_player[id].synergy().group == "room"))
	var trio: Dictionary = RaceData.load_default().synergy_for(["elf", "elf", "elf", "elf"])
	ctx.check("online squads: 4 of one race = Trio", trio.kind == "trio")


func _save_load(ctx) -> void:
	var f := party([squad_of(77, ["elf", "elf", "human"]), squad_of(78, ["viking", "viking", "viking"])])
	var j = f.journey
	if j == null:
		ctx.check("online squads: save party built", false)
		return
	j.choose(0)
	j.health_by_player[5] = 0.5
	j.runs_by_player[2].died = true
	var saved: Dictionary = JSON.parse_string(JSON.stringify(j.to_dict()))
	ctx.check("online squads: several squads save as party_v 3", int(saved.party_v) == 3 and saved.squads.size() == 2)
	var back = Party.from_dict(saved, f.data, f.rules, f.camp, f.loot, f.combat.weapon_ids)
	ctx.check("online squads: party_v 3 loads", back != null)
	if back == null: return
	ctx.check("online squads: v3 round trip keeps owners and cards", back.fighters_of(1) == [1, 2, 3] and back.fighters_of(2) == [4, 5, 6] and range(1, 7).all(func(id): return back.runs_by_player[id].card_id == j.runs_by_player[id].card_id))
	ctx.check("online squads: v3 round trip keeps one bag per squad", back.runs_by_player[1].bag == back.runs_by_player[2].bag and back.runs_by_player[1].bag != back.runs_by_player[6].bag and back.runs_by_player[4].profile != back.runs_by_player[1].profile)
	ctx.check("online squads: v3 round trip keeps member state", back.runs_by_player[2].died and is_equal_approx(float(back.health_by_player[5]), 0.5) and back.runs_by_player[4].synergy().kind == "trio")
	ctx.check("online squads: v3 save is stable", JSON.stringify(back.to_dict()) == JSON.stringify(j.to_dict()))
	var solo := party([squad_of(79, ["human", "elf", "viking"])])
	var v2: Dictionary = JSON.parse_string(JSON.stringify(solo.journey.to_dict()))
	ctx.check("online squads: one squad still saves party_v 2", int(v2.party_v) == 2)
	ctx.check("online squads: party_v 2 still loads", Party.from_dict(v2, solo.data, solo.rules, solo.camp, solo.loot, solo.combat.weapon_ids) != null)
	var bad := saved.duplicate(true)
	bad.squads[1].members = [4, 5]
	ctx.check("online squads: v3 with a fighter outside every squad is rejected", Party.from_dict(bad, f.data, f.rules, f.camp, f.loot, f.combat.weapon_ids) == null)


func _rejects(ctx) -> void:
	var a := squad_of(77, ["elf", "elf", "human"])
	var twin := SquadMember.make_squad(a.run, CARDS)  # a second squad on the SAME account trip/profile
	var trips := {1: a.members[0], 2: a.members[1], 3: twin[0], 4: twin[1]}
	ctx.check("online squads: one profile in two squads is rejected", Party.start_party(a.data, trips, a.rules, a.loot, a.combat.weapon_ids, 77, 1, {1: 1, 2: 1, 3: 2, 4: 2}) == null)
	var b := squad_of(78, ["viking", "viking", "viking"])
	ctx.check("online squads: two squads cannot share one owner slot", Party.start_party(a.data, {1: a.members[0], 2: b.members[0]}, a.rules, a.loot, a.combat.weapon_ids, 77, 1, {1: 1, 2: 1}) == null)
	var c := squad_of(81, ["human", "human", "human"])
	var seven := {}
	var next := 1
	for squad in [a, b, c]:
		for member in squad.members:
			seven[next] = member
			next += 1
	ctx.check("online squads: more than 6 fighters is rejected", Party.start_party(a.data, seven, a.rules, a.loot, a.combat.weapon_ids, 77) == null)


func _data(ctx) -> void:
	var f := F.make()
	ctx.check("online squads: combat coop allows 6 fighters", int(f.combat.coop.max_fighters) == 6 and int(f.combat.coop.room_card_cap) == 6 and int(f.combat.coop.auto_continue_seconds) == 20 and f.combat.coop.hp_multiplier.size() == 6)
	var waves = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	ctx.check("online squads: wave_power_by_squad has 6 entries", waves.wave_power_by_squad.size() == 6 and is_equal_approx(waves.wave_power_for(6), 2.9) and is_equal_approx(waves.wave_power_for(3), 2.01))
