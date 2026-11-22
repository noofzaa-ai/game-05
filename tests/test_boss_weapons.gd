extends RefCounted
## Boss unique weapons (Boss 2026-11-21): the pyramid pair (tools/items/build_boss_weapons.py: the Pharaoh's crook, a
## greatsword, and the High Wizard's staff, magic) and the Orc Warlock pair (tools/items/build_orc_warlock_weapons.py,
## PLACEHOLDER 3D: a Sword & Shield sword and an off-hand shield) as catalog items: level 20, no_drop, no set (not in the boss
## set / shop), Studio-rig GLBs within budget, icons, wearable only by their class at 20+, main stat at refine +0 EQUAL to the
## level-15 gear of the same kind at refine +10 (Boss 2026-11-22), dropped at refine +0, a relic socket, never purged for a new player, never a normal / race drop, and dropped by
## data/loot/boss_loot.json weapon_drops (ON for both zones).
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const BossLoot := preload("res://logic/boss_loot.gd")
const GearPurge := preload("res://logic/gear_purge.gd")
const GearLevels := preload("res://logic/gear_levels.gd")
const Loadout := preload("res://logic/loadout.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
## id -> [slot, weapon_type ("" = offhand), card class, mesh label, zone, a class that may not wear it]
const IDS := {
	"boss_mummy_boss_crook": ["weapon", "greatsword", "greatsword", "| Sword", "pyramid", "longbow"],
	"boss_mummy_high_wizard_staff": ["weapon", "magic", "magic", "| Staff", "pyramid", "longbow"],
	"boss_orc_warlock_sword": ["weapon", "blade", "sword_shield", "| Sword", "orc_camp", "greatsword"],
	"boss_orc_warlock_shield": ["offhand", "", "sword_shield", "| Shield", "orc_camp", "greatsword"],
}


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/catalog.json")).get("items", {})
	ctx.check("boss weapons: catalog has no errors %s" % [rules.catalog.errors], rules.catalog.errors.is_empty())
	for id in IDS:
		var spec: Array = IDS[id]
		var e: Dictionary = rules.catalog.entry(id)
		var slot: String = spec[0]
		var cls: String = spec[2]
		ctx.check("boss weapon %s: %s, type '%s', class %s, boss %s, no_drop, no set, req/drop level 20, en+th names" % [id, slot, spec[1], cls, spec[4]],
			e.get("slot", "") == slot and e.weapon_type == spec[1] and e["class"] == cls and e.boss == spec[4] and e.no_drop and e.set == ""
			and rules.catalog.req_level(id) == 20 and int(e.drop_level) == 20 and not str(e.name).is_empty() and not str(raw[id].get("name_th", "")).is_empty())
		ctx.check("boss weapon %s: model and icon exist (catalog paths), Studio-rig file" % id, ResourceLoader.exists(e.asset_path) and ResourceLoader.exists(e.icon_path) and CharacterModel.is_studio_rig_file(e.asset_path))
		var scene: Node = (load(e.asset_path) as PackedScene).instantiate()
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		var tris := 0
		for m in meshes:
			tris += CharacterModel._triangles((m as MeshInstance3D).mesh)
		ctx.check("boss weapon %s: one skinned '%s' piece, %d triangles <= 1500" % [id, spec[3], tris],
			meshes.size() == 1 and str(meshes[0].name).contains(spec[3]) and meshes[0].skin != null and tris > 0 and tris <= 1500)
		scene.free()
		ctx.check("boss weapon %s: not a boss set piece, not in the boss shop" % id,
			not BossLoot.set_pieces(rules, "boss_mummy_high_wizard").has(id) and not BossLoot.set_pieces(rules, "boss_orc_warlock").has(id)
			and not BossLoot.shop_offers(rules).any(func(o): return o.id == id))
		ctx.check("boss weapon %s: no normal drop candidate at any level, never a race shield / gear-level sibling" % id,
			not rules.catalog.candidates(slot, spec[1], 99).has(id) and not ["human", "viking", "elf", "runeborn"].any(func(r): return rules.catalog.race_shield(r) == id)
			and rules.catalog.items.keys().all(func(other): return GearLevels.sibling(rules, str(other), 20) != id))
		var item = ItemSystem.create_item(rules, "bw-" + id, slot, 1, RandomNumberGenerator.new(), "", id)
		ctx.check("boss weapon %s: wearable by %s at 20, not at 19, not by %s" % [id, cls, spec[5]],
			Profile.slot_problem(cls, item, rules, 20) == "" and Profile.slot_problem(cls, item, rules, 19) == "level_too_low"
			and Profile.slot_problem(spec[5], item, rules, 25) != "")
		# the level-15 reference: the race weapon of the class; the shield: the race shield (no level-15 shield item exists)
		var ref_id: String = rules.catalog.race_piece("human", cls, "weapon") if slot == "weapon" else rules.catalog.race_shield("human")
		var ref = ItemSystem.create_item(rules, "bw-ref", slot, 1, RandomNumberGenerator.new(), "", ref_id)
		# Boss 2026-11-22: a level-20 boss weapon at refine +0 has exactly the main stat of the level-15 weapon of the same
		# type/tier at refine +10 (for the shield: the race shield x the level-15 multiplier, since no level-15 shield item
		# exists). Checked at every tier with the real main_value.
		var equal := true
		var line := ""
		for t in rules.tiers.size():
			var w = ItemSystem.create_item(rules, "bw-t-" + id, slot, t, RandomNumberGenerator.new(), "", id)
			var r = ItemSystem.create_item(rules, "bw-tr-" + id, slot, t, RandomNumberGenerator.new(), "", ref_id)
			var l15: float = rules.catalog.level_mul(15) / rules.catalog.main_stat_mul(ref_id, r.id)  # 1.0 for the sword refs, x1.5 for the race shield
			var ref0: float = r.main_value(rules) * l15
			r.refine_level = 10
			var ref10: float = r.main_value(rules) * l15
			equal = equal and w.refine_level == 0 and absf(w.main_value(rules) - ref10) <= 0.001 * ref10 and w.main_value(rules) > ref0
			line += " t%d L15 +0 %.2f / +10 %.2f / L20 +0 %.2f;" % [t, ref0, ref10, w.main_value(rules)]
		ctx.check("boss weapon %s: main stat x%.3f at +0 = level-15 %s at +10 (%s)" % [id, rules.catalog.main_stat_mul(id, item.id), ref_id, line],
			item.main_stat == ref.main_stat and equal)
		ctx.check("boss weapon %s: has a relic socket (boss piece), shows the top tier" % id, BossLoot.has_socket(rules, item) and BossLoot.shown_tier(rules, id, 0) == rules.tiers.size() - 1)
		var p = Profile.new_player(rules, camp, RandomNumberGenerator.new())
		p.stash.items.append(item)
		ctx.check("boss weapon %s: the one-time lv15 gear purge never runs again on a new player" % id, GearPurge.done(p) and not GearPurge.purge(p, rules)["ran"] and p.stash.items.has(item))
		var icon = ItemAssets.icon(item, rules.catalog)
		ctx.check("boss weapon %s: client icon is the 96x96 boss icon" % id, icon is Texture2D and icon.get_width() == 96)
		var entry: Dictionary = BossLoot.boss(spec[4])
		ctx.check("boss weapon %s: boss_loot.json %s drops it at 10%% (Boss 2026-11-22) at refine +0, drops ON" % [id, spec[4]],
			bool(entry.get("weapon_drops_enabled", false)) and Array(entry.get("weapon_drops", [])).any(func(d): return str(d.item) == id and is_equal_approx(float(d.chance), 0.10) and not d.has("refine")))
	_level20(ctx, rules)
	_looks(ctx, rules)


## Nothing else is level 20 by drops (Boss 2026-11-22): wave / race drops stay capped at 15 (no droppable catalog piece is
## above 15), the level-20 items are exactly the four boss weapons (own main_stat_mul) and the Warlock accessory set, which keeps
## level_stat_mul "20" and starts at refine 0.
func _level20(ctx, rules) -> void:
	var droppable_max := 0
	var lv20: Array = []
	for id in rules.catalog.items:
		var e: Dictionary = rules.catalog.items[id]
		if not e.no_drop:
			droppable_max = maxi(droppable_max, maxi(int(e.drop_level), rules.catalog.req_level(id)))
		if int(e.drop_level) >= 20 or rules.catalog.req_level(id) >= 20:
			lv20.append(str(id))
	lv20.sort()
	var weapons: Array = IDS.keys()
	weapons.sort()
	var dropped: Array = []
	for zone in ["goblin_base", "pyramid", "orc_camp"]:
		for d in Array(BossLoot.boss(zone).get("weapon_drops", [])):
			dropped.append(str(d.item))
	dropped.sort()
	var accessories: Array = BossLoot.set_pieces(rules, "boss_orc_warlock")
	accessories.sort()
	ctx.check("level 20: no normally droppable catalog piece is above level 15 (max %d), so wave drops stay capped at 15" % droppable_max, droppable_max <= 15)
	ctx.check("level 20: the only boss weapon drops are the four no_drop boss weapons %s" % [dropped], dropped == weapons and weapons.all(func(id): return rules.catalog.items[id].no_drop and int(rules.catalog.items[id].drop_level) == 20))
	var expected: Array = weapons + accessories
	expected.sort()
	ctx.check("level 20: the level-20 items are exactly the four boss weapons + the Warlock accessory set (%d)" % lv20.size(), lv20 == expected and accessories.size() == 5)
	var acc_ok := true
	for id in accessories:
		var piece = ItemSystem.create_item(rules, "acc-" + id, str(rules.catalog.entry(id).slot), 1, RandomNumberGenerator.new(), "", id)
		acc_ok = acc_ok and is_equal_approx(rules.catalog.main_stat_mul(id, piece.id), rules.catalog.level_mul(20)) and piece.refine_level == 0
	ctx.check("level 20: the Warlock accessories keep level_stat_mul 20 = x%.2f (unchanged) and refine 0" % rules.catalog.level_mul(20), acc_ok and is_equal_approx(rules.catalog.level_mul(20), 1.8))


## The client dresses a Sword & Shield card in the Warlock pair: the weapon look and the off-hand look use the catalog
## asset_path files (swapping in the real 3D is data only).
func _looks(ctx, rules) -> void:
	var worn = Loadout.new(rules)
	var sword = ItemSystem.create_item(rules, "bw-look-sword", "weapon", 2, RandomNumberGenerator.new(), "", "boss_orc_warlock_sword")
	var shield = ItemSystem.create_item(rules, "bw-look-shield", "offhand", 2, RandomNumberGenerator.new(), "", "boss_orc_warlock_shield")
	worn.equip(sword, 0)
	worn.equip(shield, 0)
	var looks := ItemAssets.looks(worn, rules.catalog, "blade", "human")
	ctx.check("boss weapons: a Sword & Shield card shows the Warlock sword and shield files (%s, %s)" % [looks["weapon"]["path"], looks["offhand"].get("path", "")],
		looks["weapon"]["path"] == rules.catalog.entry("boss_orc_warlock_sword").asset_path and looks["offhand"].get("path", "") == rules.catalog.entry("boss_orc_warlock_shield").asset_path)
