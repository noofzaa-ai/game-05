extends SceneTree
## The My Cards hub with each card's LEVEL (Boss 2026-11-19), one shot per level style. Run windowed (no --headless):
##   godot --path . --script res://tools/shots/hub_level_shots.gd -- --fixture veteran --size 1280x720 --style 1 --out build/hub_level/x.png [--lock-magic] [--level 15] [--lang th]
## The fixture (tools/localstack/fixtures/<name>.json) is applied to the local profile IN MEMORY only (never saved, no
## server), so the shot needs no local stack. The project's canvas_items stretch stays on, so 844x390 shows the real
## phone canvas (1558x720 scaled to the window).

var fixture := "veteran"
var size := Vector2i(1280, 720)
var style := -1
var out := ""
var lock_magic := false
var level := 0
var hover := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--fixture": fixture = nxt
			"--size": size = Vector2i(int(nxt.split("x")[0]), int(nxt.split("x")[1]))
			"--style": style = int(nxt)
			"--out": out = nxt
			"--lock-magic": lock_magic = true
			"--level": level = int(nxt)
			"--hover": hover = nxt
			"--lang": load("res://client/card_tokens.gd").language = nxt
	var tokens = load("res://client/card_tokens.gd")
	if style >= 0:
		tokens.hub_level_style = style
	if out.is_empty():
		out = "build/hub_level/%s_%dx%d_s%d.png" % [fixture, size.x, size.y, tokens.hub_level_style]
	out = ProjectSettings.globalize_path("res://" + out) if not out.contains(":") else out
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tools/localstack/fixtures/%s.json" % fixture))
	var deck: Dictionary = gs.profile.card_deck.duplicate(true)
	for id in fx["card_deck"]["cards"]:
		if deck["cards"].has(id):
			for k in fx["card_deck"]["cards"][id]:
				deck["cards"][id][k] = fx["card_deck"]["cards"][id][k]
			if level > 0:
				deck["cards"][id]["progress"] = {"level": level, "xp": 0}
	deck["squad"] = fx["card_deck"].get("squad", deck["squad"])
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	screen.locked_classes = ["magic"] if lock_magic else []
	root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.show_deck(deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(int(str(fx.get("stash", {}).get("gold", "1200"))))
	screen._layout()
	for i in 50:
		await process_frame
	if not hover.is_empty() and screen._cards.has(hover):
		screen._cards[hover]._hover(true)
		for i in 20:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out, " style=", tokens.hub_level_style)
	quit()
