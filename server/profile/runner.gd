extends RefCounted
## Trusted Nakama-to-Godot boundary. Never accepts client snapshots or journey state.
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
const Camp := preload("res://logic/camp.gd")
const ALLOWED := ["relic_equip", "mall_buy", "farm_seed", "farm_plant", "farm_harvest", "skill_build", "storage_item", "storage_material", "upgrade", "shop_buy", "shop_sell", "shop_sell_material", "shop_sell_batch", "refine", "equip", "unequip", "discard", "discard_material", "repair", "repair_all", "upgrade_camp", "upgrade_facility", "appearance", "randomize_appearance", "enhance", "upgrade_tier"]
var rules = preload("res://logic/item_rules_loader.gd").load_default()
var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
var cosmetics = preload("res://logic/cosmetic_options.gd").load_default()

func ready() -> bool:
	return rules.errors.is_empty() and camp.errors.is_empty() and cosmetics.errors.is_empty()

func execute(request: Variant) -> Dictionary:
	if not ready(): return failure("not_configured")
	if not request is Dictionary or request.size() != 5 or not request.has_all(["v", "state", "seed", "name", "command"]) or not request.v is float and not request.v is int or request.v != 1:
		return failure("invalid_payload")
	if not request.name is String or not request.seed is String or RegEx.create_from_string("^[a-f0-9]{15}$").search(request.seed) == null:
		return failure("invalid_payload")
	if not request.name.is_empty() and not Profile.name_problem(request.name).is_empty(): return failure("invalid_state")
	var rng := RandomNumberGenerator.new()
	var profile
	if request.state == null:
		rng.seed = request.seed.hex_to_int()
		profile = Profile.new_player(rules, camp, rng)
		profile.appearance = cosmetics.starter()
	else:
		if not request.state is Dictionary or not request.state.has_all(["profile", "rng_state"]) or not request.state.profile is Dictionary or not request.state.rng_state is String:
			return failure("invalid_state")
		var saved: Dictionary = request.state.profile
		if not saved.has_all(["v", "stash", "loadout", "camp_level", "facility_levels", "appearance", "name", "created"]): return failure("invalid_state")
		if RegEx.create_from_string("^-?[0-9]{1,20}$").search(request.state.rng_state) == null: return failure("invalid_state")
		profile = Profile.from_dict(saved, rules, camp)
		if profile == null: return failure("invalid_state")
		rng.state = int(request.state.rng_state)
	profile.armor_migration_version = 2
	_repair_wave_chest_ids(profile)
	if profile.appearance.is_empty(): profile.appearance = cosmetics.starter()
	# Retire the v1 staging catalog grant. Preserve equipped gear and earned loot.
	# Run only once; a later unequip of a retained beta item must remain valid ownership.
	if profile.beta_kit_version == 1:
		for index in range(profile.stash.items.size() - 1, -1, -1):
			var item = profile.stash.items[index]
			if item.id == "beta-v1-" + item.item_id and rules.catalog.items.has(item.item_id):
				profile.stash.items.remove_at(index)
		profile.bonus_stash_slots = 0
		Camp.refresh(profile, camp)
		# Do not discard earned items/materials when retiring the temporary capacity.
		profile.bonus_stash_slots = maxi(0, profile.stash.slots_used() - profile.stash.capacity)
		profile.beta_kit_version = 2
	profile.ensure_starter_weapons(rules, rng)
	profile.ensure_starter_armor(rules, rng)
	# Reserve only the capacity needed for this bounded starter kit; never discard earned gear.
	Camp.refresh(profile, camp)
	profile.bonus_stash_slots += maxi(0, profile.stash.slots_used() - profile.stash.capacity)
	# Names are projected from the separate authoritative reservation, never client input.
	profile.name = request.name
	profile.created = not request.name.is_empty()
	Camp.refresh(profile, camp)
	var result := {"ok": true}
	if request.command != null:
		if not request.command is Dictionary: return failure("invalid_payload")
		var kind = request.command.get("type")
		if kind == "set_name": return failure("name_rpc_required")
		if not kind in ALLOWED: return failure("not_available_here")
		result = Commands.apply({"now":int(Time.get_unix_time_from_system()),"profile": profile, "rules": rules, "camp": camp, "cosmetics": cosmetics, "location": "camp"}, request.command, rng)
		if not result.get("ok", false): return result
	return {"v": 1, "ok": true, "profile": profile.to_dict(), "rng_state": str(rng.state), "result": result}

static func failure(reason: String) -> Dictionary:
	return {"v": 1, "ok": false, "error": reason}

## Only trusted stored profiles enter this runner. Retain the first legacy ID
## and all earned items; repair collisions caused by the old wave-chest IDs.
static func _repair_wave_chest_ids(profile) -> void:
	var containers: Array = [profile.loadout._equipped.values(), profile.stash.items, profile.vault.items]
	var used := {}
	for items in containers:
		for item in items: used[item.id] = true
	var seen := {}
	for items in containers:
		for item in items:
			var original: String = item.id
			if seen.has(original) and original.begins_with("treasure-"):
				var suffix := 1
				while used.has(original + "-recovered-%d" % suffix): suffix += 1
				item.id = original + "-recovered-%d" % suffix
				used[item.id] = true
			seen[original] = true


func recover(request: Variant) -> Dictionary:
	var result := execute(request)
	if not result.get("ok", false): return result
	var p = Profile.from_dict(result.profile, rules, camp)
	var trip = preload("res://logic/run.gd").start(p, camp)
	trip.death()
	preload("res://logic/wear.gd").death(trip.loadout(), rules)
	return {"v": 1, "ok": true, "profile": p.to_dict(), "rng_state": result.rng_state}
