extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 root.size=Vector2i(1000,700)
 var asset:Node3D=load("res://art/props/modular_wall/modular_wall.glb").instantiate();root.add_child(asset)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.light_energy=1.5;root.add_child(light)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("384651");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;root.add_child(env)
 var cam:=Camera3D.new();root.add_child(cam);cam.position=Vector3(2,2,4);cam.look_at(Vector3(0,.6,0));cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=3;cam.current=true
 for i in range(5):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/modular-wall-source.png");quit()
