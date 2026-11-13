extends "res://logic/journey.gd"
## Shared route with separate ownership, HP, gauge and incapacitation per participant.
const PartySpawns := preload("res://logic/party_spawns.gd")
const Fighter := preload("res://logic/fighter.gd")
const SquadMember := preload("res://logic/squad_member.gd")

var primary_id := 1
var runs_by_player: Dictionary = {}
var health_by_player: Dictionary = {}
var gauge_by_player: Dictionary = {}
var downed_by_player: Dictionary = {}
var last_rewards: Dictionary = {}
## Online squads (design/gdd/online-squads.md 3.1, chunk 1): fighter id -> the player slot that owns it. A squad's
## cards all belong to one player; a plain separate-profile party owns itself (fighter id = player slot).
var owner_by_fighter: Dictionary = {}

## Structural ceilings: separate-profile parties (one fighter per player) and squad parties (online rooms field
## at most combat coop.max_fighters = 6 cards; populate checks the configured cap).
const MAX_PLAIN_PLAYERS := 4
const MAX_SQUAD_FIGHTERS := 6

## `trips`: fighter id -> Run. Either all separate players (plain Runs, different profiles) or all squad members
## (logic/squad_member.gd). Several squads may share one party (online squads): the members of one squad share a
## profile, different squads must not. `owners` (optional): fighter id -> player slot; by default each squad is
## owned by its lowest fighter id and a plain run by its own id.
static func start_party(journey_data, trips: Dictionary, rules, loot, weapons: Array, seed: int, leader: int = 1, owners: Dictionary = {}):
	if trips.size() < 2 or not trips.has(leader): return null
	var ids := trips.keys()
	ids.sort()
	for id in ids:
		if not id is int or id < 0 or trips[id] == null or trips[id].died: return null
	var squads := trips.values().all(func(t): return t is SquadMember)
	if not squads and trips.values().any(func(t): return t is SquadMember): return null  # a squad never mixes with an outside run
	if trips.size() > (MAX_SQUAD_FIGHTERS if squads else MAX_PLAIN_PLAYERS): return null
	var owner_of := _owners_for(trips, ids, owners)
	if owner_of.is_empty(): return null
	var j = load("res://logic/coop_journey.gd").new()
	j.owner_by_fighter = owner_of
	j.data = journey_data
	j.item_rules = rules
	j.loot_data = loot
	j.weapon_ids = weapons.duplicate()
	j.seed_value = seed
	j.primary_id = leader
	for id in ids:
		j.runs_by_player[id] = trips[id]
		j.health_by_player[id] = 1.0
		j.gauge_by_player[id] = 0.0
	j.run = trips[leader]
	if squads and j.owners().size() > 1:  # several squads: each is its own synergy group unless the caller named one (4-player room)
		for id in ids:
			if str(trips[id].squad_synergy.get("group", "")).is_empty():
				trips[id].squad_synergy["group"] = "p%d" % owner_of[id]
	j._generate()
	return j

## Checks the profile rule and returns fighter id -> owner slot ({} when invalid). Members of one squad (one shared
## Array) share a profile and one owner; separate players and different squads never share a profile or an owner.
static func _owners_for(trips: Dictionary, ids: Array, owners: Dictionary) -> Dictionary:
	var groups: Array = []  ## one key per squad (its shared member Array) or per plain run
	var group_of := {}
	for id in ids:
		var key = trips[id].squad if trips[id] is SquadMember else id  # a plain run is its own group
		var at := -1
		for i in groups.size():
			if is_same(groups[i], key): at = i
		if at < 0:
			at = groups.size()
			groups.append(key)
		group_of[id] = at
	var profile_group := {}
	var owner_group := {}
	var result := {}
	for id in ids:
		var group: int = group_of[id]
		var profile = trips[id].profile
		for other in profile_group:
			if is_same(other, profile) and profile_group[other] != group: return {}
		profile_group[profile] = group
		var owner: int = id
		if owners.has(id): owner = int(owners[id])
		else:
			for other in ids:
				if group_of[other] == group:
					owner = other
					break
		if owner_group.has(owner) and owner_group[owner] != group: return {}
		owner_group[owner] = group
		result[id] = owner
	for id in ids:  # one owner per group
		for other in ids:
			if group_of[id] == group_of[other] and result[id] != result[other]: return {}
	return result

func player_ids() -> Array:
	return runs_by_player.keys()  # inserted in sorted order

## The player slots of this party (owners), sorted.
func owners() -> Array:
	var slots: Array = []
	for id in player_ids():
		var slot := owner_of(id)
		if not slots.has(slot): slots.append(slot)
	slots.sort()
	return slots

func owner_of(fighter: int) -> int:
	return int(owner_by_fighter.get(fighter, fighter))

## The fighter ids owned by player slot `player`, sorted.
func fighters_of(player: int) -> Array:
	return player_ids().filter(func(id): return owner_of(id) == player)

## Card XP (GDD skill-tree 3.7): every member's card (a squad's cards, or each separate player's lead card).
func xp_cards() -> Array:
	var cards: Array = []
	for id in player_ids():
		var trip = runs_by_player[id]
		var pair := [trip.profile, _card_of(trip)]
		if not cards.any(func(c): return c[0] == pair[0] and c[1] == pair[1]):
			cards.append(pair)
	return cards

## Loot by squad size: the party's fighters (a member down still counts; the squad chose its size).
func fighter_count() -> int:
	return runs_by_player.size()

## Personal loot (online-squads 3.5, 4.3): player `slot`'s factor = loot_by_squad[k - 1], k = that player's card count.
## A party of one squad (solo) or of separate players keeps the party factor.
func loot_factor_for(slot: int) -> float:
	return data.loot_for(fighters_of(slot).size()) if owners().size() > 1 else loot_factor()

func choose(index: int) -> Dictionary:
	hp_fraction = float(health_by_player[primary_id])
	var node := super.choose(index)
	if node.is_empty(): return node
	last_rewards.clear()
	if node["kind"] == "camp":
		for id in player_ids():
			if runs_by_player[id].died: continue
			health_by_player[id] = minf(1, float(health_by_player[id]) + data.camp_heal_fraction)
			downed_by_player.erase(id)
	hp_fraction = float(health_by_player[primary_id])
	return node

func populate(sim: GameSim, map, _player_id: int, first_enemy_id: int) -> Array[int]:
	var ids := player_ids()
	if sim.combat == null or sim.combat.coop.is_empty() or ids.size() > int(sim.combat.coop.get("max_fighters", sim.combat.coop.max_players)): return []
	var spots := PartySpawns.points(map, ids.size(), float(sim.combat.coop["spawn_spacing"]))
	if spots.size() != ids.size(): return []
	for i in ids.size():
		var id: int = ids[i]
		if not sim.bodies.has(id): sim.add_player(id, spots[i])
		if not sim.runs.has(id): sim.attach_run(id, runs_by_player[id], item_rules, loot_data)
		sim.bodies[id].position = spots[i]
		var fighter = sim.fighters[id]
		fighter.hp = fighter.max_hp() * float(health_by_player[id])
		fighter.gauge = float(gauge_by_player[id])
		if runs_by_player[id].died:
			fighter.state = Fighter.State.DEAD
			fighter.hp = 0
			fighter.eliminated = true
		elif downed_by_player.has(id):
			fighter.state = Fighter.State.DOWNED
			fighter.downed_at = -1
			fighter.bleedout_left = int(downed_by_player[id]["left"])
	hp_fraction = float(health_by_player[primary_id])
	gauge = float(gauge_by_player[primary_id])
	var bosses: Array[int] = []
	if not is_at_camp(): bosses = super.populate(sim, map, primary_id, first_enemy_id)
	var scale: float = sim.combat.coop["hp_multiplier"][ids.size() - 1]
	for id in sim.fighters:
		var fighter = sim.fighters[id]
		if fighter.team == "enemy":
			fighter.stats["HP"] *= scale
			fighter.hp = fighter.max_hp()
	for wave in sim._waves:
		for entry in wave["enemies"]:
			entry["hp_scale"] = float(entry.get("hp_scale", 1.0)) * scale
	sim.enable_coop(ids)
	sim.loot_players.clear()
	if owners().size() > 1:  # personal loot (online-squads 3.5): each player rolls with their own factor and stream
		for id in ids:
			sim.loot_players[id] = [owner_of(id), loot_factor_for(owner_of(id))]
	return bosses

func capture_party(sim) -> void:
	if is_over():
		return  # run end: the gauges were cleared (GDD races 3.10.2)
	for id in player_ids():
		if not sim.fighters.has(id): continue
		var fighter = sim.fighters[id]
		health_by_player[id] = clampf(fighter.hp / fighter.max_hp(), 0, 1)
		gauge_by_player[id] = fighter.gauge
		if fighter.state == Fighter.State.DOWNED:
			downed_by_player[id] = {"left": fighter.bleedout_left}
		else:
			downed_by_player.erase(id)
	hp_fraction = float(health_by_player[primary_id])
	gauge = float(gauge_by_player[primary_id])

func stage_cleared(hp_left: float) -> void:
	if state != IN_STAGE: return
	health_by_player[primary_id] = clampf(hp_left, 0, 1)
	hp_fraction = float(health_by_player[primary_id])
	last_rewards.clear()
	last_reward = {}
	if str(current["kind"]) == "challenge":
		for id in _paying_players():
			last_rewards[id] = runs_by_player[id].loot_into_bag(challenge_reward(_rng_for("challenge-player-%d" % id, completed + 1)))
		last_reward = last_rewards.get(primary_id, {})
	_advance()

func open_treasure() -> Dictionary:
	if not treasure_pending or state != AT_NODE: return {}
	treasure_pending = false
	last_rewards.clear()
	for id in _paying_players():
		last_rewards[id] = runs_by_player[id].loot_into_bag(treasure_drop("treasure-player-%d" % id, runs_by_player[id], loot_factor_for(owner_of(id))))
	last_reward = last_rewards.get(primary_id, {})
	return last_reward

## The living players that get a reward: one per bag (a squad shares one bag, so it is paid once).
func _paying_players() -> Array:
	var paid: Array = []
	var bags: Array = []
	for id in player_ids():
		if not runs_by_player[id].died and not bags.has(runs_by_player[id].bag):
			bags.append(runs_by_player[id].bag)
			paid.append(id)
	return paid

func bank_bag_for(id: int) -> Dictionary:
	return runs_by_player[id].return_to_camp() if can_bank_bag() and runs_by_player.has(id) else {}

func bank_bag() -> Dictionary:
	return bank_bag_for(primary_id)

func finish_rewards() -> Dictionary:
	var summaries := {}
	for id in player_ids(): summaries[id] = runs_by_player[id].return_to_camp()
	var summary: Dictionary = summaries[primary_id].duplicate(true)
	summary["players"] = summaries
	return summary

func died() -> void:
	for trip in runs_by_player.values():
		if not trip.died: trip.death()
	state = LOST
	clear_gauges()
	pay_card_xp()

func retreat() -> Dictionary:
	if not is_at_camp(): return {}
	state = RETREATED
	clear_gauges()
	pay_card_xp()
	return finish_rewards()

func abandon() -> Dictionary:
	if is_over() or state == IN_STAGE or is_at_camp(): return {}
	state = ABANDONED
	clear_gauges()
	pay_card_xp()
	var losses := {}
	for id in player_ids(): losses[id] = runs_by_player[id].discard_loot()
	return losses[primary_id]

## Run end (GDD races 3.10.2): every member's carried gauge goes back to 0.
func clear_gauges() -> void:
	for id in gauge_by_player:
		gauge_by_player[id] = 0.0
	gauge = 0.0

## True when the party is several squads, or one squad owned by a slot other than its first fighter (online rooms).
func _needs_v3() -> bool:
	if not runs_by_player.values().all(func(t): return t is SquadMember): return false
	var slots := owners()
	return slots.size() > 1 or slots[0] != player_ids()[0]


func to_dict() -> Dictionary:
	var saved := super.to_dict()
	var squad := runs_by_player.values().all(func(t): return t is SquadMember)
	# 1: separate runs; 2: one shared squad run in "run", member fields per player; 3: several squads (online squads,
	# design/gdd/online-squads.md chunk 1): "squads" [{player, run (shared, with profile), members}] + party rows.
	saved["party_v"] = 3 if _needs_v3() else (2 if squad else 1)
	saved["primary_id"] = primary_id
	if saved["party_v"] == 3:
		var squads: Array = []
		for slot in owners():
			var ids := fighters_of(slot)
			squads.append({"player": slot, "run": runs_by_player[ids[0]].shared.to_dict(), "members": ids})
		saved["squads"] = squads
	var players: Array = []
	for id in player_ids():
		players.append({"id": id, "run": runs_by_player[id].member_fields() if squad else runs_by_player[id].to_dict(), "hp": StateCodec.float_text(health_by_player[id]), "gauge": StateCodec.float_text(gauge_by_player[id]), "downed": downed_by_player.get(id, {}).duplicate()})
	saved["party"] = players
	var rewards: Array = []
	for id in last_rewards:
		var reward: Dictionary = last_rewards[id].duplicate(true)
		if reward.has("gold"): reward.gold = str(reward.gold)
		for key in ["items", "lost_items"]:
			if reward.has(key): reward[key] = reward[key].map(func(item): return item.to_dict())
		rewards.append({"id": id, "reward": reward})
	saved["party_rewards"] = rewards
	return saved

static func from_dict(d: Dictionary, journey_data: JourneyData, rules, camp_data, loot, weapons: Array):
	var version := int(d.get("party_v", 0))
	if version < 1 or version > 3: return null
	var base = load("res://logic/journey.gd").from_dict(d, journey_data, rules, camp_data, loot, weapons)
	if base == null: return null
	var j = load("res://logic/coop_journey.gd").new()
	StateCodec.apply_fields(j, StateCodec.fields(base))
	j.primary_id = int(d["primary_id"])
	var members: Array = []
	if version == 2:  # an auto-battle squad: base.run is the shared account trip
		var cards: Array = d["party"].map(func(player): return str(player["run"].get("card", "")))
		members = SquadMember.make_squad(base.run, cards)
	elif version == 3:
		members = _v3_members(d, rules, camp_data, j)
		if members.size() != d["party"].size(): return null
	for at in d["party"].size():
		var player: Dictionary = d["party"][at]
		var id := int(player["id"])
		if j.runs_by_player.has(id): return null
		var trip = members[at] if version >= 2 else Run.from_dict(player["run"], rules, camp_data)
		if trip == null: return null
		if version >= 2:
			if not trip.profile.card_gear.has(trip.card_id): return null
			trip.apply_member_fields(player["run"])
		j.runs_by_player[id] = trip
		j.health_by_player[id] = StateCodec.float_value(player["hp"])
		j.gauge_by_player[id] = StateCodec.float_value(player["gauge"])
		if not player["downed"].is_empty(): j.downed_by_player[id] = {"left": int(player["downed"]["left"])}
	if j.runs_by_player.size() < 2 or j.runs_by_player.size() > (MAX_SQUAD_FIGHTERS if version >= 2 else MAX_PLAIN_PLAYERS) or not j.runs_by_player.has(j.primary_id): return null
	for entry in d.get("party_rewards", []):
		var id := int(entry.id)
		var reward: Dictionary = entry.reward.duplicate(true)
		if reward.has("gold"): reward.gold = int(reward.gold)
		for key in ["materials", "lost_materials"]:
			for material in reward.get(key, {}): reward[key][material] = int(reward[key][material])
		for key in ["items", "lost_items"]:
			if reward.has(key): reward[key] = reward[key].map(func(raw): return load("res://logic/item.gd").from_dict(raw))
		j.last_rewards[id] = reward
	j.run = j.runs_by_player[j.primary_id]
	return j


## party_v 3: rebuilds every squad from its own saved shared run, in the order of d.party (fighter rows); fills
## j.owner_by_fighter. Returns [] when the squads and the party rows disagree.
static func _v3_members(d: Dictionary, rules, camp_data, j) -> Array:
	var by_id := {}
	for row in d["party"]:
		by_id[int(row["id"])] = row
	var trips := {}
	for entry in d.get("squads", []):
		var base = Run.from_dict(entry["run"], rules, camp_data)
		if base == null: return []
		var ids: Array = entry["members"].map(func(v): return int(v))
		if ids.is_empty() or not ids.all(func(id): return by_id.has(id) and not trips.has(id)): return []
		var cards: Array = ids.map(func(id): return str(by_id[id]["run"].get("card", "")))
		var squad: Array = SquadMember.make_squad(base, cards)
		for i in ids.size():
			trips[ids[i]] = squad[i]
			j.owner_by_fighter[ids[i]] = int(entry["player"])
	var members: Array = []
	for row in d["party"]:
		if not trips.has(int(row["id"])): return []
		members.append(trips[int(row["id"])])
	return members
