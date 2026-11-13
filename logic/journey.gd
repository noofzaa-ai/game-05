extends RefCounted
const StateCodec := preload("res://logic/state_codec.gd")
## The rules of a JOURNEY: 12 stages played one after another with the same run bag. After each stage
## the player picks the next one from a few random choices (combat, challenge combat, treasure); two
## stages are always a CAMP (one at a random stage among first_camp_stages, one right before the boss)
## and the last stage is the BOSS. Monsters get stronger stage by stage (data/journeys/*.json).
## Everything is decided from the seed passed in, so a journey repeats exactly (tests, server).
## Dying anywhere loses the bag (Run.death, as in any trip). Pure rules: the client shows the choices
## and plays the stages; it tells the journey what happened (stage_cleared / died / retreat).

const GameSim := preload("res://logic/game_sim.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Loot := preload("res://logic/loot.gd")
const Run := preload("res://logic/run.gd")
const CardProgress := preload("res://logic/card_progress.gd")

## What the journey is waiting for.
const CHOOSING := "choosing"  ## the player picks the next stage
const IN_STAGE := "in_stage"  ## a fight (combat, challenge or boss) is being played
const AT_NODE := "at_node"  ## at a camp or treasure: leave_node() moves on
const WON := "won"  ## the boss is down
const LOST := "lost"  ## the player died: carried loot was secured
const RETREATED := "retreated"  ## went home with the bag (from a camp)
const ABANDONED := "abandoned"  ## left before reaching a camp: the bag is lost

var data: JourneyData
var run: Run
var item_rules
var loot_data
var weapon_ids: Array = []
var seed_value := 0
var nodes: Array = []  ## index = stage - 1 -> Array of choice nodes {"stage", "kind", "map"}
var first_camp := 0  ## the stage the first camp landed on
var completed := 0  ## stages finished so far
var current: Dictionary = {}  ## the node being played / visited
var state := CHOOSING
var hp_fraction := 1.0  ## the player's health carried from stage to stage (0..1 of max HP)
## The player's ultimate gauge carried from stage to stage (Boss 2026-10-15: it does not reset). Cleared at run end
## (GDD races 3.10.2): once the journey is over it stays 0, whatever a late capture writes.
var gauge := 0.0:
	set(value):
		gauge = 0.0 if is_over() else value
var path: Array[String] = []  ## types of the nodes taken, in order (for the summary)
var last_reward: Dictionary = {}  ## what the last treasure / challenge gave (from Run.loot_into_bag)
var treasure_pending := false  ## at a treasure node whose chest is not opened yet (open_treasure())
## Card XP (design/gdd/skill-tree.md 3.7, logic/card_progress.gd): waves cleared in the wave-mode fight so far
## (note_waves), whether the run's XP was paid (once only) and what each card got {card_id: CardProgress.grant()}.
var waves_cleared := 0
var card_xp_paid := false
var card_xp: Dictionary = {}


## Starts a journey and lays out every stage's choices from `seed`.
static func start(journey_data: JourneyData, trip: Run, rules, loot, weapons: Array, seed: int) -> RefCounted:
	var journey = load("res://logic/journey.gd").new()
	journey.data = journey_data
	journey.run = trip
	journey.item_rules = rules
	journey.loot_data = loot
	journey.weapon_ids = weapons
	journey.seed_value = seed
	journey._generate()
	return journey


## The stage the player is about to play or is playing (1-based).
## The squad's race synergy for this run (design/gdd/races-and-classes.md 3.5), read-only for the UI.
## {"kind": "none", ...} for a trip that is not a squad (single profile, old saves).
func synergy() -> Dictionary:
	if run != null and run.has_method("synergy"):
		return run.synergy()
	return {"kind": "none", "race": "", "name": "", "text": "", "effects": []}


func stage_number() -> int:
	return mini(completed + 1, total_stages())


## Stages to play: 12 on the road; a wave-mode journey (data.wave_mode) is one fight with 12 waves.
func total_stages() -> int:
	return 1 if data.wave_mode else data.stage_count


## How many waves the one fight of a wave-mode journey has.
func wave_total() -> int:
	return data.stage_count


## "Stage 4/12" for the screens.
func progress_text() -> String:
	if data.wave_mode:
		return "Wave 1/%d" % data.stage_count
	return "Stage %d/%d" % [stage_number(), data.stage_count]


func choices() -> Array:
	if state != CHOOSING:
		return []
	return nodes[completed]


## What the next stage offers: choices() while choosing; at a camp or treasure (AT_NODE) the choices
## of the stage after it, which choose_next() picks from (the exit portals show these before leaving).
func upcoming_choices() -> Array:
	if treasure_pending:
		return []
	if state == CHOOSING:
		return choices()
	if state == AT_NODE and completed + 1 < nodes.size():
		return nodes[completed + 1]
	return []


## Picks upcoming choice `index`: leaves the camp or treasure first if the journey is at one, then choose().
func choose_next(index: int) -> Dictionary:
	if index < 0 or index >= upcoming_choices().size():
		return {}
	leave_node()
	return choose(index)


func is_over() -> bool:
	return state == WON or state == LOST or state == RETREATED or state == ABANDONED


## Picks choice `index` for the next stage. A treasure waits to be opened (open_treasure(), Boss 2026-10-13:
## the player opens its chest) and a camp heals at once; both then wait for leave_node(). A fight waits
## for stage_cleared() / died(). Returns the chosen node ({} if invalid).
func choose(index: int) -> Dictionary:
	var options := choices()
	if index < 0 or index >= options.size():
		return {}
	current = options[index]
	path.append(str(current["kind"]))
	last_reward = {}
	match str(current["kind"]):
		"treasure":
			# Also repair old saved layouts without changing choice indices.
			if completed + 1 < nodes.size():
				for i in nodes[completed + 1].size():
					if str(nodes[completed + 1][i].get("kind", "")) == "treasure":
						nodes[completed + 1][i] = _fight_node(completed + 2, "combat", _rng_for("after-treasure", completed + 2 + i))
			treasure_pending = true
			state = AT_NODE
		"camp":
			hp_fraction = minf(1.0, hp_fraction + data.camp_heal_fraction)
			state = AT_NODE
		_:
			state = IN_STAGE
	return current


## Opens the chosen treasure: its piece goes into the bag (once; later calls give {}). Returns
## Run.loot_into_bag()'s summary, also kept in last_reward.
func open_treasure() -> Dictionary:
	if not treasure_pending or state != AT_NODE:
		return {}
	treasure_pending = false
	last_reward = run.loot_into_bag(treasure_drop("treasure"))
	return last_reward


## How many fighters this journey fights with (a party overrides it).
func fighter_count() -> int:
	return 1


## Loot by squad size (Boss 2026-11-12): the factor every loot source of this journey is scaled by.
func loot_factor() -> float:
	return data.loot_for(fighter_count())


## A treasure's contents for the reward key `what`: its piece, given with a chance of loot_factor() (always
## at 1.0). The pay roll has its own generator, so the piece rolled is the same at any factor.
func treasure_drop(what: String) -> Dictionary:
	var item = treasure_item(_rng_for(what, completed + 1))
	# Race gear (design/gdd/race-gear-sets.md 3.12): a chest piece may become a race piece of a squad card.
	var RaceDrops = load("res://logic/race_drops.gd")
	item = RaceDrops.convert_piece(item_rules, item, RaceDrops.picks_for(run), RaceDrops.CHEST, waves_cleared if data.wave_mode else completed + 1)
	var pays := _rng_for(what + "-pays", completed + 1).randf() < loot_factor()
	return {"gold": 0, "materials": {}, "items": [item] if pays else []}


func is_treasure_closed() -> bool:
	return treasure_pending and state == AT_NODE


## Leaves a camp or opened treasure. An unopened chest must be explicitly opened first.
func leave_node() -> void:
	if treasure_pending:
		return
	if state == AT_NODE:
		open_treasure()
		_advance()


## At a camp (only when camp_banks_bag is on): the bag goes into the stash now, so a later death
## cannot take it. Returns Run.return_to_camp()'s summary, or {} when not allowed.
func bank_bag() -> Dictionary:
	if not can_bank_bag():
		return {}
	return run.return_to_camp()


func can_bank_bag() -> bool:
	return data.camp_banks_bag and is_at_camp()


func is_at_camp() -> bool:
	return state == AT_NODE and str(current.get("kind", "")) == "camp"


## The current fight was won with `hp_left` (0..1 of max HP). A challenge pays its extra reward.
func stage_cleared(hp_left: float) -> void:
	if state != IN_STAGE:
		return
	hp_fraction = clampf(hp_left, 0.01, 1.0)
	last_reward = {}
	if str(current["kind"]) == "challenge":
		last_reward = run.loot_into_bag(challenge_reward(_rng_for("challenge", completed + 1)))
	_advance()


## The player fell: secure carried loot if needed and end the journey.
func died() -> void:
	if not run.died:
		run.death()
	state = LOST
	clear_gauges()
	pay_card_xp()


## Goes home with the bag. Only from a camp: leaving anywhere else is abandon(). Returns Run.return_to_camp().
func retreat() -> Dictionary:
	if not is_at_camp():
		return {}
	state = RETREATED
	clear_gauges()
	pay_card_xp()
	return run.return_to_camp()


## Leaves the journey between stages before reaching a camp (Boss 2026-10-09): the bag's loot is lost,
## the stash and worn gear are kept. Returns what was lost (Inventory.clear_loot), or {} when not allowed.
func abandon() -> Dictionary:
	if is_over() or state == IN_STAGE or is_at_camp():
		return {}
	state = ABANDONED
	clear_gauges()
	pay_card_xp()
	return run.discard_loot()


## The fight description for a node: {"level", "power", "enemies"} from the stage's data (challenge or not).
func fight_for(node: Dictionary) -> Dictionary:
	var stage: Dictionary = data.stages[int(node["stage"]) - 1]
	if str(node["kind"]) == "challenge" and not stage.get("challenge", {}).is_empty():
		return stage["challenge"]
	return stage


## Puts the current fight's monsters into `sim` at the map's enemy spawn spots (in file order; extra
## monsters stand next to the last spots) and sets the player's carried-over health.
## Returns the fighter ids of the boss monsters (the client labels them).
func populate(sim: GameSim, map, player_id: int, first_enemy_id: int) -> Array[int]:
	var bosses: Array[int] = []
	sim.loot_factor = loot_factor()
	if sim.fighters.has(player_id):
		sim.fighters[player_id].hp = minf(sim.fighters[player_id].max_hp(), sim.fighters[player_id].max_hp() * hp_fraction)
		sim.fighters[player_id].gauge = gauge
	# Safe nodes never inherit the combat roster for their stage number.
	if state != IN_STAGE or map.kind == "rest":
		return bosses
	if data.wave_mode:
		return _populate_waves(sim, map, first_enemy_id)
	var fight := fight_for(current)
	var spots: Array = map.enemy_spawns.map(func(s): return s["position"])
	if spots.is_empty():
		spots = [map.spawn + Vector3(6.0, 0.0, -6.0)]
	var next_id := first_enemy_id
	var placed := 0
	var later: Array = []  ## [{"entry", "wave"}]: monsters of wave 2+ (they join when the boss is hurt or the field is clear)
	var power := float(fight.get("power", 1.0))
	for enemy in fight.get("enemies", []):
		for i in int(enemy["count"]):
			var spot: Vector3 = spots[placed % spots.size()] + Vector3(1.5 * float(placed / spots.size()), 0.0, 0.0)
			var level := int(enemy.get("level", fight["level"]))
			var wave := int(enemy.get("wave", 1))
			if wave > 1:
				later.append({"wave": wave, "entry": {"id": next_id, "position": spot, "type": str(enemy["type"]), "level": level, "hp_scale": power, "atk_scale": power}})
			else:
				sim.add_enemy(next_id, spot, str(enemy["type"]), level)
				_apply_power(sim.fighters[next_id], power)
				if bool(enemy.get("boss", false)):
					_make_boss(sim.fighters[next_id])
					bosses.append(next_id)
			next_id += 1
			placed += 1
	var rule: Dictionary = fight.get("waves", {})
	var waves := later.map(func(l): return int(l["wave"]))
	for wave in range(2, (waves.max() if not waves.is_empty() else 1) + 1):
		var entries := later.filter(func(l): return int(l["wave"]) == wave).map(func(l): return l["entry"])
		if not entries.is_empty():
			sim.queue_wave(entries, bosses[0] if not bosses.is_empty() else -1, float(rule.get("boss_hp_below", 0.0)))
	return bosses


## Wave mode: wave 1 stands on the field now, waves 2..N are queued and arrive when the field is clear
## (GameSim.queue_wave). Every non-boss count is multiplied by data.wave_count_scale (rounded up); the boss
## wave (the last) brings the Chief with its escorts. Returns the boss ids that exist now (none: it comes last).
func _populate_waves(sim: GameSim, map, first_enemy_id: int) -> Array[int]:
	var spots: Array = map.enemy_spawns.map(func(s): return s["position"])
	if spots.is_empty():
		spots = [map.spawn + Vector3(6.0, 0.0, -6.0)]
	var players := 0
	for id in sim.fighters:
		if sim.fighters[id].team != "enemy":
			players += 1
	var squad_power := data.wave_power_for(players)
	# No party HP scaling here: PartyJourney.populate multiplies every enemy on the field and in the queued
	# waves by combat coop hp_multiplier once (scaling here too counted it twice: 4.84x for a squad of 3).
	sim.wave_heal_fraction = data.wave_heal_fraction
	var next_id := first_enemy_id
	for wave in range(1, data.stage_count + 1):
		var fight: Dictionary = data.stages[wave - 1]
		var power := float(fight.get("power", 1.0)) * squad_power
		var entries: Array = []
		var placed := 0
		for enemy in fight.get("enemies", []):
			var is_boss := bool(enemy.get("boss", false))
			var count := int(enemy["count"]) if is_boss else int(ceil(float(enemy["count"]) * data.wave_count_scale))
			for i in count:
				var spot: Vector3 = spots[placed % spots.size()]
				var row := placed / spots.size()
				spot += Vector3(-0.8 * float(row), 0.0, (0.9 if row % 2 == 0 else -0.9) * float(row))
				if is_boss:
					spot = Vector3(5.2, 0.05, 0.0)
				var hp_scale := power * (float(data.boss.get("hp_mult", 1.0)) if is_boss else 1.0)
				var entry := {"id": next_id, "position": spot, "type": str(enemy["type"]), "level": int(enemy.get("level", fight["level"])), "hp_scale": hp_scale, "atk_scale": power}
				if is_boss:
					entry["poise_scale"] = float(data.boss.get("poise_mult", 1.0))
				entries.append(entry)
				next_id += 1
				placed += 1
		if wave == 1:
			for entry in entries:
				sim.add_enemy(int(entry["id"]), entry["position"], str(entry["type"]), int(entry["level"]))
				var fighter = sim.fighters[int(entry["id"])]
				fighter.stats["HP"] = float(fighter.stats["HP"]) * float(entry["hp_scale"])
				fighter.stats["ATK"] = float(fighter.stats["ATK"]) * float(entry["atk_scale"])
				fighter.hp = fighter.max_hp()
				fighter.max_poise *= float(entry.get("poise_scale", 1.0))
				fighter.poise = fighter.max_poise
		else:
			sim.queue_wave(entries)
	return []


## How dangerous a fight is: the sum over its monsters of HP x ATK (after level and power), divided by
## the HP x ATK of one base level-1 grunt. Used to keep the curve rising (tests) and for balance notes.
static func threat(fight: Dictionary, combat, boss: Dictionary = {}) -> float:
	var base: Dictionary = combat.enemy_stats("dummy_grunt", 1)
	var unit := float(base["HP"]) * float(base["ATK"])
	var total := 0.0
	for enemy in fight.get("enemies", []):
		var stats: Dictionary = combat.enemy_stats(str(enemy["type"]), int(enemy.get("level", fight["level"])))
		var power := float(fight.get("power", 1.0))
		var hp := float(stats["HP"]) * power * (float(boss.get("hp_mult", 1.0)) if bool(enemy.get("boss", false)) else 1.0)
		total += float(enemy["count"]) * hp * float(stats["ATK"]) * power
	return total / unit


## A guaranteed wearable piece of tier >= treasure.min_tier, its tier drawn from treasure.tier_weights.
func treasure_item(rng: RandomNumberGenerator):
	var tier_ids: Array = item_rules.tiers.map(func(t): return str(t["id"]))
	var min_tier := maxi(0, tier_ids.find(str(data.treasure["min_tier"])))
	var weights: Dictionary = data.treasure["tier_weights"]
	var total := 0.0
	for tier_id in weights:
		if tier_ids.find(str(tier_id)) >= min_tier:
			total += float(weights[tier_id])
	var tier := min_tier
	var roll := rng.randf() * total
	for tier_id in weights:
		var index := tier_ids.find(str(tier_id))
		if index < min_tier:
			continue
		roll -= float(weights[tier_id])
		if roll < 0.0:
			tier = index
			break
	# Only a piece with a model (Loot.roll_piece); the stage's monster level decides which ones can come.
	var level := int(fight_for(current).get("level", stage_number())) if not current.is_empty() else stage_number()
	return Loot.roll_piece(item_rules, "treasure-%d-%d" % [seed_value, completed + 1], tier, level, weapon_ids, rng)


## The extra drop for winning a challenge: loot rolls of a monster table at a higher level.
func challenge_reward(rng: RandomNumberGenerator) -> Dictionary:
	var reward := {"gold": 0, "materials": {}, "items": []}
	var fight := fight_for(current)
	var level := int(fight["level"]) + int(data.challenge_reward.get("level_bonus", 0))
	for i in int(data.challenge_reward.get("rolls", 1)):
		var drop := Loot.roll(item_rules, loot_data, str(data.challenge_reward.get("table", "brute")), level, weapon_ids, rng, loot_factor())
		reward["gold"] += int(drop["gold"])
		for id in drop["materials"]:
			reward["materials"][id] = int(reward["materials"].get(id, 0)) + int(drop["materials"][id])
		reward["items"].append_array(drop["items"])
	return reward


func _advance() -> void:
	completed += 1
	current = {}
	state = WON if completed >= total_stages() else CHOOSING
	if is_over():
		clear_gauges()
		pay_card_xp()


## Wave mode: records how many waves of the one fight are cleared (a wave is cleared when the next one arrives).
## The session/room calls it every tick with its sim; it only ever goes up and stops once the run is over.
func note_waves(sim) -> void:
	if data.wave_mode and sim != null and not is_over():
		waves_cleared = maxi(waves_cleared, int(sim._waves_released))


## Normal waves cleared this run, for the XP formula (the boss wave is the boss bonus, not a wave).
func xp_waves_cleared() -> int:
	var normal := maxi(data.stage_count - 1, 0)
	if state == WON:
		return normal
	return mini(waves_cleared if data.wave_mode else completed, normal)


## The cards that started this run: the squad member's card, or the lead card of a plain (pre-card) run.
func xp_cards() -> Array:
	return [[run.profile, _card_of(run)]]


static func _card_of(trip) -> String:
	var card := str(trip.get("card_id")) if "card_id" in trip else ""
	return card if not card.is_empty() else str(trip.profile.lead_card())


## Run end (GDD skill-tree 3.7): every card that started the run gets the same XP, downed or not. Paid ONCE
## (card_xp_paid is saved with the journey), so a repeated end never pays twice. Lost, retreated and abandoned
## runs pay for the waves already cleared.
func pay_card_xp() -> void:
	if card_xp_paid or not is_over():
		return
	card_xp_paid = true
	var amount := CardProgress.run_xp(xp_waves_cleared(), state == WON, state == WON)
	for entry in xp_cards():
		var granted: Dictionary = CardProgress.grant(entry[0].card_deck, str(entry[1]), amount)
		if not granted.is_empty():
			card_xp[str(entry[1])] = granted


## Run end (GDD races 3.10.2): the carried ultimate gauge goes back to 0.
func clear_gauges() -> void:
	gauge = 0.0


func _apply_power(fighter, power: float) -> void:
	fighter.stats["HP"] = float(fighter.stats["HP"]) * power
	fighter.stats["ATK"] = float(fighter.stats["ATK"]) * power
	fighter.hp = fighter.max_hp()


func _make_boss(fighter) -> void:
	fighter.stats["HP"] = float(fighter.stats["HP"]) * float(data.boss.get("hp_mult", 1.0))
	fighter.hp = fighter.max_hp()
	fighter.max_poise *= float(data.boss.get("poise_mult", 1.0))
	fighter.poise = fighter.max_poise


## A generator for one stage's random event, derived from the journey seed (same seed = same result).
func _rng_for(what: String, stage: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, what, stage])
	return rng


## Lays out every stage's choices: stage 1 is a plain fight, the camps and the boss are fixed, every
## other stage offers `choice_count` nodes drawn by node_weights with at least one plain combat.
func _generate() -> void:
	var rng := _rng_for("layout", 0)
	first_camp = data.first_camp_stages[rng.randi_range(0, data.first_camp_stages.size() - 1)]
	nodes.clear()
	if data.wave_mode:  # one fight, one map: the waves are inside it
		var pool: Array[String] = data.fight_map_pool()
		nodes.append([{"stage": 1, "kind": "combat", "map": pool[seed_value % pool.size()]}])
		return
	for stage in range(1, data.stage_count + 1):
		var options: Array = []
		if stage == data.stage_count:
			options.append({"stage": stage, "kind": "boss", "map": data.boss_map})
		elif stage == first_camp or stage == data.last_camp_stage:
			options.append({"stage": stage, "kind": "camp", "map": data.camp_map})
		elif stage == 1:
			options.append(_fight_node(stage, "combat", rng))
		else:
			var has_combat := false
			for i in data.choice_count:
				var type := _weighted_type(rng)
				if type == "treasure" and not nodes.is_empty() and nodes[-1].any(func(node): return str(node.get("kind", "")) == "treasure"):
					type = "combat"
				if type == "challenge" and data.stages[stage - 1].get("challenge", {}).is_empty():
					type = "combat"
				has_combat = has_combat or type == "combat"
				options.append(_fight_node(stage, type, rng) if type != "treasure" else {"stage": stage, "kind": "treasure", "map": ""})
			if not has_combat:
				options[0] = _fight_node(stage, "combat", rng)
		nodes.append(options)


func _fight_node(stage: int, type: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array[String] = data.fight_map_pool()
	return {"stage": stage, "kind": type, "map": pool[rng.randi_range(0, pool.size() - 1)]}


func _weighted_type(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for type in data.node_weights:
		total += float(data.node_weights[type])
	var roll := rng.randf() * total
	for type in data.node_weights:
		roll -= float(data.node_weights[type])
		if roll < 0.0:
			return str(type)
	return "combat"


func to_dict() -> Dictionary:
	var reward := last_reward.duplicate(true)
	if reward.has("gold"):
		reward["gold"] = str(reward["gold"])
	for key in ["items", "lost_items"]:
		if reward.has(key):
			reward[key] = reward[key].map(func(item): return item.to_dict())
	return {"v": 1, "run": run.to_dict(), "seed": str(seed_value), "nodes": nodes.duplicate(true),
		"first_camp": first_camp, "completed": completed, "current": current.duplicate(true),
		"state": state, "hp_fraction": StateCodec.float_text(hp_fraction), "gauge": StateCodec.float_text(gauge),
		"path": path.duplicate(), "last_reward": reward, "treasure_pending": treasure_pending,
		"waves_cleared": waves_cleared, "card_xp_paid": card_xp_paid, "card_xp": card_xp.duplicate(true)}


static func from_dict(d: Dictionary, journey_data: JourneyData, rules, camp_data, loot, weapons: Array):
	if int(d.get("v", 0)) != 1:
		return null
	var trip = Run.from_dict(d["run"], rules, camp_data)
	if trip == null:
		return null
	var j = load("res://logic/journey.gd").new()
	j.data = journey_data
	j.run = trip
	j.item_rules = rules
	j.loot_data = loot
	j.weapon_ids = weapons.duplicate()
	j.seed_value = int(d["seed"])
	j.nodes = d["nodes"].duplicate(true)
	j.first_camp = int(d["first_camp"])
	j.completed = int(d["completed"])
	# Stage numbers arrive as JSON floats; restore their integer meaning.
	for options in j.nodes:
		for node in options:
			node["stage"] = int(node["stage"])
	j.current = d["current"].duplicate(true)
	if j.current.has("stage"):
		j.current["stage"] = int(j.current["stage"])
	j.state = str(d["state"])
	j.hp_fraction = StateCodec.float_value(d["hp_fraction"])
	j.gauge = StateCodec.float_value(d["gauge"])
	j.path.assign(d["path"])
	j.treasure_pending = bool(d["treasure_pending"])
	j.waves_cleared = int(d.get("waves_cleared", 0))  # older checkpoints: none cleared, not paid yet
	j.card_xp_paid = bool(d.get("card_xp_paid", false))
	j.card_xp = {}
	var paid_xp = d.get("card_xp", {})
	if paid_xp is Dictionary:
		for card in paid_xp:
			var entry: Dictionary = {}
			for key in paid_xp[card]:
				entry[key] = paid_xp[card][key] if paid_xp[card][key] is String else int(paid_xp[card][key])
			j.card_xp[str(card)] = entry
	j.last_reward = d["last_reward"].duplicate(true)
	if j.last_reward.has("gold"):
		j.last_reward["gold"] = int(j.last_reward["gold"])
	for key in ["materials", "lost_materials"]:
		for material in j.last_reward.get(key, {}):
			j.last_reward[key][material] = int(j.last_reward[key][material])
	for key in ["items", "lost_items"]:
		if j.last_reward.has(key):
			j.last_reward[key] = j.last_reward[key].map(func(raw): return load("res://logic/item.gd").from_dict(raw))
	return j
