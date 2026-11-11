extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var manager=preload("res://server/rooms/manager.gd").new()
 var rng=RandomNumberGenerator.new();rng.seed=42
 var profile=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
 for map_id in ["practice_field","goblin_arena_a"]:
  var result=manager.create("practicecontract"+map_id.replace("_","-"),42,[{"id":1,"profile":profile.to_dict()}],false,1,map_id)
  assert(result.ok,str(result))
  var room=manager.rooms["practicecontract"+map_id.replace("_","-")].room
  if map_id=="practice_field":
   var initial:Vector3=room.sim.bodies[1].position
   for tick in range(1,121):
    var frame=preload("res://logic/sim_input.gd").new();frame.move=Vector2.RIGHT
    assert(room.input(1,tick,frame.encode()))
    room.tick()
   assert(room.status=="active" and room.clock_tick==120)
   assert(room.sim.bodies[1].position.distance_to(initial)>1)
   assert(not room.journey.is_over() and not room.cloud_saved)
   room.sim.fighters[1].hp=0;room.tick()
   assert(room.status=="finished")
  else:
   room.sim._waves.clear()
   for id in room.sim.fighters:
    if room.sim.fighters[id].team=="enemy":room.sim.fighters[id].state=preload("res://logic/fighter.gd").State.DEAD;room.sim.fighters[id].hp=0
   room.tick()
   print("COMBAT CLEAR ",room.status," journey=",room.journey.state," living=",room.sim.living_enemy_count()," waves=",room.sim.pending_wave_count())
   assert(room.status in ["finished","route"] and room.journey.state!=preload("res://logic/journey.gd").IN_STAGE)
 print("PRACTICE ROOM LIFECYCLE PASS: empty practice keeps moving; death and cleared combat still finish")
 quit()
