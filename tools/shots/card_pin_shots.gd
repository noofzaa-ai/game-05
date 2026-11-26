extends "res://tools/promo/promo_capture.gd"
## Card pin review (ux-ui 2026-11-26): Orc Camp boss wave (same setup as fight_text_shots.gd), selects card 2,
## pins it away from the boss, and saves stills to ZORX_SHOTS/<W>x<H> (default %TEMP%/zorx_card_pin).
##   godot --path . --fixed-fps 60 --script res://tools/shots/card_pin_shots.gd -- --size=844x390


func run() -> void:
	seed(4242)
	var size_text := _arg("size", "1280x720").split("x")
	var size := Vector2i(int(size_text[0]), int(size_text[1]))
	var base := OS.get_environment("ZORX_SHOTS")
	if base.is_empty():
		base = OS.get_environment("TEMP").path_join("zorx_card_pin")
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
	for f in 150:
		await process_frame
	var stage = _stage()
	var pin = stage._card_pin
	if pin == null:
		print("CARD PIN MISSING"); quit(1); return
	stage._squad_panel.select(2)
	await _pin_shot(out, "a_selected")
	var sess = stage._session
	var boss_at := Vector3.ZERO
	for id in sess.fighters:
		if sess.fighters[id].team == "enemy" and sess.fighters[id].is_alive():
			boss_at = sess.bodies[id].position
			if stage._boss_id == id: break
	var me: Vector3 = sess.bodies[2].position
	var away := (me - boss_at)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
	var cam: Camera3D = stage._rig.get("_camera")
	var res: Dictionary = {}
	var at := Vector2.ZERO
	for turn in 8:  # away from the boss; skip points under the HUD (the pin refuses those)
		var target := boss_at + away.rotated(Vector3.UP, TAU * turn / 8.0) * 5.0
		at = cam.unproject_position(target)
		if not Rect2(Vector2.ZERO, Vector2(size)).has_point(at): continue
		res = pin.tap(at)
		if not res.is_empty(): break
	print("PIN at screen ", at, " -> ", res, " boss ", boss_at)
	await _pin_shot(out, "b_pinned_tap")
	for f in 40: await process_frame
	await _pin_shot(out, "c_walking")
	for f in 240: await process_frame
	await _pin_shot(out, "d_at_pin")
	for f in 120: await process_frame
	await _pin_shot(out, "e_at_pin_later")
	print("CARD PIN SHOTS ", out)
	quit()


func _pin_shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
