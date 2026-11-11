extends SceneTree
## Native scenery review, static figures, no progression/profile writes.
func _initialize() -> void:
	root.size=Vector2i(1600,1000);DisplayServer.window_set_size(root.size)
	await process_frame
	root.scaling_3d_scale=1.0
	var ids=OS.get_cmdline_user_args()
	if ids.is_empty():ids=PackedStringArray(["mummy_arena_a","mummy_arena_b","mummy_arena_c"])
	for id in ids:await capture_map(id)
	quit()

func capture_map(id: String) -> void:
	var scene=Node3D.new();root.add_child(scene)
	var atmosphere=preload("res://client/atmosphere.gd").new();atmosphere.style="ink";scene.add_child(atmosphere)
	var map=preload("res://logic/map_loader.gd").load_by_id(id)
	if not map.errors.is_empty():push_error(str(map.errors));quit(1);return
	preload("res://client/stage_props.gd").build(scene,map.props,false)
	var hero=preload("res://client/character_model.gd").new();scene.add_child(hero);hero.load_model();hero.position=map.spawn
	var rules=preload("res://logic/item_rules_loader.gd").load_default()
	var camp=preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var rng=RandomNumberGenerator.new();rng.seed=1
	var profile=preload("res://logic/profile.gd").new_player(rules,camp,rng)
	var looks=preload("res://client/item_assets.gd").looks(profile.loadout,rules.catalog,"")
	looks["appearance"]=preload("res://client/item_assets.gd").appearance(profile.appearance)
	hero.dress(looks);hero.set_pose("idle",0,0,true,Vector2(0,-1),false)
	for spawn in map.enemy_spawns:
		var mummy=load("res://art/monsters/mummy/mummy.glb").instantiate();scene.add_child(mummy);mummy.position=spawn.position
	var camera=Camera3D.new();scene.add_child(camera);camera.current=true
	var directory="res://art_source/preview/mummy_tomb";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for view in ["overview","gameplay","sanctuary"]:
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL if view=="overview" else Camera3D.PROJECTION_PERSPECTIVE
		camera.size=42;camera.fov=55
		if view=="overview":
			if id=="mummy_arena_a":camera.size=64;camera.position=Vector3(29,32,42);camera.look_at(Vector3(0,5,-15))
			else:camera.position=Vector3(23,29,30);camera.look_at(Vector3(0,1,-2))
		elif view=="gameplay":
			hero.position=Vector3(0,.05,0);camera.position=Vector3(0,7,7);camera.look_at(Vector3(0,.5,0))
		else:
			hero.position=Vector3(0,.05,-7);camera.position=Vector3(0,6,3);camera.look_at(Vector3(0,2,-12))
			if id=="mummy_arena_c":hero.position=Vector3(0,.05,-2.8);camera.position=Vector3(0,6.5,5.5);camera.look_at(Vector3(0,2.2,-9))
		for i in 30:
			hero.apply_pose(1.0/30.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var image=root.get_texture().get_image();image.save_png(directory+"/"+id+"_"+view+".png")
		if id=="mummy_arena_a":image.save_png(directory+"/"+view+".png")
		print("MUMMY_STAGE_PREVIEW ",id," ",view)
	scene.queue_free();await process_frame
