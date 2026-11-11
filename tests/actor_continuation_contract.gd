extends SceneTree
const State=preload("res://logic/net/actor_continuation.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var combat=preload("res://logic/combat_data_loader.gd").load_default()
 var sim=preload("res://logic/game_sim.gd").new(preload("res://logic/sim_world.gd").new(),combat,RandomNumberGenerator.new())
 sim.add_player(1,Vector3.ZERO)
 sim.fighters[1].stats={"HP":100.0,"ATK":20.0,"MOVESPD":4.0}
 var frame=preload("res://logic/sim_input.gd").new();frame.move=Vector2.RIGHT
 for i in 10:sim.set_input(1,frame);sim.tick(1)
 var original:=State.capture(sim,1)
 if original.is_empty():
  for key in State.Codec.fields(sim.fighters[1],State.EXCLUDED):
   var v=sim.fighters[1].get(key)
   if not State._value_safe(v):print("UNSAFE FIELD ",key," ",type_string(typeof(v))," ",v)
  quit(1);return
 var saved:Dictionary=State.inspect(original,1)
 sim.fighters[1].stats.HP=2.0;sim.bodies[1].position=Vector3(5,0,0)
 assert(saved.fighter.stats.HP==100.0) # no cross-tick Dictionary aliasing
 assert(State.restore(sim,1,original))
 assert(State.capture(sim,1)==original)
 # Same exact continuation + same input -> identical production movement/combat state.
 sim.set_input(1,frame);sim.tick(1);var result:=State.capture(sim,1)
 assert(State.restore(sim,1,original));sim.set_input(1,frame);sim.tick(1)
 assert(State.capture(sim,1)==result)
 var before:=State.capture(sim,1)
 var bad:Dictionary=bytes_to_var(before);bad.body.position=Vector3(INF,0,0)
 assert(not State.restore(sim,1,var_to_bytes(bad)) and State.capture(sim,1)==before)
 bad=bytes_to_var(before);bad.fighter.erase("move_frame")
 assert(not State.restore(sim,1,var_to_bytes(bad)) and State.capture(sim,1)==before)
 bad=bytes_to_var(before);bad.fighter.hit_ids=["wrong_type"]
 assert(not State.restore(sim,1,var_to_bytes(bad)) and State.capture(sim,1)==before)
 bad=bytes_to_var(before);bad.actor=2
 assert(not State.restore(sim,1,var_to_bytes(bad)))
 assert(not State.restore(sim,1,PackedByteArray()))
 print("ACTOR CONTINUATION PASS: immutable value history, exact roundtrip, production tick replay parity, invalid/nonfinite/wrongactor rejected before mutation. Skill-runtime parity is separate and OPEN.")
 quit()
