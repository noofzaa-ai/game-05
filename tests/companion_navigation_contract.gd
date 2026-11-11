extends SceneTree
func _initialize() -> void:
	var world := preload("res://logic/sim_world.gd").new()
	world.half_width = 10; world.half_depth = 10
	world.add_solid(AABB(Vector3(-10,-1,-10),Vector3(20,1,20)))
	world.add_solid(AABB(Vector3(-0.5,0,-3),Vector3(1,3,6)))
	var navigation := preload("res://logic/companions/navigation.gd").new()
	var body := preload("res://logic/sim_body.gd").new()
	body.position = Vector3(-4,0,0); body.grounded = true
	var goal := Vector3(4,0,0)
	assert(not navigation.line_clear(world, body.position, goal))
	var moved_around := false
	for tick in 1000:
		var frame := preload("res://logic/sim_input.gd").new()
		frame.move = navigation.direction(world,body.position,goal)
		var events: Array[Dictionary] = []
		preload("res://logic/movement.gd").step(4,body,frame,world,events)
		if absf(body.position.z) > 3.0: moved_around = true
		assert(not body.aabb().intersects(world.solids[1]), "must keep actual capsule clearance")
		if body.position.distance_to(goal) < 0.35: break
	assert(moved_around and body.position.distance_to(goal) < 0.35)
	var hole := preload("res://logic/sim_world.gd").new()
	hole.half_width=10;hole.half_depth=10
	hole.add_solid(AABB(Vector3(-10,-1,-10),Vector3(10,1,20)))
	var route := preload("res://logic/companions/navigation.gd").new()
	body.position=Vector3(-4,0,0)
	for tick in 200:
		var frame := preload("res://logic/sim_input.gd").new()
		frame.move=route.direction(hole,body.position,Vector3(4,0,0))
		var events: Array[Dictionary]=[]
		preload("res://logic/movement.gd").step(4,body,frame,hole,events)
		assert(body.position.x <= -0.43 and body.position.y >= -0.01)
	print("COMPANION NAVIGATION PASS: full-body wall detour, no unsupported floor traversal")
	quit()
