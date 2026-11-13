extends RefCounted
## Tests the item catalog made from the model team's assets: every item points at a ready model,
## set bonuses add up by pieces worn, drops and the starter gear are catalog items, and the
## character puts the pieces on (clothing on the shared skeleton, daggers in both hands).
## (Run `godot --headless --path . --import` once after the model team delivers new art/items.)

const CharacterModel := preload("res://client/character_model.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Hud := preload("res://client/hud.gd")
const Item := preload("res://logic/item.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemText := preload("res://client/item_text.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")
const Loot := preload("res://logic/loot.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const Profile := preload("res://logic/profile.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const Stats := preload("res://logic/stats.gd")
const TestKit := preload("res://client/test_kit.gd")

const AEGIS := ["aegis_helmet", "aegis_cuirass", "aegis_bracers", "aegis_tassets", "aegis_sabatons"]


func run(ctx) -> void:
	var rules := ItemRulesLoader.load_default()
	ctx.check("the rule book with the catalog is valid %s" % [rules.errors], rules.is_valid())
	var catalog = rules.catalog
	ctx.check("the catalog has the model team's weapons and clothing (%d items, %d sets)" % [catalog.items.size(), catalog.sets.size()], catalog.items.size() >= 100 and catalog.sets.size() >= 19)
	var not_english: Array[String] = []
	for item_id in catalog.items:
		var name: String = catalog.items[item_id]["name"]
		for index in name.length():
			if name.unicode_at(index) > 127:
				not_english.append(name)
				break
	for set_id in catalog.sets:
		if catalog.sets[set_id]["name"] == set_id:
			not_english.append(set_id)
	ctx.check("every item and set has an English name the web font can show (bad: %s)" % [not_english], not_english.is_empty())
	var rng := RandomNumberGenerator.new()
	var katana = ItemSystem.create_item(rules, "k", "weapon", 1, rng, "", "blade_05")
	ctx.check("a catalog item is titled by its own name (%s)" % ItemText.title(katana, rules), ItemText.title(katana, rules) == "Rare Golden Blossom Katana")
	var cuirass = ItemSystem.create_item(rules, "h", "shirt", 0, rng, "", "armor_ash_steel_shirt")
	var line := ItemText.set_text(cuirass, rules, ["armor_ash_steel_shirt", "armor_ash_steel_pants"])
	ctx.check("the set line names the set, pieces worn and the next bonus (%s)" % line, line.begins_with("Ash Knight (Heavy) 2/4: ") and line.contains("(3: "))
	ctx.check("a piece with no set has no set line", ItemText.set_text(katana, rules, []) == "")
	var no_icon: Array[String] = []
	for item_id in catalog.items:
		if catalog.items[item_id].get("procedural", false):
			continue  # a look built in code (off-hand round shield): its slot shape is drawn, like a plain piece
		if ItemAssets.icon(ItemSystem.create_item(rules, "i", catalog.items[item_id]["slot"], 0, rng, "", item_id), catalog) == null:
			no_icon.append(item_id)
	ctx.check("catalog items have an inventory icon from the model team's preview (none: %s)" % [no_icon], no_icon.is_empty())
	ctx.check("a plain piece has no icon picture (its slot shape is drawn)", ItemAssets.icon(ItemSystem.create_item(rules, "p", "ring", 0, rng), catalog) == null)
	_test_assets(ctx, catalog)
	_test_sets(ctx, rules, catalog)
	_test_drops(ctx, rules)
	_test_kit(ctx, rules)
	await _test_model(ctx, rules, catalog)


func _test_assets(ctx, catalog) -> void:
	var missing: Array[String] = []
	var combat := CombatDataLoader.load_default()
	var bad_type: Array[String] = []
	for item_id in catalog.items:
		var item: Dictionary = catalog.items[item_id]
		if ItemAssets.path(item["asset_id"]).is_empty() and not item.get("procedural", false):
			missing.append(item_id)
		if item["slot"] == "weapon" and not combat.styles.has(item["weapon_type"]):
			bad_type.append(item_id)
	ctx.check("every catalog item points at a ready model in the manifest (missing: %s)" % [missing], missing.is_empty())
	ctx.check("every catalog weapon is a combat style the game has (wrong: %s)" % [bad_type], bad_type.is_empty())
	# Character Studio parity migration (2026-10-23): EMPTY_LOOKS is now deliberately empty for
	# every slot — the native body/fashion rig supplies the base look; old garment placeholders
	# use an incompatible rig. An unset slot simply resolves to no override asset.
	ctx.check("an empty shirt/pants slot has no override asset (native body supplies the base)", ItemAssets.path(ItemAssets.EMPTY_LOOKS.get("shirt", "")).is_empty() and ItemAssets.path(ItemAssets.EMPTY_LOOKS.get("pants", "")).is_empty())
	ctx.check("an unknown asset id has no model (a stand-in is shown)", ItemAssets.path("no_such_asset").is_empty())
	# The model team's budget: a whole set stays within its triangle budget.
	var per_set := {}
	var budget := {}
	for item_id in catalog.items:
		var item: Dictionary = catalog.items[item_id]
		if item["set"].is_empty() or str(catalog.sets[item["set"]].get("kind", "")) == "race":
			continue  # race sets reuse the class starter meshes until the Studio files land (docs/art/race_gear_handoff.md)
		var asset := ItemAssets.entry(item["asset_id"])
		per_set[item["set"]] = int(per_set.get(item["set"], 0)) + int(asset.get("triangle_count", 0))
		budget[item["set"]] = int(asset.get("set_triangle_budget", 1500))
	var over: Array[String] = []
	for set_id in per_set:
		if per_set[set_id] > budget[set_id]:
			over.append("%s %d" % [set_id, per_set[set_id]])
	ctx.check("every set is within its triangle budget (over: %s)" % [over], over.is_empty())


func _test_sets(ctx, rules, catalog) -> void:
	var set_id: String = catalog.entry("aegis_helmet")["set"]
	ctx.check("the Aegis pieces are one set with a bonus table", not set_id.is_empty() and catalog.sets[set_id]["bonuses"].size() == 4)
	var bonuses: Array = catalog.sets[set_id]["bonuses"]
	ctx.check("one piece gives no set bonus", catalog.set_bonus(["aegis_helmet"]).is_empty())
	var two: Dictionary = catalog.set_bonus(["aegis_helmet", "aegis_cuirass"])
	ctx.check("two pieces give the first bonus only", two.size() == 1 and is_equal_approx(two.get(bonuses[0]["stat"], 0.0), bonuses[0]["value"]))
	var five: Dictionary = catalog.set_bonus(AEGIS)
	var expected := {}
	for bonus in bonuses:
		expected[bonus["stat"]] = float(expected.get(bonus["stat"], 0.0)) + bonus["value"]
	ctx.check("all five pieces give every step of the bonus", five == expected)
	ctx.check("pieces of different sets do not count together", catalog.set_bonus(["aegis_helmet", "knight_cuirass"]).is_empty())
	# The bonus reaches the character's stats.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worn: Array = []
	for item_id in AEGIS:
		worn.append(ItemSystem.create_item(rules, item_id, catalog.entry(item_id)["slot"], 0, rng, "", item_id))
	var plain: Array = []
	for item in worn:
		var copy = item.duplicate_item()
		copy.item_id = ""
		plain.append(copy)
	var with_set: Dictionary = Stats.totals(rules, _typed(worn))
	var without: Dictionary = Stats.totals(rules, _typed(plain))
	var adds := true
	for stat in expected:
		adds = adds and is_equal_approx(with_set[stat] - without[stat], expected[stat])
	ctx.check("the worn set's bonus is added to the stat totals", adds)
	var broken = worn[0].duplicate_item()
	broken.destroyed = true
	var counted: Dictionary = Stats.totals(rules, _typed([broken, worn[1]]))
	ctx.check("a destroyed piece does not count toward its set", counted == Stats.totals(rules, _typed([plain[1]])))
	ctx.check("a catalog item keeps its id when copied", worn[0].duplicate_item().item_id == "aegis_helmet")


func _test_drops(ctx, rules) -> void:
	var loot := LootDataLoader.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var named := 0
	var weapons_ok := true
	var body_ok := true
	var total := 0
	for i in 400:
		var drop := Loot.roll(rules, loot, "brute", 3, ["fists", "blade", "dagger", "spear", "hammer"], rng)
		for item in drop["items"]:
			total += 1
			if not item.item_id.is_empty():
				named += 1
				var base: Dictionary = rules.catalog.entry(item.item_id)
				body_ok = body_ok and base["slot"] == item.slot
				if item.slot == "weapon":
					weapons_ok = weapons_ok and base["weapon_type"] == item.weapon_type
			else:
				body_ok = false  # Boss 2026-10-15: a piece with no model (accessory, back, fists) never drops
	ctx.check("every dropped piece is a catalog item: only pieces with a model drop (%d of %d named)" % [named, total], total > 0 and named == total and body_ok)
	var allowed: Dictionary = rules.catalog.droppable(["weapon", "shirt", "ring", "back"], ["fists", "blade"], 1)
	ctx.check("slots and weapon types with no catalog item cannot drop (%s)" % [allowed], allowed["slots"] == ["weapon", "shirt"] and allowed["weapon_types"] == ["blade"])
	ctx.check("a dropped catalog weapon has the catalog's weapon type", weapons_ok)
	var profile = Profile.new_player(rules, CampDataLoader.load_default(), rng)
	var weapon = profile.loadout.item_at("weapon")
	ctx.check("the starter gear is catalog items (%s, %s, %s)" % [weapon.item_id, profile.loadout.item_at("shirt").item_id, profile.loadout.item_at("shoes").item_id], weapon.item_id == "race_human_sword_shield_weapon" and profile.loadout.item_at("shirt").item_id == "race_human_sword_shield_shirt" and profile.loadout.item_at("shoes").item_id == "race_human_sword_shield_shoes")


## The Boss test kit: one of every catalog item not worn, all of it fits in the stash.
func _test_kit(ctx, rules) -> void:
	var camp := CampDataLoader.load_default()
	var base_slots: int = camp.stash_slots
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var profile = Profile.new_player(rules, camp, rng)
	var added := TestKit.fill(profile, rules, camp, rng)
	var ids := {}
	for item in profile.stash.items:
		ids[item.item_id] = true
	var worn := 0
	for slot_id in ["weapon", "shirt", "pants", "armband", "shoes", "offhand"]:
		worn += 1 if profile.loadout.item_at(slot_id) != null and rules.catalog.items.has(profile.loadout.item_at(slot_id).item_id) else 0
	ctx.check("the test kit puts every catalog item that is not worn in the stash (%d + %d worn of %d)" % [added, worn, rules.catalog.items.size()], added == rules.catalog.items.size() - worn and ids.size() == added)
	ctx.check("the stash grows to fit the kit and keeps its normal free room (%d free of %d)" % [profile.stash.free_slots(), profile.stash.capacity], profile.stash.free_slots() >= base_slots - profile.stash.materials.size())


func _test_model(ctx, rules, catalog) -> void:
	var model := CharacterModel.new()
	ctx.root.add_child(model)
	if not model.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb"):
		ctx.check("the chibi model loads", false)
		model.queue_free()
		return
	ctx.check("the chibi is scaled to the game's body height (%.3f)" % model.model_height(), absf(model.model_height() - 1.8) < 0.02)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var loadout := Loadout.new(rules)
	var bare := ItemAssets.looks(loadout, catalog, "fists")
	model.dress(bare)
	var worn: Dictionary = model.worn_paths()
	ctx.check("with nothing worn the basic shirt and pants show, and only those", worn.size() == 2 and worn.has("shirt") and worn.has("pants"))
	ctx.check("with nothing on the head the hair shows", model.is_hair_shown())
	for item_id in AEGIS:
		loadout.equip(ItemSystem.create_item(rules, item_id, catalog.entry(item_id)["slot"], 0, rng, "", item_id))
	loadout.equip(ItemSystem.create_item(rules, "daggers", "weapon", 0, rng, "", "dagger_02"))
	model.dress(ItemAssets.looks(loadout, catalog, loadout.weapon_style(["fists", "blade", "dagger", "spear", "hammer"])))
	worn = model.worn_paths()
	ctx.check("the whole Aegis set is worn (%d pieces)" % worn.size(), worn.size() == 5 and str(worn["hat"]).ends_with("clothing_aegis_helmet_01.glb"))
	ctx.check("the Aegis helmet hides the hair", not model.is_hair_shown())
	ctx.check("twin daggers sit in both hands", model.has_weapon_model() and model.has_left_weapon())
	ctx.check("the clothing moves with the character's own skeleton", _skinned_to(model, model._skeleton))
	model.set_pose("run", 0.5, 1.0, true, Vector2(1.0, 0.0), false)
	model.apply_pose(0.016)
	loadout.unequip("hat")
	loadout.unequip("weapon")
	model.dress(ItemAssets.looks(loadout, catalog, loadout.weapon_style(["fists"])))
	ctx.check("taking the helmet off brings the hair back and frees the slot", model.is_hair_shown() and not model.worn_paths().has("hat"))
	ctx.check("bare hands after the daggers come off", not model.has_weapon_model() and not model.has_left_weapon())
	# The model team's weapons draw a swing trail between their own trail points while the blow is live.
	loadout.equip(ItemSystem.create_item(rules, "katana", "weapon", 0, rng, "", "blade_05"))
	model.dress(ItemAssets.looks(loadout, catalog, "blade"))
	ctx.check("a catalog weapon with trail points gets a swing trail", model.has_blade_trail())
	model.set_pose("heavy", 0.0, 0.0, true, Vector2(1.0, 0.0), false, "windup", "light_1", "blade")
	model.apply_pose(0.016)
	await ctx.process_frame
	ctx.check("no trail before the blow lands", not model.is_trailing())
	for step in 4:
		model.set_pose("heavy", 0.25 * step, 0.0, true, Vector2(1.0, 0.0), false, "strike", "light_1", "blade")
		model.apply_pose(0.016)
		await ctx.process_frame
	ctx.check("the trail draws during the strike", model.is_trailing())
	model.queue_free()
	_test_loot_feed(ctx)


func _skinned_to(model, skeleton: Skeleton3D) -> bool:
	for child in skeleton.get_children():
		if child is MeshInstance3D and child.visible and child.skin != null:
			if child.get_node_or_null(child.skeleton) != skeleton:
				return false
	return true


static func _typed(items: Array) -> Array[Item]:
	var result: Array[Item] = []
	for item in items:
		result.append(item)
	return result


func _test_loot_feed(ctx) -> void:
	var hud: CanvasLayer = Hud.new()
	ctx.root.add_child(hud)
	hud.add_loot("+ Golden Blossom Katana  Rare", Color.CORNFLOWER_BLUE, ItemAssets.icon_for_id("blade_05", ItemRulesLoader.load_default().catalog))
	hud.add_loot("+ 12 gold", Color.GOLD)
	ctx.check("the loot feed lists what went into the bag", hud.loot_lines() == ["+ Golden Blossom Katana  Rare", "+ 12 gold"])
	for i in 10:
		hud.add_loot("+ %d Ore" % i, Color.WHITE)
	ctx.check("the loot feed keeps only the latest lines (%d)" % hud.loot_lines().size(), hud.loot_lines().size() == Hud.LOOT_LINES and hud.loot_lines()[-1] == "+ 9 Ore")
	hud.queue_free()
