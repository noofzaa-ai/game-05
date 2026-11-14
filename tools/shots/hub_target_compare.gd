extends SceneTree
## The My Cards hub next to Boss's carved target (art_source/boss_refs/hub_inkwash_2026-11-14/hub_TARGET_carved.png).
## Run windowed:  godot --path . --script res://tools/shots/hub_target_compare.gd
## Shoots the hub at 2796x1290 (phone) and 1920x1080 (16:9) into ZORX_SHOT_DIR (default
## art_source/codex_review/hub_target_build_2026-11-14/). ZORX_LOADING=1 shows the web "Loading battle N%" ribbon
## (forced text; on desktop the battle packs are already in, so the ribbon is normally hidden).

const CardTokens := preload("res://client/card_tokens.gd")
const SIZES := [Vector2i(2796, 1290), Vector2i(1920, 1080)]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var out := OS.get_environment("ZORX_SHOT_DIR")
	if out.is_empty():
		out = ProjectSettings.globalize_path("res://art_source/codex_review/hub_target_build_2026-11-14")
	DirAccess.make_dir_recursive_absolute(out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	for size in SIZES:
		DisplayServer.window_set_size(size)
		root.size = size
		var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
		screen.auto_wire = false
		root.add_child(screen)
		current_scene = screen  # the Online status pill shows over the hub scene only
		screen.size = Vector2(size)
		screen.show_deck(gs.profile.card_deck.duplicate(true), load("res://client/item_assets.gd").cosmetics())
		screen.set_gold(gs.profile.stash.gold)
		screen._layout()
		for i in 40:
			await process_frame
		if OS.get_environment("ZORX_LOADING") == "1":  # the web loading line (the screen's _process would clear it)
			screen.set_process(false)
			screen._fight_progress.text = CardTokens.t("fight_loading") % 96
			screen._fight_progress.visible = true
			screen._fight_ribbon.visible = true
			screen._fit_fight_progress()
			for i in 4:
				await process_frame
		await RenderingServer.frame_post_draw
		var path := out.path_join("hub_%dx%d.png" % [size.x, size.y])
		root.get_texture().get_image().save_png(path)
		print("SHOT ", path)
		screen.queue_free()
		await process_frame
	quit()
