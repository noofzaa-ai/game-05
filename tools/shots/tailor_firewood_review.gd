extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var state=root.get_node("GameState");state.ensure_profile();state.profile.created=true;state.local_perf_test=true
 var hub=load("res://scenes/hub.tscn").instantiate();root.add_child(hub);current_scene=hub
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
 for i in range(15):await process_frame
 assert(hub.find_child("col_firewood",true,false)==null)
 hub.place_player(Vector3(-3.2,0,-1.25))
 for i in range(90):
  var frame=load("res://logic/sim_input.gd").new();frame.move=Vector2(-1,0);hub._training.step(frame)
 assert(hub.player_position().x< -5.2,"Must walk through the former firewood collider")
 print("TAILOR FIREWOOD PASS: removed collider; actual player walked across former pile: ",hub.player_position())
 if not DisplayServer.get_name()=="headless":
  var camera=hub.get_viewport().get_camera_3d();camera.get_parent().set_process(false);camera.get_parent().set_physics_process(false)
  camera.global_position=Vector3(-2,10,7);camera.look_at(Vector3(-5,0,-3));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12
  await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/tailor-firewood-removed.png")
 quit()
