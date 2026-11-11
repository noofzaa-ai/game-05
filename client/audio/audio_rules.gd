extends RefCounted
## Turns one simulation event into "facts" (plain values the sound rules can test) and picks the
## cues the rules in data/audio/audio.json ask for. No nodes and no playback here, so it is easy to
## test; client/audio/audio_director.gd does the playing.
##
## Facts every event gets:
##   type, actor (id doing it), target (id it is done to, or -1),
##   local (actor is the local player), to_local (target is the local player),
##   enemy (actor is a monster), target_enemy (target is a monster),
##   weapon (actor's move set: fists/blade/dagger/spear/hammer or a monster style),
##   kind (the move without its weapon prefix: light_1, heavy, special, ultimate, slam, bite, ...),
##   position (Vector3 or null: where it happened, for distance)
## and, per event type, the event's own numbers and flags (crit, launched, armored, power, combo,
## attacker_combo, damage, effect, gold ...) plus:
##   hit: heavy_hit (big enough for the heavy body), killed (the target died from it)
##   effect_*: effect_kind ("buff" / "debuff")
##   loot: item_count, material_count, best_tier
## EXTENDING: a new fact is one more line in facts(); then rules in the data can use it.

## A hit at least this strong (move power) plays the heavy hit body instead of the light one.
const HEAVY_HIT_POWER := 1.6
const HEAVY_KINDS := ["heavy", "air_heavy", "run_heavy", "special", "ultimate"]


static func facts(event: Dictionary, sim = null, local_id: int = 1) -> Dictionary:
	var type := str(event.get("type", ""))
	var out := {"type": type}
	for key in event:
		var value = event[key]
		if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
			out[key] = value
	var actor := -1
	var target := -1
	if event.has("player"):
		actor = int(event["player"])
	elif event.has("attacker"):
		actor = int(event["attacker"])
	if event.has("target"):
		target = int(event["target"])
	if actor == -1:
		actor = target  # effects, dots and deaths happen to the target
	out["actor"] = actor
	out["target"] = target
	out["local"] = actor == local_id and actor != -1
	out["to_local"] = target == local_id and target != -1
	out["enemy"] = is_enemy(sim, actor)
	out["ally"] = sim != null and sim.fighters.has(actor) and sim.fighters[actor].team == "player" and actor != local_id
	out["target_enemy"] = is_enemy(sim, target)
	out["weapon"] = style_of(sim, actor)
	out["kind"] = move_kind(str(event.get("move", "")), str(out["weapon"]))
	out["position"] = position_of(event, sim, actor if type != "killed" else target)

	match type:
		"hit":
			var power := float(event.get("power", 0.0))
			out["heavy_hit"] = power >= HEAVY_HIT_POWER or bool(event.get("launched", false)) or str(out["kind"]) in HEAVY_KINDS
			out["killed"] = _is_dead(sim, target)
		"effect_applied", "effect_resisted", "effect_ended", "dot":
			out["effect_kind"] = _effect_kind(sim, str(event.get("effect", "")))
		"loot":
			var items: Array = event.get("items", [])
			var best := -1
			for item in items:
				best = maxi(best, int(item.get("tier", 0)))
			out["item_count"] = items.size()
			out["best_tier"] = best
			var materials = event.get("materials", {})
			var material_total := 0
			if materials is Dictionary:
				for key in materials:
					material_total += int(materials[key])
			out["material_count"] = material_total
	return out


## The cues to play for these facts: [{"cue": name, "pitch": extra pitch scale offset}].
static func pick(rules: Array, facts_of: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rule in rules:
		if not (rule is Dictionary) or not matches(rule.get("when", {}), facts_of):
			continue
		var pitch := 0.0
		var from = rule.get("pitch_from", null)
		if from is Dictionary and facts_of.has(str(from.get("fact", ""))):
			var value := float(facts_of[str(from["fact"])])
			pitch = minf(float(from.get("max", 0.1)), maxf(0.0, value - 1.0) * float(from.get("per", 0.0)))
		for cue in rule.get("play", []):
			out.append({"cue": expand(str(cue), facts_of), "pitch": pitch})
		if bool(rule.get("stop", false)):
			break
	return out


## True when every condition holds. A condition is a value (equal), a list (one of) or {min, max}.
static func matches(when, facts_of: Dictionary) -> bool:
	if not (when is Dictionary):
		return true
	for key in when:
		if not facts_of.has(key):
			return false
		var have = facts_of[key]
		var want = when[key]
		if want is Array:
			var found := false
			for option in want:
				if _same(have, option):
					found = true
					break
			if not found:
				return false
		elif want is Dictionary:
			if not (typeof(have) in [TYPE_INT, TYPE_FLOAT]):
				return false
			if want.has("min") and float(have) < float(want["min"]):
				return false
			if want.has("max") and float(have) > float(want["max"]):
				return false
		elif not _same(have, want):
			return false
	return true


static func expand(cue: String, facts_of: Dictionary) -> String:
	return cue.replace("{weapon}", str(facts_of.get("weapon", "")))


static func move_kind(move_id: String, style: String) -> String:
	if move_id.is_empty():
		return ""
	if not style.is_empty() and move_id.begins_with(style + "_"):
		return move_id.substr(style.length() + 1)
	var cut := move_id.find("_")
	return move_id.substr(cut + 1) if cut >= 0 else move_id


static func is_enemy(sim, id: int) -> bool:
	if sim == null or id < 0 or not sim.fighters.has(id):
		return false
	return not str(sim.fighters[id].enemy_type).is_empty()


static func style_of(sim, id: int) -> String:
	if sim == null or id < 0 or not sim.fighters.has(id):
		return ""
	return str(sim.fighters[id].style)


static func position_of(event: Dictionary, sim, id: int):
	if event.get("pos") is Vector3:
		return event["pos"]
	if sim != null and id >= 0 and sim.bodies.has(id):
		return sim.bodies[id].position
	return null


static func _is_dead(sim, id: int) -> bool:
	if sim == null or id < 0 or not sim.fighters.has(id):
		return false
	return float(sim.fighters[id].hp) <= 0.0


static func _effect_kind(sim, effect_id: String) -> String:
	if sim == null or sim.combat == null or not sim.combat.effects.has(effect_id):
		return ""
	return str(sim.combat.effects[effect_id].get("kind", ""))


static func _same(a, b) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return is_equal_approx(float(a), float(b))
	if typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
		return typeof(a) == typeof(b) and a == b
	return str(a) == str(b)

static func friend_gain_db(facts_of: Dictionary) -> float:
	return -6.0 if facts_of.get("ally", false) else 0.0
