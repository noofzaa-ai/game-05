extends SceneTree
## API compatibility gate only. Uses production GameSim; no performance assertions.
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var time=root.get_node("NetworkTime")
 assert(time.tickrate==60)
 assert(load("res://addons/netfox/rollback/rollback-synchronizer.gd").can_instantiate())
 assert(load("res://addons/netfox/state-synchronizer.gd").can_instantiate())
 assert(load("res://addons/netfox/tick-interpolator.gd").can_instantiate())
 var world=preload("res://logic/sim_world.gd").new()
 var rng=RandomNumberGenerator.new();rng.seed=28
 var sim=preload("res://logic/game_sim.gd").new(world,preload("res://logic/combat_data_loader.gd").load_default(),rng)
 sim.add_player(1,Vector3.ZERO)
 var frame=preload("res://logic/sim_input.gd").new();frame.move=Vector2.RIGHT
 var stepped:=[0]
 time.on_tick.connect(func(dt:float,_tick:int):
  assert(is_equal_approx(dt,1.0/60.0))
  sim.set_input(1,frame);sim.tick(1);stepped[0]+=1
 )
 var bridge_sim=preload("res://logic/game_sim.gd").new(preload("res://logic/sim_world.gd").new(),preload("res://logic/combat_data_loader.gd").load_default(),RandomNumberGenerator.new())
 bridge_sim.add_player(1,Vector3.ZERO)
 var bridge=load("res://actor_bridge.gd").new();bridge.name="ActualActor"
 bridge.configure(bridge_sim,1,1);bridge.get_node("Input").payload=frame.encode()
 root.add_child(bridge)
 var result:int=await time.start()
 assert(result==OK)
 for i in 240:
  await process_frame
  if stepped[0]>=12 and bridge.rollback_calls>=12:break
  await create_timer(.002).timeout
 assert(stepped[0]>=12 and sim.bodies[1].position.x>0)
 assert(bridge.rollback_calls>=12 and bridge_sim.bodies[1].position.x>0)
 time.stop()
 print("NETFOX GAME API PASS: Godot runtime loads library;60Hz NetworkTime drives actual production GameSim; RollbackSynchronizer drives actual actor bridge. NOT a multiplayer/prediction/latency acceptance.")
 quit()
