extends SceneTree
class PathStub:
	extends "res://logic/companions/navigation.gd"
	func direction(_world,_at: Vector3,_goal: Vector3) -> Vector2:return Vector2.RIGHT
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var Resident=load("res://client/companions/camp_adventurer.gd")
	var npc = Resident.new();npc.navigation=PathStub.new();npc.hub={"_sim":{"world":null}}
	npc.body.position=Vector3.ZERO;npc.rest_rng.seed=81
	for n in 60*45:
		var frame=npc._camp_frame(false,false)
		assert(frame.move==Vector2.ZERO and not frame.run)
	npc.rest_ticks=0
	for n in Resident.MOVE_TICKS:
		var frame=npc._camp_frame(false,false)
		assert(is_equal_approx(frame.move.length(),.35) and not frame.run)
	assert(npc.move_ticks==0 and npc.rest_ticks>=Resident.REST_MIN_TICKS and npc.rest_ticks<=Resident.REST_MAX_TICKS)
	assert(npc._camp_frame(false,false).move==Vector2.ZERO)
	npc.rest_ticks=0;npc.move_ticks=10
	assert(npc._camp_frame(true,false).move==Vector2.ZERO and npc.move_ticks==10)
	assert(npc._camp_frame(false,true).move==Vector2.ZERO and npc.move_ticks==10)
	npc.body.position=Vector3(-3,0,-17)
	assert(npc._camp_frame(false,false).move==Vector2.ZERO and npc.rest_ticks>=Resident.REST_MIN_TICKS)
	npc.free();print("CAMP IDLE PASS: long rests,2s slow walk only,no running,pause near people/menu,rest after waypoint")
	quit()
