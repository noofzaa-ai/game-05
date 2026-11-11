extends RefCounted
## Tests the loot-and-camp loop: durability and repair, the run bag and stash, drops, dying and
## returning to camp, camp upgrades, and the simulation tying them to a fight.

const Camp := preload("res://logic/camp.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Fighter := preload("res://logic/fighter.gd")
const GameSim := preload("res://logic/game_sim.gd")
const Inventory := preload("res://logic/inventory.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loot := preload("res://logic/loot.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Repair := preload("res://logic/repair.gd")
const Run := preload("res://logic/run.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const Wear := preload("res://logic/wear.gd")

var _rules
var _camp
var _loot
var _combat


func run(ctx) -> void:
	_rules = ItemRulesLoader.load_default()
	_camp = CampDataLoader.load_default(_rules.tiers.size())
	_combat = CombatDataLoader.load_default()
	var material_ids: Array = _camp.materials.keys()
	_loot = LootDataLoader.load_default(material_ids, _rules.tiers.size())
	ctx.check("the camp data is valid %s" % [_camp.errors], _camp.is_valid())
	ctx.check("the loot data is valid %s" % [_loot.errors], _loot.is_valid())
	ctx.check("the item rules (with durability) are valid %s" % [_rules.errors], _rules.is_valid())
	if not (_camp.is_valid() and _loot.is_valid() and _rules.is_valid()):
		return
	_test_data(ctx)
	_test_durability(ctx)
	_test_inventory(ctx)
	_test_loot(ctx)
	_test_run(ctx)
	_test_wear(ctx)
	_test_camp(ctx)
	_test_repair(ctx)
	_test_simulation(ctx)
	_test_rest_and_weapon_stats(ctx)


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _profile(seed_value: int = 1):
	var profile = Profile.new_player(_rules, _camp, _rng(seed_value))
	Camp.refresh(profile, _camp)
	return profile


func _item(slot: String, tier: int = 1):
	return ItemSystem.create_item(_rules, "t-%s" % slot, slot, tier, _rng(), "blade" if slot == "weapon" else "")


func _test_data(ctx) -> void:
	for enemy_id in _combat.enemies:
		ctx.check("the monster '%s' has a loot table" % enemy_id, _loot.by_enemy.has(enemy_id))
	var camp_text := FileAccess.get_file_as_string(CampDataLoader.DATA_PATH)
	var tiers: int = _rules.tiers.size()
	ctx.check("broken camp JSON is reported", not CampDataLoader.parse("{ nope", tiers).is_valid())
	ctx.check("a repair price table of the wrong size is reported", not CampDataLoader.parse(camp_text.replace("[1.0, 1.6, 2.5, 4.0]", "[1.0, 2.0]"), tiers).is_valid())
	ctx.check("a repair material that does not exist is reported", not CampDataLoader.parse(camp_text.replace("\"essence\": 0.02", "\"mithril\": 0.02"), tiers).is_valid())
	ctx.check("camp levels out of order are reported", not CampDataLoader.parse(camp_text.replace("{\"level\": 3, \"cost\"", "{\"level\": 7, \"cost\""), tiers).is_valid())
	ctx.check("a facility needing a camp level that does not exist is reported", not CampDataLoader.parse(camp_text.replace("\"camp_level\": 5, \"cost\": {\"gold\": 4000", "\"camp_level\": 9, \"cost\": {\"gold\": 4000"), tiers).is_valid())
	ctx.check("an unknown facility effect is reported", not CampDataLoader.parse(camp_text.replace("\"repair_discount\": 0.15", "\"free_lunch\": 0.15"), tiers).is_valid())
	ctx.check("a new player cannot start with a facility that needs a higher camp level", not CampDataLoader.parse(camp_text.replace("\"start_levels\": {\"workbench\": 1, \"storage\": 1}", "\"start_levels\": {\"workbench\": 2, \"storage\": 1}"), tiers).is_valid())
	ctx.check("a skill with no stats is reported", not CampDataLoader.parse(camp_text.replace("\"stats\": {\"HP\": 60}", "\"stats\": {}"), tiers).is_valid())
	var skill_stats_known := true
	for skill in _camp.skills:
		for stat in skill["stats"]:
			skill_stats_known = skill_stats_known and _rules.stat_ids.has(stat)
	ctx.check("camp skills only give stats that exist", skill_stats_known)
	var loot_text := FileAccess.get_file_as_string(LootDataLoader.DATA_PATH)
	ctx.check("broken loot JSON is reported", not LootDataLoader.parse("{ nope").is_valid())
	ctx.check("a drop of an unknown material is reported", not LootDataLoader.parse(loot_text.replace("\"material\": \"leather\"", "\"material\": \"mithril\""), _camp.materials.keys(), tiers).is_valid())
	ctx.check("a chance above 1 is reported", not LootDataLoader.parse(loot_text.replace("\"chance\": 0.35", "\"chance\": 1.35"), _camp.materials.keys(), tiers).is_valid())
	ctx.check("tier weights of the wrong size are reported", not LootDataLoader.parse(loot_text.replace("[85, 13, 2, 0]", "[85, 15]"), _camp.materials.keys(), tiers).is_valid())
	ctx.check("an enemy pointing at a missing table is reported", not LootDataLoader.parse(loot_text.replace("\"brute\": \"brute\"", "\"brute\": \"nope\""), _camp.materials.keys(), tiers).is_valid())
	var rules_text := FileAccess.get_file_as_string(ItemRulesLoader.RULES_PATH)
	ctx.check("a durability section with a bad threshold is reported", not ItemRulesLoader.parse(rules_text.replace("\"full_stats_above\": 0.3", "\"full_stats_above\": 3")).is_valid())
	ctx.check("a missing durability section is reported", not ItemRulesLoader.parse(rules_text.replace("\"durability\": {", "\"durabilityx\": {")).is_valid())


func _test_durability(ctx) -> void:
	var item = _item("shirt", 2)
	ctx.check("a new item is at full durability", item.durability == _rules.durability_max and item.durability_ratio() == 1.0)
	ctx.check("a pristine item gives full stats", _rules.durability_factor(1.0) == 1.0 and _rules.durability_factor(_rules.durability_full_above) == 1.0)
	ctx.check("a completely worn item gives its broken-down fraction of the stats", absf(_rules.durability_factor(0.0) - _rules.durability_broken_factor) < 0.0001)
	var steady := true
	var last := 0.0
	for step in 21:
		var factor: float = _rules.durability_factor(float(step) / 20.0)
		steady = steady and factor >= last
		last = factor
	ctx.check("the stat factor only rises with durability", steady)
	var full: Dictionary = item.stat_totals(_rules)
	item.durability = 0.0
	var worn: Dictionary = item.stat_totals(_rules)
	var halved := true
	for stat in full:
		halved = halved and absf(worn[stat] - full[stat] * _rules.durability_broken_factor) < 0.001
	ctx.check("a broken-down item still gives stats, reduced", halved and item.is_broken_down() and not item.destroyed)
	var copy = item.duplicate_item()
	ctx.check("a copy of an item keeps its durability", copy.durability == 0.0 and copy.max_durability == item.max_durability)


func _test_inventory(ctx) -> void:
	var bag := Inventory.new(3, {"ore": 10})
	ctx.check("an empty bag has all its slots free", bag.free_slots() == 3 and bag.is_empty())
	ctx.check("equipment takes one slot each", bag.add_item(_item("hat")) and bag.add_item(_item("shirt")) and bag.free_slots() == 1)
	ctx.check("materials stack in a slot up to their stack size", bag.add_material("ore", 10) == 10 and bag.free_slots() == 0)
	ctx.check("a full bag takes no more equipment", not bag.add_item(_item("pants")))
	ctx.check("or materials beyond the stack", bag.add_material("ore", 5) == 0 and bag.material_count("ore") == 10)
	bag.take_item(0)
	ctx.check("removing equipment frees a slot, which a partly different stack can use", bag.add_material("ore", 15) == 10 and bag.material_count("ore") == 20)
	var wallet := Inventory.new(5, {"ore": 99})
	wallet.gold = 100
	wallet.add_material("ore", 10)
	ctx.check("a cost can be checked without paying", wallet.can_afford({"gold": 100, "materials": {"ore": 10}}) and not wallet.can_afford({"gold": 101, "materials": {}}) and not wallet.can_afford({"gold": 0, "materials": {"ore": 11}}))
	ctx.check("a cost that cannot be afforded takes nothing", not wallet.pay({"gold": 50, "materials": {"ore": 11}}) and wallet.gold == 100 and wallet.material_count("ore") == 10)
	ctx.check("paying takes gold and materials", wallet.pay({"gold": 50, "materials": {"ore": 4}}) and wallet.gold == 50 and wallet.material_count("ore") == 6)
	var lost := wallet.clear_loot()
	ctx.check("clearing the bag reports what was lost", lost["gold"] == 50 and lost["materials"]["ore"] == 6 and wallet.is_empty())
	ctx.check("gold takes no slot", Inventory.new(1, {}).free_slots() == 1)


func _test_loot(ctx) -> void:
	var weapons: Array = _combat.weapon_ids
	var a := Loot.roll(_rules, _loot, "brute", 1, weapons, _rng(5))
	var b := Loot.roll(_rules, _loot, "brute", 1, weapons, _rng(5))
	ctx.check("the same seed gives the same drops", a["gold"] == b["gold"] and a["materials"] == b["materials"] and a["items"].size() == b["items"].size())
	var none := Loot.roll(_rules, _loot, "ghost", 1, weapons, _rng(5))
	ctx.check("a monster with no loot table drops nothing", none["gold"] == 0 and none["materials"].is_empty() and none["items"].is_empty())
	var gold_range: Vector2i = _loot.tables["brute"]["gold"]
	var in_range := true
	for seed_value in 50:
		var gold: int = Loot.roll(_rules, _loot, "brute", 1, weapons, _rng(seed_value))["gold"]
		in_range = in_range and gold >= gold_range.x and gold <= gold_range.y
	ctx.check("gold stays in the table's range at level 1", in_range)
	var level_one := 0
	var level_ten := 0
	for seed_value in 50:
		level_one += Loot.roll(_rules, _loot, "brute", 1, weapons, _rng(seed_value))["gold"]
		level_ten += Loot.roll(_rules, _loot, "brute", 10, weapons, _rng(seed_value))["gold"]
	ctx.check("a higher level monster drops more gold (%d vs %d)" % [level_ten, level_one], level_ten > level_one)

	var rng := _rng(9)
	var low_tiers := 0
	var high_tiers := 0
	var items_seen := 0
	var weapon_types_ok := true
	var slots_seen := {}
	var all_modeled := true
	for i in 600:
		for item in Loot.roll(_rules, _loot, "brute", 1, weapons, rng)["items"]:
			low_tiers += item.tier
			items_seen += 1
			slots_seen[item.slot] = true
			all_modeled = all_modeled and not item.item_id.is_empty()
			weapon_types_ok = weapon_types_ok and (item.slot != "weapon" or weapons.has(item.weapon_type))
		for item in Loot.roll(_rules, _loot, "brute", 10, weapons, rng)["items"]:
			high_tiers += item.tier
	ctx.check("dropped weapons have a weapon type that exists", weapon_types_ok)
	var modeled_slots: Array = _rules.catalog.droppable(_rules.slots.map(func(s): return s["id"]), weapons, 1)["slots"]
	ctx.check("drops come in every slot that has models (%d of %d kinds)" % [slots_seen.size(), modeled_slots.size()], slots_seen.size() == modeled_slots.size() and modeled_slots.size() >= 5)
	ctx.check("every dropped piece is a catalog item (it has a model)", all_modeled)
	ctx.check("higher level monsters drop better tiers (%d vs %d over %d items)" % [high_tiers, low_tiers, items_seen], items_seen > 50 and high_tiers > low_tiers * 2)
	var chances := 0
	var ore_total := 0
	for i in 400:
		var grunt := Loot.roll(_rules, _loot, "dummy_grunt", 1, weapons, rng)
		ore_total += int(grunt["materials"].get("ore", 0))
		chances += 1
	var expected := 0.0  # chance x average count, read from the grunt's table
	for drop in _loot.tables[_loot.by_enemy["dummy_grunt"]]["drops"]:
		if drop.get("material", "") == "ore":
			expected += float(drop["chance"]) * float(drop["count"].x + drop["count"].y) * 0.5
	var per_kill := float(ore_total) / float(chances)
	ctx.check("a grunt drops ore about as often as the table says (%.2f per kill, table %.2f)" % [per_kill, expected], absf(per_kill - expected) < expected * 0.2)


func _test_run(ctx) -> void:
	var profile = _profile()
	var trip = Run.start(profile, _camp)
	ctx.check("a trip's bag has the base size at a fresh camp", trip.bag.capacity == _camp.run_slots)
	var stats: Dictionary = trip.stats(_rules)
	ctx.check("the trip's stats come from the worn gear", stats["ATK"] > _rules.stat_base["ATK"] and stats["DEF"] > _rules.stat_base["DEF"])
	var drop := {"gold": 40, "materials": {"ore": 3}, "items": [_item("hat"), _item("pants")]}
	var stored: Dictionary = trip.loot_into_bag(drop)
	ctx.check("loot goes straight into the run bag", trip.bag.gold == 40 and trip.bag.material_count("ore") == 3 and trip.bag.items.size() == 2 and stored["lost_items"].is_empty())
	ctx.check("but it is not the player's yet", profile.stash.gold == int(_camp.starter["gold"]) and profile.stash.items.is_empty())

	var tight = Run.start(profile, _camp)
	tight.bag.capacity = 2
	var overflow: Dictionary = tight.loot_into_bag({"gold": 0, "materials": {"ore": 5}, "items": [_item("hat"), _item("pants")]})
	ctx.check("what does not fit in a full bag is lost", tight.bag.items.size() == 1 and overflow["lost_items"].size() == 1 and tight.bag.free_slots() == 0)
	ctx.check("a loot item can be thrown away to make room", tight.discard_item(0) and tight.bag.free_slots() == 1 and not tight.discard_item(5))

	var home_gold: int = profile.stash.gold
	var summary: Dictionary = trip.return_to_camp()
	ctx.check("returning to camp moves the gold, materials and equipment into the stash", profile.stash.gold == home_gold + 40 and profile.stash.material_count("ore") == int(_camp.starter["materials"]["ore"]) + 3 and profile.stash.items.size() == 2 and summary["items"] == 2)
	ctx.check("and the bag is empty afterwards", trip.bag.is_empty())

	var crowded = Run.start(profile, _camp)
	crowded.bag.add_item(_item("armband"))
	crowded.bag.add_item(_item("earring"))
	profile.stash.capacity = profile.stash.slots_used() + 1  # room for just one more piece
	var left: Dictionary = crowded.return_to_camp()
	ctx.check("whatever does not fit in the stash stays in the bag, nothing is lost (%d left)" % left["left_items"], left["items"] + left["left_items"] == 2 and crowded.bag.items.size() == left["left_items"])

	var dying = Run.start(profile, _camp)
	dying.loot_into_bag({"gold": 99, "materials": {"leather": 2}, "items": [_item("ring")]})
	var gold_at_camp: int = profile.stash.gold
	var lost: Dictionary = dying.death()
	ctx.check("dying empties the bag and reports the loss", dying.bag.is_empty() and lost["gold"] == 99 and lost["items"] == 1 and dying.died)
	ctx.check("a dead player brings nothing home", dying.return_to_camp()["gold"] == 0 and profile.stash.gold == gold_at_camp)

	var swap = Run.start(profile, _camp)
	var shirt_worn = profile.loadout.item_at("shirt")
	var better = _item("shirt", 3)
	swap.bag.add_item(better)
	ctx.check("a bag item can be worn, and the old piece goes into the bag", swap.equip_from_bag(0) and profile.loadout.item_at("shirt") == better and swap.bag.items.size() == 1 and swap.bag.items[0] == shirt_worn)
	ctx.check("an item that does not exist cannot be worn", not swap.equip_from_bag(7))

	# Taking a worn piece off into the run bag (rest points).
	var strip = Run.start(profile, _camp)
	var shirt_on = profile.loadout.item_at("shirt")
	var off: Dictionary = strip.unequip_to_bag("shirt")
	ctx.check("a worn piece can be taken off into the bag while it has room", off["ok"] and profile.loadout.item_at("shirt") == null and strip.bag.items.has(shirt_on))
	var empty_slot: Dictionary = strip.unequip_to_bag("hat")
	ctx.check("an empty slot cannot be taken off, with the reason", not empty_slot["ok"] and empty_slot["reason"] == "nothing_worn")
	var ring_a = _item("ring", 1)
	var ring_b = _item("ring", 2)
	profile.loadout.equip(ring_a, 0)
	profile.loadout.equip(ring_b, 1)
	var second: Dictionary = strip.unequip_to_bag("ring", 1)
	ctx.check("the second position of a paired slot comes off on its own", second["ok"] and profile.loadout.item_at("ring", 1) == null and profile.loadout.item_at("ring", 0) == ring_a and strip.bag.items.has(ring_b))
	ctx.check("an empty second position is refused", strip.unequip_to_bag("ring", 1)["reason"] == "nothing_worn")
	while strip.bag.free_slots() > 0:
		strip.bag.add_item(_item("earring"))
	var full: Dictionary = strip.unequip_to_bag("ring", 0)
	ctx.check("a full bag refuses, with the reason, and the piece stays worn", not full["ok"] and full["reason"] == "bag_full" and profile.loadout.item_at("ring", 0) == ring_a)
	strip.bag.take_item(strip.bag.items.size() - 1)
	strip.died = true
	ctx.check("after a fall nothing can be taken off into the (lost) bag", strip.unequip_to_bag("ring", 0)["reason"] == "trip_over")
	strip.died = false
	ctx.check("with room again it comes off", strip.unequip_to_bag("ring", 0)["ok"] and profile.loadout.item_at("ring", 0) == null)
	profile.loadout.equip(shirt_on)  # leave the profile as the later checks expect

	var starter = _profile(3)
	ctx.check("a new player wears a starter set and has starter money", starter.loadout.item_at("weapon") != null and starter.loadout.item_at("shirt") != null and starter.stash.gold > 0)
	var spare = _item("hat", 2)
	starter.stash.add_item(spare)
	ctx.check("stash gear can be worn at camp", starter.equip_from_stash(starter.stash.items.size() - 1) and starter.loadout.item_at("hat") == spare)
	ctx.check("and taken off again", starter.unequip_to_stash("hat") and starter.loadout.item_at("hat") == null and starter.stash.items.has(spare))


func _test_wear(ctx) -> void:
	var profile = _profile()
	var loadout = profile.loadout
	var shirt = loadout.item_at("shirt")
	var weapon = loadout.item_at("weapon")
	var before: float = shirt.durability
	Wear.damage_taken(loadout, _rules, 500.0, 1000.0)
	var expected: float = _rules.armor_wear_per_full_hp * 0.5
	ctx.check("armor wears in proportion to the damage taken (%.1f lost)" % (before - shirt.durability), absf((before - shirt.durability) - expected) < 0.001)
	ctx.check("the weapon does not wear from damage taken", weapon.durability == weapon.max_durability)
	Wear.hit_landed(loadout, _rules)
	ctx.check("the weapon wears when it lands a hit", absf((weapon.max_durability - weapon.durability) - _rules.weapon_wear_per_hit) < 0.001)
	Wear.death(loadout, _rules)
	ctx.check("dying wears everything", absf((before - shirt.durability) - expected - _rules.death_wear) < 0.001)
	for i in 100:
		Wear.damage_taken(loadout, _rules, 5000.0, 1000.0)
	ctx.check("durability never goes below 0 and the item is not destroyed", shirt.durability == 0.0 and not shirt.destroyed and loadout.item_at("shirt") == shirt)
	var fresh = _profile(2)
	var changed := Wear.damage_taken(fresh.loadout, _rules, 1.0, 1000.0)
	ctx.check("a tiny hit on pristine gear changes no stats", not changed)
	var heavy := false
	for i in 60:
		heavy = heavy or Wear.damage_taken(fresh.loadout, _rules, 300.0, 1000.0)
	ctx.check("enough wear eventually tells the simulation to recompute stats", heavy)


func _test_camp(ctx) -> void:
	var profile = _profile()
	ctx.check("a new camp starts at level 1 with its start facilities", profile.camp_level == 1 and Camp.is_built(profile, "workbench") and Camp.is_built(profile, "storage") and not Camp.is_built(profile, "farm") and not Camp.is_built(profile, "armory"))
	ctx.check("a fresh camp has the base bag and stash sizes", Camp.bag_slots(profile, _camp) == _camp.run_slots and profile.stash.capacity == _camp.stash_slots)
	ctx.check("a poor player cannot upgrade the camp", not profile.stash.pay({"gold": 99999}) and Camp.upgrade_camp(_profile(), _camp)["reason"] == "cannot_afford")
	var rich = _profile()
	rich.stash.gold = 100000
	rich.stash.capacity = 200
	for i in 4:
		for material in ["ore", "leather", "essence"]:
			rich.stash.add_material(material, 99)
	rich.stash.add_material("herb", 50)
	ctx.check("a facility cannot be built before the camp level it needs", Camp.upgrade_facility(rich, _camp, "farm")["reason"] == "camp_level_too_low")
	var gold_before: int = rich.stash.gold
	ctx.check("the camp can be upgraded by paying", Camp.upgrade_camp(rich, _camp)["ok"] and rich.camp_level == 2 and rich.stash.gold < gold_before)
	ctx.check("the farm unlocks at camp level 2", Camp.upgrade_facility(rich, _camp, "farm")["ok"] and Camp.is_built(rich, "farm"))
	ctx.check("the armory is not available yet", Camp.upgrade_facility(rich, _camp, "armory")["reason"] == "camp_level_too_low")
	ctx.check("the camp skill for level 2 now applies", Camp.skill_bonus(rich, _camp).get("HP", 0.0) == 60.0 and Camp.skill_bonus(profile, _camp).is_empty())
	ctx.check("an unknown facility is refused", Camp.upgrade_facility(rich, _camp, "castle")["reason"] == "unknown_facility")
	var stash_before: int = Camp.stash_slots(rich, _camp)
	var bag_before: int = Camp.bag_slots(rich, _camp)
	ctx.check("upgrading storage enlarges the stash and the run bag", Camp.upgrade_facility(rich, _camp, "storage")["ok"] and Camp.stash_slots(rich, _camp) > stash_before and Camp.bag_slots(rich, _camp) > bag_before and rich.stash.capacity == Camp.stash_slots(rich, _camp))
	for i in 3:
		Camp.upgrade_camp(rich, _camp)
	ctx.check("the camp stops at its top level", rich.camp_level == _camp.max_camp_level() and Camp.upgrade_camp(rich, _camp)["reason"] == "max_level")
	ctx.check("the armory can be built at camp level 3 or more", Camp.upgrade_facility(rich, _camp, "armory")["ok"])
	var stats_plain: Dictionary = Run.start(profile, _camp).stats(_rules)
	var stats_rich: Dictionary = Run.start(rich, _camp).stats(_rules)
	ctx.check("camp skills raise the stats of a trip (HP %.0f vs %.0f)" % [stats_rich["HP"], stats_plain["HP"]], stats_rich["HP"] > stats_plain["HP"] + 100.0)
	var final_levels := {"workbench": 3, "storage": 4}
	ctx.check("the best workbench gives the biggest repair discount", _camp.effect_total(final_levels, "repair_discount") > _camp.effect_total({"workbench": 2}, "repair_discount"))


func _test_repair(ctx) -> void:
	var profile = _profile()
	var item = profile.loadout.item_at("shirt")
	ctx.check("a pristine item has nothing to repair", Repair.quote(item, _camp)["kind"] == "none" and Repair.repair(item, profile, _camp)["reason"] == "nothing_to_repair")
	item.durability = 60.0
	var normal: Dictionary = Repair.quote(item, _camp)
	ctx.check("a worn item costs gold and only a little ore (%d gold, %s)" % [normal["gold"], normal["materials"]], normal["kind"] == "normal" and normal["gold"] > 0 and normal["materials"].keys() == ["ore"] and normal["materials"]["ore"] <= 6)
	item.durability = 0.0
	var broken: Dictionary = Repair.quote(item, _camp)
	item.durability = 0.5  # almost nothing left, but not broken down yet
	var nearly: Dictionary = Repair.quote(item, _camp)
	ctx.check("a broken-down item costs far more than one repaired in time (%d vs %d gold)" % [broken["gold"], nearly["gold"]], broken["kind"] == "broken" and broken["gold"] >= nearly["gold"] * 3)
	ctx.check("and needs several kinds of material", broken["materials"].size() >= 3 and nearly["materials"].size() <= 1)
	item.durability = 0.0
	var tier_zero = _item("shirt", 0)
	var tier_three = _item("shirt", 3)
	tier_zero.durability = 0.0
	tier_three.durability = 0.0
	ctx.check("a higher tier costs more to repair", Repair.quote(tier_three, _camp)["gold"] > Repair.quote(tier_zero, _camp)["gold"])
	ctx.check("the workbench discount lowers the price", Repair.quote(item, _camp, 0.3)["gold"] < Repair.quote(item, _camp, 0.0)["gold"])

	profile.stash.gold = 0
	ctx.check("a poor player cannot repair, and nothing changes", Repair.repair(item, profile, _camp)["reason"] == "cannot_afford" and item.durability == 0.0)
	profile.stash.gold = 100000
	profile.stash.add_material("ore", 99)
	profile.stash.add_material("leather", 99)
	profile.stash.add_material("essence", 99)
	profile.stash.capacity = 50
	var gold_before: int = profile.stash.gold
	var done: Dictionary = Repair.repair(item, profile, _camp)
	ctx.check("repairing restores full durability and takes the price", done["ok"] and item.durability == item.max_durability and profile.stash.gold == gold_before - int(done["cost"]["gold"]))
	var no_bench = _profile()
	no_bench.facility_levels["workbench"] = 0
	var worn = no_bench.loadout.item_at("weapon")
	worn.durability = 50.0
	ctx.check("without a workbench nothing can be repaired", Repair.repair(worn, no_bench, _camp)["reason"] == "no_workbench")

	var all = _profile()
	all.stash.gold = 100000
	all.stash.add_material("ore", 90)
	for worn_item in all.loadout.items():
		worn_item.durability = 40.0
	var summary: Dictionary = Repair.repair_all_worn(all, _camp)
	var all_fixed := true
	for worn_item in all.loadout.items():
		all_fixed = all_fixed and worn_item.durability == worn_item.max_durability
	ctx.check("repair all fixes every worn item that needs it (%d)" % summary["repaired"], summary["repaired"] == all.loadout.items().size() and all_fixed and summary["skipped"] == 0)
	var poor = _profile()
	poor.stash.gold = 40
	for worn_item in poor.loadout.items():
		worn_item.durability = 10.0
	var partial: Dictionary = Repair.repair_all_worn(poor, _camp)
	ctx.check("with little money repair all does what it can and says what it skipped (%d done, %d skipped)" % [partial["repaired"], partial["skipped"]], partial["skipped"] >= 1 and poor.stash.gold >= 0)


## A trip in the real simulation: kills drop loot into the bag, damage wears gear, dying loses the bag.
func _sim_with_run(profile, enemy_type: String = "dummy_grunt", gap: float = 1.0) -> Array:
	var world := SimWorld.new()
	world.half_width = 30.0
	world.half_depth = 3.0
	world.add_solid(AABB(Vector3(-40, -0.4, -5), Vector3(80, 0.4, 10)))
	var data = CombatDataLoader.load_default()
	data.rules["attack_assist_range"] = 0.0
	var sim := GameSim.new(world, data, _rng(4))
	sim.add_player(1, Vector3(0, 0.05, 0))
	sim.add_enemy(2, Vector3(gap, 0.05, 0), enemy_type)
	sim._ai.erase(2)
	var trip = Run.start(profile, _camp)
	sim.attach_run(1, trip, _rules, _loot)
	for i in 12:
		sim.tick()
	var face := SimInput.new()
	face.move = Vector2(0.01, 0)
	sim.set_input(1, face)
	sim.tick()
	sim.set_input(1, SimInput.new())
	return [sim, trip]


func _events_of(sim: GameSim, kind: String) -> Array:
	return sim.events.filter(func(e): return e["type"] == kind)


func _test_simulation(ctx) -> void:
	var profile = _profile()
	var made := _sim_with_run(profile)
	var sim: GameSim = made[0]
	var trip = made[1]
	ctx.check("an attached player's stats come from the gear", sim.fighters[1].stats["ATK"] == trip.stats(_rules)["ATK"] and sim.fighters[1].hp == sim.fighters[1].max_hp())

	sim.fighters[2].hp = 1.0
	var press := SimInput.new()
	press.light = true
	sim.set_input(1, press)
	var loot_events: Array = []
	var weapon_worn_before: float = profile.loadout.item_at("weapon").durability
	for i in 30:
		sim.tick()
		sim.set_input(1, SimInput.new())
		loot_events.append_array(_events_of(sim, "loot"))
	ctx.check("a kill drops loot into the killer's bag and tells the client", loot_events.size() == 1 and loot_events[0]["player"] == 1 and loot_events[0]["enemy"] == 2 and trip.bag.gold == loot_events[0]["gold"] and trip.bag.gold > 0)
	ctx.check("landing hits wears the weapon", profile.loadout.item_at("weapon").durability < weapon_worn_before)
	ctx.check("the loot is not in the stash until the player returns", profile.stash.gold == int(_camp.starter["gold"]))
	var carried_gold: int = trip.bag.gold
	trip.return_to_camp()
	ctx.check("returning to camp after the stage banks it", profile.stash.gold == int(_camp.starter["gold"]) + carried_gold)

	# Taking damage wears armor and lowers the stats once it is worn enough.
	var hurt := _sim_with_run(_profile(2), "brute", 1.2)
	var hurt_sim: GameSim = hurt[0]
	var shirt = hurt[1].profile.loadout.item_at("shirt")
	var shirt_before: float = shirt.durability
	var brain = load("res://logic/enemy_ai.gd").new()
	brain.attack_range = 2.0
	brain.cooldown_min = 5
	brain.cooldown_max = 5
	brain.attack_input = "light"
	hurt_sim._ai[2] = brain
	for i in 300:
		hurt_sim.tick()
	ctx.check("taking damage wears armor (%.1f -> %.1f)" % [shirt_before, shirt.durability], shirt.durability < shirt_before)

	# Gear worn to nothing weakens the player.
	var weak := _sim_with_run(_profile(3))
	var weak_sim: GameSim = weak[0]
	var atk_before: float = weak_sim.fighters[1].stats["ATK"]
	var weak_weapon = weak[1].profile.loadout.item_at("weapon")
	weak_weapon.durability = 0.0
	Wear.hit_landed(weak[1].loadout(), _rules)
	weak_sim._refresh_run_stats(1)
	ctx.check("a broken-down weapon lowers the attack (%.0f -> %.0f)" % [atk_before, weak_sim.fighters[1].stats["ATK"]], weak_sim.fighters[1].stats["ATK"] < atk_before)
	weak[1].profile.stash.gold = 100000
	weak[1].profile.stash.add_material("ore", 90)
	weak[1].profile.stash.add_material("leather", 90)
	weak[1].profile.stash.add_material("essence", 90)
	Repair.repair(weak_weapon, weak[1].profile, _camp)
	weak_sim._refresh_run_stats(1)
	ctx.check("and repairing brings the attack back", absf(weak_sim.fighters[1].stats["ATK"] - atk_before) < 0.01)

	# Dying: the bag is lost, the worn gear stays, and it wears.
	var doomed := _sim_with_run(_profile(4))
	var doomed_sim: GameSim = doomed[0]
	doomed[1].loot_into_bag({"gold": 77, "materials": {"ore": 4}, "items": [_item("hat")]})
	var worn_hat = _item("hat", 1)
	doomed[1].profile.loadout.equip(worn_hat)
	var hat_before: float = worn_hat.durability
	doomed_sim.fighters[1].hp = 0.0
	doomed_sim.fighters[1].state = Fighter.State.DEAD
	doomed_sim.events.append({"type": "killed", "target": 1, "by": 2})
	doomed_sim._process_economy()
	var lost_events := _events_of(doomed_sim, "bag_lost")
	ctx.check("dying loses everything in the bag and says so", doomed[1].bag.is_empty() and lost_events.size() == 1 and lost_events[0]["gold"] == 77 and lost_events[0]["items"] == 1)
	ctx.check("but the worn gear is kept, a little more worn", doomed[1].profile.loadout.item_at("hat") == worn_hat and worn_hat.durability < hat_before)
	ctx.check("a dead player's lost loot does not come back as a drop", _events_of(doomed_sim, "loot").is_empty())

	# A full bag loses what does not fit and says so.
	var full := _sim_with_run(_profile(5))
	var full_sim: GameSim = full[0]
	full[1].bag.capacity = 0
	full_sim.fighters[2].hp = 1.0
	full_sim.set_input(1, press)
	for i in 30:
		full_sim.tick()
		full_sim.set_input(1, SimInput.new())
	ctx.check("with no room the gold still counts but nothing else is kept", full[1].bag.items.is_empty() and full[1].bag.materials.is_empty() and full[1].bag.gold > 0)


func _test_rest_and_weapon_stats(ctx) -> void:
	var made := _sim_with_run(_profile(6))
	var sim: GameSim = made[0]
	var trip = made[1]
	var fighter: Fighter = sim.fighters[1]
	fighter.hp = fighter.max_hp() * 0.2
	fighter.energy = 0.0
	var before: float = fighter.hp
	ctx.check("resting at a rest point heals part of the max HP and refills stamina", sim.use_rest(1, "p1") and absf(fighter.hp - (before + fighter.max_hp() * _camp.rest_heal_fraction)) < 1.0 and fighter.energy == fighter.max_energy())
	ctx.check("and tells the client how much", _events_of(sim, "rested").size() == 1 and _events_of(sim, "rested")[0]["healed"] > 0)
	var hp_after: float = fighter.hp
	ctx.check("the same rest point works only once per trip", not sim.use_rest(1, "p1") and fighter.hp == hp_after)
	ctx.check("another rest point works", sim.use_rest(1, "p2"))
	ctx.check("healing never goes above the maximum", fighter.hp <= fighter.max_hp())
	ctx.check("a dead player cannot rest", (func() -> bool:
		fighter.hp = 0.0
		fighter.state = Fighter.State.DEAD
		return not sim.use_rest(1, "p3")).call())
	ctx.check("a player with no trip cannot rest", not GameSim.new(SimWorld.new(), _combat, _rng()).use_rest(1, "p1"))
	var wounded := _sim_with_run(_profile(7))
	wounded[0].fighters[1].hp = wounded[0].fighters[1].max_hp() * 0.2
	wounded[0].fighters[1].effects["wound"] = {"stacks": 1, "left": 600, "age": 0, "dps": 0.0, "source": 2}
	var no_effects_data = wounded[0].combat
	wounded[0].fighters[1].stat_mods = {"HEALING": {"add": 0.0, "mul": -0.6}}
	var hp_before: float = wounded[0].fighters[1].hp
	wounded[0].use_rest(1, "p1")
	ctx.check("a wound lowers the healing of a rest (%.0f vs %.0f)" % [wounded[0].fighters[1].hp - hp_before, fighter.max_hp() * _camp.rest_heal_fraction], wounded[0].fighters[1].hp - hp_before < fighter.max_hp() * _camp.rest_heal_fraction * 0.6)
	var bad_rest := FileAccess.get_file_as_string(CampDataLoader.DATA_PATH).replace("\"heal_fraction\": 0.5", "\"heal_fraction\": 1.5")
	ctx.check("a rest heal fraction above 1 is reported", not CampDataLoader.parse(bad_rest, _rules.tiers.size()).is_valid())

	# Weapon attack speed: every weapon has its own, and the ATKSPD stat makes it faster.
	var dagger: Dictionary = _combat.weapon_stats("dagger")
	var fists: Dictionary = _combat.weapon_stats("fists")
	var hammer: Dictionary = _combat.weapon_stats("hammer")
	ctx.check("the dagger attacks faster than fists, and fists faster than the hammer (%.2fs, %.2fs, %.2fs per light hit)" % [dagger["light_seconds"], fists["light_seconds"], hammer["light_seconds"]], dagger["light_seconds"] < fists["light_seconds"] and fists["light_seconds"] < hammer["light_seconds"])
	ctx.check("the ATKSPD stat shortens the time of a hit", _combat.weapon_stats("blade", 50.0)["light_seconds"] < _combat.weapon_stats("blade")["light_seconds"] * 0.7)
	ctx.check("weapon stats tell reach, power, push and stun", hammer["reach"] > 0.0 and hammer["heavy_power"] > fists["heavy_power"] and hammer["knockback"] > dagger["knockback"] and hammer["stun"] > dagger["stun"] and _combat.weapon_stats("ghost").is_empty())
