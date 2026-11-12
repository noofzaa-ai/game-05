extends RefCounted
## Race passives and squad synergy bonuses at fight time (design/gdd/races-and-classes.md 3.4-3.6, 4.2, phase 2 + 5).
## Pure rules. Each squad fighter carries `Fighter.race_state` (plain data, saved in GameSim checkpoints):
##   {"race", "class", "passive", "synergy", "effects": [{"src": "passive"|"synergy", "effect": {...}}],
##    "fx": {index: {"last", "n", "wave", "low"}}, "pseudo": {stat: {"add", "mul"}}, "wave", "heal_window": [tick, amount]}
## What runs now: `stat_mod` (real stats on the stat refresh, HEALING via Fighter.heal_factor) and `trigger` with the
## actions `apply_status`, `heal` and `shield` (Fighter.shield, 4.3), on the events wave_start, hit, heavy_hit, skill_cast, skill_hit, kill, hurt,
## guard_block, self_low_hp (fields: chance, every_n, cooldown_ticks, once_per_wave, hp_below).
## `low_hp_scaling` (4.1) is read live by Fighter.stat through scaling_mul (race_state.scaling).
## `skill_mod` (4.4) changes a skill-build cast in logic/skills/system.gd cast() through modify_skill_stats.
## `charges` (runes): count events in fx[index].charges, run the actions at `max`, reset; RUNE_GAIN adds to int gains.
## `burst` hits enemies within `radius` of `center` (self | target) for atk_mul x ATK (vs DEF), + optional status.
## Class signatures (data/classes/<id>.json "signature", any race): `cleave` (greatsword, read by logic/combat.gd
## resolve_hits through cleave_mul) and a `trigger` with `new_target` (longbow Hunter's Mark: sunder on the first
## hit on a target new to this card).
## `aggro` (a class signature, data/classes/<id>.json "signature": Bulwark) pulses every `every_ticks` once an enemy
## is within `radius`; `pulse_aggro` taunts enemies within radius (5) for duration_ticks (180) via GameSim.taunt_enemy.
## Ultimate gauge (GDD 3.10.2, 3.10.6, formula 4.7): with rules.ultimates_enabled the race engine owns a squad card's
## Fighter.gauge. gain_gauge() fills it once per tick from time in combat, damage dealt (/ own ATK), damage taken after
## shields (/ own max HP), heal + shield given to other allies (/ own ATK) and kills, scaled by the class `gauge` block and
## the ultimate's charge_mul; capped at ultimate_gauge_max; no gain while an ultimate move runs or from an event tagged
## "ultimate". The old gains (combat gauge_per_hit_*, ULTREGEN) and the skill system's gauge wipe skip such fighters
## (owns_gauge). The gauge is a Fighter field, so it is in checkpoints and carries across waves; journeys clear it at run end.
## Ultimates (3.10): logic/race_ultimates.gd runs the cast; its actions go through run_action like any trigger's.
## run_action knows all 7 actions (apply_status, heal incl. revive on ally_downed and split, shield, burst with the v2
## fields, pulse_aggro, zone, skill_refresh) and every target/center of the vocabulary. An ultimate's context has
## "ultimate": true: its heals skip the per-second passive cap (4.2), its shields use ult_shield_cap_max_hp (4.3), and
## every event it causes is tagged "ultimate" (no gauge, measured apart). The race event ultimate_cast fires after the
## actions resolve (Runeborn runes then discharge, 3.4).
## Deterministic: a `chance` roll uses the sim RNG; nothing else is random. Order = fighter id, then effect order.

const CardDeck := preload("res://logic/card_deck.gd")
const RaceData := preload("res://logic/race_data.gd")
const Effects := preload("res://logic/effects.gd")
const Fighter := preload("res://logic/fighter.gd")
const RaceUltimates := preload("res://logic/race_ultimates.gd")
const TreeEffects := preload("res://logic/skill_tree_effects.gd")  ## card skill tree nodes (design/gdd/skill-tree.md 3.5)
const RUNNING_ACTIONS: Array[String] = ["apply_status", "heal", "shield", "burst", "pulse_aggro", "zone", "skill_refresh"]
const PULSE_RADIUS := 5.0  ## pulse_aggro defaults (GDD 3.6: the Bulwark values)
const PULSE_TICKS := 180
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
	for effect in CardDeck.class_data(class_id).get("signature", []):  # the class signature (3.2), any race
		effects.append({"src": "signature", "effect": effect.duplicate(true)})
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
		"effects": effects, "fx": {}, "pseudo": pseudo, "scaling": scaling, "wave": 0, "heal_window": [-1, 0.0],
		"ultimate": races.ultimate_for(race, class_id).duplicate(true), "full_at": -1}
	TreeEffects.attach(fighter, run)  # learned tree nodes join the effects / cells / signature (skill-tree.md 3.5)


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


## The fighter's skill_mods combined (4.4): damage/cooldown/radius multiply, crit_add and hp_cost add, min_hp = largest.
static func skill_mods(fighter) -> Dictionary:
	var out := {"damage_mul": 1.0, "cooldown_mul": 1.0, "radius_mul": 1.0, "crit_add": 0.0, "hp_cost": 0.0, "min_hp": 0.0}
	for entry in fighter.race_state.get("effects", []):
		var effect: Dictionary = entry["effect"]
		if effect["type"] != "skill_mod":
			continue
		for key in ["damage_mul", "cooldown_mul", "radius_mul"]:
			out[key] *= float(effect.get(key, 1.0))
		out["crit_add"] += float(effect.get("crit_add", 0.0))
		out["hp_cost"] += float(effect.get("hp_cost", 0.0))
		out["min_hp"] = maxf(float(out["min_hp"]), float(effect.get("min_hp", 0.0)))
	return out


## SKILL_DMG pseudo-stat (4.4, 3.7): race stat_mod SKILL_DMG plus any status that grants it (recital, later).
static func skill_dmg(fighter) -> float:
	var total := 0.0
	var race: Dictionary = fighter.race_state.get("pseudo", {}).get("SKILL_DMG", {})
	total += float(race.get("add", 0.0)) + float(race.get("mul", 0.0))
	var status: Dictionary = fighter.stat_mods.get("SKILL_DMG", {})
	total += float(status.get("add", 0.0)) + float(status.get("mul", 0.0))
	return total


## The skill_mod hook (4.4), called once where a skill-build cast resolves (logic/skills/system.gd cast()), on the
## cast's stats before the caster takes them. Returns "" or a refusal ("race_min_hp": Blood Rite below 10% HP).
##   damage = base x product(damage_mul) x (1 + SKILL_DMG)   (also the skill's burn/bleed damage)
##   cooldown = base x product(cooldown_mul), floored at base x cooldown_mul_floor (rules.json, 0.60)
##   radius x product(radius_mul); crit chance + crit_add/100.
## Nothing to do for a fighter without race state or mods (plain profile runs, enemies).
static func modify_skill_stats(fighter, stats: Dictionary) -> String:
	if fighter.race_state.is_empty():
		return ""
	var mods := skill_mods(fighter)
	if float(mods["min_hp"]) > 0.0 and fighter.hp < fighter.max_hp() * float(mods["min_hp"]):
		return "race_min_hp"
	var damage_mul: float = float(mods["damage_mul"]) * (1.0 + skill_dmg(fighter))
	for key in ["damage", "burn_damage_mul", "bleed_damage_mul"]:
		if stats.has(key):
			stats[key] = float(stats[key]) * damage_mul
	if stats.has("cooldown"):
		var floor_mul := float(RaceData.load_default().rules.get("cooldown_mul_floor", 0.0))
		stats["cooldown"] = float(stats["cooldown"]) * maxf(float(mods["cooldown_mul"]), floor_mul)
	if stats.has("radius"):
		stats["radius"] = float(stats["radius"]) * float(mods["radius_mul"])
	if float(mods["crit_add"]) != 0.0:
		stats["crit_chance"] = minf(1.0, float(stats.get("crit_chance", 0.0)) + float(mods["crit_add"]) / 100.0)
	return ""


## Blood Rite's price (3.4, 5): hp_cost x CURRENT HP, paid after a cast is accepted. Not damage: no hurt event,
## no runes, no lifesteal. Returns the HP paid.
static func pay_skill_hp(sim, id: int, fighter) -> float:
	if fighter.race_state.is_empty():
		return 0.0
	var cost: float = float(skill_mods(fighter)["hp_cost"]) * fighter.hp
	if cost <= 0.0:
		return 0.0
	fighter.hp = maxf(1.0, fighter.hp - cost)
	sim.events.append({"type": "race_hp_cost", "player": id, "amount": cost})
	return cost


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
	for id in ids:  # ultimates first: a wind-up resolves or is lost, zones and repeat hits run (3.10.3)
		RaceUltimates.step(sim, id, sim.fighters[id])
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
		_check_aggro(sim, id, fighter)
	if ultimates_enabled():  # after the triggers: their heals/shields/bursts this tick count too
		var in_combat: bool = sim.living_enemy_count() > 0
		for id in ids:
			gain_gauge(sim, id, sim.fighters[id], sim.events, in_combat)


## rules.ultimates_enabled (data/races/rules.json): race ultimates and their gauge are on.
static func ultimates_enabled() -> bool:
	return bool(RaceData.load_default().rules.get("ultimates_enabled", false))


## True when the race engine owns this fighter's gauge (a squad card with ultimates on): the old gauge gains and the
## skill system's "retired gauge" wipe leave it alone.
static func owns_gauge(fighter) -> bool:
	return not fighter.race_state.is_empty() and ultimates_enabled()


## Formula 4.7 for one tick of fighter `id` from this tick's `events`:
##   gain = charge_mul x (T/60 + Gd x md x dealt/ATK + Gt x mt x 100 x taken/maxHP + Gs x ms x support/ATK) + Gk x kills
## T only while `in_combat` (living enemies). Running totals per source go to race_state.gauge_by (measurement).
static func gain_gauge(sim, id: int, fighter, events: Array, in_combat: bool) -> float:
	if not fighter.is_alive() or (fighter.state == Fighter.State.ATTACK and fighter.move_id.ends_with("ultimate")):
		return 0.0
	var data = RaceData.load_default()
	var rule: Dictionary = data.rules.get("gauge", {})
	var mul: Dictionary = CardDeck.class_data(str(fighter.race_state["class"])).get("gauge", {})
	var charge := float(data.ultimate_for(str(fighter.race_state["race"]), str(fighter.race_state["class"])).get("charge_mul", 1.0))
	var atk: float = maxf(1.0, fighter.stat("ATK"))
	var dealt := 0.0
	var taken := 0.0
	var support := 0.0
	var kills := 0
	for event in events:
		if bool(event.get("ultimate", false)) or str(event.get("move", "")).ends_with("ultimate"):
			continue  # an ultimate never feeds the gauge (no chaining, 3.10.2)
		var kind := str(event.get("type", ""))
		match kind:
			"hit", "blocked", "skill_hit", "skill_dot", "race_burst_hit", "dot":
				var attacker := int(event.get("attacker", -1))
				var target := int(event.get("target", -1))
				if kind != "dot" and attacker == id and target != id and sim.fighters.has(target) and sim.fighters[target].team != fighter.team:
					dealt += float(event.get("damage", 0.0))
				if target == id and attacker != id and (kind == "dot" or not sim.fighters.has(attacker) or sim.fighters[attacker].team != fighter.team):
					# skill hits report the damage after shields; the others report the full blow and what the shield took
					var absorbed := 0.0 if kind.begins_with("skill") else float(event.get("absorbed", 0.0))
					taken += maxf(0.0, float(event.get("damage", 0.0)) - absorbed)
			"race_heal", "race_shield":
				if int(event.get("player", -1)) == id and int(event.get("target", -1)) != id:
					support += float(event.get("amount", 0.0))
			"killed":
				var dead := int(event.get("target", -1))
				if int(event.get("by", -1)) == id and sim.fighters.has(dead) and sim.fighters[dead].team != fighter.team:
					kills += 1
	var parts := {
		"time": charge * (float(rule.get("time", 0.0)) / 60.0 if in_combat else 0.0),
		"dealt": charge * float(rule.get("dealt", 0.0)) * float(mul.get("dealt", 1.0)) * dealt / atk,
		"taken": charge * float(rule.get("taken", 0.0)) * float(mul.get("taken", 1.0)) * 100.0 * taken / maxf(1.0, fighter.max_hp()),
		"support": charge * float(rule.get("support", 0.0)) * float(mul.get("support", 1.0)) * support / atk,
		"kill": float(rule.get("kill", 0.0)) * float(kills),
	}
	TreeEffects.gauge_parts(fighter, parts, kills)  # tree gauge_mod (skill-tree.md 4.7)
	var total := 0.0
	var by: Dictionary = fighter.race_state.get("gauge_by", {})
	for key in parts:
		total += float(parts[key])
		if float(parts[key]) > 0.0:
			by[key] = float(by.get(key, 0.0)) + float(parts[key])
	fighter.race_state["gauge_by"] = by
	var before: float = fighter.gauge
	var top := float(sim.combat.rules["ultimate_gauge_max"])
	fighter.gauge = minf(top, fighter.gauge + total)  # overflow is lost (3.10.2)
	if fighter.gauge >= top and int(fighter.race_state.get("full_at", -1)) < 0:
		fighter.race_state["full_at"] = sim.tick_count  # the pilot's max_hold_ticks clock (3.10.4)
	return fighter.gauge - before


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
		"skill_heavy":  # a class skill that counts as a heavy hit (Reaping Arc), once per cast (class-skills.md 5.2)
			if int(event.get("player", -1)) == id:
				out.append("heavy_hit")
		"dodge_started":
			if int(event.get("player", -1)) == id:
				out.append("dodge")
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
		if effect["type"] == "charges":
			_gain_charges(sim, id, index, event_name, context)
			continue
		if effect["type"] != "trigger" or str(effect["on"]) != event_name:
			continue
		if not TreeEffects.filter_ok(sim, id, effect, context):  # tree trigger filters (skill-tree.md 3.5)
			continue
		var fx: Dictionary = fighter.race_state["fx"].get(str(index), {"last": -1, "n": 0, "wave": 0, "low": false})
		fighter.race_state["fx"][str(index)] = fx
		if TreeEffects.once_per_tick(sim, effect, fx):
			continue
		if int(effect.get("cooldown_ticks", 0)) > 0 and int(fx["last"]) >= 0 and sim.tick_count - int(fx["last"]) < int(effect["cooldown_ticks"]):
			continue
		if bool(effect.get("once_per_wave", false)) and int(fx["wave"]) == int(fighter.race_state["wave"]):
			continue
		if bool(effect.get("new_target", false)):  # Hunter's Mark (3.2): only the first hit on a target new to this card
			var hit_target := int(context.get("target", -1))
			if hit_target == int(fx.get("target", -1)):
				continue
			fx["target"] = hit_target
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
		sim.events.append({"type": "race_proc", "player": id, "source": effects[index]["src"], "name": _source_name(fighter, effects[index]), "on": event_name})


## The name a race_proc shows: the passive name, the synergy kind, or the class signature's own `name`.
static func _source_name(fighter, entry: Dictionary) -> String:
	match str(entry["src"]):
		"passive": return str(fighter.race_state["passive"])
		"signature": return str(entry["effect"].get("name", ""))
	return str(fighter.race_state["synergy"])


## Cleave (class signature, GDD 3.2): damage multiplier for one heavy swing that hit `hit_count` enemies:
## 1 + min(max_bonus, per_extra x (hit_count - 1)). 1.0 without the signature or for a single target.
static func cleave_mul(fighter, hit_count: int) -> float:
	var bonus := 0.0
	for entry in fighter.race_state.get("effects", []):
		var effect: Dictionary = entry["effect"]
		if effect["type"] == "cleave":
			bonus += minf(float(effect["max_bonus"]), float(effect["per_extra"]) * float(maxi(0, hit_count - 1)))
	return 1.0 + bonus


## charges (3.4 Runeborn, 3.6 #5): +gain per listed event (+RUNE_GAIN for int gains; "max" fills at once).
## ultimate_cast always fills (GDD 3.4 "gain: max" on ultimate_cast; the data has one `gain` for all gain_on events).
## At `max` the actions run once and the count resets (a "max" gain near max discharges once, never twice).
## The count lives in fx[index].charges (checkpointed) and carries across waves. Emits race_runes for the rune pips.
static func _gain_charges(sim, id: int, index: int, event_name: String, context: Dictionary) -> void:
	var fighter = sim.fighters[id]
	var entry: Dictionary = fighter.race_state["effects"][index]
	var effect: Dictionary = entry["effect"]
	var gains = effect.get("gain_on", [])
	if not (gains if gains is Array else [gains]).has(event_name):
		return
	var fx: Dictionary = fighter.race_state["fx"].get(str(index), {"last": -1, "n": 0, "wave": 0, "low": false})
	fighter.race_state["fx"][str(index)] = fx
	var top := int(effect["max"])
	var have := int(fx.get("charges", 0))
	if str(effect.get("gain", 1)) == "max" or event_name == "ultimate_cast":  # GDD 3.4: an ultimate fills the runes
		have = top
	else:
		var bonus: Dictionary = fighter.race_state.get("pseudo", {}).get("RUNE_GAIN", {})
		have += maxi(0, int(effect.get("gain", 1)) + int(bonus.get("add", 0.0)))
	have = mini(have, top)
	fx["charges"] = have
	if have < top:
		sim.events.append({"type": "race_runes", "player": id, "runes": have, "max": top})
		return
	fx["charges"] = mini(int(effect.get("reset_to", 0)), top - 1)  # Rune Battery (tree cell_mod charges_reset_to)
	sim.events.append({"type": "race_runes", "player": id, "runes": int(fx["charges"]), "max": top})
	if TreeEffects.discharge_gauge(fighter) > 0.0:  # Stored Power (tree gauge_mod discharge_add)
		fighter.gauge = minf(float(sim.combat.rules["ultimate_gauge_max"]), fighter.gauge + TreeEffects.discharge_gauge(fighter))
	var done := 0
	for action in effect["actions"]:
		if run_action(sim, id, action, context):
			done += 1
	fx["last"] = sim.tick_count
	sim.events.append({"type": "race_proc", "player": id, "source": entry["src"], "name": fighter.race_state["passive"] if entry["src"] == "passive" else fighter.race_state["synergy"], "on": event_name, "discharge": true, "did": done})


## Runs one action; returns true when it did something. Inert (not yet built) actions return false.
static func run_action(sim, id: int, action: Dictionary, context: Dictionary) -> bool:
	if TreeEffects.ACTIONS.has(str(action["action"])):
		return TreeEffects.run_action(sim, id, action, context)  # node actions: pull, cleanse, skill_status
	if not RUNNING_ACTIONS.has(str(action["action"])):
		return false
	if not context.has("points"):  # a passive's context is the sim event itself: never write into it
		context = context.duplicate()
		context["points"] = {}
		context["picked"] = {}
	var source = sim.fighters[id]
	var ult := bool(context.get("ultimate", false))
	match str(action["action"]):
		"burst":
			return RaceUltimates.burst(sim, id, action, context)
		"pulse_aggro":
			return pulse_aggro(sim, id, float(action.get("radius", PULSE_RADIUS)), int(action.get("duration_ticks", PULSE_TICKS)), ult)
		"zone":
			return RaceUltimates.start_zone(sim, id, action, context)
		"skill_refresh":
			return RaceUltimates.skill_refresh(sim, id, action, context)
	var did := false
	var chosen := targets(sim, id, str(action.get("target", "self")), context, action)
	for target_id in chosen:
		var target = sim.fighters[target_id]
		match str(action["action"]):
			"apply_status":
				var entry := {"id": str(action["status"]), "chance": 100.0, "duration": int(action.get("duration", 0))}
				did = Effects.apply(id, source, target_id, target, entry, sim.combat, sim.rng, sim.events) or did
			"heal":
				if target.state == Fighter.State.DOWNED:  # ally_downed: a revive at fraction x max HP (3.10.5)
					did = RaceUltimates.revive(sim, id, target_id, float(action["fraction"])) or did
					continue
				var amount := heal_amount(action, source, target, float(context.get("damage", 0.0)) / (float(chosen.size()) if bool(action.get("split", false)) else 1.0))
				if not ult:
					amount = _within_heal_cap(sim, target, amount)  # ultimate heals are exempt from the per-second cap (4.2)
				var healed := minf(amount, target.max_hp() - target.hp)
				if healed > 0.0:
					target.hp += healed
					sim.events.append({"type": "race_heal", "player": id, "target": target_id, "amount": healed, "ultimate": ult})
					did = true
			"shield":
				var cap := float(RaceData.load_default().rules.get("ult_shield_cap_max_hp" if ult else "shield_cap_max_hp", 0.30))
				var base := float(context.get("damage", 0.0)) / (float(chosen.size()) if bool(action.get("split", false)) else 1.0)
				var added: float = target.add_shield(shield_amount(action, source, base), int(action.get("duration_ticks", SHIELD_TICKS)), sim.tick_count, cap)
				if added > 0.0:
					sim.events.append({"type": "race_shield", "player": id, "target": target_id, "amount": added, "shield": target.shield, "until": target.shield_until, "ultimate": ult})
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


## Target ids for an action, in id order. The v2 targets (ally_downed, *_in_zone, enemies_in_radius,
## enemy_lowest_hp_pct, enemy_highest_hp) are in RaceUltimates.targets_v2. Within one ultimate cast (context.picked)
## ally_most_hurt is picked once, so a heal, its regen and a burst centered on that ally agree on who.
static func targets(sim, id: int, kind: String, context: Dictionary, action: Dictionary = {}) -> Array:
	var picked = context.get("picked")
	if picked is Dictionary and kind == "ally_most_hurt" and picked.has(kind):
		return picked[kind]
	var out := _targets(sim, id, kind, context, action)
	if picked is Dictionary and kind == "ally_most_hurt":
		picked[kind] = out
	return out


static func _targets(sim, id: int, kind: String, context: Dictionary, action: Dictionary) -> Array:
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
		"allies_in_radius":
			return TreeEffects.targets(sim, id, kind, action)
	return RaceUltimates.targets_v2(sim, id, kind, context, action)


## Taunt (3.6): every living enemy within `radius` m of fighter `id` attacks it for `ticks` (the longer remaining
## taunt wins on overlap). Returns true when at least one enemy was taunted. Emits race_taunt for the client.
static func pulse_aggro(sim, id: int, radius: float, ticks: int, ultimate: bool = false) -> bool:
	var me: Vector3 = sim.bodies[id].position
	var taunted: Array = []
	var ids: Array = sim.fighters.keys()
	ids.sort()
	for other in ids:
		var f = sim.fighters[other]
		if f.team == sim.fighters[id].team or not f.is_alive():
			continue
		var pos: Vector3 = sim.bodies[other].position
		if Vector2(pos.x - me.x, pos.z - me.z).length() <= radius and sim.taunt_enemy(other, id, ticks):
			taunted.append(other)
	if taunted.is_empty():
		return false
	sim.events.append({"type": "race_taunt", "player": id, "enemies": taunted, "radius": radius, "ticks": ticks, "pos": me, "ultimate": ultimate})
	return true


## aggro (class signature, Bulwark): a pulse every `every_ticks`; it waits until an enemy is in range, so a pulse is
## never spent on nobody. The timer is in fx[index].last (checkpointed).
static func _check_aggro(sim, id: int, fighter) -> void:
	var effects: Array = fighter.race_state["effects"]
	for index in effects.size():
		var effect: Dictionary = effects[index]["effect"]
		if effect["type"] != "aggro":
			continue
		var fx: Dictionary = fighter.race_state["fx"].get(str(index), {"last": -1, "n": 0, "wave": 0, "low": false})
		fighter.race_state["fx"][str(index)] = fx
		if int(fx["last"]) >= 0 and sim.tick_count - int(fx["last"]) < int(effect["every_ticks"]):
			continue
		if pulse_aggro(sim, id, float(effect["radius"]), int(effect["duration_ticks"])):
			fx["last"] = sim.tick_count
			sim.events.append({"type": "race_proc", "player": id, "source": "signature", "name": str(effect.get("name", "")), "on": "aggro"})


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
