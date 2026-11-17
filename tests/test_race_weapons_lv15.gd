extends RefCounted
## Level-15 race weapons (Boss delivery 2026-11-17, tools/items/split_race_weapons_lv15.py): the race weapon items
## (race_<race>_<class>_weapon, req_level 15) and race shields show art/weapons/race_<race>/<file>_lv15.glb (icons
## icon-<file>_lv15.png) when they are not starter pieces (instance ids "starter-..."), the MID file is the fallback, and every
## level-15 weapon is as long as the level-1 weapon the game shows (the MID race file, which starter pieces use) within 3% and is
## held at the same place along its axis (the holding joint's position on the axis, within 5% of the length).
const ItemAssets := preload("res://client/item_assets.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const RACES := ["human", "viking", "elf", "runeborn"]
const FILES := ["sword_shield", "shield", "greatsword", "longbow", "magic"]
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const HOLD := {"sword_shield": "mixamorig_RightHand", "shield": "mixamorig_LeftForeArm", "greatsword": "mixamorig_RightHand",
	"longbow": "mixamorig_LeftHand", "magic": "mixamorig_RightHand"}
const TOLERANCE := 0.03
const GRIP_TOLERANCE := 0.05


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


## {"length", "grip", "axis"} of a weapon scene: the main axis of all its vertices (power iteration on the covariance, bind-pose mesh
## space, pointing like `ref_axis` when given), the length along it, and where the holding bone projects on it as a fraction of the
## length from the low end.
func _shape(root: Node, hold: String, ref_axis: Vector3 = Vector3.ZERO) -> Dictionary:
	var pts := PackedVector3Array()
	for m in root.find_children("*", "MeshInstance3D", true, false):
		pts.append_array((m as MeshInstance3D).mesh.get_faces())
	# the holding joint in the vertices' space: the origin of the inverse of the skin's bind pose of that bone
	var joint := Vector3.ZERO
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var skin: Skin = (m as MeshInstance3D).skin
		for i in skin.get_bind_count():
			if skin.get_bind_name(i) == hold:
				joint = skin.get_bind_pose(i).affine_inverse().origin
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
	if ref_axis != Vector3.ZERO and axis.dot(ref_axis) < 0.0:
		axis = -axis
	var lo := 1e9
	var hi := -1e9
	for p in pts:
		var t: float = (p - centre).dot(axis)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return {"length": hi - lo, "grip": ((joint - centre).dot(axis) - lo) / (hi - lo), "axis": axis}


func _size(ctx) -> void:
	var worst_length := 0.0
	var worst_grip := 0.0
	var worst_name := ""
	for file in FILES:
		for race in RACES:
			var mid_root: Node = (load("res://art/weapons/race_%s/%s.glb" % [race, file]) as PackedScene).instantiate()
			var mid := _shape(mid_root, HOLD[file])
			var root: Node = (load("res://art/weapons/race_%s/%s_lv15.glb" % [race, file]) as PackedScene).instantiate()
			var now := _shape(root, HOLD[file], mid["axis"])
			var off_length := absf(float(now["length"]) / maxf(float(mid["length"]), 0.0001) - 1.0)
			var off_grip := absf(float(now["grip"]) - float(mid["grip"]))
			if off_length > worst_length or off_grip > worst_grip:
				worst_name = "%s %s length %.3f/%.3f grip %.2f/%.2f" % [race, file, now["length"], mid["length"], now["grip"], mid["grip"]]
			worst_length = maxf(worst_length, off_length)
			worst_grip = maxf(worst_grip, off_grip)
			mid_root.free()
			root.free()
	ctx.check("lv15 weapons: every lv15 weapon is as long as the MID (level-1) file within %d%% (worst %.1f%%) and held at the same place within %d%% of its length (worst %.1f%%; last worst: %s)" % [
		int(TOLERANCE * 100), worst_length * 100.0, int(GRIP_TOLERANCE * 100), worst_grip * 100.0, worst_name], worst_length <= TOLERANCE and worst_grip <= GRIP_TOLERANCE)
