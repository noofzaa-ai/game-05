extends SceneTree
## The hub's four live 3D cards, card ink look off and on (2026-11-14), in one run so the random profile's
## looks and gear are the same in both. Run windowed:
##   godot --path . --script res://tools/shots/card_ink_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/card_ink/hub).
## Saves <prefix>_before.png / <prefix>_after.png and a crop of each card (<prefix>_<before|after>_<class>.png).
const CardPortrait := preload("res://client/card_portrait.gd")


func _initialize():
	call_deferred("run")


func _shoot(screen: Control, path: String) -> void:
	screen._rebuild_cards()
	screen._refresh_all()
	screen._layout()
	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path + ".png")
	for id in screen._cards:
		var card: Control = screen._cards[id]
		var r := Rect2i(card.get_global_rect()).grow(6).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		image.get_region(r).save_png("%s_%s.png" % [path, id])
	print("SHOT ", path)


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var prefix := OS.get_environment("ZORX_SHOT")
	if prefix.is_empty():
		prefix = ProjectSettings.globalize_path("res://build/card_ink/hub")
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(gs.profile.card_deck.duplicate(true), load("res://client/item_assets.gd").cosmetics())
	var ink := CardPortrait.ink_look
	CardPortrait.ink_look = false
	await _shoot(screen, prefix + "_before")
	CardPortrait.ink_look = true
	await _shoot(screen, prefix + "_after")
	CardPortrait.ink_look = ink
	quit()
