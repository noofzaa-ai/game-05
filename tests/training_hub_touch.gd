extends SceneTree
const Inputs=preload("res://logic/sim_input.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var state=root.get_node("GameState");state.ensure_profile();state.profile.created=true;state.local_perf_test=true
 var rng:=RandomNumberGenerator.new();rng.seed=42
 state.profile.loadout.equip(load("res://logic/item_system.gd").create_item(state.item_rules,"training-review-blade","weapon",1,rng,"blade","blade_01"))
 state.profile.skill_build=load("res://logic/skill_build.gd").initial("blade")
 var before:Dictionary=state.profile.to_dict().duplicate(true)
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(844,390)
 var hub=load("res://scenes/hub.tscn").instantiate();root.add_child(hub);current_scene=hub
 state.mobile_controls.force_mobile=true
 for i in range(20):await process_frame
 # Actual west entrance must be walkable through the unchanged camp colliders.
 hub.place_player(Vector3(-10,0,5.8))
 for i in range(120):
  var input=Inputs.new();input.move=Vector2(-1,0);hub._training.step(input)
  if hub.player_position().x< -13:break
 assert(hub.player_position().x< -12.5,"West path must be open to walking")
 hub.place_player(Vector3(-18,0,3))
 for i in range(8):await process_frame
 assert(hub.training_combat_active() and state.mobile_controls._combat)
 assert(not hub._touch.enabled and not hub._shortcut_root.visible)
 var button=hub._training_view._hud._buttons[0]
 assert(button.get_global_rect().end.x<=844 and button.get_global_rect().end.y<=390)
 button.pressed.emit()
 for i in range(100):await physics_frame
 assert(hub._training.hits>0,"Mobile skill button must cast through normal input")
 assert(hub._training.hits_by_target.size()>=3)
 assert(state.profile.to_dict()==before,"Training must preserve actual profile, wallet, wear, build, owned gear")
 hub._training.reset()
 assert(hub._training.hits==0)
 hub.place_player(Vector3(-10,0,5.8))
 for i in range(8):await process_frame
 assert(not hub.training_combat_active() and not state.mobile_controls._combat)
 assert(hub._touch.enabled and hub._shortcut_root.visible)
 assert(not hub._training_view.player.visible and not hub._training_view._hud.visible)
 assert(state.profile.to_dict()==before)
 print("TRAINING HUB TOUCH PASS: real west path, automatic mobile combat, equipped skill button AoE3targets, profile/wear/currency invariant, reset, exit restores camp controls")
 hub.queue_free();await process_frame;current_scene=null
 quit()
