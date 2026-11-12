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

static func start_party(journey_data, trips: Dictionary, rules, loot, weapons: Array, seed: int, leader: int = 1):
	if trips.size() < 2 or trips.size() > 4 or not trips.has(leader): return null
	var ids := trips.keys()
	ids.sort()
	var profiles := []
	for id in ids:
		if not id is int or id < 0 or trips[id] == null or trips[id].died: return null
		# Separate players never share a profile. An auto-battle squad (logic/squad_member.gd) is the one
		# exception: its members all wrap one account trip, so they must ALL be members of that same squad.
		if profiles.has(trips[id].profile) and not (trips[id] is SquadMember and trips[id].squad == trips[ids[0]].squad): return null
		profiles.append(trips[id].profile)
	if trips.values().any(func(t): return t is SquadMember) and not trips.values().all(func(t): return t is SquadMember and t.squad == trips[ids[0]].squad): return null
	var j = load("res://logic/coop_journey.gd").new()
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
	j._generate()
	return j

func player_ids() -> Array:
	return runs_by_player.keys()  # inserted in sorted order

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
	if sim.combat == null or sim.combat.coop.is_empty() or ids.size() > int(sim.combat.coop.max_players): return []
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
		last_rewards[id] = runs_by_player[id].loot_into_bag(treasure_drop("treasure-player-%d" % id))
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

func to_dict() -> Dictionary:
	var saved := super.to_dict()
	var squad := runs_by_player.values().all(func(t): return t is SquadMember)
	saved["party_v"] = 2 if squad else 1  # 2: one shared squad run in "run", member fields per player
	saved["primary_id"] = primary_id
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
	if version != 1 and version != 2: return null
	var base = load("res://logic/journey.gd").from_dict(d, journey_data, rules, camp_data, loot, weapons)
	if base == null: return null
	var j = load("res://logic/coop_journey.gd").new()
	StateCodec.apply_fields(j, StateCodec.fields(base))
	j.primary_id = int(d["primary_id"])
	var members: Array = []
	if version == 2:  # an auto-battle squad: base.run is the shared account trip
		var cards: Array = d["party"].map(func(player): return str(player["run"].get("card", "")))
		members = SquadMember.make_squad(base.run, cards)
	for at in d["party"].size():
		var player: Dictionary = d["party"][at]
		var id := int(player["id"])
		if j.runs_by_player.has(id): return null
		var trip = members[at] if version == 2 else Run.from_dict(player["run"], rules, camp_data)
		if trip == null: return null
		if version == 2:
			if not base.run.profile.card_gear.has(trip.card_id): return null
			trip.apply_member_fields(player["run"])
		j.runs_by_player[id] = trip
		j.health_by_player[id] = StateCodec.float_value(player["hp"])
		j.gauge_by_player[id] = StateCodec.float_value(player["gauge"])
		if not player["downed"].is_empty(): j.downed_by_player[id] = {"left": int(player["downed"]["left"])}
	if j.runs_by_player.size() < 2 or j.runs_by_player.size() > 4 or not j.runs_by_player.has(j.primary_id): return null
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
