extends SceneTree
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1600,850);root.content_scale_size=Vector2i.ZERO
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("273b43");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.9;root.add_child(env)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-25,0);root.add_child(light)
 var doc=ClassDB.instantiate("FBXDocument");var state=ClassDB.instantiate("FBXState");assert(doc.append_from_file(ProjectSettings.globalize_path("res://../../assets/gobbin_base.fbx").simplify_path(),state)==OK);root.add_child(doc.generate_scene(state))
 var cam=Camera3D.new();root.add_child(cam);cam.position=Vector3(0,.32,3);cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=.8;cam.current=true
 for i in range(8):await process_frame
 root.scaling_3d_scale=1;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://art_source/props/goblin_base/gobbin_base-direct.png");quit()
