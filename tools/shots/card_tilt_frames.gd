extends SceneTree
## Saves a frame sequence of the hub while a simulated mouse sweeps across one card (hover -> tilt, holo foil,
## parallax) so the card's depth can be reviewed without opening Godot. Output: build/card_tilt/f_###.png
##   godot --path . --script res://tools/shots/card_tilt_frames.gd   (windowed; ZORX_CARD=class id)
const OUT := "res://build/card_tilt"


func _initialize() -> void:
	call_deferred("run")


func _move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)


func run() -> void:
	var size := Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	DirAccess.make_dir_recursive_absolute(OUT)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	for i in 40:
		await process_frame
	var card_id := OS.get_environment("ZORX_CARD") if OS.get_environment("ZORX_CARD") != "" else "sword_shield"
	var card: Control = screen._cards.get(card_id)
	if card == null:
		print("TILT no card ", card_id)
		quit(1)
		return
	var rect: Rect2 = card.get_global_rect()
	print("TILT card rect ", rect)
	# Start outside the card, enter, sweep a loop around the card, leave.
	var path: Array[Vector2] = [rect.position + Vector2(-60, rect.size.y * 0.5)]
	var steps := 48
	for i in steps:
		var t := float(i) / float(steps) * TAU
		path.append(rect.get_center() + Vector2(cos(t) * rect.size.x * 0.42, sin(t) * rect.size.y * 0.40))
	path.append(rect.position + Vector2(rect.size.x + 80, rect.size.y * 0.5))
	var frame := 0
	for p in path:
		_move(p)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var crop := Rect2i(rect.grow(40)).intersection(Rect2i(Vector2i.ZERO, size))
		img.get_region(crop).save_png("%s/f_%03d.png" % [OUT, frame])
		frame += 1
	print("TILT frames ", frame)
	quit()
