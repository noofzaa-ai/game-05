extends SceneTree
## The tutorial battle tip in a real solo stage (design/gdd/tutorial.md 4 battle_tip). Run windowed:
##   godot --path . --script res://tools/shots/tutorial_battle_shot.gd
## ZORX_SIZE=WxH, ZORX_SHOT=folder (default art_source/codex_review/tutorial_ui_2026-11-15). In-memory profile only.
func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var folder := OS.get_environment("ZORX_SHOT")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://art_source/codex_review/tutorial_ui_2026-11-15")
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	for pair in [["sword_shield", "human"], ["greatsword", "viking"], ["longbow", "elf"]]:
		gs.profile.card_deck["cards"][pair[0]]["race"] = pair[1]
	gs.profile.card_deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	gs.profile.tutorial = {"version": 1, "step": "battle_tip", "tour_done": false, "unlock_seen": false}
	gs.start_stage(gs.Mode.PVE, "goblin_base_gate")
	for i in 150:
		await process_frame
	await RenderingServer.frame_post_draw
	var tip = current_scene.get_node_or_null("TutorialBattle") if current_scene != null else null
	print("BATTLE tip=", tip != null)
	var path := "%s/%dx%d_24_battle_tip.png" % [folder, size.x, size.y]
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)
	quit()
