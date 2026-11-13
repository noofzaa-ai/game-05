extends SceneTree
## Race UI shots (design/gdd/races-and-classes.md 3.7-3.9): the hub with race badges + synergy line, the race picker,
## a race change with the refund warning (before / after). Run windowed:
##   godot --path . --script res://tools/shots/race_ui_shots.gd
## ZORX_SIZE=WxH (default 1920x1080). Output: build/race_ui/<W>x<H>_*.png
const SkillTree := preload("res://logic/skill_tree.gd")
const CardDeck := preload("res://logic/card_deck.gd")


func _initialize():
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var prefix := ProjectSettings.globalize_path("res://build/race_ui/%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var deck: Dictionary = gs.profile.card_deck
	# Sword & Shield: level it and learn 2 race nodes (2 race points) so a race change refunds them
	var progress = load("res://logic/card_progress.gd")
	var need := 0
	for level in range(1, 9):
		need += progress.xp_req(level)
	progress.grant(deck, "sword_shield", need)
	var race := CardDeck.race_of(deck, "sword_shield")
	for node_id in ["hu_1", "hu_2"]:
		print("LEARN ", node_id, " ", SkillTree.learn(deck, "sword_shield", node_id))
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 30:
		await process_frame
	print("RACE before ", race, " squad ", CardDeck.squad_races(deck))
	await _shot(prefix + "_hub_badges_synergy.png")
	screen.open_character("sword_shield")
	var ch = screen._character
	for i in 30:
		await process_frame
	await _shot(prefix + "_char_race_button.png")
	ch.open_race_picker()
	await _shot(prefix + "_picker_open.png")
	var picker = ch._race_picker
	print("REFUND points ", picker.refund_points)
	picker._on_tile("viking")
	await _shot(prefix + "_picker_refund_warning.png")
	picker._on_confirm()
	for i in 20:
		await process_frame
	print("RACE after ", CardDeck.race_of(gs.profile.card_deck, "sword_shield"), " tree ", SkillTree.state(gs.profile.card_deck, "sword_shield")["spent"])
	await _shot(prefix + "_picker_after_change.png")
	picker.close()
	ch.close()
	for i in 20:
		await process_frame
	await _shot(prefix + "_hub_after_change.png")
	quit()
