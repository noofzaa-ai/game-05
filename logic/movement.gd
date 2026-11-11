extends RefCounted
## Walking, jumping, gravity and collision against the stage's solid boxes.
## Deterministic fixed-step math, no engine physics: the same code can run on the server and on a
## client (for prediction), and tests can run it without a window.
## EXTENDING: tune the constants here (they will move to character/item data later); new movement
## rules (dash, knockback) become new static functions called from `step`.

const SimBody := preload("res://logic/sim_body.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const TICK_DT := 1.0 / 60.0
const SPEED := 3.8  ## walking speed in units per second
const RUN_MULTIPLIER := 1.75  ## running is this much faster than walking
const JUMP_VELOCITY := 7.5
const GRAVITY := 20.0
const EPSILON := 0.0001
const KNOCKBACK_FRICTION := 0.88  ## each tick a push keeps this fraction of its speed


static func step(id: int, body: SimBody, input: SimInput, world: SimWorld, events: Array[Dictionary], dt: float = TICK_DT) -> void:
	var was_grounded := body.grounded
	var move := input.move.limit_length(1.0)
	var speed := SPEED * body.move_speed_multiplier * (RUN_MULTIPLIER if input.run else 1.0)
	body.velocity.x = move.x * speed + body.knockback.x
	body.velocity.z = move.y * speed + body.knockback.y

	if body.grounded and input.jump:
		body.velocity.y = JUMP_VELOCITY
		events.append({"type": "jumped", "player": id})
	body.velocity.y -= GRAVITY * dt

	_move_axis(body, world, 0, body.velocity.x * dt)
	_move_axis(body, world, 2, body.velocity.z * dt)
	body.grounded = false
	_move_axis(body, world, 1, body.velocity.y * dt)

	body.position.x = clampf(body.position.x, -world.half_width, world.half_width)
	body.position.z = clampf(body.position.z, -world.half_depth, world.half_depth)

	body.knockback *= KNOCKBACK_FRICTION
	if body.knockback.length() < 0.05:
		body.knockback = Vector2.ZERO

	if body.grounded and not was_grounded:
		events.append({"type": "landed", "player": id})


static func _overlaps(a: AABB, b: AABB) -> bool:
	return (
		a.position.x < b.end.x - EPSILON and a.end.x > b.position.x + EPSILON
		and a.position.y < b.end.y - EPSILON and a.end.y > b.position.y + EPSILON
		and a.position.z < b.end.z - EPSILON and a.end.z > b.position.z + EPSILON
	)


## Moves the body along one axis, then pushes it out of any solid it ran into.
static func _move_axis(body: SimBody, world: SimWorld, axis: int, amount: float) -> void:
	if amount == 0.0:
		return
	body.position[axis] += amount
	var reach := body.extent(axis)
	for solid in world.solids:
		if not _overlaps(body.aabb(), solid):
			continue
		if amount > 0.0:
			body.position[axis] = solid.position[axis] - reach.y
		else:
			body.position[axis] = solid.end[axis] - reach.x
			if axis == 1:
				body.grounded = true
		body.velocity[axis] = 0.0
