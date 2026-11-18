extends RefCounted
## Boss-approved perf fix 2026-11-18: a snapshot that moves only the loot bag / worn-gear wear / stash must not rebuild the
## whole Profile. Same resulting state as the full rebuild (Profile.from_dict + copy_fields), and the Lag report "cost"
## section survives the report codec.
const F := preload("res://tests/online_fixture.gd")
const Patch := preload("res://runtime/netfox/profile_patch.gd")
const Session := preload("res://client/session/online_session.gd")
const FIELDS := ["stash", "vault", "loadout", "camp_level", "facility_levels", "farm", "appearance", "name", "created", "beta_kit_version", "diamonds", "mall_owned", "bonus_stash_slots"]

func _wire(profile) -> Dictionary:
	var raw: Dictionary = profile.to_dict()
	raw.erase("card_deck"); raw.erase("card_gear")  # the room snapshot has none
	return JSON.parse_string(JSON.stringify(raw))

func _state(profile) -> Dictionary:
	var out := {}
	for field in FIELDS:
		var v = profile.get(field)
		out[field] = v.to_dict() if v is Object else v
	return out

func run(ctx) -> void:
	var f := F.make(77)
	preload("res://logic/test_kit.gd").fill(f.profile, f.rules, f.camp, F.rng())
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var base := _wire(f.profile)
	var P = preload("res://logic/profile.gd")
	var live = P.from_dict(base, f.rules, f.camp)  # what the client holds (cards adopted separately: not touched)
	var previous := base
	var all_equal := true; var patched := 0; var full := 0
	for round in 24:
		# a random server-side change: worn-item wear, stash gold/materials/items, or something outside the patchable set
		var next: Dictionary = previous.duplicate(true)
		var kind := rng.randi_range(0, 4)
		match kind:
			0:
				var keys: Array = next.loadout.equipped.keys()
				var item: Dictionary = next.loadout.equipped[keys[rng.randi() % keys.size()]]
				item.durability = preload("res://logic/state_codec.gd").float_text(rng.randf_range(1.0, 40.0))
				item.refine_level = rng.randi_range(0, 3)
			1: next.stash.gold = str(rng.randi_range(0, 9999))
			2: next.stash.materials["ore"] = rng.randi_range(0, 50)
			3: next.vault.gold = str(rng.randi_range(0, 9999))
			4: next.diamonds = rng.randi_range(0, 999)  # NOT patchable: must take the full path
		var ok: bool = Patch.apply(live, previous, next, f.rules, f.camp)
		var reference = P.from_dict(next, f.rules, f.camp)
		if ok:
			patched += 1
			var expected_full = P.from_dict(previous, f.rules, f.camp)  # the same dance the old code did, on a copy
			Session.copy_fields(reference, expected_full, FIELDS)
			if _state(live) != _state(expected_full): all_equal = false
		else:
			full += 1
			Session.copy_fields(reference, live, FIELDS)
		if _state(live) != _state(reference) and ok: all_equal = false
		previous = next
	ctx.check("profile patch: patched state equals the full rebuild for random bag/gear/stash changes", all_equal)
	ctx.check("profile patch: the patchable changes took the cheap path, the others the full one", patched >= 10 and full >= 1)
	# a swapped worn piece and an unrelated field are refused (full rebuild)
	var swapped: Dictionary = base.duplicate(true)
	var first_key: String = swapped.loadout.equipped.keys()[0]
	swapped.loadout.equipped[first_key].id = "someone-elses-piece"
	ctx.check("profile patch: a different worn item takes the full path", not Patch.apply(live, base, swapped, f.rules, f.camp))
	var renamed: Dictionary = base.duplicate(true); renamed.name = "Other"
	ctx.check("profile patch: a name change takes the full path", not Patch.apply(live, base, renamed, f.rules, f.camp))
	ctx.check("profile patch: no previous block takes the full path", not Patch.apply(live, {}, base, f.rules, f.camp))
	# Lag report cost section: round trip through the report codec, size stays small
	var Cost := preload("res://client/lag_cost.gd")
	Cost.reset()
	Cost.note_profile(12000, false); Cost.note_profile(0, true); Cost.note_view_build(5000, 17)
	for i in 400: Cost.slow_frames.append([i, 150, "view_build", 90, 1, 2, 90, 0, 150, 3]); 
	while Cost.slow_frames.size() > Cost.SLOW_KEPT: Cost.slow_frames.pop_front()
	for s in 10: Cost.buckets.append([s, 60, 20, 50, 1, 12, 3, 9, 30, 150, 150, 2, 70])
	var report := {"v": 2, "client": {"cost": Cost.export(), "incidents": [], "live": {"events": [], "samples": []}}, "worker": {}}
	var encoded = preload("res://runtime/diagnostics/report_codec.gd").encode(report)
	ctx.check("lag cost: report encodes", encoded.get("ok", false))
	var decoded = preload("res://runtime/diagnostics/report_codec.gd").decode(encoded)
	ctx.check("lag cost: round trip keeps the cost section", decoded.get("client", {}).get("cost", {}) == JSON.parse_string(JSON.stringify(report.client.cost)))
	ctx.check("lag cost: section is small", JSON.stringify(Cost.export()).length() < 3000)
	ctx.check("lag cost: totals count the full and in-place rebuilds", Cost.export().totals.profile_full == 1 and Cost.export().totals.profile_inplace == 1 and Cost.export().totals.view_nodes == 17)
	Cost.reset()
