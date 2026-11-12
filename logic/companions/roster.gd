extends RefCounted
## Shared authored identity; no account, token, currency or player-derived profile.
static func get_entry(id: String) -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string("res://data/companions/roster.json"))
	return value.get("adventurers", {}).get(id, {}).duplicate(true) if value is Dictionary else {}

static func make_profile(id: String, rules, camp, round_seed: int = -1):
	var entry := get_entry(id)
	if entry.is_empty(): return null
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.seed) if round_seed < 0 else round_seed
	var profile = preload("res://logic/profile.gd").new_player(rules, camp, rng)
	profile.name = str(entry.name)
	profile.created = true
	profile.appearance = entry.appearance.duplicate(true)
	profile.stash.items.clear()
	profile.stash.gold = 0
	profile.stash.materials.clear()
	profile.vault.items.clear()
	profile.vault.gold = 0
	profile.vault.materials.clear()
	if round_seed >= 0: _randomize(profile, rules, rng)
	return profile

static func _pick(values: Array, rng: RandomNumberGenerator):
	return values[rng.randi_range(0, values.size()-1)]

static func _randomize(profile, rules, rng: RandomNumberGenerator) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/companions/roster.json"))
	var config: Dictionary = data.randomization
	profile.name = str(_pick(config.names,rng)) + str(rng.randi_range(10,99))
	var families: Array = config.weapon_families.filter(func(f):return not rules.catalog.candidates("weapon",str(f),999).is_empty())
	var family: String = str(_pick(families,rng))
	var slots: Array = ["weapon"]
	slots.append_array(config.armor_slots)
	for slot in slots:
		var candidates: Array = rules.catalog.candidates(slot,family if slot=="weapon" else "",999)
		if candidates.is_empty(): continue
		var item_id: String = str(_pick(candidates,rng))
		var tier := rng.randi_range(0,mini(int(config.max_tier),rules.tiers.size()-1))
		var item = preload("res://logic/item_system.gd").create_item(rules,"companion-"+slot,slot,tier,rng,family if slot=="weapon" else "",item_id)
		assert(item != null)
		var equipped: bool = profile.loadout.equip(item)
		assert(equipped)
	var options = preload("res://logic/cosmetic_options.gd").load_default()
	profile.appearance = options.starter()
	for part in ["eye_color","skin"]:
		var choices: Array = options.choices.get(part,[])
		if not choices.is_empty(): profile.appearance[part] = _pick(choices,rng).id
	# (skills: the sim gives the fighter its weapon style's class skills, GameSim.attach_run; PO default 2026-11-13)
