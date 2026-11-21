extends RefCounted
## Pyramid boss unique weapons (Boss 2026-11-21, tools/items/build_boss_weapons.py): the Pharaoh's crook (greatsword) and
## the High Wizard's staff (magic) as catalog items: level 20, no_drop, no set (not in the boss set / shop), Studio-rig GLBs
## within budget, icons, wearable only by their class at 20+, never purged for a new player.
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const BossLoot := preload("res://logic/boss_loot.gd")
const GearPurge := preload("res://logic/gear_purge.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const IDS := {"boss_mummy_boss_crook": ["greatsword", "| Sword"], "boss_mummy_high_wizard_staff": ["magic", "| Staff"]}


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/catalog.json")).get("items", {})
	ctx.check("boss weapons: catalog has no errors %s" % [rules.catalog.errors], rules.catalog.errors.is_empty())
	for id in IDS:
		var e: Dictionary = rules.catalog.entry(id)
		var cls: String = IDS[id][0]
		ctx.check("boss weapon %s: weapon of type/class %s, boss pyramid, no_drop, no set, req/drop level 20, en+th names" % [id, cls],
			e.get("slot", "") == "weapon" and e.weapon_type == cls and e["class"] == cls and e.boss == "pyramid" and e.no_drop and e.set == ""
			and rules.catalog.req_level(id) == 20 and int(e.drop_level) == 20 and not str(e.name).is_empty() and not str(raw[id].get("name_th", "")).is_empty())
		ctx.check("boss weapon %s: model and icon exist, Studio-rig file" % id, ResourceLoader.exists(e.asset_path) and ResourceLoader.exists(e.icon_path) and CharacterModel.is_studio_rig_file(e.asset_path))
		var scene: Node = (load(e.asset_path) as PackedScene).instantiate()
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		var tris := 0
		for m in meshes:
			tris += CharacterModel._triangles((m as MeshInstance3D).mesh)
		ctx.check("boss weapon %s: one skinned '%s' piece, %d triangles <= 1500" % [id, IDS[id][1], tris],
			meshes.size() == 1 and str(meshes[0].name).contains(IDS[id][1]) and meshes[0].skin != null and tris > 0 and tris <= 1500)
		scene.free()
		ctx.check("boss weapon %s: not a boss set piece, not in the boss shop" % id,
			not BossLoot.set_pieces(rules, "boss_mummy_high_wizard").has(id) and not BossLoot.shop_offers(rules).any(func(o): return o.id == id))
		ctx.check("boss weapon %s: no normal drop candidate at any level" % id, not rules.catalog.candidates("weapon", cls, 99).has(id))
		var item = ItemSystem.create_item(rules, "bw-" + id, "weapon", 1, RandomNumberGenerator.new(), "", id)
		ctx.check("boss weapon %s: wearable by its class at 20, not at 19, not by another class" % id,
			Profile.slot_problem(cls, item, rules, 20) == "" and Profile.slot_problem(cls, item, rules, 19) == "level_too_low"
			and Profile.slot_problem("longbow", item, rules, 25) == "wrong_weapon_family")
		var lv15 = ItemSystem.create_item(rules, "bw-ref", "weapon", 1, RandomNumberGenerator.new(), "", rules.catalog.race_piece("human", cls, "weapon"))
		ctx.check("boss weapon %s: main stat above the level-15 race weapon of the same tier (%.2f vs %.2f)" % [id, item.main_value(rules), lv15.main_value(rules)],
			item.main_value(rules) > lv15.main_value(rules))
		ctx.check("boss weapon %s: has a relic socket (boss piece)" % id, BossLoot.has_socket(rules, item))
		var p = Profile.new_player(rules, camp, RandomNumberGenerator.new())
		p.stash.items.append(item)
		ctx.check("boss weapon %s: the one-time lv15 gear purge never runs again on a new player" % id, GearPurge.done(p) and not GearPurge.purge(p, rules)["ran"] and p.stash.items.has(item))
		var icon = ItemAssets.icon(item, rules.catalog)
		ctx.check("boss weapon %s: client icon is the 96x96 boss icon" % id, icon is Texture2D and icon.get_width() == 96)
	var drops: Array = BossLoot.boss("pyramid").get("weapon_drops", [])
	ctx.check("boss weapons: boss_loot.json pyramid lists both weapons with a chance in (0, 0.25]",
		drops.size() == 2 and drops.all(func(d): return IDS.has(str(d.item)) and float(d.chance) > 0.0 and float(d.chance) <= 0.25))
