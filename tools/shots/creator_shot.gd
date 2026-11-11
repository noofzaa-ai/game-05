extends SceneTree
## Starts the game at the campfire as a new player and saves two pictures: the character creator
## (after a roll of the dice and a typed name), then the campfire with the made character.
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/creator_shot.gd -- <out_dir>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	await process_frame  # (the autoloads start first)
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	for frame in 5:
		await process_frame
	var creator = hub._creator
	creator.randomize_look()
	creator.name_field.text = "Mira"
	creator.name_field.text_changed.emit("Mira")
	await _save(out.path_join("creator.png"))
	creator.start_button.pressed.emit()
	await _save(out.path_join("campfire.png"))
	quit()


func _save(file: String) -> void:
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
