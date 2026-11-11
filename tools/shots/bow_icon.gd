extends SceneTree
func _initialize():call_deferred("capture")
func capture():
 var vp:=SubViewport.new();vp.size=Vector2i(128,128);vp.transparent_bg=true;vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_CLEAR_COLOR;env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;vp.add_child(env)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=1.1;vp.add_child(light)
 var bow=load("res://art/items/weapons/bow.glb").instantiate();bow.rotation.z=-.35;vp.add_child(bow)
 var camera:=Camera3D.new();vp.add_child(camera);camera.position=Vector3(2,0,.4);camera.look_at(Vector3.ZERO);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.2;camera.current=true
 for i in 12:await process_frame
 await RenderingServer.frame_post_draw
 var image=vp.get_texture().get_image()
 image.save_png("res://art/items/icons/weapon_bow_jade_01.png")
 print("BOW ICON ",image.get_size()," alpha ",image.get_pixel(0,0).a)
 quit()
