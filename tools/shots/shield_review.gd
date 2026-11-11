extends SceneTree
## Off-hand shield review (run windowed, nothing is saved): the class card hub with the Sword & Shield card's
## starter shield equipped and with the slot emptied, and a real stage fighter with and without it.
## PNGs in build/studio_v1111/.
const OUT := "res://build/studio_v1111/"


func _initialize():
	call_deferred("run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("SHOT ", name)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _hub(gs, name: String) -> void:
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(root.size)
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen._layout()
	await _wait(40)
	await _shot(name)
	screen.queue_free()
	await _wait(2)


func _fighter(gs, name: String) -> void:
	gs.start_stage(gs.Mode.PVE, "goblin_base_gate")
	await _wait(150)
	var scene = current_scene
	var rig = scene.get("_rig") if scene != null else null
	if rig != null:
		for i in 6:
			rig._orbit(Vector2.ZERO, 0.88)
	await _wait(20)
	var views: Dictionary = scene.get("_views") if scene != null else {}
	for id in views:
		var view = views[id]
		if view.get("_model") != null and view._model.has_method("shield_kind"):
			print("FIGHTER ", name, " id=", id, " class=", view._model.class_id, " shield=", view._model.shield_kind())
	await _shot(name)


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	var size := Vector2i(1600, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var worn = gs.profile.loadout_of("sword_shield")
	print("STARTER offhand=", worn.item_at("offhand", 0).item_id if worn.item_at("offhand", 0) != null else "none")
	var mode := OS.get_environment("ZORX_SHIELD_MODE")
	if mode == "fighter_on":
		gs.squad_size = 1
		await _fighter(gs, "fighter_shield_on")
	elif mode == "fighter_off":
		gs.squad_size = 1
		worn.unequip("offhand", 0)
		await _fighter(gs, "fighter_shield_off")
	else:
		await _hub(gs, "hub_shield_on")
		worn.unequip("offhand", 0)
		await _hub(gs, "hub_shield_off")
	quit()
