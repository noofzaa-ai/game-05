extends SceneTree
func _initialize() -> void:
	await process_frame
	root.size=Vector2i(1280,720)
	var state=root.get_node("GameState")
	state.ensure_profile()
	state.profile.created=true
	var hub=load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	for i in 50: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hub-camera-fixed.png")
	hub._rig._orbit(Vector2(240,50),.8)
	for i in 35: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hub-camera-orbit.png")
	print("CAMP AND ORBIT CAPTURED")
	quit()
