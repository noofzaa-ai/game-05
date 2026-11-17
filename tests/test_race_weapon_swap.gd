extends RefCounted
## Regression (found 2026-11-17 while reviewing the level-15 weapons): dressing a race weapon file over another one in the SAME
## frame (MID file, then the level-15 file) left the old nodes queued to free; they still held their names, so the new meshes
## got auto names ("@MeshInstance3D@19"), weapon_kind() read "" and the class weapon stayed visible next to the race weapon (a
## double sword). The old meshes now leave the tree at once (client/characters/studio05_character_model.gd _wear_race_weapon).
const StudioModel := preload("res://client/characters/studio05_character_model.gd")
const FILES := {"sword_shield": ["blade", "Sword"], "greatsword": ["greatsword", "Sword"], "longbow": ["longbow", "Bow"], "magic": ["magic", "Staff"]}


func run(ctx) -> void:
	var model := StudioModel.new()
	if not model.load_model():
		ctx.check("weapon swap: the model loads", false)
		return
	var all_ok := true
	var report := ""
	for cls in FILES:
		model.dress({"class": cls})
		var style: String = FILES[cls][0]
		var kind: String = FILES[cls][1]
		for race in ["human", "elf"]:
			for order in [["", "_lv15"], ["_lv15", ""]]:
				for suffix in order:  # no frame in between: the old meshes are still queued to free
					model.dress({"weapon": {"path": "res://art/weapons/race_%s/%s%s.glb" % [race, cls, suffix], "family": style, "style": style}})
				var wanted := "res://art/weapons/race_%s/%s%s.glb" % [race, cls, order[1]]
				var visible_class := 0
				for mesh in model._class_weapons:
					if mesh.visible and StudioModel.weapon_kind(str(mesh.name)) == kind:
						visible_class += 1
				var named := true
				for mesh in model._race_weapon_meshes:
					named = named and StudioModel.weapon_kind(str(mesh.name)) == kind
				var one := model._race_weapon_meshes.size() == 1 and str(model._race_weapon_meshes[0].get_meta("race_weapon_file", "")) == wanted
				var ok: bool = visible_class == 0 and named and one
				all_ok = all_ok and ok
				if not ok:
					report += " [%s %s %s: class pieces shown %d, named %s, one race mesh %s]" % [cls, race, order, visible_class, named, one]
	ctx.check("weapon swap: a race weapon dressed over another in one frame is the only weapon, named by its kind, no class weapon shown%s" % report, all_ok)
	model.free()
