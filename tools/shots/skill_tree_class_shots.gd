extends SceneTree
## Skills tab of all four class cards (icon size / frame clutter review, Boss 2026-11-23). Run windowed:
##   godot --path . --script res://tools/shots/skill_tree_class_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/skill_tree_ui/classes/<tag>_<W>x<H>),
## ZORX_TAG (default "after"). Every card is levelled to 17 and given a few nodes (local profile only, nothing saved).
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]


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
	var tag := OS.get_environment("ZORX_TAG")
	if tag.is_empty():
		tag = "after"
	var prefix := OS.get_environment("ZORX_SHOT")
	if prefix.is_empty():
		prefix = ProjectSettings.globalize_path("res://build/skill_tree_ui/classes/%s_%dx%d" % [tag, size.x, size.y])
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
	var races: Array = load("res://logic/race_data.gd").load_default().ids()
	for i in CLASSES.size():  # a different race per card: every race branch, frame colour and combo is seen
		progress.grant(gs.profile.card_deck, CLASSES[i], need)
		load("res://logic/card_deck.gd").set_race(gs.profile.card_deck, CLASSES[i], str(races[i % races.size()]))
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
	var data = load("res://logic/skill_tree_data.gd").load_default()
	screen.open_character(CLASSES[0])
	var ch = screen._character
	for c in CLASSES:
		ch.open(c, screen._class_ids, gs.profile.card_deck)
		ch.send = func(request: Dictionary) -> Dictionary: return gs.get_session().command(request)
		for i in 20:
			await process_frame
		ch.select_tab("skills")
		var tab = ch._skills
		var class_nodes: Array = data.class_nodes(c)
		for n in class_nodes.filter(func(x): return int(x["tier"]) == 1).slice(0, 3):
			tab.learn(str(n["id"]))
		await tab.confirm()
		ch._refresh_skills()
		var race: String = load("res://logic/card_deck.gd").race_of(gs.profile.card_deck, c)
		for n in data.race_nodes(race).filter(func(x): return int(x["tier"]) == 1):
			tab.learn(str(n["id"]))
		await tab.confirm()
		ch._refresh_skills()
		var fork: Array = class_nodes.filter(func(x): return int(x["tier"]) == 2)
		tab.learn(str(fork[0]["id"]))  # one draft node
		tab.select(str(fork[2]["id"]))
		for i in 4:
			await process_frame
		if OS.get_environment("ZORX_DUMP") == "1":  # node sizes for the report
			for id in tab._nodes:
				var b: Control = tab._nodes[id]
				print("NODE %s %s side=%.0f icon=%.0f" % [c, id, b.size.x, b.icon_side() if b.has_method("icon_side") else b.size.x * float(load("res://client/card_tokens.gd").TREE_ICON_HOLE.get(b.kind, 0.7))])
		await _shot("%s_%s.png" % [prefix, c])
	quit()
