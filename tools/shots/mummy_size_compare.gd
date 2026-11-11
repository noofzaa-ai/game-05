extends SceneTree
## Native comparison only: real CharacterModel scale versus player-matched Mummy scale.
func _initialize() -> void:
	root.size=Vector2i(1280,800)
	DisplayServer.window_set_size(root.size)
	await process_frame
	var scene=Node3D.new();root.add_child(scene)
	var environment=WorldEnvironment.new();scene.add_child(environment)
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("18212b")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=0.65
	var light=DirectionalLight3D.new();scene.add_child(light);light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=1.5
	var hero=preload("res://client/character_model.gd").new();scene.add_child(hero);hero.load_model();hero.position.x=-0.7
	var rules=preload("res://logic/item_rules_loader.gd").load_default()
	var camp=preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var rng=RandomNumberGenerator.new();rng.seed=1
	var profile=preload("res://logic/profile.gd").new_player(rules,camp,rng)
	var looks=preload("res://client/item_assets.gd").looks(profile.loadout,rules.catalog,"")
	looks["appearance"]=preload("res://client/item_assets.gd").appearance(profile.appearance)
	hero.dress(looks);hero.set_pose("idle",0,0,true,Vector2(0,1),false)
	var mummy=load("res://art/monsters/mummy/mummy.glb").instantiate();scene.add_child(mummy);mummy.position.x=0.7
	var ground=MeshInstance3D.new();scene.add_child(ground);ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(4,2)
	var material=StandardMaterial3D.new();material.albedo_color=Color("2b3945");ground.material_override=material;ground.position.y=-0.005
	var camera=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.1;camera.position=Vector3(0,1.0,7);camera.look_at(Vector3(0,1.0,0))
	for info in [[-0.7,"PLAYER · 1.80 m"],[0.7,"MUMMY · 1.80 m (100%)"]]:
		var label=Label3D.new();scene.add_child(label);label.text=info[1];label.font_size=42;label.pixel_size=0.0017;label.position=Vector3(info[0],-0.16,0.1)
	for i in 20:
		hero.apply_pose(1.0/30.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_source/monsters/mummy/review/size_compare.png")
	print("MUMMY_COMPARISON hero scale=",hero.model_scale()," hero display height=",hero.model_height())
	quit()
