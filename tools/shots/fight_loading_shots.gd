extends SceneTree
## The FIGHT loading overlay (client/fight_loading.gd) over the hub, in its states, at the phone size.
## Run windowed:  godot --path . --script res://tools/shots/fight_loading_shots.gd
## ZORX_SIZE=WxH (default 2796x1290), ZORX_SHOT_DIR (default art_source/codex_review/fight_loading_2026-11-14/).
## ZORX_LANG=th for the Thai strings. Nothing is loaded or started: the states are set by hand.

var _out := ""


func _initialize() -> void:
	call_deferred("run")


func _shot(name: String, frames: int = 6) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run() -> void:
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(2796, 1290)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	_out = OS.get_environment("ZORX_SHOT_DIR")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://art_source/codex_review/fight_loading_2026-11-14")
	DirAccess.make_dir_recursive_absolute(_out)
	var CardTokens = load("res://client/card_tokens.gd")
	var lang := OS.get_environment("ZORX_LANG")
	if lang != "":
		CardTokens.language = lang
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	current_scene = screen
	screen.size = Vector2(size)
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen._layout()
	await _shot("hub_before_fight", 40)
	var FL = load("res://client/fight_loading.gd")
	var overlay = FL.open(self, true)
	overlay.set_process(false)  # states by hand only
	var suffix := "_" + lang if lang != "" else ""
	overlay._set_step(FL.Step.PACKS)
	overlay._advance(0.18)
	await _shot("fight_loading_download_18" + suffix)
	overlay._set_step(FL.Step.LOADING)
	overlay._advance(0.57)
	await _shot("fight_loading_battle_57" + suffix)
	overlay._set_step(FL.Step.BUILD)
	overlay._advance(0.9)
	await _shot("fight_loading_build_90" + suffix)
	overlay._set_step(FL.Step.CONNECTING)
	overlay._stripe = 0.3
	overlay._fill.stripe = 0.3
	overlay._fill.queue_redraw()
	await _shot("fight_connecting" + suffix)
	overlay.step = FL.Step.PACKS
	overlay._pack_failed = true
	overlay._fill.indeterminate = false
	overlay._refresh_text()
	await _shot("fight_loading_download_failed" + suffix)
	quit()
