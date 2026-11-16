extends RefCounted
## Tier-aware race armour look (PO 2026-11-16): normal (white) shows the starter file, rare / epic / legendary the MID file
## (`<race>_<slot>_mid.glb`, `icon-<race>_<slot>_mid.png`), a missing MID file falls back to the starter one, and a race x
## class file (asset_path) still wins at every tier. Same item ids at every tier (no per-tier catalog entries).

const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const OTHER := "res://art/characters/studio05/split/body_greatsword.glb"
const DIR := "res://art/armor/race_shared/"


func run(ctx) -> void:
	var rules := ItemRulesLoader.load_default()
	var info: Dictionary = rules.catalog.entry("race_viking_greatsword_shirt")
	ctx.check("race_viking_greatsword_shirt is a catalog item with a race-shared fallback", str(info.get("fallback_asset_path", "")).begins_with(DIR))
	var old := str(info["fallback_asset_path"]).split("|")[0]  # the race-shared starter step (no race x class file exists yet)
	ctx.check("tier 0 (normal) keeps the starter file", ItemAssets.armor_file(info, 0) == old and old == DIR + "viking_shirt.glb")
	for tier in [1, 2, 3]:
		ctx.check("tier %d (%s) picks the MID file" % [tier, rules.tiers[tier]["id"]], ItemAssets.armor_file(info, tier) == DIR + "viking_shirt_mid.glb")
	ctx.check("no tier argument = starter (old callers)", ItemAssets.armor_file(info) == DIR + "viking_shirt.glb")
	ctx.check("MID icon for rare, starter icon for normal", ItemAssets.tiered(DIR + "icon-viking_shirt.png", 1) == DIR + "icon-viking_shirt_mid.png" and ItemAssets.tiered(DIR + "icon-viking_shirt.png", 0) == DIR + "icon-viking_shirt.png")
	ctx.check("an already-mid or non race-shared path is not touched", ItemAssets.tiered(DIR + "viking_shirt_mid.glb", 2) == DIR + "viking_shirt_mid.glb" and ItemAssets.tiered(OTHER, 2) == OTHER)
	# a missing MID file falls back: the step is skipped to the next step (its MID file) to the next existing one, and a starter with no MID twin is kept
	var skip := {"asset_path": "", "fallback_asset_path": DIR + "elf_hat.glb|" + DIR + "elf_shirt.glb"}
	ctx.check("a step with neither starter nor MID file is skipped to the next step (its MID file)", ItemAssets.armor_file(skip, 2) == DIR + "elf_shirt_mid.glb")
	ctx.check("a race x class file wins at every tier", ItemAssets.armor_file({"asset_path": DIR + "viking_shirt.glb", "fallback_asset_path": ""}, 3) == DIR + "viking_shirt.glb")
	ctx.check("a starter file with no MID twin is kept at every tier", ItemAssets.armor_file({"fallback_asset_path": OTHER}, 3) == OTHER)
	# every race x slot x catalog piece: the MID file and icon exist and the tier picks them
	var missing: Array[String] = []
	for race in ["human", "viking", "elf", "runeborn"]:
		for slot in ["shirt", "pants", "armband", "shoes"]:
			for f in ["%s%s_%s_mid.glb", "%sicon-%s_%s_mid.png"]:
				var p: String = f % [DIR, race, slot]
				if not ResourceLoader.exists(p):
					missing.append(p)
	ctx.check("all 16 MID meshes and 16 MID icons load (missing %s)" % [missing], missing.is_empty())
	var icon_rare := ItemAssets.icon_for_id("race_viking_greatsword_shirt", rules.catalog, 1)
	var icon_norm := ItemAssets.icon_for_id("race_viking_greatsword_shirt", rules.catalog, 0)
	ctx.check("icon_for_id returns a different picture for rare than for normal", icon_rare != null and icon_norm != null and icon_rare.resource_path.ends_with("_mid.png") and not icon_norm.resource_path.ends_with("_mid.png"))
