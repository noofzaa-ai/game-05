extends SceneTree
## Saves pictures of the title screen (client/title_screen.gd): the menu, Version Info, Settings and
## Staff & Credits, on a desktop window (1600x900), a phone in landscape (932x430) and a phone held
## upright (430x932). Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/title_shots.gd -- <out_dir>

const SIZES := {"desktop": Vector2i(1600, 900), "phone_landscape": Vector2i(932, 430), "portrait": Vector2i(430, 932)}


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame  # (the autoloads start first)
	var title: Node = load("res://scenes/title.tscn").instantiate()
	title.density_override = 1.0  # (the window's real pixels are the target size, also on a Retina Mac)
	root.add_child(title)
	for size_name in SIZES:
		root.size = SIZES[size_name]
		await _settle(10)
		title._fit()
		await _settle(30)
		title.items["start"].grab_focus()
		await _save(out.path_join("title_%s.png" % size_name))
		title.items["versions"].grab_focus()  # (the brass marker on another item)
		await _save(out.path_join("title_%s_focus.png" % size_name))
		for kind in ["versions", "staff", "settings"]:
			title.open_panel(kind)
			await _save(out.path_join("%s_%s.png" % [kind, size_name]))
			title.close_panel()
		title.open_panel("versions")
		title.show_version(title.info.versions.size() - 1)
		await _save(out.path_join("versions_%s_oldest.png" % size_name))
		title.close_panel()
	quit()


func _settle(frames: int) -> void:
	for frame in frames:
		await process_frame


func _save(file: String) -> void:
	await _settle(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("saved ", file)
