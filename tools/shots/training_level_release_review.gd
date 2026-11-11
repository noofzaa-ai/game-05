extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var state=root.get_node("GameState");state.ensure_profile();state.profile.created=true;state.local_perf_test=true
 var hub=load("res://scenes/hub.tscn").instantiate();root.add_child(hub);current_scene=hub
 for i in range(5):await process_frame
 for level in [1,2,3,1,2]:
  state.profile.camp_level=level;hub.refresh_character()
  print("LEVEL BOUNDS ",level," ",hub.world.half_extents," ",hub._sim.world.half_width)
  assert(hub.world.half_extents.x>=25.5 and hub._sim.world.half_width>=25.5)
  assert(is_instance_valid(hub.world._farm_extension)==(level>=2))
  hub.place_player(Vector3(-10,0,5.8))
  for i in range(100):
   var input=load("res://logic/sim_input.gd").new();input.move=Vector2(-1,0);hub._training.step(input)
   if hub.player_position().x< -13:break
  assert(hub.player_position().x< -12.5)
  assert(hub.find_child("col_firewood",true,false)==null)
 print("TRAINING LEVEL REFRESH PASS: Lv1/2/3 + downgrade/reupgrade, farm gate, west path, firewood removal")
 quit()
