extends SceneTree
const InputFrame=preload("res://logic/sim_input.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var manager=preload("res://server/rooms/manager.gd").new()
 var rng=RandomNumberGenerator.new();rng.seed=24
 var p=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
 assert(manager.create("heldtest12345",24,[{"id":1,"profile":p.to_dict()}],true,1).ok)
 var room=manager.rooms["heldtest12345"].room
 room.sim.world.solids.clear();room.sim.bodies[1].position=Vector3.ZERO
 var input=InputFrame.new();input.move=Vector2.RIGHT;input.run=true;input.light=true;input.skill_slot=3;input.dodge=true;input.jump=true
 assert(room.input(1,1,input.encode()));room.tick()
 var before:float=room.sim.bodies[1].position.x
 for i in range(24):room.tick()
 assert(room.sim.bodies[1].position.x>before and room.acknowledged[1]==1 and room.input_repeated[1]==24)
 var held=InputFrame.decode(room.held_inputs[1])
 assert(held.move==input.move and held.run and not held.light and not held.dodge and not held.jump and held.skill_slot==-1)
 var stopped:float=room.sim.bodies[1].position.x
 room.tick();assert(is_equal_approx(room.sim.bodies[1].position.x,stopped))
 assert(not room.input(1,2,input.encode()))
 assert(room.input_audit[1].back().kind=="late_unapplied")
 assert(not room.input(1,room.clock_tick+25,input.encode()) and room.input_audit[1].back().kind=="too_far_future")
 var fresh=InputFrame.new();fresh.move=Vector2.LEFT
 assert(room.input(1,room.clock_tick+1,fresh.encode()));room.tick()
 assert(room.acknowledged[1]==room.clock_tick)
 room.presence(1,false);assert(not room.held_inputs.has(1))
 print("HELD INPUT GAP PASS:24bounded held repeats,ACKnotfabricated,no action/skill repeats,neutral afterlimit,late/future trace,disconnect clears")
 quit()
