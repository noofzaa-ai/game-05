extends SceneTree
## The Quests panel's MAIN and DAILY pages (Boss 2026-11-21) and the hub quest tracker. Run windowed (no --headless):
##   godot --path . --script res://tools/shots/quest_pages_shots.gd -- --size 844x390 --page daily --lang th --out build/quest_pages/x.png [--hub]
## The profile is the local one, changed IN MEMORY only (past the tutorial, goblin boss beaten, cards at Lv 12/8/...,
## two dailies done and one claimed), so the shot needs no server.

var size := Vector2i(1280, 720)
var page := "main"
var out := ""
var hub_only := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--size": size = Vector2i(int(nxt.split("x")[0]), int(nxt.split("x")[1]))
			"--page": page = nxt
			"--out": out = nxt
			"--hub": hub_only = true
			"--lang": load("res://client/card_tokens.gd").language = nxt
	out = ProjectSettings.globalize_path("res://" + out) if not out.contains(":") else out
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var p = gs.profile
	var F = load("res://tests/online_fixture.gd")
	F.past_tutorial(p)
	p.unlocks["boss_goblin_base"] = true
	var lv := [12, 8, 10, 6]
	var ids: Array = p.card_deck["cards"].keys()
	for i in ids.size():
		p.card_deck["cards"][ids[i]]["progress"] = {"level": lv[i % lv.size()], "xp": 0}
	var Daily = load("res://logic/daily_quests.gd")
	var now := int(Time.get_unix_time_from_system())
	p.daily = {}
	Daily.record_run(p, now, 6, false)
	Daily.record_run(p, now, 9, true)
	Daily.claim(p, "daily_boss", now)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	screen.tracker_reads_profile = true
	root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.show_deck(p.card_deck.duplicate(true), load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(p.stash.gold)
	screen._layout()
	for i in 30:
		await process_frame
	if not hub_only:
		screen.open_service("quests")
		var panel = screen._panels["quests"]
		panel.show_page(page)
		for i in 30:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit()
