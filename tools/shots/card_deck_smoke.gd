extends SceneTree
## Smoke: opens the class card screen, the editor and a summon; with ZORX_SHOT=path saves a PNG (run windowed).
func _initialize():
	call_deferred("run")

func run():
	root.size = Vector2i(1280, 720)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	for i in 20:
		await process_frame
	print("SMOKE deck ok cards=", screen._cards.size())
	var shot := OS.get_environment("ZORX_SHOT")
	if not shot.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot + "_deck.png")
	screen._open_editor("greatsword")
	for i in 20:
		await process_frame
	screen._pick("hair", "e")
	screen._select_tab("eyes")
	await process_frame
	print("SMOKE editor ok")
	if not shot.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot + "_editor.png")
	screen._close_editor()
	screen.play_summon(["sword_shield", "greatsword"])
	await create_timer(1.4).timeout
	print("SMOKE summon ok done=", screen._summon_done)
	quit()
