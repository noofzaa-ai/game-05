extends RefCounted
## Level-15 race weapons (Boss delivery 2026-11-17, tools/items/split_race_weapons_lv15.py): the race weapon items
## (race_<race>_<class>_weapon, req_level 15) and race shields show art/weapons/race_<race>/<file>_lv15.glb (icons
## icon-<file>_lv15.png) when they are not starter pieces (instance ids "starter-..."), the MID file is the fallback, and every
## level-15 weapon is as long as the level-1 weapon the game shows (the class gear's own) within 3%.
const ItemAssets := preload("res://client/item_assets.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const RACES := ["human", "viking", "elf", "runeborn"]
const FILES := ["sword_shield", "shield", "greatsword", "longbow", "magic"]
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const GEAR := {"sword_shield": ["armor_sword_shield", "| Sword"], "shield": ["armor_sword_shield", "| Shield"], "greatsword": ["armor_greatsword", "| Sword"],
	"longbow": ["armor_longbow", "| Bow"], "magic": ["armor_magic", "| Staff"]}
const TOLERANCE := 0.03


class _Loadout:
	var items := {}
	func item_at(slot: String, _index: int):
		return items.get(slot)


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var catalog = rules.catalog
	_files(ctx)
	_chain(ctx, rules, catalog)
	_size(ctx)


func _files(ctx) -> void:
	var loads := true
	var n := 0
	for race in RACES:
		for file in FILES:
			var glb := "res://art/weapons/race_%s/%s_lv15.glb" % [race, file]
			var png := "res://art/weapons/race_%s/icon-%s_lv15.png" % [race, file]
			loads = loads and load(glb) is PackedScene and load(png) is Texture2D
			n += 2
	ctx.check("lv15 weapons: all %d files (20 meshes, 20 icons) load" % n, loads and n == 40)


func _chain(ctx, rules, catalog) -> void:
	var picks := true
	var icons := true
	var kept := true
	for race in RACES:
		for cls in CLASSES:
			var info: Dictionary = catalog.entry("race_%s_%s_weapon" % [race, cls])
			var mid := str(info["asset_path"])
			picks = picks and ItemAssets.lv15_weapon(mid) == mid.replace(".glb", "_lv15.glb")
			icons = icons and ItemAssets.icon_for_id("race_%s_%s_weapon" % [race, cls], catalog) == load(str(info["icon_path"]).replace(".png", "_lv15.png"))
			icons = icons and ItemAssets.icon_for_id("race_%s_%s_weapon" % [race, cls], catalog, "", true) == load(str(info["icon_path"]))
		picks = picks and ItemAssets.lv15_weapon(str(catalog.entry("race_%s_shield" % race)["asset_path"])) == "res://art/weapons/race_%s/shield_lv15.glb" % race
	ctx.check("lv15 weapons: race weapon and shield items resolve to the _lv15 file, their icons to icon-<file>_lv15.png", picks and icons)
	# the whole looks() chain: a bought / dropped weapon shows lv15, a starter piece the old file
	var rng := RandomNumberGenerator.new()
	rng.seed = 1117
	var loadout := _Loadout.new()
	loadout.items["weapon"] = ItemSystem.create_item(rules, "drop-1", "weapon", 0, rng, "greatsword", "race_elf_greatsword_weapon")
	var shown: Dictionary = ItemAssets.looks(loadout, catalog, "greatsword")
	ctx.check("lv15 weapons: looks() gives the lv15 file for a normal race weapon (%s)" % [shown["weapon"]["path"]], shown["weapon"]["path"] == "res://art/weapons/race_elf/greatsword_lv15.glb")
	loadout.items["weapon"] = ItemSystem.create_item(rules, "starter-kit-v3-greatsword-weapon", "weapon", 0, rng, "greatsword", "race_elf_greatsword_weapon")
	shown = ItemAssets.looks(loadout, catalog, "greatsword")
	ctx.check("lv15 weapons: a starter piece keeps the MID file (%s)" % [shown["weapon"]["path"]], shown["weapon"]["path"] == "res://art/weapons/race_elf/greatsword.glb")
	ctx.check("lv15 weapons: missing lv15 file falls back (no path, nothing to pick)", ItemAssets.lv15_weapon("res://art/weapons/race_human/nothing.glb").is_empty()
		and ItemAssets.lv15_weapon("res://art/armor/race_shared/human_shirt.glb").is_empty() and ItemAssets.lv15_weapon("res://art/weapons/race_human/greatsword_lv15.glb").is_empty())


## Length along the main axis of all vertices of `pieces` (power iteration on the covariance), bind-pose mesh space.
func _length(pieces: Array) -> float:
	var pts := PackedVector3Array()
	for m in pieces:
		pts.append_array((m as MeshInstance3D).mesh.get_faces())
	if pts.size() < 10:
		return 0.0
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= pts.size()
	var axis := Vector3(0.3, 0.5, 0.8).normalized()
	for i in 30:
		var next := Vector3.ZERO
		for p in pts:
			var d: Vector3 = p - centre
			next += d * d.dot(axis)
		axis = next.normalized()
	var lo := 1e9
	var hi := -1e9
	for p in pts:
		var t: float = (p - centre).dot(axis)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return hi - lo


func _size(ctx) -> void:
	var worst := 0.0
	var worst_name := ""
	for file in FILES:
		var reference_root: Node = (load("res://art/characters/studio05/v1111/outfits/%s.glb" % GEAR[file][0]) as PackedScene).instantiate()
		var reference := []
		for m in reference_root.find_children("*", "MeshInstance3D", true, false):
			if str(m.name).contains(GEAR[file][1]):
				reference.append(m)
		var reference_length := _length(reference)
		for race in RACES:
			var root: Node = (load("res://art/weapons/race_%s/%s_lv15.glb" % [race, file]) as PackedScene).instantiate()
			var length := _length(root.find_children("*", "MeshInstance3D", true, false))
			var off := absf(length / maxf(reference_length, 0.0001) - 1.0)
			if off > worst:
				worst = off
				worst_name = "%s %s %.3f/%.3f" % [race, file, length, reference_length]
			root.free()
		reference_root.free()
	ctx.check("lv15 weapons: every lv15 weapon is as long as the level-1 class weapon within %d%% (worst %.1f%%: %s)" % [int(TOLERANCE * 100), worst * 100.0, worst_name], worst <= TOLERANCE)
