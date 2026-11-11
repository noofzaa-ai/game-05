extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new();root.get_node("GameState").profile=source.profile
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1000,600)
 var world=load("res://client/hub_world.gd").new();root.add_child(world)
 assert(world.loaded and is_instance_valid(world._farm_boundary_trees))
 world.environment.ambient_light_energy=1.0
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-65,-20,0);light.light_energy=1.4;root.add_child(light)
 var camera:=Camera3D.new();root.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=22
 camera.position=Vector3(14,30,16);camera.look_at(Vector3(12,0,-2.8));camera.current=true
 for level in [1,2]:
  source.profile.camp_level=level;world.refresh_facilities()
  assert(world._farm_boundary_trees.visible==(level==1))
  for i in range(8):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/farm-clearance-lv%d.png"%level)
 assert(is_equal_approx(world.farm_plot_position(0).z,-6.2) and is_equal_approx(world.farm_plot_position(2).z,-.4))
 print("FARM CLEARANCE PASS: same scene preserves Lv1 trees; Lv2 hides complete pine group and shows4 plots")
 quit()
