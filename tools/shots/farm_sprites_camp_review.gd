extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1440,810)
	var source=load("res://data/perf/scenario.gd").new()
	var game=root.get_node("GameState");game.profile=source.profile;source.profile.camp_level=2
	var now:=int(Time.get_unix_time_from_system())
	source.profile.farm={"plots":{"0":{"crop":"carrot","planted_at":now-900},"1":{"crop":"potato","planted_at":now-1800},"2":{"crop":"herb","planted_at":now-2700},"3":{"crop":"carrot","planted_at":now-300}}}
	var world=load("res://client/hub_world.gd").new();root.add_child(world)
	world._update_farm_plants()
	var edge:float=world._base_half_extents.x
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12
	camera.position=Vector3(edge+4,9,12);camera.look_at(Vector3(edge+4,0,-2.8));camera.current=true
	for i in range(16):await process_frame
	root.scaling_3d_scale=1.0;root.msaa_3d=Viewport.MSAA_4X
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/farm-sprites-camp.png")
	print("CAMP SPRITES SAVED");quit()
