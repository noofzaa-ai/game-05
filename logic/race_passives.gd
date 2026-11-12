extends RefCounted
## Race passives and squad synergy bonuses at fight time (design/gdd/races-and-classes.md 3.4-3.6, 4.2, phase 2 + 5).
## Pure rules. Each squad fighter carries `Fighter.race_state` (plain data, saved in GameSim checkpoints):
##   {"race", "class", "passive", "synergy", "effects": [{"src": "passive"|"synergy", "effect": {...}}],
##    "fx": {index: {"last", "n", "wave", "low"}}, "pseudo": {stat: {"add", "mul"}}, "wave", "heal_window": [tick, amount]}
## What runs now: `stat_mod` (real stats on the stat refresh, HEALING via Fighter.heal_factor) and `trigger` with the
## actions `apply_status`, `heal` and `shield` (Fighter.shield, 4.3), on the events wave_start, hit, heavy_hit, skill_cast, skill_hit, kill, hurt,
## guard_block, self_low_hp (fields: chance, every_n, cooldown_ticks, once_per_wave, hp_below).
## `low_hp_scaling` (4.1) is read live by Fighter.stat through scaling_mul (race_state.scaling).
## INERT until their phase-4 feature exists (loaded and validated, no effect): skill_mod, charges,
## aggro, and the actions burst, pulse_aggro, zone, skill_refresh. The event ultimate_cast never fires yet.
## Deterministic: a `chance` roll uses the sim RNG; nothing else is random. Order = fighter id, then effect order.

const CardDeck := preload("res://logic/card_deck.gd")
const RaceData := preload("res://logic/race_data.gd")
const Effects := preload("res://logic/effects.gd")
const RUNNING_ACTIONS: Array[String] = ["apply_status", "heal", "shield"]
const SHIELD_TICKS := 600  ## default shield life when an action has no duration_ticks (GDD 4.3)


## Gives a squad member's fighter its card's race passive and the squad's synergy bonus. A trip that is not a squad
## member (old single-profile runs, test trips) gets no race.
static func attach(fighter, run) -> void:
	fighter.race_state = {}
	if run == null or not "card_id" in run or str(run.card_id).is_empty():
		return
	var races = RaceData.load_default()
	if not races.errors.is_empty():
		return
	var class_id := str(run.card_id)
	var race := CardDeck.race_of(run.profile.card_deck, class_id)
	var passive: Dictionary = races.passive_for(race, class_id)
	var synergy: Dictionary = run.synergy() if run.has_method("synergy") else {}
	var effects: Array = []
	for effect in passive.get("effects", []):
		effects.append({"src": "passive", "effect": effect.duplicate(true)})
	for effect in synergy.get("effects", []):
		effects.append({"src": "synergy", "effect": effect.duplicate(true)})
	var pseudo := {}
	var scaling: Array = []
	for entry in effects:
		if entry["effect"]["type"] == "low_hp_scaling":
			scaling.append(entry["effect"])
		var effect: Dictionary = entry["effect"]
		if effect["type"] == "stat_mod" and not RaceData.STAT_NAMES.has(str(effect["stat"])):
			var mod: Dictionary = pseudo.get(str(effect["stat"]), {"add": 0.0, "mul": 0.0})
			mod["add"] += float(effect.get("add", 0.0))
			mod["mul"] += float(effect.get("mul", 0.0))
			pseudo[str(effect["stat"])] = mod
	fighter.race_state = {"race": race, "class": class_id, "passive": str(passive.get("name", "")), "synergy": str(synergy.get("kind", "none")),
		"effects": effects, "fx": {}, "pseudo": pseudo, "scaling": scaling, "wave": 0, "heal_window": [-1, 0.0]}


## stat_mod on real stats, applied to freshly computed base stats (GameSim._refresh_run_stats): (base + add) x (1 + mul).
static func apply_stats(fighter) -> void:
	for entry in fighter.race_state.get("effects", []):
		var effect: Dictionary = entry["effect"]
		if effect["type"] != "stat_mod" or not RaceData.STAT_NAMES.has(str(effect["stat"])):
			continue
		var stat := str(effect["stat"])
		fighter.stats[stat] = (float(fighter.stats.get(stat, 0.0)) + float(effect.get("add", 0.0))) * (1.0 + float(effect.get("mul", 0.0)))


## Extra stat multiplier from every low_hp_scaling effect on `stat_name` at the fighter's current HP (summed, 4.1).
static func scaling_mul(fighter, stat_name: String) -> float:
	var total := 0.0
	var h: float = clampf(fighter.hp / maxf(1.0, fighter.max_hp()), 0.0, 1.0)
	for effect in fighter.race_state.get("scaling", []):
		if str(effect["stat"]) == stat_name:
			total += low_hp_bonus(effect, h)
	return total


## Formula 4.1: bonus = max_mul x clamp((from_hp - h) / (from_hp - full_at_hp), 0, 1), h = HP / max HP.
## With `below`: a step, 0 at h >= below, max_mul under it.
static func low_hp_bonus(effect: Dictionary, h: float) -> float:
	var max_mul := float(effect["max_mul"])
	if effect.has("below"):
		return max_mul if h < float(effect["below"]) else 0.0
	var from_hp := float(effect.get("from_hp", 1.0))
	var full_at := float(effect.get("full_at_hp", 0.2))
	if from_hp <= full_at:
		return max_mul if h <= full_at else 0.0
	return max_mul * clampf((from_hp - h) / (from_hp - full_at), 0.0, 1.0)


## Healing received multiplier from race pseudo-stat HEALING (Elf default/pair/trio), for Fighter.heal_factor.
static func healing_factor(fighter) -> float:
	var mod: Dictionary = fighter.race_state.get("pseudo", {}).get("HEALING", {})
	if mod.is_empty():
		return 1.0
	return maxf(0.0, (1.0 + float(mod.get("add", 0.0))) * (1.0 + float(mod.get("mul", 0.0))))


## One authoritative tick: reads this tick's sim events and fires the matching triggers. Call after hits, skills
## and wave releases resolved (GameSim.tick).
static func step(sim) -> void:
	var ids: Array = []
	for id in sim.fighters:
		if not sim.fighters[id].race_state.is_empty():
			ids.append(id)
	if ids.is_empty():
		return
	ids.sort()
	var wave: int = sim._waves_released + 1
	var seen: Array = sim.events.duplicate()
	for id in ids:
		var fighter = sim.fighters[id]
		if not fighter.is_alive():
			continue
		if fighter.shield_until >= 0 and sim.tick_count >= fighter.shield_until:
			_end_shield(sim, id, fighter, "expired")
		if int(fighter.race_state["wave"]) != wave:
			if int(fighter.race_state["wave"]) != 0 and fighter.shield > 0.0:
				_end_shield(sim, id, fighter, "wave_end")  # shields are cleared at wave end (4.3)
			fighter.race_state["wave"] = wave
			fire(sim, id, "wave_start", {})
		for event in seen:
			for raced in race_events(id, fighter, event, sim.fighters):
				fire(sim, id, raced, event)
		_check_low_hp(sim, id, fighter)


## The race events one sim event means for fighter `id` (the doc's event list, 3.6).
static func race_events(id: int, fighter, event: Dictionary, fighters: Dictionary) -> Array:
	var out: Array = []
	match str(event.get("type", "")):
		"hit":
			if int(event.get("attacker", -1)) == id and not str(event.get("move", "")).ends_with("ultimate"):
				out.append("hit")
				if str(event.get("move", "")).contains("heavy"):
					out.append("heavy_hit")
			if int(event.get("target", -1)) == id and float(event.get("damage", 0)) > 0.0:
				out.append("hurt")
		"skill_hit":
			if int(event.get("attacker", -1)) == id:
				out.append("skill_hit")
			if int(event.get("target", -1)) == id and float(event.get("damage", 0)) > 0.0:
				out.append("hurt")
		"blocked":
			if int(event.get("target", -1)) == id:
				out.append("guard_block")
		"skill_cast":
			if int(event.get("player", -1)) == id:
				out.append("skill_cast")
		"killed":
			var target := int(event.get("target", -1))
			if int(event.get("by", -1)) == id and fighters.has(target) and fighters[target].team != fighter.team:
				out.append("kill")
	return out


## Fires every trigger of fighter `id` listening to `event_name`. `context` is the sim event (target, damage).
static func fire(sim, id: int, event_name: String, context: Dictionary) -> void:
	var fighter = sim.fighters[id]
	var effects: Array = fighter.race_state.get("effects", [])
	for index in effects.size():
		var effect: Dictionary = effects[index]["effect"]
		if effect["type"] != "trigger" or str(effect["on"]) != event_name:
			continue
		var fx: Dictionary = fighter.race_state["fx"].get(str(index), {"last": -1, "n": 0, "wave": 0, "low": false})
		fighter.race_state["fx"][str(index)] = fx
		if int(effect.get("cooldown_ticks", 0)) > 0 and int(fx["last"]) >= 0 and sim.tick_count - int(fx["last"]) < int(effect["cooldown_ticks"]):
			continue
		if bool(effect.get("once_per_wave", false)) and int(fx["wave"]) == int(fighter.race_state["wave"]):
			continue
		if int(effect.get("every_n", 0)) > 1:
			fx["n"] = int(fx["n"]) + 1
			if int(fx["n"]) < int(effect["every_n"]):
				continue
			fx["n"] = 0
		if effect.has("chance") and sim.rng.randf() >= float(effect["chance"]):
			continue
		var done := 0
		for action in effect["actions"]:
			if run_action(sim, id, action, context):
				done += 1
		if done == 0:
			continue  # only inert actions (a later phase): nothing happened, no proc
		fx["last"] = sim.tick_count
		fx["wave"] = int(fighter.race_state["wave"])
		sim.events.append({"type": "race_proc", "player": id, "source": effects[index]["src"], "name": fighter.race_state["passive"] if effects[index]["src"] == "passive" else fighter.race_state["synergy"], "on": event_name})


## Runs one action; returns true when it did something. Inert (not yet built) actions return false.
static func run_action(sim, id: int, action: Dictionary, context: Dictionary) -> bool:
	if not RUNNING_ACTIONS.has(str(action["action"])):
		return false
	var source = sim.fighters[id]
	var did := false
	for target_id in targets(sim, id, str(action.get("target", "self")), context):
		var target = sim.fighters[target_id]
		match str(action["action"]):
			"apply_status":
				var entry := {"id": str(action["status"]), "chance": 100.0, "duration": int(action.get("duration", 0))}
				did = Effects.apply(id, source, target_id, target, entry, sim.combat, sim.rng, sim.events) or did
			"heal":
				var amount := heal_amount(action, source, target, float(context.get("damage", 0.0)))
				amount = _within_heal_cap(sim, target, amount)
				var healed := minf(amount, target.max_hp() - target.hp)
				if healed > 0.0:
					target.hp += healed
					sim.events.append({"type": "race_heal", "player": id, "target": target_id, "amount": healed})
					did = true
			"shield":
				var cap := float(RaceData.load_default().rules.get("shield_cap_max_hp", 0.30))
				var added: float = target.add_shield(shield_amount(action, source, float(context.get("damage", 0.0))), int(action.get("duration_ticks", SHIELD_TICKS)), sim.tick_count, cap)
				if added > 0.0:
					sim.events.append({"type": "race_shield", "player": id, "target": target_id, "amount": added, "shield": target.shield, "until": target.shield_until})
					did = true
	return did


## Formula 4.3: amount = fraction x source max HP (or x the damage dealt). The target's cap is applied by Fighter.add_shield.
static func shield_amount(action: Dictionary, source, damage: float) -> float:
	var base: float = damage if str(action["fraction_of"]) == "damage" else source.max_hp()
	var amount := float(action["fraction"]) * base
	if action.has("cap_max_hp"):
		amount = minf(amount, float(action["cap_max_hp"]) * source.max_hp())
	return maxf(0.0, amount)


## Shield gone (its time ran out, or the wave ended); the client hides the shield bar on this event.
static func _end_shield(sim, id: int, fighter, why: String) -> void:
	fighter.clear_shield()
	sim.events.append({"type": "race_shield_end", "target": id, "reason": why})


## Formula 4.2: heal = min(fraction x base, cap_max_hp x target max HP) x target.heal_factor().
## base = the damage dealt (fraction_of "damage"), the target's max HP ("max_hp") or the source's ("source_max_hp").
static func heal_amount(action: Dictionary, source, target, damage: float) -> float:
	var base := 0.0
	match str(action["fraction_of"]):
		"damage": base = damage
		"max_hp": base = target.max_hp()
		"source_max_hp": base = source.max_hp()
	var amount := float(action["fraction"]) * base
	if action.has("cap_max_hp"):
		amount = minf(amount, float(action["cap_max_hp"]) * target.max_hp())
	return maxf(0.0, amount * target.heal_factor())


## Global passive safety (4.2): race healing into one target within one second is <= heal_cap_per_second_max_hp.
static func _within_heal_cap(sim, target, amount: float) -> float:
	var cap := float(RaceData.load_default().rules.get("heal_cap_per_second_max_hp", 0.0))
	if cap <= 0.0 or target.race_state.is_empty():
		return amount
	var window: Array = target.race_state["heal_window"]
	if int(window[0]) < 0 or sim.tick_count - int(window[0]) >= 60:
		window[0] = sim.tick_count
		window[1] = 0.0
	var allowed := maxf(0.0, cap * target.max_hp() - float(window[1]))
	var given := minf(amount, allowed)
	window[1] = float(window[1]) + given
	return given


## Target ids for an action, in id order. Unknown or not-yet-built targets give nobody.
static func targets(sim, id: int, kind: String, context: Dictionary) -> Array:
	var me = sim.fighters[id]
	var allies: Array = []
	for other in sim.fighters:
		if sim.fighters[other].team == me.team and sim.fighters[other].is_alive():
			allies.append(other)
	allies.sort()
	match kind:
		"self":
			return [id]
		"allies_all":
			return allies
		"ally_most_hurt":  # skips full-HP allies; nobody hurt = nobody (the heal is lost, GDD 5)
			var best := -1
			var best_ratio := 1.0
			for other in allies:
				var f = sim.fighters[other]
				var ratio: float = f.hp / maxf(1.0, f.max_hp())
				if ratio < best_ratio:
					best_ratio = ratio
					best = other
			return [best] if best >= 0 else []
		"target":
			var target := int(context.get("target", -1))
			return [target] if sim.fighters.has(target) and sim.fighters[target].is_alive() and target != id else []
	return []


## self_low_hp: fires when HP crosses below `hp_below` (not every tick it stays low); once_per_wave gates it further.
static func _check_low_hp(sim, id: int, fighter) -> void:
	var effects: Array = fighter.race_state["effects"]
	for index in effects.size():
		var effect: Dictionary = effects[index]["effect"]
		if effect["type"] != "trigger" or str(effect["on"]) != "self_low_hp":
			continue
		var fx: Dictionary = fighter.race_state["fx"].get(str(index), {"last": -1, "n": 0, "wave": 0, "low": false})
		fighter.race_state["fx"][str(index)] = fx
		var low: bool = fighter.hp < fighter.max_hp() * float(effect.get("hp_below", 0.0))
		if low and not bool(fx["low"]):
			fx["low"] = true
			fire(sim, id, "self_low_hp", {})
		elif not low:
			fx["low"] = false
