extends RefCounted
## Buffs and debuffs (status effects): applying them, ticking them (damage over time, healing over
## time, running out), and the cached results the fighting rules read (stat changes, whether the
## fighter can act or move). The effect definitions are data (data/combat/effects.json).
## A fighter's `effects` hold {effect id -> {"left", "stacks", "dps", "age", "source"}}.
## EXTENDING: a new effect is a data entry; a new kind of behavior (a new `control` value, a new
## per-tick result) is a branch in refresh() / tick() here and the rule that reads it in combat.gd.

const CombatData := preload("res://logic/combat_data.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")

const CONTROLS_THAT_STOP_ACTION: Array[String] = ["stun", "sleep"]


## Applies one entry of a move's `effects` list from `source` to `target`. Returns true if it took hold.
## A debuff's chance is moved by the source's EFFECT_ACC against the target's EFFECT_RES; a control
## effect cannot land while the target is still immune from the last one. Uses a random number only
## when the chance is neither certain nor impossible.
static func apply(source_id: int, source: Fighter, target_id: int, target: Fighter, entry: Dictionary, data: CombatData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> bool:
	var effect_id: String = entry["id"]
	var definition: Dictionary = data.effects[effect_id]
	if not target.is_alive():
		return false
	if definition["control"] != "" and target.control_immune_left > 0:
		events.append({"type": "effect_resisted", "target": target_id, "effect": effect_id})
		return false
	var chance := float(entry["chance"])
	if definition["kind"] == "debuff" and source != target:
		chance += source.stat("EFFECT_ACC") - target.stat("EFFECT_RES")
	chance = clampf(chance, 0.0, 100.0)
	if chance <= 0.0 or (chance < 100.0 and rng.randf() * 100.0 >= chance):
		events.append({"type": "effect_resisted", "target": target_id, "effect": effect_id})
		return false
	var duration: int = int(entry["duration"]) if int(entry["duration"]) > 0 else int(definition["duration"])
	var instance: Dictionary = target.effects.get(effect_id, {"stacks": 0, "age": 0})
	instance["stacks"] = mini(int(definition["max_stacks"]), int(instance["stacks"]) + 1)
	instance["left"] = duration
	instance["dps"] = source.stat("ATK") * float(definition["dot_power"])  # fixed when it lands
	instance["source"] = source_id
	target.effects[effect_id] = instance
	refresh(target, data)
	events.append({"type": "effect_applied", "target": target_id, "effect": effect_id, "stacks": int(instance["stacks"]), "source": source_id})
	return true


## Applies the entries of `entries` that fire at `moment` ("hit" or "cast") for one attacker/target pair.
static func apply_move_effects(entries: Array, moment: String, attacker_id: int, attacker: Fighter, target_id: int, target: Fighter, data: CombatData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	for entry in entries:
		if entry["on"] != moment:
			continue
		if entry["target"] == "self":
			apply(attacker_id, attacker, attacker_id, attacker, entry, data, rng, events)
		elif target != null:
			apply(attacker_id, attacker, target_id, target, entry, data, rng, events)


## Advances every effect on a fighter by one tick: damage over time, healing over time, running out.
static func tick(id: int, fighter: Fighter, data: CombatData, events: Array[Dictionary]) -> void:
	if not fighter.is_alive():
		if not fighter.effects.is_empty():
			fighter.effects.clear()
			refresh(fighter, data)
		return
	if fighter.effects.is_empty():
		if fighter.control_immune_left > 0:
			fighter.control_immune_left -= 1
		return
	var interval := int(data.rules["dot_interval_ticks"])
	var ended: Array[String] = []
	var controlled := false
	var hurt := false
	for effect_id in fighter.effects:
		var instance: Dictionary = fighter.effects[effect_id]
		var definition: Dictionary = data.effects[effect_id]
		instance["age"] = int(instance["age"]) + 1
		instance["left"] = int(instance["left"]) - 1
		if definition["control"] != "":
			controlled = true
		if float(definition["heal_percent"]) > 0.0:
			var heal: float = fighter.max_hp() * float(definition["heal_percent"]) / 100.0 / 60.0 * int(instance["stacks"]) * fighter.heal_factor()
			fighter.hp = minf(fighter.max_hp(), fighter.hp + heal)
		if float(definition["dot_power"]) > 0.0 and int(instance["age"]) % interval == 0:
			var damage := maxf(1.0, roundf(float(instance["dps"]) * int(instance["stacks"]) * float(interval) / 60.0))
			if bool(instance.get("exact_dot",false)):damage=maxf(0,float(instance["dps"])*float(interval)/60.0)
			if _damage_over_time(id, fighter, damage, effect_id, int(instance["source"]), data, events):
				return  # died: everything was cleared
			hurt = true
		if int(instance["left"]) <= 0:
			ended.append(effect_id)
	for effect_id in ended:
		if fighter.effects.has(effect_id):
			_end(id, fighter, effect_id, data, events)
	if hurt:
		wake(id, fighter, data, events)  # damage over time wakes a sleeper too
	if controlled:
		fighter.control_immune_left = int(data.rules["control_immunity_ticks"])
	elif fighter.control_immune_left > 0:
		fighter.control_immune_left -= 1


## A real hit woke the fighter: effects that break on damage end (sleep), and the control immunity starts.
static func wake(id: int, fighter: Fighter, data: CombatData, events: Array[Dictionary]) -> void:
	for effect_id in fighter.effects.keys():
		if data.effects[effect_id]["break_on_damage"]:
			_end(id, fighter, effect_id, data, events)
			fighter.control_immune_left = int(data.rules["control_immunity_ticks"])


## Removes every effect of a fighter (dying, leaving the stage).
static func clear(fighter: Fighter, data: CombatData) -> void:
	fighter.effects.clear()
	refresh(fighter, data)


## Recomputes what the effects on a fighter add up to: stat changes and the action limits.
static func refresh(fighter: Fighter, data: CombatData) -> void:
	var mods := {}
	fighter.incapacitated = false
	fighter.rooted = false
	for effect_id in fighter.effects:
		var definition: Dictionary = data.effects[effect_id]
		var stacks: int = int(fighter.effects[effect_id]["stacks"])
		for stat in definition["stats"]:
			var entry: Dictionary = mods.get(stat, {"add": 0.0, "mul": 0.0})
			entry["add"] += float(definition["stats"][stat].get("add", 0.0)) * stacks
			entry["mul"] += float(definition["stats"][stat].get("mul", 0.0)) * stacks
			mods[stat] = entry
		if CONTROLS_THAT_STOP_ACTION.has(definition["control"]):
			fighter.incapacitated = true
		elif definition["control"] == "shock":
			fighter.rooted = true
	fighter.stat_mods = mods


## The input a rooted (shocked) fighter may use: it can turn, attack and guard but not move, jump, run or dodge.
static func rooted_input(input: SimInput) -> SimInput:
	var limited: SimInput = input.duplicate_input()
	limited.move = Vector2.ZERO
	limited.jump = false
	limited.run = false
	limited.dodge = false
	if input.move != Vector2.ZERO and input.aim == Vector2.ZERO:
		limited.aim = input.move  # still turns toward where it tried to go
	return limited


static func _end(id: int, fighter: Fighter, effect_id: String, data: CombatData, events: Array[Dictionary]) -> void:
	fighter.effects.erase(effect_id)
	refresh(fighter, data)
	events.append({"type": "effect_ended", "target": id, "effect": effect_id})


## Returns true if the damage killed the fighter.
static func _damage_over_time(id: int, fighter: Fighter, damage: float, effect_id: String, source_id: int, data: CombatData, events: Array[Dictionary]) -> bool:
	var absorbed := fighter.absorb(damage)  # race shield first (GDD races 4.3)
	fighter.hp = maxf(0.0, fighter.hp - (damage - absorbed))
	events.append({"type": "dot", "target": id, "effect": effect_id, "damage": damage if effect_id=="relic_goblin_poison" else int(damage), "absorbed": absorbed})
	if fighter.hp <= 0.0:
		fighter.launched = false
		fighter.move_id = ""
		fighter.buffered = ""
		fighter.state = Fighter.State.DEAD
		fighter.state_ticks = 0
		clear(fighter, data)
		events.append({"type": "killed", "target": id, "by": source_id})
		return true
	return false
