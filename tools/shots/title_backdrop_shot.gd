extends SceneTree
## Pictures of the title screen's animated backdrop (client/title_backdrop.gd) with a few render numbers.
## Saves to art_source/preview/title/backdrop/ (or the folder given after --):
##   desktop_1..3   1600x900, about 1 s apart (the motion: fire, embers, clouds, camera drift)
##   phone          1560x720 (a 20:9 phone held sideways)
##   phone_low      the same with set_quality(true)
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/title_backdrop_shot.gd [-- <out_dir>]

const TitleBackdrop := preload("res://client/title_backdrop.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://art_source/preview/title/backdrop")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var backdrop := TitleBackdrop.new()
	root.add_child(backdrop)
	for i in 30:
		await process_frame
	await create_timer(1.5).timeout  # (the noise textures are made on a thread)
	for i in 3:
		await _save(out, "desktop_%d" % (i + 1))
		await create_timer(1.0).timeout
	DisplayServer.window_set_size(Vector2i(1560, 720))
	root.size = Vector2i(1560, 720)
	for i in 10:
		await process_frame
	await _save(out, "phone")
	backdrop.set_quality(true)
	for i in 10:
		await process_frame
	await _save(out, "phone_low")
	quit()


func _save(out: String, name: String) -> void:
	await process_frame
	await process_frame
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	print("saved %s %dx%d  draw_calls=%d objects=%d primitives=%d fps=%d" % [name, image.get_width(), image.get_height(), calls, objects, primitives, Engine.get_frames_per_second()])
