extends SceneTree
const Review := preload("res://client/workshop_review.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1440, 900)
	root.scaling_3d_scale = 1.0
	Engine.max_fps = 30
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene := Review.new()
	root.add_child(scene)
	var folder := "res://art_source/props/camp_modular/review/prepared"
	DirAccess.make_dir_recursive_absolute(folder)
	var motion := "--motion" in OS.get_cmdline_user_args()
	for level in ([1] if motion else [1, 2, 3]):
		scene.show_level(level)
		for frame in range(640 if motion else 145):
			await process_frame
			root.scaling_3d_scale = 1.0
			await RenderingServer.frame_post_draw
			if frame == 20 or frame == 130:
				root.get_texture().get_image().save_png(folder + "/workshop_lv%d_%s.png" % [level, "idle" if frame == 20 else "walking"])
			if motion and frame >= 171 and frame <= 621 and frame % 9 == 0:
				root.get_texture().get_image().save_png(folder + "/motion_%03d.png" % frame)
			if not motion and level == 1 and frame % 6 == 0:
				root.get_texture().get_image().save_png(folder + "/walk_%03d.png" % frame)
	quit()
