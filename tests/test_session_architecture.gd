extends RefCounted
## Structural guard for the M1-6 authority boundary, recursively including client subfolders.
const MUTATORS := ["equip", "unequip", "equip_from_stash", "unequip_to_stash", "equip_from_bag", "unequip_to_bag", "discard_item", "take_item", "add_item", "add_material", "remove_material", "pay", "clear_loot", "create_character", "return_to_camp", "upgrade_camp", "upgrade_facility", "enhance", "upgrade_tier", "repair", "repair_all_worn", "bank_bag", "open_treasure", "abandon", "retreat", "leave_node", "choose_next"]

func run(ctx) -> void:
	var method := RegEx.create_from_string("\\.(" + "|".join(MUTATORS) + ")\\s*\\(")
	var assignment := RegEx.create_from_string("\\bprofile\\.(appearance|name|created|camp_level|facility_levels)(\\[[^\\]]*\\])*\\s*(=|\\+=|-=)")
	for path in _scripts("res://client"):
		var errors: Array = []
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			var line: String = raw.split("#")[0]
			if not path.begins_with("res://client/session/") and line.contains('get("_sim")'):
				errors.append("raw simulation access")
			var found := method.search(line)
			# OptionButton.add_item populates a menu, not an owned inventory.
			var menu_entry := path == "res://client/online/room_panel.gd" and line.strip_edges() == 'for count in range(1, 5): capacity.add_item("%d คน" % count)'
			if found != null and not menu_entry: errors.append(found.get_string())
			if assignment.search(line) != null: errors.append("owned assignment")
		ctx.check("M1-6 %s does not mutate ownership outside Commands %s" % [path, errors], errors.is_empty())
	var stage := FileAccess.get_file_as_string("res://client/stage_view.gd")
	ctx.check("M1-6 stage reads/steps Session, not raw GameSim", not stage.contains("_sim.") and not stage.contains("logic/game_sim.gd") and stage.contains("_session.step("))
	var boundary := FileAccess.get_file_as_string("res://client/session/local_session.gd")
	ctx.check("M1-6 LocalSession quantizes both offline and future remote input identically", boundary.contains("SimInput.decode(input.encode())"))

func _scripts(folder: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"): result.append(folder.path_join(file))
	for child in DirAccess.get_directories_at(folder):
		result.append_array(_scripts(folder.path_join(child)))
	return result
