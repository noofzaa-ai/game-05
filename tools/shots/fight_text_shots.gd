extends "res://tools/promo/promo_capture.gd"
## Fight-text review (ux-ui 2026-11-25): the clip-6 Orc Warlock fight (same profile and skip as promo_capture.gd
## --promo=orc_boss) in a window of --size=WxH, saving PNG stills every --every frames to ZORX_SHOTS (default
## %TEMP%/zorx_fight_text/<W>x<H>).
##   godot --path . --fixed-fps 60 --script res://tools/shots/fight_text_shots.gd -- --size=844x390 --seed=5


func run() -> void:
	seed(4242)
	var size_text := _arg("size", "1280x720").split("x")
	var size := Vector2i(int(size_text[0]), int(size_text[1]))
	var base := OS.get_environment("ZORX_SHOTS")
	if base.is_empty():
		base = OS.get_environment("TEMP").path_join("zorx_fight_text")
	var out := base.path_join("%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(out)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var rng := RandomNumberGenerator.new()
	rng.seed = PROFILE_SEED
	gs.session.create_profile(rng, true)
	gs.profile = gs.session.profile
	gs.profile.tutorial = load("res://logic/profile.gd").done_tutorial()
	gs.profile.unlocks[load("res://logic/unlocks.gd").flag()] = true
	_orc_profile(gs)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	gs.selected_zone = "orc_camp"
	gs.start_journey("orc_waves", int(_arg("seed", "5")))
	while _stage() == null or not _stage()._scene_presented:
		await process_frame
	_hide_pill()
	_skip_to_boss()
	var every := int(_arg("every", "90"))
	for f in int(_arg("frames", "1500")):
		await process_frame
		if f % every == 0 and f > 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("f%04d.png" % f))
	print("FIGHT TEXT SHOTS ", out)
	quit()
