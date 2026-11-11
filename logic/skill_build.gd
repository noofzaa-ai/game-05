extends RefCounted
## Server-owned build rules. Requests contain IDs only, never costs, stats or Resource paths.
const ROOT := "res://data/skill_system/"
static var _config: Dictionary = {}
static var _tree
static var _snapshots: Dictionary = {}
static var _basics: Dictionary = {}

static func config() -> Dictionary:
	if _config.is_empty():
		var value = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "integration.json"))
		if value is Dictionary: _config = value
	return _config

static func enabled() -> bool:
	return bool(config().get("enabled", false))

static func start_for(family: String) -> String:
	return str(config().get("weapon_starts", {}).get(family, ""))

static func ready_for_run(profile) -> bool:
	if not enabled(): return true
	var weapon = profile.loadout.item_at("weapon",0)
	return weapon != null and not weapon.destroyed and not start_for(weapon.weapon_type).is_empty() and validate(profile.skill_build).is_empty() and profile.skill_build.start == start_for(weapon.weapon_type)

static func initial(family: String) -> Dictionary:
	var start := start_for(family)
	var slots: Array = []
	for id in config().get("class_skills", {}).get(family, config().get("default_skills", [])):
		slots.append({"skill": id, "shape": "", "effect": ""})
	return {"v": 1, "start": start, "allocated": ["start_" + start] if not start.is_empty() else [], "skills": slots}

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.size() != 4 or not value.has_all(["v", "start", "allocated", "skills"]): return "invalid_skill_build"
	if value.v != 1 or not value.start is String or not value.start in config().weapon_starts.values(): return "invalid_tree_start"
	if not value.allocated is Array or value.allocated.is_empty() or value.allocated.size() > int(config().max_points) + 1: return "invalid_tree_points"
	if value.allocated[0] != "start_" + value.start: return "invalid_tree_start"
	var tree = load(ROOT + "tree/full_tree.tres").duplicate(true)
	var run = load(ROOT + "scripts/run_state.gd").new()
	var weapon = load(ROOT + "scripts/weapon_data.gd").new()
	weapon.id = value.start
	weapon.start_node = "start_" + value.start
	var problem: String = run.start(weapon, tree, int(config().max_points))
	if not problem.is_empty(): return "invalid_tree"
	for id in value.allocated.slice(1):
		if not id is String or not run.allocate(tree, id).is_empty(): return "invalid_tree_path"
	if not value.skills is Array or value.skills.size() != 4: return "invalid_skill_slots"
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var used: Array = []
	for row in value.skills:
		if not row is Dictionary or row.size() != 3 or not row.has_all(["skill", "shape", "effect"]): return "invalid_skill_slots"
		if not row.skill is String or not row.skill in catalog or row.skill in used: return "invalid_skill_id"
		used.append(row.skill)
		var skill = load(ROOT + "skills/" + row.skill + ".tres")
		for slot in ["shape", "effect"]:
			var id = row[slot]
			if not id is String: return "invalid_gem"
			if id.is_empty(): continue
			# IDs are checked against a fixed catalog BEFORE any path is constructed.
			var allowed: Array = ["wide", "dense", "remote", "echo", "multishot", "chain", "pierce", "knockback", "charge", "quickcast", "quickcd", "longer"] if slot == "shape" else ["ignite", "bleed", "chill", "shock", "stun", "leech", "thorns", "regen"]
			if not id in allowed: return "invalid_gem"
			var gem = load(ROOT + "gems/" + id + ".tres")
			if not load(ROOT + "scripts/build_calc.gd").can_equip(skill, gem, slot).is_empty(): return "incompatible_gem"
	return ""

static func calculate(value: Dictionary, slot: int) -> Dictionary:
	var cache_key := JSON.stringify(value) + ":" + str(slot)
	if _snapshots.has(cache_key): return _snapshots[cache_key].duplicate(true)
	if slot < 0 or slot > 3 or not validate(value).is_empty(): return {"error": "invalid_skill_build"}
	var tree = load(ROOT + "tree/full_tree.tres").duplicate(true)
	tree.build()
	var run = load(ROOT + "scripts/run_state.gd").new()
	run.allocated.assign(value.allocated)
	var row: Dictionary = value.skills[slot]
	var skill = load(ROOT + "skills/" + row.skill + ".tres")
	var gems: Array[ZorxGemData] = []
	for kind in ["shape", "effect"]:
		if not row[kind].is_empty(): gems.append(load(ROOT + "gems/" + row[kind] + ".tres"))
	var result: Dictionary = load(ROOT + "scripts/build_calc.gd").calc_skill(skill, gems, tree, run)
	if not result.has("error"):
		if _snapshots.size() >= 128: _snapshots.erase(_snapshots.keys()[0])
		_snapshots[cache_key] = result.duplicate(true)
	return result

static func basic_stats(value: Dictionary) -> Dictionary:
	var key := JSON.stringify(value)
	if _basics.has(key): return _basics[key].duplicate(true)
	if not validate(value).is_empty(): return {}
	var tree = load(ROOT + "tree/full_tree.tres").duplicate(true)
	tree.build()
	var run = load(ROOT + "scripts/run_state.gd").new()
	run.allocated.assign(value.allocated)
	var skill := ZorxSkillData.new()
	skill.id = "basic_attack"
	skill.tags.assign(["projectile","hit"] if value.get("start","")=="bow" else ["melee","hit"])
	skill.base_stats = {"damage":1.0,"range":1.0,"projectile_speed":1.0,"stun_build":0.0,"cast_time":0.0,"cooldown":0.0}
	var gems: Array[ZorxGemData] = []
	var result := ZorxBuildCalc.calc_skill(skill,gems,tree,run)
	if _basics.size() >= 64: _basics.erase(_basics.keys()[0])
	_basics[key] = result.duplicate(true)
	return result

## Whether the weapon family fits the build. With a `card` the class decides the tree (class_style), so
## any weapon the class may hold (Profile.card_can_wear) fits: returns true. "" = the legacy weapon-led rule.
static func can_equip(profile, family: String, card: String = "") -> bool:
	if not enabled() or not card.is_empty(): return true
	var start := start_for(family)
	return not start.is_empty() and (not has_allocated_passives(profile.skill_build) or profile.skill_build.get("start", "") == start)

## Only an empty tree or its own single start node is free to follow a new weapon.
static func has_allocated_passives(value: Dictionary) -> bool:
	var owned = value.get("allocated", [])
	if not owned is Array: return true
	if owned.is_empty(): return false
	return owned.size()!=1 or str(owned[0])!="start_"+str(value.get("start",""))

## Legacy weapon-led path only: per-card builds follow the class, never the weapon item.
static func follow_unspent_weapon(profile, family: String, card: String = "") -> void:
	if not card.is_empty() or not enabled() or has_allocated_passives(profile.skill_build): return
	var start := start_for(family)
	if start.is_empty(): return
	profile.skill_build.start=start
	profile.skill_build.allocated=["start_"+start]

## Saves/resets a skill build. `card` = the class card whose build changes (per-card gear, Boss 2026-11-11):
## its tree start must match the card's class style (data/classes/<card>.json "weapon"), not the weapon item,
## because the class decides the fighting style. "" = the legacy path: the lead card, matched to its weapon.
static func apply(profile, request: Dictionary, card: String = "") -> Dictionary:
	if not enabled(): return {"ok": false, "reason": "not_configured"}
	var build: Dictionary = profile.build_of(card)
	var action: String = request.get("action", "")
	if action == "reset":
		var cost := int(config().reskill_gold)
		if profile.stash.gold < cost: return {"ok": false, "reason": "cannot_afford"}
		if build.get("start", "").is_empty(): return {"ok": false, "reason": "tree_already_reset"}
		profile.stash.gold -= cost
		build.start = ""
		build.allocated = []
		return {"ok": true, "gold": cost}
	if action != "save": return {"ok": false, "reason": "invalid_command"}
	var value = request.get("build", {})
	var problem := validate(value)
	if not problem.is_empty(): return {"ok": false, "reason": problem}
	var old_start: String = build.get("start", "")
	if not old_start.is_empty():
		if value.start != old_start: return {"ok": false, "reason": "reskill_required"}
		for id in build.get("allocated", []):
			if not id in value.allocated: return {"ok": false, "reason": "reskill_required"}
	if card.is_empty():
		var weapon = profile.loadout.item_at("weapon", 0)
		if weapon == null or start_for(weapon.weapon_type) != value.start: return {"ok": false, "reason": "weapon_tree_mismatch"}
		profile.skill_build = value.duplicate(true)
	else:
		if start_for(class_style(card)) != value.start: return {"ok": false, "reason": "weapon_tree_mismatch"}
		profile.card_gear[card]["skill_build"] = value.duplicate(true)
	return {"ok": true}


## The fighting style of a class card (its combat weapon id, data/classes/<card>.json "weapon").
static func class_style(card: String) -> String:
	return str(preload("res://logic/card_deck.gd").class_data(card).get("weapon", ""))
