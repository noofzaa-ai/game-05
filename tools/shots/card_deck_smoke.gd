extends SceneTree
## Smoke: opens the class card hub, a service panel, the look editor and a summon; with ZORX_SHOT=path saves PNGs
## (run windowed). ZORX_SIZE=WxH sets the window size (default 1920x1080).
func _initialize():
	call_deferred("run")

func _shot(path: String) -> void:
	if path.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SMOKE shot ", path)

func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	screen.locked_services = ["relics"]
	screen.service_badges = {"quests": "2"}
	screen.locked_classes = ["magic"] if OS.get_environment("ZORX_LOCK_MAGIC") == "1" else []
	root.add_child(screen)
	screen.size = Vector2(size)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 40:
		await process_frame
	print("SMOKE deck ok cards=", screen._cards.size(), " size=", screen.size, " phone=", screen._phone)
	var shot := OS.get_environment("ZORX_SHOT")
	await _shot(shot + "_hub.png" if not shot.is_empty() else "")
	screen._menu[0].grab_focus()
	for i in 4:
		await process_frame
	await _shot(shot + "_hub_focus.png" if not shot.is_empty() else "")
	screen.open_service("shop")
	for i in 4:
		await process_frame
	print("SMOKE service ok open=", screen._service_open)
	await _shot(shot + "_service.png" if not shot.is_empty() else "")
	screen._close_service()
	screen._open_editor("greatsword")
	for i in 20:
		await process_frame
	screen._pick("hair", "e")
	screen._select_tab("eyes")
	await process_frame
	print("SMOKE editor ok")
	await _shot(shot + "_editor.png" if not shot.is_empty() else "")
	screen._close_editor()
	screen.play_summon(["sword_shield", "greatsword"])
	await create_timer(1.4).timeout
	print("SMOKE summon ok done=", screen._summon_done)
	quit()
