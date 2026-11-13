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
	_rooms(ctx)
	_tamper(ctx)
	_auto_pilot_authority(ctx)
	_disconnect_and_leader(ctx)
	_solo_parity(ctx)
	_personal_loot(ctx)
	_two_clients(ctx)
	_leader_route_and_auto_continue(ctx)


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


static func sim_for(f: Dictionary, sim_seed: int = 12345):
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
	var sim := Sim.new(world, f.combat, F.rng(sim_seed))
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


# ---------------------------------------------------------------- chunks 2-3: squad rooms

const Manager := preload("res://server/rooms/manager.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Codec := preload("res://logic/state_codec.gd")


static func players(count: int) -> Array:
	var out := []
	for id in range(1, count + 1): out.append({"id": id, "profile": F.make(id).profile.to_dict()})
	return out


static func squad_manager():
	var mgr = Manager.new()
	mgr.squad_rooms = true
	return mgr


func _rooms(ctx) -> void:
	for pair in [[1, 3], [2, 6], [3, 6], [4, 4]]:
		var mgr = squad_manager()
		var room_id := "squad-room-%d" % pair[0]
		var made: Dictionary = mgr.create(room_id, 77, players(pair[0]))
		ctx.check("online squads AC2: %d-player room created" % pair[0], made.ok)
		if not made.ok: continue
		var room = mgr.rooms[room_id].room
		var ids: Array = room.fighter_ids()
		ctx.check("online squads AC2: %d players field %d cards" % pair, ids.size() == pair[1] and ids.all(func(id): return room.sim.fighters.has(id) and room.sim.fighters[id].team == "player"))
		ctx.check("online squads AC2: each card has its class skills, race and ultimate (%d players)" % pair[0], ids.all(func(id): return str(room.sim.fighters[id].skill_state.get("class", "")) == room.trip_of_fighter(id).card_id and not room.sim.fighters[id].race_state.is_empty()))
		ctx.check("online squads: room plays the goblin wave journey (%d players)" % pair[0], room.journey.data.id == "goblin_waves" and room.goblin_waves == null and room.sim.pending_wave_count() > 0)
		ctx.check("online squads: every player slot owns a fighter with its own id (%d players)" % pair[0], range(1, pair[0] + 1).all(func(slot): return room.fighters_of(slot).has(slot)))
		ctx.check("online squads: no companion bots in squad rooms (%d players)" % pair[0], not room.install_companions([{"id": "arun", "slot": 2}]) and room.companion_slots.is_empty())
	var legacy = Manager.new()
	legacy.squad_rooms = false
	ctx.check("online squads: legacy rooms (squad rooms off) keep ink_road", legacy.create("legacy-room-1", 77, players(2)).ok and legacy.rooms["legacy-room-1"].room.journey.data.id == "ink_road" and not legacy.rooms["legacy-room-1"].room.squads)


func _tamper(ctx) -> void:
	var mgr = squad_manager()
	var raw := players(1)
	var card: String = raw[0].profile.card_deck.squad[0]
	var missing: Dictionary = raw[0].profile.duplicate(true)
	missing.card_gear.erase(missing.card_deck.squad[1])
	ctx.check("online squads AC7: a squad card without card_gear is rejected", mgr.create("tamper-room-1", 77, [{"id": 1, "profile": missing}]).get("error", "") == "invalid_payload")
	var greedy: Dictionary = raw[0].profile.duplicate(true)
	var tree_data = preload("res://logic/skill_tree_data.gd").load_default()
	var nodes: Array = tree_data.class_nodes(card).map(func(n): return str(n.get("id", "")) if n is Dictionary else str(n))
	greedy.card_deck.cards[card]["skill_tree"] = {"class": nodes.slice(0, 4), "race": [], "combo": []}
	ctx.check("online squads AC7: a tree spending unearned points is rejected", nodes.size() >= 1 and mgr.create("tamper-room-2", 77, [{"id": 1, "profile": greedy}]).get("error", "") == "invalid_payload")
	var unknown: Dictionary = raw[0].profile.duplicate(true)
	unknown.card_deck.cards[card]["skill_tree"] = {"class": ["no_such_node"], "race": [], "combo": []}
	ctx.check("online squads AC7: a tree with an unknown node is rejected", mgr.create("tamper-room-3", 77, [{"id": 1, "profile": unknown}]).get("error", "") == "invalid_payload")
	var no_squad: Dictionary = raw[0].profile.duplicate(true)
	no_squad.card_deck.squad = []
	ctx.check("online squads AC7: an empty squad is rejected", mgr.create("tamper-room-4", 77, [{"id": 1, "profile": no_squad}]).get("error", "") == "invalid_payload")
	ctx.check("online squads AC7: the untouched profile is accepted", mgr.create("tamper-room-5", 77, raw).ok)


static func room_hash(room) -> String:
	return Codec.digest(room.sim.snapshot()) + ":" + str(room.journey.waves_cleared)


func _auto_pilot_authority(ctx) -> void:
	var a = squad_manager()
	var b = squad_manager()
	a.create("auto-room-a", 77, players(2))
	b.create("auto-room-b", 77, players(2))
	var ra = a.rooms["auto-room-a"].room
	var rb = b.rooms["auto-room-b"].room
	var noise := RandomNumberGenerator.new()
	noise.seed = 5
	var accepted := false
	var enemy_hp_start := _enemy_hp(ra)
	for tick in 300:
		for slot in [1, 2]:
			var bytes := PackedByteArray()
			for i in SimInput.wire_size(): bytes.append(noise.randi_range(0, 255))
			accepted = ra.input(slot, ra.clock_tick + 1, bytes) or accepted
		ra.tick()
		rb.tick()
	ctx.check("online squads AC4: client combat input is refused in squad rooms", not accepted)
	ctx.check("online squads AC4: random client bytes vs none give the same sim state", room_hash(ra) == room_hash(rb))
	ctx.check("online squads: the server auto-pilot fights (enemy HP drops in 5 s)", _enemy_hp(ra) < enemy_hp_start)
	ctx.check("online squads: input clock acknowledges every connected player", ra.acknowledged[1] == ra.clock_tick and ra.acknowledged[2] == ra.clock_tick)


static func _enemy_hp(room) -> float:
	var total := 0.0
	for id in room.sim.fighters:
		if room.sim.fighters[id].team == "enemy": total += room.sim.fighters[id].hp
	return total + 100000.0 * room.sim.pending_wave_count()


func _disconnect_and_leader(ctx) -> void:
	var mgr = squad_manager()
	mgr.create("leader-room-1", 77, players(2))
	var room = mgr.rooms["leader-room-1"].room
	ctx.check("online squads: leader is the lowest connected player", room.party.leader() == 1)
	room.eliminate(1)
	ctx.check("online squads AC6: leader passes to the next connected player", room.party.leader() == 2)
	ctx.check("online squads AC6: an offline player's cards are not eliminated", room.fighters_of(1).all(func(id): return not room.sim.fighters[id].eliminated))
	var acted := false
	for tick in 600:
		room.tick()
		for event in room.sim.events:
			for key in ["by", "attacker", "player", "source"]:
				if event.has(key) and room.fighters_of(1).has(int(event[key])) and str(event.get("type", "")) in ["hit", "skill_cast", "class_skill", "killed", "projectile", "attack"]:
					acted = true
	ctx.check("online squads AC6: a disconnected player's cards keep being piloted", room.fighters_of(1).all(func(id): return room._auto_memory.has(id)) and acted)
	ctx.check("online squads AC6: the new leader's leader-only command is not refused as leader_only", room.command(2, 1, {"type": "journey_choose", "index": 0}).get("error", "") != "leader_only")
	var saved: Dictionary = room.finalize(true)
	ctx.check("online squads AC6: the offline player's profile is saved at finalize", saved.has("1") and saved.has("2"))


# ---------------------------------------------------------------- AC 1 parity, chunk 4 personal loot

## AC 1: a 1-player squad room and solo LocalSession (same profile, seed, cards, sim RNG) play the same fight.
func _solo_parity(ctx) -> void:
	var mgr = squad_manager()
	var raw := players(1)
	mgr.create("parity-room-1", 77, raw)
	var room = mgr.rooms["parity-room-1"].room
	var profile = preload("res://logic/profile.gd").from_dict(raw[0].profile.duplicate(true), mgr.rules, mgr.camp)
	var session = preload("res://client/session/local_session.gd").new(profile, mgr.rules, mgr.camp, mgr.loot)
	var cards: Array = profile.card_deck.squad.slice(0, 3)
	session.squad_classes = cards
	session.start_journey(mgr.squad_journey, mgr.combat.weapon_ids, 77, {}, cards)
	session.journey.choose(0)
	var map = Map.load_by_id(str(session.journey.current["map"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + session.journey.stage_number() * 997
	session.begin_stage(map, mgr.combat, session.journey, 1, 100, rng)
	var same_start: bool = Codec.digest(session._sim.snapshot()) == Codec.digest(room.sim.snapshot())
	ctx.check("online squads AC1: a 1-player room starts the same fight as solo", same_start)
	var diverged := -1
	for tick in 1800:
		for id in [2, 3, 1]:  # solo order: the other squad fighters first, then the local player (stage_view)
			session.set_input(id, session.auto_input(id))
		session.tick()
		room.tick()
		if tick % 30 == 29 and Codec.digest(session._sim.snapshot()) != Codec.digest(room.sim.snapshot()):
			diverged = tick
			break
	ctx.check("online squads AC1: 30 s of room play match solo tick for tick (diverged at %d)" % diverged, diverged < 0)
	ctx.check("online squads AC1: same waves cleared and haul as solo", session.journey.waves_cleared == room.journey.waves_cleared and session.journey.run.bag.gold == room.journey.run.bag.gold and session.journey.run.bag.items.size() == room.journey.run.bag.items.size())


## Kills `count` level-1 goblins in `sim` through the real kill path; returns the sim.
static func _kill_many(sim, count: int, first_id: int = 50000):
	for i in count:
		var id := first_id + i
		sim.add_enemy(id, Vector3(30, 0, 30), "goblin", 1)
		sim.fighters[id].hp = 0
		sim._on_killed(id, 1)
	return sim


static func _haul(trip) -> float:
	return float(trip.bag.gold) + 25.0 * float(trip.bag.items.size()) + float(trip.bag.materials.values().reduce(func(a, b): return a + int(b), 0))


## AC 5 (unit form): per-player rolls with own stream and factor. Over 30 seeds, a 2-player room's per-player haul is
## within 10% of a solo 3-card squad's on the same kills; race pieces only fit the owner's cards.
func _personal_loot(ctx) -> void:
	var room_total := [0.0, 0.0]
	var solo_total := 0.0
	var race_ok := true
	var independent := true
	for seed_value in 30:
		var f := party([squad_of(100 + seed_value, ["elf", "elf", "human"]), squad_of(200 + seed_value, ["viking", "viking", "viking"])])
		var sim = sim_for(f, 9000 + seed_value)
		_strip_enemies(sim)
		ctx.check("online squads: personal loot set for both players (seed %d)" % seed_value, sim.loot_players.size() == 6 and int(sim.loot_players[4][0]) == 2) if seed_value == 0 else null
		var rng_before: int = sim.rng.state
		_kill_many(sim, 40)
		independent = independent and sim.rng.state == rng_before
		room_total[0] += _haul(f.journey.runs_by_player[1])
		room_total[1] += _haul(f.journey.runs_by_player[4])
		for trip in [f.journey.runs_by_player[1], f.journey.runs_by_player[4]]:
			var mine: Array = trip.squad.map(func(m): return m.card_id)
			for item in trip.bag.items:
				var race_set: Dictionary = f.rules.catalog.race_set_of(item.item_id)
				if not race_set.is_empty() and not mine.has(str(race_set.get("class", ""))): race_ok = false
		var solo := squad_of(300 + seed_value, ["human", "human", "human"])
		var solo_party := party([solo])
		var solo_sim = sim_for(solo_party, 9000 + seed_value)
		_strip_enemies(solo_sim)
		_kill_many(solo_sim, 40)
		solo_total += _haul(solo_party.journey.run)
	var ratio_1: float = room_total[0] / maxf(1.0, solo_total)
	var ratio_2: float = room_total[1] / maxf(1.0, solo_total)
	ctx.check("online squads AC5: player 1 haul within 10%% of solo (x%.2f)" % ratio_1, absf(ratio_1 - 1.0) <= 0.10)
	ctx.check("online squads AC5: player 2 haul within 10%% of solo (x%.2f)" % ratio_2, absf(ratio_2 - 1.0) <= 0.10)
	ctx.check("online squads AC5: personal rolls never touch the sim RNG stream", independent)
	ctx.check("online squads AC5: race pieces only fit the owner's cards", race_ok)
	var three := party([squad_of(400, ["elf", "elf"], CARDS.slice(0, 2)), squad_of(401, ["human", "human"], CARDS.slice(0, 2)), squad_of(402, ["viking", "viking"], CARDS.slice(0, 2))])
	ctx.check("online squads 4.3: a 2-card player rolls with loot_by_squad[1]", three.journey != null and is_equal_approx(three.journey.loot_factor_for(2), three.data.loot_for(2)))


static func _strip_enemies(sim) -> void:
	for id in sim.fighters.keys():
		if sim.fighters[id].team == "enemy": sim.remove_player(id)
	sim._waves.clear()


func _data(ctx) -> void:
	var f := F.make()
	ctx.check("online squads: combat coop allows 6 fighters", int(f.combat.coop.max_fighters) == 6 and int(f.combat.coop.room_card_cap) == 6 and int(f.combat.coop.auto_continue_seconds) == 20 and f.combat.coop.hp_multiplier.size() == 6)
	var waves = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	ctx.check("online squads: wave_power_by_squad has 6 entries", waves.wave_power_by_squad.size() == 6 and is_equal_approx(waves.wave_power_for(6), 2.9) and is_equal_approx(waves.wave_power_for(3), 2.01))


# ---------------------------------------------------------------- chunk 5: wire and client (two clients, one room)

## A client view of the room as player `slot` sees it (the same OnlineSession read helpers stage_view uses).
static func client_for(mgr, room, slot: int):
	var c = preload("res://client/session/online_session.gd").new(null, mgr.rules, mgr.camp, mgr.loot)
	c._player_id = slot
	view_into(c, room)
	return c


static func view_into(c, room) -> void:
	c.server_state = room.public_state(c._player_id)
	c.ready = true
	c.journey.update(c.server_state.meta, null)


func _two_clients(ctx) -> void:
	var mgr = squad_manager()
	mgr.create("two-client-room", 77, players(2))
	var room = mgr.rooms["two-client-room"].room
	var one = client_for(mgr, room, 1)
	var two = client_for(mgr, room, 2)
	for c in [one, two]:
		var all: Array = c.fighters_of(1) + c.fighters_of(2)
		all.sort()
		ctx.check("online squads chunk 5: client %d sees all 6 cards" % c._player_id, c.is_squad_room() and all == room.fighter_ids())
		ctx.check("online squads chunk 5: client %d sees the right owner of every card" % c._player_id, room.fighter_ids().all(func(id): return c.owner_of(id) == int(room.owner_by_fighter[id])))
		ctx.check("online squads chunk 5: client %d sees each card's class" % c._player_id, room.fighter_ids().all(func(id): return c.card_of(id) == room.trip_of_fighter(id).card_id))
		ctx.check("online squads chunk 5: client %d spectates (no combat input)" % c._player_id, c.spectating())
	ctx.check("online squads chunk 5: my cards come first and are mine", one.fighters_of() == room.fighters_of(1) and two.fighters_of() == room.fighters_of(2))
	var groups: Array = one.synergy_groups()
	ctx.check("online squads chunk 5: one synergy group per player", groups.size() == 2 and groups.any(func(g): return g.players == [1]) and groups.any(func(g): return g.players == [2]))
	ctx.check("online squads chunk 5: a card's name plate is its owner's name", one.player_name(room.fighters_of(2)[1]) == str(room.trip_for(2).profile.name))
	var line: String = preload("res://client/online/squad_room_hud.gd").synergy_line(groups, {1: "A", 2: "B"}, 1)
	ctx.check("online squads chunk 5: synergy banner names both groups", line.contains(":") and line.contains("B"))
	var panel = preload("res://client/squad_panel.gd").new()
	panel.local_slot = 1
	for id in room.fighter_ids(): panel.owners[id] = room.owner_by_fighter[id]
	ctx.check("online squads chunk 5: squad panel puts my cards first", panel.ordered(room.fighter_ids()).slice(0, 3) == room.fighters_of(1))
	panel.free()
	# Client input does nothing: a client's netfox input never reaches the sim, and the room refuses raw frames.
	var noise := RandomNumberGenerator.new(); noise.seed = 9
	var refused := true
	var waves_seen := 0
	for tick in 1800:
		var bytes := PackedByteArray()
		for i in SimInput.wire_size(): bytes.append(noise.randi_range(0, 255))
		refused = refused and not room.input(1 + tick % 2, room.clock_tick + 1, bytes)
		room.tick()
		waves_seen = maxi(waves_seen, room.journey.waves_cleared)
	ctx.check("online squads chunk 5: client input does nothing in a squad room", refused)
	ctx.check("online squads chunk 5: the room plays waves (cleared %d in 30 s)" % waves_seen, waves_seen >= 1)
	view_into(one, room)
	ctx.check("online squads chunk 5: snapshot still carries the owners after waves", one.fighters_of(2) == room.fighters_of(2))
	var meta_bytes := var_to_bytes({"squads": room.public_state(1).meta.squads, "synergy": room.public_state(1).meta.synergy}).size()
	ctx.check("online squads chunk 5: squad meta stays small (%d B < 1200 B uncompressed)" % meta_bytes, meta_bytes < 1200)


## Leader route choice and the auto-continue, on a multi-stage journey (goblin_waves is one stage of 12 waves, so
## the route/camp flow is checked on ink_road through the same squad room code).
func _leader_route_and_auto_continue(ctx) -> void:
	var mgr = squad_manager()
	mgr.squad_journey = mgr.journey_data
	mgr.create("route-room", 77, players(2))
	var room = mgr.rooms["route-room"].room
	room.goblin_waves = null  # ink_road stage 1 runs the wave lab; plain stage flow here
	_clear_stage(room)
	ctx.check("online squads chunk 5: the stage clears into a route choice (%s)" % room.status, room.status == "route" and not room.journey.upcoming_choices().is_empty())
	room.tick(); room.tick()
	var one = client_for(mgr, room, 1)
	var two = client_for(mgr, room, 2)
	ctx.check("online squads chunk 5: both clients see the auto-continue countdown", one.auto_continue_left() > 0.0 and two.auto_continue_left() > 0.0 and absf(one.auto_continue_left() - 20.0) < 0.2)
	ctx.check("online squads chunk 5: player 1 is the leader, player 2 is not", one.is_leader() and not two.is_leader())
	ctx.check("online squads chunk 5: a friend's route choice is refused", room.command(2, 1, {"type": "journey_choose", "index": 0}).get("error", "") == "leader_only")
	var stage: int = room.epoch
	var chosen: Dictionary = room.command(1, 1, {"type": "journey_choose", "index": 0})
	ctx.check("online squads chunk 5: the leader's route choice works (%s, epoch %d -> %d)" % [chosen, stage, room.epoch], chosen.get("ok", false) and room.epoch > stage and room.journey.state == room.journey.IN_STAGE)
	if room.status == "treasure":
		for i in 200: room.tick()
	_clear_stage(room)
	var waited := 0
	var before: int = room.journey.stage_number()
	while room.journey.stage_number() == before and waited < 20 * 60 + 400:
		room.tick(); waited += 1
	ctx.check("online squads chunk 5: with no choice the server auto-continues after ~20 s (%d ticks)" % waited, room.journey.stage_number() == before + 1 and waited >= 20 * 60)


static func _clear_stage(room) -> void:
	for guard in 4000:
		if room.status != "active": return
		for id in room.sim.fighters:
			if room.sim.fighters[id].team == "enemy" and room.sim.fighters[id].is_alive():
				room.sim.fighters[id].hp = 0
				room.sim._on_killed(id, room.fighter_ids()[0])
		room.sim._waves.clear()
		room.tick()
