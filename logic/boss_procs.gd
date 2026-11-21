extends RefCounted
## Boss option (Boss 2026-11-21): a boss-drop piece's status-on-hit proc. Pure rules; data in data/items/boss_options.json
## (one option per boss catalog item: status, chance %, duration ticks, internal cooldown ticks).
## - Fighter.boss_procs: the options of the worn pieces (GameSim._refresh_run_stats fills it from the gear; a destroyed or
##   broken-down piece gives none; two copies of one piece give one option). Fighter.proc_ready: option -> tick it may
##   trigger again. Both are plain fighter fields, so checkpoints and replays carry them.
## - step(sim) runs on the authority once per tick after hits and class skills: for each landed "hit" / "skill_hit" event
##   (not periodic, reflected or redirected) of a wearer on a living enemy, each option off cooldown rolls its chance with
##   its OWN random stream (seeded from the sim seed, tick, event index, attacker, target, option), so the shared sim RNG
##   and every other roll are unchanged. A trigger starts the cooldown, then the status goes through Effects.apply at base
##   100: + the wearer's ACC layers - the target's RES layers; resistance >= 100 = immune (no control on CTRL_RES 100 bosses).
##   Events: Effects' effect_applied / effect_resisted, then {"type": "boss_proc", "player", "target", "item", "effect", "landed"}.

const Effects := preload("res://logic/effects.gd")
const PATH := "res://data/items/boss_options.json"
const CONTROL := ["stun", "shock", "sleep"]

static var _cached: Dictionary = {}


static func data() -> Dictionary:
	if _cached.is_empty():
		var text := FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		_cached = parsed if parsed is Dictionary else {"options": {}, "rules": {}, "status_names": {}}
	return _cached


## The option of catalog item `item_id` as {"item", "status", "chance", "duration", "icd"} ({} when it has none).
static func option(item_id: String) -> Dictionary:
	var raw = data().get("options", {}).get(item_id, null)
	if not raw is Dictionary:
		return {}
	return {"item": item_id, "status": str(raw.get("status", "")), "chance": float(raw.get("chance", 0.0)),
		"duration": int(raw.get("duration", 0)), "icd": int(raw.get("icd", 0))}


## The options of the worn `items` (Item objects), one per catalog id, sorted by id (a fixed roll order).
static func options_for(items: Array) -> Array:
	var by_id := {}
	for item in items:
		if item == null or item.destroyed or item.is_broken_down():
			continue
		var found := option(str(item.item_id))
		if not found.is_empty():
			by_id[found["item"]] = found
	var ids: Array = by_id.keys()
	ids.sort()
	return ids.map(func(id): return by_id[id])


## [Thai, English] name of a status for the option text.
static func status_name(status: String) -> Array:
	var names = data().get("status_names", {}).get(status, null)
	return names if names is Array and names.size() == 2 else [status.capitalize(), status.capitalize()]


## Every mistake in the option data against the item catalog and the combat effects ([] when valid).
static func validate(rules, combat) -> Array[String]:
	var errors: Array[String] = []
	var r: Dictionary = data().get("rules", {})
	var lo := float(r.get("chance_min", 5))
	var hi := float(r.get("chance_max", 15))
	var control_max := int(r.get("weapon_control_max_ticks", 30))
	var by_boss := {}
	for item_id in data().get("options", {}):
		var o := option(str(item_id))
		var entry: Dictionary = rules.catalog.entry(str(item_id))
		var tag := "boss option %s" % item_id
		if entry.is_empty():
			errors.append("%s: not a catalog item" % tag)
			continue
		if str(entry.get("boss", "")).is_empty():
			errors.append("%s: not a boss-drop piece (catalog boss is empty)" % tag)
		if not combat.effects.has(o["status"]) or str(combat.effects[o["status"]]["kind"]) != "debuff":
			errors.append("%s: status '%s' is not a debuff in effects.json" % [tag, o["status"]])
			continue
		if o["chance"] < lo or o["chance"] > hi:
			errors.append("%s: chance %s outside %s..%s" % [tag, o["chance"], lo, hi])
		if o["duration"] <= 0:
			errors.append("%s: duration must be > 0 ticks" % tag)
		if o["icd"] <= o["duration"]:
			errors.append("%s: icd %d must be longer than duration %d (no chaining)" % [tag, o["icd"], o["duration"]])
		if Effects.group_of(combat.effects[o["status"]]) == "control":
			if str(entry.get("slot", "")) != "weapon":
				errors.append("%s: a control status (%s) only on a weapon" % [tag, o["status"]])
			elif o["duration"] > control_max:
				errors.append("%s: weapon control %d ticks > %d (a short stun at most)" % [tag, o["duration"], control_max])
		var boss := str(entry.get("boss", ""))
		var used: Array = by_boss.get(boss, [])
		if used.has(o["status"]):
			errors.append("%s: status '%s' repeats within boss %s" % [tag, o["status"], boss])
		used.append(o["status"])
		by_boss[boss] = used
	for item_id in rules.catalog.items:
		if not str(rules.catalog.items[item_id].get("boss", "")).is_empty() and option(str(item_id)).is_empty():
			errors.append("boss piece %s has no boss option" % item_id)
	for status in data().get("status_names", {}):
		if not combat.effects.has(str(status)):
			errors.append("status_names: unknown effect '%s'" % status)
	return errors


## The authority's per-tick pass (see the file comment). Needs sim.combat; does nothing without wearers.
static func step(sim) -> void:
	if sim.combat == null:
		return
	var seen: Array = sim.events.duplicate()  # Effects.apply appends events while this runs
	for index in seen.size():
		var event: Dictionary = seen[index]
		var kind := str(event.get("type", ""))
		if kind != "hit" and kind != "skill_hit":
			continue
		if bool(event.get("periodic", false)) or str(event.get("effect", "hit")) in ["redirect", "reflect"]:
			continue
		var a := int(event.get("attacker", -1))
		var t := int(event.get("target", -1))
		if not sim.fighters.has(a) or not sim.fighters.has(t) or a == t:
			continue
		var attacker = sim.fighters[a]
		if attacker.boss_procs.is_empty() or not attacker.is_alive():
			continue
		var target = sim.fighters[t]
		if not target.is_alive() or target.team == attacker.team:
			continue
		for o in attacker.boss_procs:
			var key := str(o["item"])
			if int(attacker.proc_ready.get(key, 0)) > sim.tick_count:
				continue
			var roll := RandomNumberGenerator.new()
			roll.seed = hash([sim.rng.seed, sim.tick_count, index, a, t, key])
			if roll.randf() * 100.0 >= float(o["chance"]):
				continue
			attacker.proc_ready[key] = sim.tick_count + int(o["icd"])
			var landed := Effects.apply(a, attacker, t, target, {"id": str(o["status"]), "target": "enemy", "on": "hit", "chance": 100.0, "duration": int(o["duration"])}, sim.combat, roll, sim.events)
			sim.events.append({"type": "boss_proc", "player": a, "target": t, "item": key, "effect": str(o["status"]), "landed": landed})
			if not target.is_alive():
				break
