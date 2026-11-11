extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var state=root.get_node("GameState");state.ensure_profile();state.profile.created=true;state.local_perf_test=true
 var rng:=RandomNumberGenerator.new();rng.seed=42
 var weapon=load("res://logic/item_system.gd").create_item(state.item_rules,"training-review-blade","weapon",1,rng,"blade","blade_01")
 state.profile.loadout.equip(weapon);state.profile.skill_build=load("res://logic/skill_build.gd").initial("blade")
 var hub=load("res://scenes/hub.tscn").instantiate();root.add_child(hub);current_scene=hub
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1440,810)
 for i in range(15):await process_frame
 hub.place_player(Vector3(-18,0,5));hub._facing=Vector2(0,-1)
 for i in range(60):await process_frame
 var camera=hub._rig.get_viewport().get_camera_3d()
 print("TRAINING HUB active ",hub._training.enabled," player ",hub.player_position())
 for size in [Vector2i(1440,810),Vector2i(844,390)]:
  root.size=size
  if size.x==844:state.mobile_controls.force_mobile=true
  for i in range(12):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/training-hub-%d.png"%size.x)
 hub.place_player(Vector3(-18,0,3));await process_frame
 var frame=load("res://logic/sim_input.gd").new();frame.aim=Vector2(0,-1);frame.aim_distance=2;frame.skill_slot=0
 hub._training.step(frame)
 for i in range(40):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/training-aoe-844.png")
 print("TRAINING HUB NATIVE CAPTURE COMPLETE")
 quit()
