extends SceneTree
## Screenshot: hub -> world map panel, at a given size. godot --path . --script res://tools/localstack/map_shot.gd -- 1280x720 OUT.png [beaten]
func _initialize():
	call_deferred("run")

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(int(args[0].split("x")[0]), int(args[0].split("x")[1]))
	root.size = size
	DisplayServer.window_set_size(size)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	if args.has("beaten"):
		gs.profile.unlocks["boss_goblin_base"] = true
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	root.add_child(screen)
	await create_timer(1.5).timeout
	screen.open_world_map()
	await create_timer(1.0).timeout
	if args.has("pick"):
		screen._panels["map"].select_zone("pyramid")
		await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1])
	quit()
