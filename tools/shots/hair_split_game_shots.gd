extends SceneTree
## Hair split check in the real screens (run windowed, once with the old model code and once with the new):
##   ZORX_TAG=before|after ZORX_SET=1|2 godot --path . --script res://tools/shots/hair_split_game_shots.gd
## Set 1: Sword & Shield hair A, Great Sword hair G, Longbow hair E + Silver Silk, Magic hair F.
## Set 2: Sword & Shield hair G + Silver Silk, Great Sword hair F + Silver Silk, Longbow hair G, Magic hair G + silk.
## Saves the deck cards, each class's character screen and battle frames to build/hair_split/game/.
const SETS := {
	"1": {"cards": {"sword_shield": ["a", "none"], "greatsword": ["g", "none"], "longbow": ["e", "silver"], "magic": ["f", "none"]},
		"squad": ["sword_shield", "greatsword", "longbow"]},
	"2": {"cards": {"sword_shield": ["g", "silver"], "greatsword": ["f", "silver"], "longbow": ["g", "none"], "magic": ["g", "silver"]},
		"squad": ["greatsword", "longbow", "magic"]},
}


func _initialize():
	call_deferred("run")


func _shot(path: String, frames: int = 8) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run():
	var tag := OS.get_environment("ZORX_TAG")
	var set_id := OS.get_environment("ZORX_SET")
	if set_id.is_empty():
		set_id = "1"
	var setup: Dictionary = SETS[set_id]
	var out := ProjectSettings.globalize_path("res://build/hair_split/game/")
	DirAccess.make_dir_recursive_absolute(out)
	var size := Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var deck: Dictionary = gs.profile.card_deck
	for cls in setup["cards"]:
		deck["cards"][cls]["hair"] = setup["cards"][cls][0]
		deck["cards"][cls]["outfit"] = setup["cards"][cls][1]
		# fixed looks so before/after match (the starter looks are random per profile)
		deck["cards"][cls]["iris_style"] = "0"
		deck["cards"][cls]["eye_color"] = ""
		deck["cards"][cls]["hair_color"] = ""
		deck["cards"][cls]["makeup"] = "none"
	deck["squad"] = setup["squad"].duplicate()
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(deck, load("res://client/item_assets.gd").cosmetics())
	screen._layout()
	await _shot(out + "set%s_deck_%s.png" % [set_id, tag], 40)
	for cls in setup["cards"]:
		screen.open_character(cls)
		await _shot(out + "set%s_char_%s_%s.png" % [set_id, cls, tag], 40)
		screen._character.close()
		await process_frame
	screen.queue_free()
	await process_frame
	gs.start_stage(gs.Mode.PVE, "goblin_base_gate")
	var shots := [[0.5, "start"], [2.5, "run"], [6.0, "fight"]]
	var frames := 0
	for s in shots:
		while frames < int(s[0] * 60.0):
			await process_frame
			frames += 1
		await _shot(out + "set%s_battle_%s_%s.png" % [set_id, s[1], tag], 1)
	quit()
