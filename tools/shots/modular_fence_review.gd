extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new();source.profile.camp_level=2
 var state=root.get_node("GameState");state.ensure_profile();source.profile.created=true;state.profile=source.profile;state.local_perf_test=true
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
 var hub=load("res://scenes/hub.tscn").instantiate();root.add_child(hub);current_scene=hub
 for i in range(10):await process_frame
 var fence=preload("res://client/modular_fence.gd")
 assert(hub.world.find_child("CampVegetableFarm",true,false).find_child("ModularFence",true,false)!=null)
 var edge:float=hub.world._base_half_extents.x
 # Entrance centres must stay clear even with a character-radius margin.
 for entry in [Vector3(-11,0,5.8),Vector3(edge-.2,0,-3.3)]:
  for box in hub.world.solids+hub.world.farm_boundaries():
   assert(not box.grow(.35).has_point(entry+Vector3(0,.1,0)),"Fence blocks entrance")
 hub.place_player(Vector3(-10,0,5.8))
 for i in range(80):
  var input=load("res://logic/sim_input.gd").new();input.move=Vector2(-1,0);hub._training.step(input)
 assert(hub.player_position().x< -12.5,"Actual player must pass through training entrance")
 hub.place_player(Vector3(edge-.9,0,-3.3))
 for i in range(60):
  var input=load("res://logic/sim_input.gd").new();input.move=Vector2(1,0);hub._training.step(input)
 assert(hub.player_position().x>edge+.7,"Actual player must pass through farm entrance")
 print("MODULAR FENCE PASS: both entrances open, actual walking across training/farm, level2 fence present")
 if DisplayServer.get_name()!="headless":
  var camera=hub.get_viewport().get_camera_3d();camera.get_parent().set_process(false);camera.get_parent().set_physics_process(false)
  camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20
  camera.global_position=Vector3(-7,17,18);camera.look_at(Vector3(-18,0,4.5))
  for i in range(3):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/modular-fence-training.png")
  camera.size=18;camera.global_position=Vector3(edge+15,17,10);camera.look_at(Vector3(edge+4,0,-3.3))
  for i in range(3):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/modular-fence-farm.png")
 print("MODULAR FENCE REVIEW COMPLETE")
 quit()
