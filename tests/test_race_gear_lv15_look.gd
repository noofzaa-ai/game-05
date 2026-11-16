extends RefCounted
## Level-15 race outfits (Boss 2026-11-16): the class armour armour_<class>_<slot> shows art/armor/race_shared/<race>_<slot>_lv15.glb
## (and icon-<race>_<slot>_lv15.png) chosen by the wearing card's race; the starter white kit (instance ids "starter-...") keeps the
## old starter file; a missing lv15 file falls back to the starter race file. Files: tools/items/split_race_outfits_lv15.py.
const ItemAssets := preload("res://client/item_assets.gd")
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const SLOTS := ["shirt", "pants", "armband", "shoes"]
const RACES := ["human", "viking", "elf", "runeborn"]
const DIR := "res://art/armor/race_shared/"


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var catalog = rules.catalog
	var lv15 := true
	var starter := true
	var icons := true
	var loads := true
	var n := 0
	for race in RACES:
		for slot in SLOTS:
			var glb := DIR + "%s_%s_lv15.glb" % [race, slot]
			var png := DIR + "icon-%s_%s_lv15.png" % [race, slot]
			loads = loads and load(glb) is PackedScene and load(png) is Texture2D
			n += 2
			for cls in CLASSES:
				var id := "armour_%s_%s" % [cls, slot]
				lv15 = lv15 and ItemAssets.armor_file(catalog.entry(id), race) == glb
				starter = starter and ItemAssets.armor_file(catalog.entry(id), race, true) == DIR + "%s_%s.glb" % [race, slot]
				icons = icons and ItemAssets.icon_for_id(id, catalog, race) == load(png) and ItemAssets.icon_for_id(id, catalog, race, true) == load(DIR + "icon-%s_%s.png" % [race, slot])
	ctx.check("lv15 look: armour_<class>_<slot> resolves to <race>_<slot>_lv15.glb for every race", lv15)
	ctx.check("lv15 look: the starter kit keeps the old starter file", starter)
	ctx.check("lv15 look: icon chain picks the lv15 icon (starter pieces the old icon)", icons)
	ctx.check("lv15 look: all %d lv15 files (16 meshes, 16 icons) load" % n, loads and n == 32)
	ctx.check("lv15 look: no race given uses the default race", ItemAssets.armor_file(catalog.entry("armour_magic_shirt")) == DIR + "human_shirt_lv15.glb")
	# a missing lv15 file falls back to the starter race file (a slot without a lv15 file, same fallback fields)
	var info: Dictionary = catalog.entry("armour_magic_shirt").duplicate()
	info["slot"] = "cape"
	info["asset_path"] = ""
	ctx.check("lv15 look: missing lv15 file falls back to the starter race file", ItemAssets.armor_file(info, "elf") == DIR + "elf_shirt.glb")
	var icon_info: Dictionary = info.duplicate()
	ctx.check("lv15 look: missing lv15 icon falls back to the starter icon", ItemAssets.icon_for_id("x", _FakeCatalog.new(icon_info), "elf") == load(DIR + "icon-elf_shirt.png"))
	# non-armour (a race weapon) never takes the lv15 path
	ctx.check("lv15 look: a race weapon has no lv15 path", ItemAssets.lv15_path(catalog.entry("race_human_greatsword_weapon"), "human").is_empty())
	var mats := true
	for race in RACES:
		for slot in SLOTS:
			var scene: PackedScene = load(DIR + "%s_%s_lv15.glb" % [race, slot])
			var root := scene.instantiate()
			var found := false
			for m in root.find_children("*", "MeshInstance3D", true, false):
				for i in (m as MeshInstance3D).mesh.get_surface_count():
					found = found or (m as MeshInstance3D).mesh.surface_get_material(i).resource_name.begins_with("Level 15 | Original Armor")
			mats = mats and found
			root.free()
	ctx.check("lv15 look: the shared material keeps its name 'Level 15 | Original Armor' in all 16 meshes", mats)
	_girth(ctx)


## Girth (Boss 2026-11-16: the lv15 outfits looked much too thin next to the starter ones): front-to-back depth of the four
## pieces together in the bind pose, at chest / waist / hips height, lv15 against the starter of the same race. The delivered
## meshes were 81-90% at the hips and waist (young viking and elf: the same); the girth adjustment of tools/items/split_race_outfits_lv15.py brings them to
## 91% or more (the rest is the shorter hem tail of the coat, a design difference).
const GIRTH_BANDS := {"chest": [0.225, 0.27], "waist": [0.185, 0.225], "hips": [0.14, 0.185]}
const GIRTH_MIN := 0.91


func _depth(race: String, suffix: String) -> Dictionary:
	var zs := {}
	for band in GIRTH_BANDS:
		zs[band] = PackedFloat32Array()
	for slot in SLOTS:
		var root: Node = (load(DIR + "%s_%s%s.glb" % [race, slot, suffix]) as PackedScene).instantiate()
		for m in root.find_children("*", "MeshInstance3D", true, false):
			var faces: PackedVector3Array = (m as MeshInstance3D).mesh.get_faces()
			for v in faces:
				for band in GIRTH_BANDS:
					if v.y >= GIRTH_BANDS[band][0] and v.y < GIRTH_BANDS[band][1]:
						zs[band].append(v.z)
		root.free()
	var out := {}
	for band in zs:
		var arr: PackedFloat32Array = zs[band]
		arr.sort()
		out[band] = arr[int(arr.size() * 0.98)] - arr[int(arr.size() * 0.02)] if arr.size() > 20 else 0.0
	return out


func _girth(ctx) -> void:
	var ok := true
	var worst := 9.9
	for race in RACES:
		var starter := _depth(race, "")
		var lv15 := _depth(race, "_lv15")
		for band in GIRTH_BANDS:
			var ratio: float = lv15[band] / maxf(starter[band], 0.0001)
			worst = minf(worst, ratio)
			ok = ok and ratio >= GIRTH_MIN
	ctx.check("lv15 look: depth of the outfit at chest, waist and hips is at least %d%% of the starter's for every race (worst %.0f%%)" % [int(GIRTH_MIN * 100), worst * 100.0], ok)


class _FakeCatalog:
	var _info: Dictionary
	func _init(info: Dictionary) -> void:
		_info = info
	func entry(_id: String) -> Dictionary:
		return _info
