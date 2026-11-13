extends RefCounted
## The game simulation: who is in the match, what they are doing, advanced one fixed tick at a time.
## This is what a dedicated server runs (headless) and what tests drive directly. It never draws
## anything and never reads a keyboard; inputs come in through `set_input`, results go out through
## `bodies`, `fighters`, `events` and `snapshot()`.
## Combat is optional: build the sim with combat data and a random number generator to enable it
## (the server passes its own generator; tests pass a seeded one so runs repeat exactly).
## EXTENDING: new systems (loot, status effects) become new classes in logic/ that `tick` calls in
## a fixed order. Anything the client must react to (hit, drop, death) is appended to `events`.

const Coop := preload("res://logic/coop.gd")
const Combat := preload("res://logic/combat.gd")
const CombatData := preload("res://logic/combat_data.gd")
const EnemyAI := preload("res://logic/enemy_ai.gd")
const Fighter := preload("res://logic/fighter.gd")
const Movement := preload("res://logic/movement.gd")
const Projectiles := preload("res://logic/projectiles.gd")
const SimBody := preload("res://logic/sim_body.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const Stats := preload("res://logic/stats.gd")
const ItemRules := preload("res://logic/item_rules.gd")
const Loot := preload("res://logic/loot.gd")
const LootData := preload("res://logic/loot_data.gd")
const Run := preload("res://logic/run.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Wear := preload("res://logic/wear.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const ClassSkills := preload("res://logic/class_skills/engine.gd")
const ClassSkillUse := preload("res://logic/class_skills/use_rules.gd")
const ClassSkillData := preload("res://logic/class_skills/skill_data.gd")

var world: SimWorld
var combat: CombatData  ## null = movement only, no fighting
var rng: RandomNumberGenerator
var bodies: Dictionary = {}  ## id (int) -> SimBody
var fighters: Dictionary = {}  ## id (int) -> Fighter (only when combat is enabled)
var events: Array[Dictionary] = []  ## things that happened during the last tick; cleared every tick
var tick_count := 0
## Live projectiles and ground areas (see projectiles.gd); plain dictionaries the client draws from.
var projectiles: Array = []
var areas: Array = []
var _ranged := {"projectiles": [], "areas": [], "next_id": 1}
var melee_target_boxes:Dictionary={} # Authority-owned historical enemy AABBs per attacker.
var skill_system = null  ## Old skill-build runtime: deleted (class-skills.md, Boss 2026-11-13). Always null; kept for old checkpoints.

var item_rules: ItemRules  ## with loot_data: monsters drop loot and gear wears (see attach_run)
var loot_data: LootData
## The wave a kill's race-gear drop counts as (logic/race_drops.gd): -1 = the local wave counter (_waves_released + 1);
## the online room sets it, because it spawns each goblin wave itself.
var reward_wave := -1
var loot_factor := 1.0  ## loot by squad size (Boss 2026-11-12): set by Journey.populate from JourneyData.loot_for
## Personal loot (design/gdd/online-squads.md 3.5, chunk 4): fighter id -> [player slot, that player's loot factor].
## Empty = the shared path above. Filled by PartyJourney.populate for a party of several squads.
var loot_players: Dictionary = {}
var runs: Dictionary = {}  ## player id (int) -> Run: the bag and gear of a player on a trip (only when attached)

var _inputs: Dictionary = {}  ## id (int) -> SimInput
var _ai: Dictionary = {}  ## enemy id (int) -> EnemyAI
var _coop := {"enabled": false, "players": [], "wiped": false, "paid": {}}
var coop_enabled: bool:
	get: return bool(_coop["enabled"])
var _had_enemies := false
var _clear_reported := false
## Reinforcements that join later (see queue_wave): [{"enemies": [...], "watch": id, "watch_hp_below": float}]
var _waves: Array = []
var wave_heal_fraction := 0.0  ## wave-mode journeys: each arriving wave first heals the living players by this much of max HP
var _waves_released := 0


func _init(sim_world: SimWorld, combat_data: CombatData = null, random: RandomNumberGenerator = null) -> void:
	world = sim_world
	combat = combat_data
	rng = random if random != null else RandomNumberGenerator.new()


## Adds a player. `stats` (for example from Stats.totals) fill in over the default stats, and
## `style` (from the equipped weapon, see Loadout.weapon_style) picks the move set.
func add_player(id: int, spawn: Vector3, stats: Dictionary = {}, style: String = "fists") -> SimBody:
	var body := _add_body(id, spawn)
	if combat != null:
		_add_fighter(id, body, "player", style if combat.styles.has(style) else "fists", combat.full_stats(stats))
	return body


## Adds an enemy of a type defined in the combat data. Requires combat to be enabled. A higher
## `level` makes it stronger (see CombatData.enemy_stats), so a stage can match the gear its players have.
func add_enemy(id: int, spawn: Vector3, enemy_type: String, level: int = 1) -> SimBody:
	var definition: Dictionary = combat.enemies[enemy_type]
	var body := _add_body(id, spawn)
	_add_fighter(id, body, "enemy", definition["style"], combat.enemy_stats(enemy_type, level))
	fighters[id].level = maxi(level, 1)
	fighters[id].enemy_type = enemy_type
	fighters[id].max_poise = float(definition["poise"])
	fighters[id].poise = fighters[id].max_poise
	var brain := EnemyAI.new()
	brain.attack_range = definition["ai"]["attack_range"]
	brain.attack_min_range = definition["ai"]["attack_min_range"]
	brain.wait_range = definition["ai"]["wait_range"]
	brain.attack_input = definition["ai"]["attack_input"]
	brain.cooldown_min = definition["ai"]["cooldown_min"]
	brain.cooldown_max = definition["ai"]["cooldown_max"]
	brain.skill_chance = definition["ai"]["skill_chance"]
	brain.retreat_ticks = definition["ai"]["retreat_ticks"]
	brain.flee_hp = definition["ai"]["flee_hp"]
	brain.flee_ticks = definition["ai"]["flee_ticks"]
	for key in ["keep_range", "retreat_range", "strafe", "escape_input", "escape_range", "escape_cooldown"]:
		brain.set(key, definition["ai"][key])
	brain.world = world
	body.height = definition["body_height"]
	_ai[id] = brain
	_had_enemies = true
	return body


## Ties a trip (run bag, worn gear, camp skills) to a player. From now on the player's stats come from
## the gear, monsters they defeat drop loot into the run bag, and the gear wears out as they fight.
func attach_run(id: int, run: Run, rules: ItemRules, loot: LootData) -> void:
	item_rules = rules
	loot_data = loot
	runs[id] = run
	preload("res://logic/relic_effects.gd").attach(fighters[id],run.profile)
	RacePassives.attach(fighters[id], run)  # a squad card: its race x class passive + the squad synergy (GDD races 3.4-3.5)
	RacePassives.RaceUltimates.register_move(combat, fighters[id])  # its synthetic <race>_<class>_ultimate move (3.10.3)
	fighters[id].style = run.loadout().weapon_style(combat.styles.keys())  # the weapon decides the fighting style
	_apply_class_style(id)
	_refresh_run_stats(id)
	fighters[id].hp = fighters[id].max_hp()
	fighters[id].energy = fighters[id].max_energy()
	if run is SquadMember:
		ClassSkills.attach(self, id, run.card_id)  # a squad card casts its class's 4 skills (design/gdd/class-skills.md)
	elif class_styles.has(id):
		ClassSkills.attach(self, id, ClassSkillData.class_for_style(class_styles[id]))  # a class was set first (set_class_style)
	# (a plain weapon-led run, an online companion, has no class: no class skills; PO default 2026-11-13)


## Auto-battler: the squad member's class decides the fighting style (data/classes/<class>.json "weapon" is a
## weapon id of data/combat/weapons.json, for example "longbow" shoots). `class_styles`: player id -> style.
var class_styles: Dictionary = {}


func set_class_style(id: int, style: String) -> void:
	if combat == null or not combat.styles.has(style):
		return
	class_styles[id] = style
	_apply_class_style(id)
	# The class decides the skills: a fighter that is not a squad card gets this class style's 4 (class-skills.md 3.6);
	# a squad card keeps its own class's. Same class again = keep the running cooldowns.
	if fighters.has(id) and not (runs.has(id) and runs[id] is SquadMember):
		var class_id := ClassSkillData.class_for_style(style)
		if str(fighters[id].skill_state.get("class", "")) != class_id:
			fighters[id].skill_state = {}
			ClassSkills.attach(self, id, class_id)


func _apply_class_style(id: int) -> void:
	if class_styles.has(id) and fighters.has(id):
		fighters[id].style = class_styles[id]


## Call after the worn gear changed in the middle of a trip (at a rest point): the weapon may have
## changed the fighting style, and the stats come from the gear.
func gear_changed(id: int) -> void:
	if not runs.has(id) or not fighters.has(id):
		return
	fighters[id].style = runs[id].loadout().weapon_style(combat.styles.keys())
	_apply_class_style(id)
	_refresh_run_stats(id)


## The player rests at a rest point (once per point per trip): heals part of their max HP and
## refills stamina. Returns false if they cannot (no trip, dead, already used it, in the middle of
## something). Tells the client with a "rested" event.
func use_rest(id: int, point_id: String) -> bool:
	if not runs.has(id) or not fighters.has(id) or not fighters[id].is_alive():
		return false
	var run: Run = runs[id]
	if not run.rest_available(point_id) or fighters[id].state == Fighter.State.HITSTUN or fighters[id].state == Fighter.State.ATTACK:
		return false
	run.used_rests.append(point_id)
	var fighter: Fighter = fighters[id]
	var healed := minf(fighter.max_hp() - fighter.hp, fighter.max_hp() * run.camp.rest_heal_fraction * fighter.heal_factor())
	fighter.hp += healed
	fighter.energy = fighter.max_energy()
	events.append({"type": "rested", "player": id, "point": point_id, "healed": int(healed)})
	return true


func remove_player(id: int) -> void:
	runs.erase(id)
	bodies.erase(id)
	fighters.erase(id)
	_inputs.erase(id)
	_ai.erase(id)


func set_input(id: int, input: SimInput) -> void:
	if bodies.has(id):
		_inputs[id] = input


func tick(prediction_player: int = -1) -> void:
	# Client prediction advances only its actor; damage, AI and rewards remain authoritative.
	events.clear()
	var ids := bodies.keys() if prediction_player < 0 else [prediction_player]
	ids.sort()
	# Monsters take turns attacking: only a few may be mid-attack at once, the rest wait their turn.
	var attack_slots := 0
	if combat != null and prediction_player < 0:
		attack_slots = int(combat.rules["enemy_max_attackers"])
		for id in fighters:
			if _ai.has(id) and fighters[id].state == Fighter.State.ATTACK:
				attack_slots -= 1
	for id in ids:
		var body: SimBody = bodies[id]
		var input: SimInput = _inputs[id]
		if combat != null and fighters.has(id):
			var fighter: Fighter = fighters[id]
			if _ai.has(id):
				input = _ai[id].think(fighter, body, bodies, fighters, rng, attack_slots > 0)
				if input.light or input.heavy or input.special:
					attack_slots -= 1
			else:
				input = _with_aim_assist(fighter, body, input,id)
				# Race ultimates (GDD races 3.10.6): a squad card's ultimate press starts its race ultimate, never the
				# weapon style's. Prediction leaves it to the authority.
				var race_ult: bool = input.ultimate and RacePassives.owns_gauge(fighter) and not fighter.race_state.get("ultimate", {}).is_empty()
				if race_ult:
					input = input.duplicate_input()
					input.ultimate = false
					if prediction_player < 0 and RacePassives.RaceUltimates.start(self, id):
						input = SimInput.new()
				# Players cast class skills by slot (class-skills.md); the old weapon special/ultimate buttons are off.
				input = input.duplicate_input()
				input.special = false
				input.ultimate = false
				if prediction_player < 0 and ClassSkills.has_skills(fighter) and input.skill_slot >= 0:
					_cast_class_skill(id, fighter, body, input)
			if ClassSkills.busy(fighter):
				input = SimInput.new()  # inside a class-skill clip window: no move, attack or other skill (class-skills.md 3.1 rule 6)
			if fighter.hitstop > 0:
				fighter.hitstop -= 1
				continue  # frozen for a moment after a hit
			input = Combat.update_fighter(id, fighter, body, input, combat, events)
			if not fighter.skill_view.is_empty():
				body.move_speed_multiplier *= float(fighter.skill_view.get("movement",1)) * float(fighter.skill_view.get("move_mul",1))
				if float(fighter.skill_view.get("movement",1)) <= 0:
					input = SimInput.new()
					body.knockback = Vector2.ZERO
					body.velocity.x = 0
					body.velocity.z = 0
					if fighter.state == Fighter.State.ATTACK:
						fighter.state = Fighter.State.IDLE
						fighter.move_id = ""
						fighter.buffered = ""
		Movement.step(id, body, input, world, events)
	if prediction_player>=0 and combat!=null and fighters.has(prediction_player):
		Combat.predict_attacker_hitstop(prediction_player,fighters,bodies,combat,melee_target_boxes)
		_predict_class_travel(prediction_player)
	if combat != null and prediction_player < 0:
		for fighter in fighters.values():preload("res://logic/relic_effects.gd").tick(fighter)
		Projectiles.step(_ranged, fighters, bodies, world, combat, rng, events)
		Projectiles.spawn_from_moves(_ranged, fighters, bodies, world, combat, events)  # (they move from the next tick on)
		projectiles = _ranged["projectiles"]
		areas = _ranged["areas"]
		Combat.resolve_hits(fighters, bodies, combat, rng, events,melee_target_boxes)
		ClassSkills.step(self)  # class skills: travel, releases, counters, orbs (logic/class_skills/engine.gd)
		_release_waves()
		RacePassives.step(self)  # after hits, skills and waves of this tick: race triggers react to them
		_check_stage_clear()
		_process_economy()
		Coop.step(self)
	tick_count += 1


## Owner prediction of a class-skill cast the authority already started (it arrives in skill_state via the actor
## continuation): the body follows the cast's travel frames and the cast ends on its end tick, exactly as
## ClassSkills.step does on the authority, so the caster's own client does not stand still and get corrected.
## Releases, hits, pulls and events stay authority-only (logic/net/skill_net.gd, network-programmer 2026-11-13).
func _predict_class_travel(id: int) -> void:
	var fighter: Fighter = fighters[id]
	var cast: Dictionary = fighter.skill_state.get("cast", {})
	if cast.is_empty() or not fighter.is_alive() or fighter.incapacitated:
		return
	ClassSkills._travel(self, id, cast)
	if tick_count >= int(cast.get("end", 0)):
		fighter.skill_state["cast"] = {}


## A squad card pressed skill slot 0..3 (the auto-pilot, logic/class_skills/use_rules.gd): the authority re-reads the
## skill's use rule for its target/point (deterministic), else aims at the enemy nearest the aimed point.
func _cast_class_skill(id: int, fighter: Fighter, body: SimBody, input: SimInput) -> void:
	var skills: Array = fighter.skill_state.get("skills", [])
	if input.skill_slot >= skills.size():
		return
	var skill := str(skills[input.skill_slot])
	var direction := input.aim.normalized() if input.aim != Vector2.ZERO else Vector2(fighter.direction).normalized()
	var point := body.position + Vector3(direction.x, 0, direction.y) * input.aim_distance
	var aimed := -1
	var best := INF
	for other_id in fighters:
		if fighters[other_id].team != fighter.team and fighters[other_id].is_alive():
			var d := Vector2(bodies[other_id].position.x - point.x, bodies[other_id].position.z - point.z).length()
			if d < best:
				best = d
				aimed = other_id
	var choice: Dictionary = ClassSkillUse.choose(self, id, skill, aimed)
	if choice.is_empty():
		choice = {"target": aimed, "point": point}
	ClassSkills.cast(self, id, skill, choice)


## Everything a client needs to draw the current state (and what will be sent over the network).
func snapshot() -> Dictionary:
	var players := {}
	for id in bodies:
		var body: SimBody = bodies[id]
		players[id] = {"position": body.position, "velocity": body.velocity, "grounded": body.grounded}
	var fighter_states := {}
	for id in fighters:
		var fighter: Fighter = fighters[id]
		fighter_states[id] = {
			"hp": fighter.hp, "state": fighter.state, "facing": fighter.facing, "direction": fighter.direction,
			"move": fighter.move_id, "frame": fighter.move_frame,
			"gauge": fighter.gauge, "dodge_cooldown": fighter.dodge_cooldown,
			"energy": fighter.energy, "combo": fighter.combo_dealt, "effects": fighter.effects.duplicate(true),
		}
	return {"v": 1, "tick": tick_count, "players": players, "fighters": fighter_states, "projectiles": projectiles.duplicate(true), "areas": areas.duplicate(true), "checkpoint": _checkpoint()}


## Aim assist: when a player attacks without holding a direction, they turn toward the nearest
## enemy that is close enough, so fighting in eight directions never needs a pixel-perfect aim.
## (attack_assist_range in the combat data; 0 turns it off.)
func _with_aim_assist(fighter: Fighter, body: SimBody, input: SimInput,owner:int=-1) -> SimInput:
	var range_limit := float(combat.rules["attack_assist_range"])
	if range_limit <= 0.0 or fighter.state != Fighter.State.IDLE:
		return input
	if not (input.light or input.heavy or input.special) or input.move.length() > 0.1 or input.aim != Vector2.ZERO:
		return input
	var nearest := range_limit
	var toward := Vector2.ZERO
	for other_id in fighters:
		var other: Fighter = fighters[other_id]
		if other.team == fighter.team or not other.is_alive():
			continue
		var target_position:Vector3=bodies[other_id].position
		if other.team=="enemy" and melee_target_boxes.get(owner,{}).has(other_id):
			var historical:AABB=melee_target_boxes[owner][other_id]
			target_position=historical.get_center()
		var delta := Vector2(target_position.x - body.position.x, target_position.z - body.position.z)
		if delta.length() < nearest:
			nearest = delta.length()
			toward = delta
	if toward == Vector2.ZERO:
		return input
	var aimed: SimInput = input.duplicate_input()
	aimed.aim = toward
	return aimed


## The race engine's taunt hook (GDD races 3.6 aggro/pulse_aggro): monster `id` attacks fighter `by` for `ticks`.
## Returns false for a fighter without a brain (a player) or when a longer taunt is already running.
func taunt_enemy(id: int, by: int, ticks: int) -> bool:
	return _ai.has(id) and fighters[id].is_alive() and _ai[id].taunt(by, ticks)


func living_enemy_count() -> int:
	var count := 0
	for id in fighters:
		if fighters[id].team == "enemy" and fighters[id].is_alive():
			count += 1
	return count


func _add_body(id: int, spawn: Vector3) -> SimBody:
	var body := SimBody.new()
	body.position = spawn
	bodies[id] = body
	_inputs[id] = SimInput.new()
	return body


func _add_fighter(id: int, body: SimBody, team: String, style: String, stats: Dictionary) -> void:
	var fighter := Fighter.new()
	fighter.team = team
	fighter.style = style
	fighter.stats = stats
	fighter.hp = fighter.max_hp()
	fighter.energy = fighter.max_energy()
	fighters[id] = fighter
	body.move_speed_multiplier = Stats.move_multiplier(stats)


## Loot and wear, reacting to what happened this tick: kills drop loot into the killer's bag, damage
## wears the armor of the one hurt, hits wear the weapon, and a player's death empties their bag.
func _process_economy() -> void:
	if runs.is_empty() or item_rules == null:
		return
	for event in events.duplicate():
		match event["type"]:
			"hit", "blocked", "skill_hit":
				if runs.has(event["target"]):
					_wear_armor(event["target"], float(event["damage"]))
				if event["type"] in ["hit", "skill_hit"] and runs.has(event["attacker"]):
					if Wear.hit_landed(runs[event["attacker"]].loadout(), item_rules):
						_refresh_run_stats(event["attacker"])
			"dot", "skill_dot":
				if runs.has(event["target"]):
					_wear_armor(event["target"], float(event["damage"]))
			"killed":
				var target := int(event["target"])
				if coop_enabled and runs.has(target) and not fighters[target].eliminated:
					Coop.down(self, target, event)
				else:
					_on_killed(target, int(event.get("by", -1)))


func _wear_armor(id: int, damage: float) -> void:
	if Wear.damage_taken(runs[id].loadout(), item_rules, damage, fighters[id].max_hp()):
		_refresh_run_stats(id)


func _on_killed(target_id: int, killer_id: int) -> void:
	if runs.has(target_id):
		_finalize_player_death(target_id)
		return
	if loot_data == null or not fighters.has(target_id) or fighters[target_id].enemy_type.is_empty():
		return
	if _coop["paid"].has(target_id): return
	_coop["paid"][target_id] = true
	if coop_enabled:
		# One drop per kill per bag: a squad shares one bag (Boss 2026-11-11), so it gets one drop, given to
		# its first living member; separate players (online party) each still get their own.
		var paid_bags: Array = []
		for id in _coop["players"]:
			if runs.has(id) and not runs[id].died and not paid_bags.has(runs[id].bag):
				paid_bags.append(runs[id].bag)
				_give_drop(target_id, id)
	elif runs.has(killer_id):
		_give_drop(target_id, killer_id)


func _finalize_player_death(target_id: int) -> void:
	var run: Run = runs[target_id]
	if run.died: return
	run.death()
	Wear.death(run.loadout(), item_rules)
	events.append({"type": "bag_saved", "player": target_id})


func _give_drop(target_id: int, killer_id: int) -> void:
	var dead: Fighter = fighters[target_id]
	var roll_rng := rng
	var factor := loot_factor
	if loot_players.has(killer_id):
		roll_rng = _personal_loot_rng(target_id, killer_id)
		factor = float(loot_players[killer_id][1])
	var drop := Loot.roll(item_rules, loot_data, dead.enemy_type, dead.level, combat.weapon_ids, roll_rng, factor)
	drop["relics"]=load("res://logic/relics.gd").roll(dead.enemy_type,roll_rng,factor)
	# Race gear (design/gdd/race-gear-sets.md 3.12): a share of the dropped pieces become race pieces of a squad card;
	# the boss's own drops use the boss shares (the only gold race source). Own RNG: the sim stream is unchanged.
	var RaceDrops = load("res://logic/race_drops.gd")
	var source: String = RaceDrops.BOSS if RaceDrops.is_boss_type(dead.enemy_type) else RaceDrops.WAVE
	drop["items"] = RaceDrops.apply(item_rules, drop["items"], RaceDrops.picks_for(runs[killer_id]), source, reward_wave if reward_wave > 0 else _waves_released + 1)
	var stored: Dictionary = runs[killer_id].loot_into_bag(drop)
	var item_summaries: Array[Dictionary] = []
	for item in stored["items"]:
		item_summaries.append({"slot": item.slot, "tier": item.tier, "weapon_type": item.weapon_type, "item_id": item.item_id})
	events.append({
		"type": "loot", "player": killer_id, "enemy": target_id, "gold": stored["gold"], "materials": stored["materials"],
		"relics": stored.relics, "items": item_summaries, "lost_items": stored["lost_items"].size(), "lost_materials": stored["lost_materials"],
	})


## Personal loot (online-squads 3.5): the player's own stream per kill, seeded from (sim seed, enemy, player slot), so
## neither the sim stream nor another player's roll depends on how many players the room has.
func _personal_loot_rng(target_id: int, fighter_id: int) -> RandomNumberGenerator:
	var personal := RandomNumberGenerator.new()
	personal.seed = hash([rng.seed, "kill-%d-%d" % [target_id, int(loot_players[fighter_id][0])]])
	return personal


## Recomputes a trip-player's stats from the gear (which wears) and camp skills. Health never goes above the new maximum.
func _refresh_run_stats(id: int) -> void:
	var fighter: Fighter = fighters[id]
	fighter.stats = combat.full_stats(runs[id].stats(item_rules))
	RacePassives.apply_stats(fighter)  # race/synergy stat_mod (HP, ATK ...) on top of gear
	fighter.hp = minf(fighter.hp, fighter.max_hp())
	bodies[id].move_speed_multiplier = Stats.move_multiplier(fighter.stats)


## Queues a wave of monsters that joins the fight later: when fighter `watch` drops below
## `watch_hp_below` of its max HP (watch = -1: never by HP), or when every monster on the field is down.
## Each entry: {"id", "position", "type", "level", "hp_scale"?, "atk_scale"?}. Waves come in queue order.
## Tells the client with a "wave_arrived" event {"wave": 2.., "enemies": [ids]}.
func queue_wave(entries: Array, watch: int = -1, watch_hp_below: float = 0.0) -> void:
	_waves.append({"enemies": entries, "watch": watch, "watch_hp_below": watch_hp_below})
	_had_enemies = true


func pending_wave_count() -> int:
	return _waves.size()


func _release_waves() -> void:
	if _waves.is_empty():
		return
	var wave: Dictionary = _waves[0]
	var watched: Fighter = fighters.get(int(wave["watch"]))
	var by_hp := watched != null and watched.is_alive() and watched.hp < watched.max_hp() * float(wave["watch_hp_below"])
	if not by_hp and living_enemy_count() > 0:
		return
	_waves.pop_front()
	if wave_heal_fraction > 0.0:
		for healed_id in fighters:
			var healed: Fighter = fighters[healed_id]
			if healed.team != "enemy" and healed.is_alive():
				healed.hp = minf(healed.max_hp(), healed.hp + healed.max_hp() * wave_heal_fraction)
	var ids: Array[int] = []
	for entry in wave["enemies"]:
		var id := int(entry["id"])
		add_enemy(id, entry["position"], str(entry["type"]), int(entry["level"]))
		var fighter: Fighter = fighters[id]
		fighter.stats["HP"] = float(fighter.stats["HP"]) * float(entry.get("hp_scale", 1.0))
		fighter.stats["ATK"] = float(fighter.stats["ATK"]) * float(entry.get("atk_scale", 1.0))
		fighter.hp = fighter.max_hp()
		fighter.max_poise *= float(entry.get("poise_scale", 1.0))  # wave-mode boss: journey boss poise_mult
		fighter.poise = fighter.max_poise
		ids.append(id)
	_waves_released += 1
	events.append({"type": "wave_arrived", "wave": _waves_released + 1, "enemies": ids})


func _check_stage_clear() -> void:
	if _had_enemies and not _clear_reported and living_enemy_count() == 0:
		_clear_reported = true
		events.append({"type": "stage_cleared"})


const StateCodec := preload("res://logic/state_codec.gd")
## 2: squad members (logic/squad_member.gd) share one saved Run ("squads"). A checkpoint without the field is
## version 1 (separate runs only) and still loads; a newer version is rejected.
const CHECKPOINT_VERSION := 2

## Complete continuation state, separate from the legacy drawing summary above.
## Rules stay external; world, AI configuration and mutable run ownership are included.
func _checkpoint() -> Array:
	var body_data := {}
	var fighter_data := {}
	var ai_data := {}
	var input_data := {}
	var run_data := {}
	for id in bodies:
		body_data[id] = StateCodec.fields(bodies[id])
	for id in fighters:
		fighter_data[id] = StateCodec.fields(fighters[id], ["facing", "skill_hit_filter", "skill_base_hit"])
	for id in _ai:
		ai_data[id] = StateCodec.fields(_ai[id], ["world"])
	for id in _inputs:
		input_data[id] = StateCodec.fields(_inputs[id])
	# A squad's members share one Run: save it once in "squads" and only the member fields per fighter.
	var squads: Array = []
	var shared_runs: Array = []
	for id in runs:
		if runs[id] is SquadMember:
			var at := shared_runs.find(runs[id].shared)
			if at < 0:
				at = shared_runs.size()
				shared_runs.append(runs[id].shared)
				squads.append(runs[id].shared.to_dict())
			run_data[id] = runs[id].member_fields()
			run_data[id]["squad"] = at
		else:
			run_data[id] = runs[id].to_dict()
	return StateCodec.pack({"checkpoint_v": CHECKPOINT_VERSION, "squads": squads,"world": StateCodec.fields(world), "bodies": body_data,
		"fighters": fighter_data, "ai": ai_data, "inputs": input_data, "runs": run_data,
		"rng_seed": rng.seed, "rng_state": rng.state, "tick": tick_count,
		"ranged": _ranged, "events": events, "waves": _waves, "waves_released": _waves_released,
		"coop": _coop, "had_enemies": _had_enemies, "clear_reported": _clear_reported,
		"wave_heal_fraction": wave_heal_fraction, "class_styles": class_styles, "loot_factor": loot_factor, "reward_wave": reward_wave, "loot_players": loot_players})


## Restore into a sim constructed with the same combat/rules. Supply camp data if runs exist.
## Returns false before mutation for incompatible version/missing rule dependencies.
func restore(saved: Dictionary, camp_data = null) -> bool:
	if int(saved.get("v", 0)) != 1 or not saved.has("checkpoint"):
		return false
	var d: Dictionary = StateCodec.unpack(saved["checkpoint"])
	if not d["fighters"].is_empty() and combat == null:
		return false
	if not d["runs"].is_empty() and (item_rules == null or loot_data == null or camp_data == null):
		return false
	var version := int(d.get("checkpoint_v", 1))
	if version < 1 or version > CHECKPOINT_VERSION:
		return false
	var restored_runs := {}
	var squad_ids: Array = []  ## per saved squad: its member ids in fighter order
	for squad in d.get("squads", []):
		squad_ids.append([])
	for id in d["runs"]:
		if d["runs"][id].has("squad"):
			var at := int(d["runs"][id]["squad"])
			if at < 0 or at >= squad_ids.size():
				return false
			squad_ids[at].append(id)
			continue
		var trip = Run.from_dict(d["runs"][id], item_rules, camp_data)
		if trip == null:
			return false
		restored_runs[id] = trip
	for at in squad_ids.size():
		var base = Run.from_dict(d["squads"][at], item_rules, camp_data)
		if base == null or squad_ids[at].is_empty():
			return false
		var ids: Array = squad_ids[at]
		ids.sort()
		var members := SquadMember.make_squad(base, ids.map(func(id): return str(d["runs"][id].get("card", ""))))
		for i in ids.size():
			if not base.profile.card_gear.has(members[i].card_id):
				return false
			members[i].apply_member_fields(d["runs"][ids[i]])
			restored_runs[ids[i]] = members[i]
	StateCodec.apply_fields(world, d["world"])
	bodies.clear()
	fighters.clear()
	_ai.clear()
	_inputs.clear()
	runs = restored_runs
	for id in d["bodies"]:
		var body := SimBody.new()
		StateCodec.apply_fields(body, d["bodies"][id])
		bodies[id] = body
	for id in d["fighters"]:
		var fighter := Fighter.new()
		StateCodec.apply_fields(fighter, d["fighters"][id])
		fighters[id] = fighter
	for id in d["ai"]:
		var brain := EnemyAI.new()
		StateCodec.apply_fields(brain, d["ai"][id])
		brain.world = world
		_ai[id] = brain
	for id in d["inputs"]:
		var input := SimInput.new()
		StateCodec.apply_fields(input, d["inputs"][id])
		_inputs[id] = input
	rng.seed = d["rng_seed"]
	rng.state = d["rng_state"]
	tick_count = d["tick"]
	_ranged = d["ranged"]
	projectiles = _ranged["projectiles"]
	areas = _ranged["areas"]
	events.assign(d["events"])
	_waves = d["waves"]
	_waves_released = d["waves_released"]
	_coop = d.get("coop", {"enabled": false, "players": [], "wiped": false, "paid": {}})
	_had_enemies = d["had_enemies"]
	_clear_reported = d["clear_reported"]
	wave_heal_fraction = float(d.get("wave_heal_fraction", 0.0))
	loot_factor = float(d.get("loot_factor", 1.0))
	loot_players = {}
	for fid in d.get("loot_players", {}):
		loot_players[int(fid)] = [int(d["loot_players"][fid][0]), float(d["loot_players"][fid][1])]
	reward_wave = int(d.get("reward_wave", -1))
	class_styles = d.get("class_styles", {}).duplicate()
	# (an old checkpoint's "skill_system" block belongs to the deleted skill-build runtime: ignored)
	for id in fighters:  # race ultimate moves are built at attach; a restored sim may have fresh combat data
		RacePassives.RaceUltimates.register_move(combat, fighters[id])
	return true


func enable_coop(player_ids: Array) -> bool:
	if combat == null or combat.coop.is_empty() or player_ids.size() < 2 or player_ids.size() > int(combat.coop.get("max_fighters", combat.coop["max_players"])):
		return false
	var ids := player_ids.duplicate()
	ids.sort()
	var seen := {}
	for id in ids:
		if seen.has(id) or not runs.has(id) or not fighters.has(id) or fighters[id].team != "player": return false
		seen[id] = true
	_coop = {"enabled": true, "players": ids, "wiped": false, "paid": {}}
	return true
