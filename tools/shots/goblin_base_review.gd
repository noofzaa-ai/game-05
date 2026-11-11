extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1440,810)
 var stage=Node3D.new();root.add_child(stage)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("1d2c31");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("a4b8c1");env.environment.ambient_light_energy=.85;stage.add_child(env)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-25,0);light.light_energy=1.1;stage.add_child(light)
 var model=load("res://art/maps/goblin_base/goblin_base_gate.tscn").instantiate();stage.add_child(model)
 var camera=Camera3D.new();stage.add_child(camera);camera.position=Vector3(22,26,34);camera.look_at(Vector3.ZERO);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=38;camera.current=true
 for i in range(12):await process_frame
 root.scaling_3d_scale=1;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/goblin-base-overview.png")
 stage.free()
 var ui=load("res://client/world_map_screen.gd").new();root.add_child(ui)
 for size in [Vector2i(1440,810),Vector2i(844,390)]:
  root.size=size
  for i in range(8):await process_frame
  root.scaling_3d_scale=1;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/goblin-world-map-%d.png"%size.x)
 ui.free();print("GOBLIN NATIVE CAPTURES PASS");quit()
