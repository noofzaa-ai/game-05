extends RefCounted
func run(ctx) -> void:
	var runner := preload("res://server/profile/runner.gd").new()
	var request := {"v": 1, "state": null, "seed": "00000000000004d", "name": "Hero", "command": null}
	var initial: Dictionary = runner.execute(request)
	var profile = preload("res://logic/profile.gd").from_dict(initial.profile, runner.rules, runner.camp)
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var test_camp = preload("res://logic/camp_data_loader.gd").load_default(runner.rules.tiers.size())
	preload("res://logic/test_kit.gd").fill(profile, runner.rules, test_camp, rng)
	for item in profile.stash.items: item.id = "beta-v1-" + item.item_id
	profile.bonus_stash_slots = profile.stash.items.size(); profile.beta_kit_version = 1
	var kept = profile.stash.items.pop_front()
	profile.loadout.equip(kept)
	var earned = kept.duplicate_item(); earned.id = "earned-drop-1"; profile.stash.items.append(earned)
	var previous: Dictionary = profile.to_dict()
	request.state = {"profile": previous, "rng_state": initial.rng_state}
	var cleaned: Dictionary = runner.execute(request)
	ctx.check("cleanup removes only catalog grant spares", cleaned.ok and cleaned.profile.stash.items.size() == 1 and cleaned.profile.stash.items[0].id == earned.id)
	ctx.check("cleanup preserves equipped set and weapon", cleaned.profile.loadout == previous.loadout)
	ctx.check("cleanup preserves earned item exact values", cleaned.profile.stash.items[0] == earned.to_dict())
	ctx.check("cleanup preserves gold materials appearance and RNG", cleaned.profile.stash.gold == previous.stash.gold and cleaned.profile.stash.materials == previous.stash.materials and cleaned.profile.appearance == previous.appearance and cleaned.rng_state == initial.rng_state)
	ctx.check("cleanup retires capacity and marks v2", cleaned.profile.beta_kit_version == 2 and cleaned.profile.bonus_stash_slots == 0 and cleaned.profile.stash.capacity == preload("res://logic/camp.gd").stash_slots(preload("res://logic/profile.gd").from_dict(cleaned.profile, runner.rules, runner.camp), runner.camp))
	ctx.check("cleanup never mutates borrowed storage", request.state.profile == previous and previous.stash.items.size() > 100)
	request.state = {"profile": cleaned.profile, "rng_state": cleaned.rng_state}
	ctx.check("cleanup is idempotent", runner.execute(request).profile == cleaned.profile)
	request.command = {"type": "unequip", "slot": kept.slot, "destination": "stash"}
	var unequipped: Dictionary = runner.execute(request)
	request.command = null; request.state = {"profile": unequipped.profile, "rng_state": unequipped.rng_state}
	ctx.check("retained gear survives later unequip and reload", runner.execute(request).profile.stash.items.size() == 2)
	var overflowing: Dictionary = previous.duplicate(true)
	for index in 60:
		var extra: Dictionary = earned.to_dict(); extra.id = "earned-extra-%d" % index
		overflowing.stash.items.append(extra)
	overflowing.stash.capacity = 500
	request.state = {"profile": overflowing, "rng_state": initial.rng_state}
	var retained: Dictionary = runner.execute(request)
	ctx.check("cleanup preserves earned overflow with bounded capacity", retained.ok and retained.profile.stash.items.size() == 61 and retained.profile.stash.capacity >= 61 and retained.profile.bonus_stash_slots > 0)
	var old_env := OS.get_environment("ZORX_BETA_TEST_KIT")
	OS.set_environment("ZORX_BETA_TEST_KIT", "1")
	request.state = null
	ctx.check("legacy environment cannot regrant full catalog", runner.execute(request).profile.stash.items.all(func(item): return str(item.id).begins_with("starter-")))
	OS.set_environment("ZORX_BETA_TEST_KIT", old_env)
