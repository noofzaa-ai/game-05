extends SceneTree
## Every hub-side screen and the battle HUD at the phone size, for the carved ink-wash restyle (Boss 2026-11-14).
## Run windowed:  godot --path . --script res://tools/shots/carved_screens_shots.gd
## ZORX_SIZE=WxH (default 2796x1290), ZORX_TAG=before|after (file prefix, default after),
## ZORX_SHOT_DIR (default art_source/codex_review/screens_carved_2026-11-14/), ZORX_ONLY=comma list of shot groups
## (char,skills,race,services,settings,battle). A local profile only; nothing is saved.

var _out := ""
var _tag := ""


func _initialize() -> void:
	call_deferred("run")


func _shot(name: String, frames: int = 8) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := _out.path_join("%s_%s.png" % [_tag, name])
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run() -> void:
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(2796, 1290)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	_tag = OS.get_environment("ZORX_TAG") if OS.get_environment("ZORX_TAG") != "" else "after"
	_out = OS.get_environment("ZORX_SHOT_DIR")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://art_source/codex_review/screens_carved_2026-11-14")
	DirAccess.make_dir_recursive_absolute(_out)
	var only := Array(OS.get_environment("ZORX_ONLY").split(",", false))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var progress = load("res://logic/card_progress.gd")
	var need := 0
	for level in range(1, 17):
		need += progress.xp_req(level)
	progress.grant(gs.profile.card_deck, "sword_shield", need)
	gs.profile.stash.gold = maxi(gs.profile.stash.gold, 5000)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	current_scene = screen
	screen.size = Vector2(size)
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	await _shot("hub", 40)
	if only.is_empty() or only.has("char") or only.has("skills") or only.has("race"):
		screen.open_character("sword_shield")
		var ch = screen._character
		ch.send = func(request: Dictionary) -> Dictionary: return gs.get_session().command(request)
		for i in 30:
			await process_frame
		if only.is_empty() or only.has("char"):
			ch.select_slot("weapon:0")
			await _shot("char_equipment")
		if only.is_empty() or only.has("skills"):
			ch.select_tab("skills")
			var tab = ch._skills
			var data = load("res://logic/skill_tree_data.gd").load_default()
			var class_nodes: Array = data.class_nodes("sword_shield")
			for n in class_nodes.filter(func(x): return int(x["tier"]) == 1).slice(0, 3):
				tab.learn(str(n["id"]))
			var fork: Array = class_nodes.filter(func(x): return int(x["tier"]) == 2)
			if not fork.is_empty():
				tab.select(str(fork[0]["id"]))
			await _shot("char_skills")
			ch.select_tab("equipment")
		if only.is_empty() or only.has("race"):
			ch.open_race_picker()
			var picker = ch._race_picker
			picker._on_tile("viking")
			await _shot("race_picker")
			picker.close()
		ch.close()
		for i in 10:
			await process_frame
	if only.is_empty() or only.has("services"):
		for service in ["blacksmith", "shop", "storage"]:
			screen.open_service(service)
			var panel = screen._panels[service]
			if service == "blacksmith":
				panel.select_source("sword_shield")
				var weapon = gs.profile.loadout_of("sword_shield").item_at("weapon", 0)
				if weapon != null:
					panel.select_item(weapon.id)
			elif service == "storage" and not gs.profile.stash.items.is_empty():
				panel.select_item(gs.profile.stash.items[0].id)
			await _shot("svc_" + service, 12)
			panel.close()
		screen.open_service("tailor")
		await _shot("svc_tailor", 30)
		screen._panels["tailor"].close()
		for i in 6:
			await process_frame
	if only.is_empty() or only.has("settings"):
		var settings = load("res://client/graphics_panel.gd").new()
		screen.add_child(settings)
		await _shot("settings", 12)
		settings.queue_free()
		for i in 4:
			await process_frame
	if only.is_empty() or only.has("battle"):
		screen.queue_free()
		await process_frame
		gs.start_journey()
		for i in 60 * 9:
			await process_frame
		await _shot("battle_hud", 2)
		var result = load("res://client/result_panel.gd").new()
		current_scene.add_child(result)
		result.show_result("stage_clear", [["continue", "continue"], ["camp", "camp"]])
		await _shot("result_panel", 6)
	quit()
