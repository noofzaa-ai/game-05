extends SceneTree
## Battle race ground ring shot (design/gdd/races-and-classes.md 3.8). Run windowed:
##   godot --path . --script res://tools/shots/race_ring_shot.gd
## Starts the wave journey with SQUAD (default sword_shield,greatsword,magic: Human / Viking / Runeborn), zooms in and
## saves build/race_ui/battle_ring_<n>.png at a few moments, and prints each squad fighter's ring.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/race_ui/")
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var squad := OS.get_environment("SQUAD")
	if squad.is_empty():
		squad = "sword_shield,greatsword,magic"
	preload("res://logic/card_deck.gd").set_squad(game_state.profile.card_deck, Array(squad.split(",")))
	game_state.start_journey()
	var shots := [150, 300]
	var frames := 0
	while frames <= shots.back():
		await process_frame
		frames += 1
		if frames == 30 and current_scene != null and current_scene.get("_rig") != null:
			for i in 7:
				current_scene._rig._orbit(Vector2.ZERO, 0.88)
		if frames in shots:
			await RenderingServer.frame_post_draw
			var path := "res://build/race_ui/battle_ring_%d.png" % frames
			root.get_texture().get_image().save_png(path)
			print("SHOT ", ProjectSettings.globalize_path(path))
	for node in current_scene.find_children("RaceRing", "", true, false):
		print("RING ", node.race, " visible=", node.visible, " at ", node.global_position)
	quit()
