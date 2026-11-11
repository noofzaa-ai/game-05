extends SceneTree
const Brain := preload("res://logic/companions/brain.gd")
const Fighter := preload("res://logic/fighter.gd")
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var manager=preload("res://server/rooms/manager.gd").new()
	var p=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,RandomNumberGenerator.new())
	assert(manager.create("companion-priority-test",81,[{"id":1,"profile":p.to_dict()},{"id":2,"profile":p.to_dict()}],true,2).ok)
	var sim=manager.rooms["companion-priority-test"].room.sim
	sim.world.half_width=40;sim.world.half_depth=40
	sim.world.solids.clear();sim.world.add_solid(AABB(Vector3(-40,-1,-40),Vector3(80,1,80)))
	sim.bodies[1].position=Vector3.ZERO;sim.bodies[2].position=Vector3(9,0,0);sim.bodies[2].grounded=true
	var brain := Brain.new()
	sim.add_enemy(100,Vector3(10,0,0),"goblin")
	var frame=brain.think(sim,2)
	assert(brain.decision=="fight" and frame.aim.x>0,"must engage nearby monster rather than run back at old7m threshold")
	sim.bodies[2].position=Vector3(16,0,0)
	frame=brain.think(sim,2);assert(brain.decision=="follow" and frame.move.x<0,"still regroup when separated")
	sim.remove_player(100)
	sim.bodies[2].position=Vector3(2.5,0,0)
	frame=brain.think(sim,2);assert(brain.decision=="idle" and frame.move==Vector2.ZERO)
	sim.bodies[2].position=Vector3(3.9,0,0)
	frame=brain.think(sim,2);assert(brain.decision=="idle" and frame.move==Vector2.ZERO,"do not cling when leader moves slightly")
	sim.bodies[2].position=Vector3(4.1,0,0)
	frame=brain.think(sim,2);assert(brain.decision=="follow" and frame.move.x<0)
	sim.bodies[2].position=Vector3(3,0,0)
	frame=brain.think(sim,2);assert(brain.decision=="follow" and frame.move.x<0,"hysteresis prevents boundary oscillation")
	sim.bodies[2].position=Vector3(2.7,0,0)
	frame=brain.think(sim,2);assert(brain.decision=="idle" and frame.move==Vector2.ZERO)
	sim.fighters[1].state=Fighter.State.DOWNED
	frame=brain.think(sim,2);assert(brain.decision=="revive","revive priority retained")
	print("COMPANION PRIORITY PASS: nearby combat over follow, long-distance regroup, follow hysteresis, revive priority")
	quit()
