extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1000, 650)
	root.add_child(preload("res://client/graphics_panel.gd").new())
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/zorx-graphics-panel.png")
	quit()
