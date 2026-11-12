extends SceneTree
## Skills tab shots (design/gdd/skill-tree.md 9.1). Run windowed:
##   godot --path . --script res://tools/shots/skill_tree_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/skill_tree_ui/<W>x<H>).
## The card is levelled for the shots (a local profile only; nothing is saved).
func _initialize():
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var prefix := OS.get_environment("ZORX_SHOT")
	if prefix.is_empty():
		prefix = ProjectSettings.globalize_path("res://build/skill_tree_ui/%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var progress = load("res://logic/card_progress.gd")
	var need := 0
	for level in range(1, 17):
		need += progress.xp_req(level)
	progress.grant(gs.profile.card_deck, "sword_shield", need)  # level 17: 17 points
	gs.profile.stash.gold = maxi(gs.profile.stash.gold, 2000)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 30:
		await process_frame
	screen.open_character("sword_shield")
	var ch = screen._character
	ch.send = func(request: Dictionary) -> Dictionary: return gs.get_session().command(request)
	for i in 20:
		await process_frame
	ch.select_tab("skills")
	var tab = ch._skills
	await _shot(prefix + "_skills_empty.png")
	# a draft: T1 x 3, select the first T2 fork node
	var data = load("res://logic/skill_tree_data.gd").load_default()
	var class_nodes: Array = data.class_nodes("sword_shield")
	for n in class_nodes.filter(func(x): return int(x["tier"]) == 1).slice(0, 3):
		tab.learn(str(n["id"]))
	var fork: Array = class_nodes.filter(func(x): return int(x["tier"]) == 2)
	tab.select(str(fork[0]["id"]))
	await _shot(prefix + "_skills_draft.png")
	# confirm through the session, then learn more (class 8, race 6) for the combo
	await tab.confirm()
	ch._refresh_skills()
	tab.learn(str(fork[0]["id"]))
	tab.learn(str(fork[2]["id"]))
	var race: String = load("res://logic/card_deck.gd").race_of(gs.profile.card_deck, "sword_shield")
	for n in data.race_nodes(race).filter(func(x): return int(x["tier"]) <= 2):
		tab.learn(str(n["id"]))
	tab.select(str(data.combo_node(race, "sword_shield")["id"]))
	await tab.confirm()
	ch._refresh_skills()
	tab.select(str(data.combo_node(race, "sword_shield")["id"]))
	print("SAVED ", load("res://logic/skill_tree.gd").state(gs.profile.card_deck, "sword_shield"))
	await _shot(prefix + "_skills_confirmed.png")
	tab._on_reset("class")
	await _shot(prefix + "_skills_reset_armed.png")
	quit()
