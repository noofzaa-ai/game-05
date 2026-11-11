extends RefCounted
## Tests the simulation (logic/) with no window, no nodes and no real keyboard.

const GameSim := preload("res://logic/game_sim.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const Movement := preload("res://logic/movement.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")


func run(ctx) -> void:
	_test_falls_and_lands(ctx)
	_test_walk_speed(ctx)
	_test_blocked_by_wall(ctx)
	_test_jump_height(ctx)
	_test_bounds(ctx)
	_test_climbs_to_plateau(ctx)
	_test_reaches_floating_platform(ctx)
	_test_events(ctx)
	_test_determinism(ctx)
	_test_two_players_are_independent(ctx)


func _flat_world(half_width: float = 20.0) -> SimWorld:
	var world := SimWorld.new()
	world.half_width = half_width
	world.half_depth = 2.5
	world.add_solid(AABB(Vector3(-30.0, -0.4, -4.0), Vector3(60.0, 0.4, 8.0)))
	return world


func _map_world() -> Array:
	var map := MapLoader.load_by_id("sunward_valley")
	var world := SimWorld.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	return [world, map]


## The player spawns slightly above the floor; let it land (jumping needs ground under the feet).
func _settle(sim: GameSim) -> void:
	for i in 10:
		sim.tick()


func _input(move: Vector2, jump: bool = false) -> SimInput:
	var input := SimInput.new()
	input.move = move
	input.jump = jump
	return input


func _test_falls_and_lands(ctx) -> void:
	var sim := GameSim.new(_flat_world())
	var body = sim.add_player(1, Vector3(0, 3, 0))
	for i in 90:
		sim.tick()
	ctx.check("falling body lands on the floor", body.grounded and absf(body.position.y) < 0.001)


func _test_walk_speed(ctx) -> void:
	var sim := GameSim.new(_flat_world())
	var body = sim.add_player(1, Vector3(0, 0.05, 0))
	sim.set_input(1, _input(Vector2.RIGHT))
	for i in 60:
		sim.tick()
	ctx.check("walking right for 1 second moves the walking speed (%.2f)" % body.position.x, absf(body.position.x - Movement.SPEED) < 0.2)

	var runner := GameSim.new(_flat_world())
	var run_body = runner.add_player(1, Vector3(0, 0.05, 0))
	var run_input := _input(Vector2.RIGHT)
	run_input.run = true
	runner.set_input(1, run_input)
	for i in 60:
		runner.tick()
	ctx.check("running is 1.75x faster than walking (%.2f)" % run_body.position.x, absf(run_body.position.x - Movement.SPEED * Movement.RUN_MULTIPLIER) < 0.3)


func _test_blocked_by_wall(ctx) -> void:
	var data := _map_world()
	var sim := GameSim.new(data[0])
	var body = sim.add_player(1, data[1].spawn)
	sim.set_input(1, _input(Vector2.RIGHT))
	for i in 240:
		sim.tick()
	# first step starts at x = 3.0 and the body is 0.4 wide on each side
	ctx.check("walking into a step stops at the wall", body.position.x <= 2.61 and body.position.x > 2.5)


func _test_jump_height(ctx) -> void:
	var sim := GameSim.new(_flat_world())
	var body = sim.add_player(1, Vector3(0, 0.05, 0))
	_settle(sim)
	sim.set_input(1, _input(Vector2.ZERO, true))
	var highest := 0.0
	for i in 90:
		sim.tick()
		sim.set_input(1, _input(Vector2.ZERO, false))
		highest = maxf(highest, body.position.y)
	ctx.check("a jump reaches about 1.4 units (got %.2f)" % highest, highest > 1.3 and highest < 1.5)


func _test_bounds(ctx) -> void:
	var sim := GameSim.new(_flat_world(5.0))
	var body = sim.add_player(1, Vector3(0, 0.05, 0))
	sim.set_input(1, _input(Vector2(1, 1)))
	for i in 600:
		sim.tick()
	ctx.check("player cannot leave the stage width", body.position.x <= 5.0 + 0.0001)
	ctx.check("player cannot leave the lane depth", body.position.z <= 2.5 + 0.0001)


## Hops toward +x at reduced speed; used to prove the test stage's stairs can be climbed.
func _hop_right(sim: GameSim, ticks: int, move_x: float) -> void:
	for i in ticks:
		var body = sim.bodies[1]
		sim.set_input(1, _input(Vector2(move_x, 0.0), body.grounded))
		sim.tick()


func _test_climbs_to_plateau(ctx) -> void:
	var data := _map_world()
	var sim := GameSim.new(data[0])
	var body = sim.add_player(1, data[1].spawn)
	var best_height := 0.0
	for i in 900:
		var current = sim.bodies[1]
		sim.set_input(1, _input(Vector2(0.5, 0.0), current.grounded))
		sim.tick()
		best_height = maxf(best_height, body.position.y)
	ctx.check("stairs can be climbed to the plateau by jumping (best height %.2f)" % best_height, best_height > 1.75)


func _test_reaches_floating_platform(ctx) -> void:
	var data := _map_world()
	var sim := GameSim.new(data[0])
	var body = sim.add_player(1, Vector3(-9.0, 0.05, 0.0))
	var stood_on_platform := false
	for i in 600:
		var current = sim.bodies[1]
		sim.set_input(1, _input(Vector2(0.5, 0.0), current.grounded))
		sim.tick()
		if body.grounded and absf(body.position.y - 1.0) < 0.01:
			stood_on_platform = true
	ctx.check("the low floating platform can be reached by jumping", stood_on_platform)


func _test_events(ctx) -> void:
	var sim := GameSim.new(_flat_world())
	sim.add_player(1, Vector3(0, 0.05, 0))
	_settle(sim)
	sim.set_input(1, _input(Vector2.ZERO, true))
	sim.tick()
	var jumped := 0
	for event in sim.events:
		if event["type"] == "jumped":
			jumped += 1
	ctx.check("a jump produces exactly one 'jumped' event", jumped == 1)
	sim.set_input(1, _input(Vector2.ZERO, false))
	var landed := 0
	for i in 120:
		sim.tick()
		for event in sim.events:
			if event["type"] == "landed":
				landed += 1
	ctx.check("landing produces exactly one 'landed' event", landed == 1)


func _test_determinism(ctx) -> void:
	var a := GameSim.new(_flat_world())
	var b := GameSim.new(_flat_world())
	# Complete snapshots now include RNG: use identical initial conditions even in movement-only sims.
	b.rng.seed = a.rng.seed
	b.rng.state = a.rng.state
	a.add_player(1, Vector3(0, 0.05, 0))
	b.add_player(1, Vector3(0, 0.05, 0))
	for i in 300:
		var jump := i % 50 == 0
		var move := Vector2(sin(float(i) * 0.1), cos(float(i) * 0.07))
		a.set_input(1, _input(move, jump))
		b.set_input(1, _input(move, jump))
		a.tick()
		b.tick()
	ctx.check("same inputs give identical results", a.snapshot() == b.snapshot())


func _test_two_players_are_independent(ctx) -> void:
	var sim := GameSim.new(_flat_world())
	var first = sim.add_player(1, Vector3(-5, 0.05, 0))
	var second = sim.add_player(2, Vector3(5, 0.05, 0))
	sim.set_input(1, _input(Vector2.RIGHT))
	sim.set_input(2, _input(Vector2.ZERO))
	for i in 60:
		sim.tick()
	ctx.check("player 1 moved", first.position.x > -5.0 + Movement.SPEED * 0.8)
	ctx.check("player 2 stayed", absf(second.position.x - 5.0) < 0.001)
	ctx.check("snapshot lists both players", sim.snapshot()["players"].size() == 2)
