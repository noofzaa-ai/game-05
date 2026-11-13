extends RefCounted
## Tests the item catalog (race gear only since the legacy items were removed, Boss 2026-11-13): every item has its
## model file and icon, drops and the starter gear are catalog items, the test kit, and the loot feed.
## (The old generic-set and chibi clothing/dagger/katana model checks left with the legacy items.)

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



func run(ctx) -> void:
	var rules := ItemRulesLoader.load_default()
	ctx.check("the rule book with the catalog is valid %s" % [rules.errors], rules.is_valid())
	var catalog = rules.catalog
	ctx.check("the catalog has the model team's weapons and clothing (%d items, %d sets)" % [catalog.items.size(), catalog.sets.size()], catalog.items.size() >= 84 and catalog.sets.size() >= 4)
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
	var katana = ItemSystem.create_item(rules, "k", "weapon", 1, rng, "", "race_human_sword_shield_weapon")
	ctx.check("a catalog item is titled by its own name (%s)" % ItemText.title(katana, rules), ItemText.title(katana, rules) == "Rare Human Sword")
	var shield = ItemSystem.create_item(rules, "s", "offhand", 0, rng, "", "race_human_shield")
	ctx.check("a piece with no set has no set line", ItemText.set_text(shield, rules, []) == "")
	var no_icon: Array[String] = []
	for item_id in catalog.items:
		if catalog.items[item_id].get("procedural", false):
			continue  # a look built in code (off-hand round shield): its slot shape is drawn, like a plain piece
		if ItemAssets.icon(ItemSystem.create_item(rules, "i", catalog.items[item_id]["slot"], 0, rng, "", item_id), catalog) == null:
			no_icon.append(item_id)
	ctx.check("catalog items have an inventory icon from the model team's preview (none: %s)" % [no_icon], no_icon.is_empty())
	ctx.check("a plain piece has no icon picture (its slot shape is drawn)", ItemAssets.icon(ItemSystem.create_item(rules, "p", "ring", 0, rng), catalog) == null)
	_test_assets(ctx, catalog)
	_test_drops(ctx, rules)
	_test_kit(ctx, rules)
	ctx.check("a catalog item keeps its id when copied", ItemSystem.create_item(rules, "c", "shirt", 0, rng, "", "race_elf_magic_shirt").duplicate_item().item_id == "race_elf_magic_shirt")
	_test_loot_feed(ctx)


func _test_assets(ctx, catalog) -> void:
	var missing: Array[String] = []
	var combat := CombatDataLoader.load_default()
	var bad_type: Array[String] = []
	for item_id in catalog.items:
		var item: Dictionary = catalog.items[item_id]
		var file := ItemAssets.armor_file(item) if item["slot"] in ItemAssets.BODY_SLOTS else str(item["asset_path"])
		if (file.is_empty() or not ResourceLoader.exists(file)) and not item.get("procedural", false):
			missing.append(item_id)
		if item["slot"] == "weapon" and not combat.styles.has(item["weapon_type"]):
			bad_type.append(item_id)
	ctx.check("every catalog item has its model file (race file or the race's shared file; missing: %s)" % [missing], missing.is_empty())
	ctx.check("every catalog weapon is a combat style the game has (wrong: %s)" % [bad_type], bad_type.is_empty())
	# Character Studio parity migration (2026-10-23): EMPTY_LOOKS is now deliberately empty for
	# every slot — the native body/fashion rig supplies the base look; old garment placeholders
	# use an incompatible rig. An unset slot simply resolves to no override asset.
	ctx.check("an empty shirt/pants slot has no override asset (native body supplies the base)", ItemAssets.path(ItemAssets.EMPTY_LOOKS.get("shirt", "")).is_empty() and ItemAssets.path(ItemAssets.EMPTY_LOOKS.get("pants", "")).is_empty())
	ctx.check("an unknown asset id has no model (a stand-in is shown)", ItemAssets.path("no_such_asset").is_empty())


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
	hud.add_loot("+ Human Sword  Rare", Color.CORNFLOWER_BLUE, ItemAssets.icon_for_id("race_human_sword_shield_weapon", ItemRulesLoader.load_default().catalog))
	hud.add_loot("+ 12 gold", Color.GOLD)
	ctx.check("the loot feed lists what went into the bag", hud.loot_lines() == ["+ Human Sword  Rare", "+ 12 gold"])
	for i in 10:
		hud.add_loot("+ %d Ore" % i, Color.WHITE)
	ctx.check("the loot feed keeps only the latest lines (%d)" % hud.loot_lines().size(), hud.loot_lines().size() == Hud.LOOT_LINES and hud.loot_lines()[-1] == "+ 9 Ore")
	hud.queue_free()
