extends RefCounted
## A monster's brain. It produces a SimInput exactly like a player would, so monsters use the same
## movement and combat rules as players.
## Each monster type is data (combat.json): how far it attacks from, which attack it uses, how long
## it rests between attacks, where it waits when it is not its turn.
## It fights in the same eight directions as the player: it faces the player on the nearest of
## them and strikes along it (diagonal swings use the turned hit box in combat.gd).
## Monsters take turns: the simulation tells each one whether it may attack right now
## (`may_attack`); the rest circle at `wait_range` instead of crowding the player.
## A skittish monster (retreat_ticks > 0, the goblin) hops back from the player for a moment after each
## attack instead of standing there to trade blows, then comes back in when its rest is over.
## A cowardly one (flee_hp > 0) runs away once its health drops below that fraction, for flee_ticks,
## then comes back to fight (once per life).
## A ranged monster (keep_range > 0: archers, mages) keeps that distance instead: it backs away when
## the player comes within retreat_range, steps in when too far, drifts sideways (strafe) while
## holding, and shoots only with a clear line (no wall between). With an escape move (escape_input,
## the mage's blink) it jumps away when the player gets within escape_range, every escape_cooldown.
## EXTENDING: smarter behaviors (guard, call for help) are new branches in think().

const Combat := preload("res://logic/combat.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimBody := preload("res://logic/sim_body.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const HIT_LANE_TOLERANCE := 0.6  ## only attack when the target is at most this far off the striking line
const DIRECTION_KEEP_DEGREES := 32.0  ## keep striking along the same direction until the target is this far off it (22.5 = always the nearest)
const APPROACH_MARGIN := 0.2  ## a monster that needs a run-up stands this much farther than its minimum range
const ARRIVE_DISTANCE := 0.12  ## close enough to its striking spot to stop walking
const FACE_WHILE_STEPPING := 1.5  ## this close beyond its reach, it faces the player instead of the way it steps
const WAIT_BAND := 0.5  ## how far from wait_range a waiting monster may drift before correcting
const CIRCLE_SPEED := 0.45  ## how fast (fraction of walking speed) a waiting monster drifts around the player
const STUCK_CHECK_TICKS := 24  ## a monster that wants to move but gets this far in this many ticks counts as stuck
const STUCK_PROGRESS := 0.35  ## (world units)
const DETOUR_TICKS := 50  ## how long it walks around an obstacle before heading for the target again
const COMMIT_TICKS := 45  ## after a detour it does not step back toward where it came from for this long
const STREAK_WINDOW := 100  ## stuck again within this many ticks of a detour = a longer detour the same way

var attack_range := 1.3  ## it starts attacking when this close along its striking direction (it walks to 0.8 of it)
var attack_min_range := 0.0  ## and not closer than this (a charger needs a run-up)
var wait_range := 3.0  ## where it waits when it is not allowed to attack
var attack_input := "light"  ## which attack it uses: light, heavy or special
var cooldown_min := 50
var cooldown_max := 90
var cooldown := 30
var skill_chance := 0  ## percent: how often it uses its special skill (a buff or debuff) instead of its normal attack
var retreat_ticks := 0  ## after an attack ends (or is cut short) it backs away from the player this long
var flee_hp := 0.0  ## below this fraction of its health it runs away (0 = never)
var flee_ticks := 0  ## for this long
var keep_range := 0.0  ## ranged: the distance it holds from the player (0 = a melee fighter)
var retreat_range := 0.0  ## ranged: it backs away when the player is closer than this
var strafe := 0.0  ## ranged: how fast (fraction of walking) it drifts sideways while holding its distance
var escape_input := ""  ## ranged: the attack that gets it out of reach (a blink), or "" for none
var escape_range := 0.0
var escape_cooldown := 300
var world: SimWorld  ## the walls, for its line of sight (set by the simulation)
## Taunt (GDD races 3.2 Bulwark, 3.6 aggro/pulse_aggro): while taunt_left > 0 and that fighter is alive, it is the
## target instead of the nearest player. Set through taunt() (GameSim.taunt_enemy); saved in checkpoints.
var taunt_target := -1
var taunt_left := 0
var _escape_left := 0

var _phase := 0.0
var _axis := Vector2.ZERO  ## the direction (unit vector, one of eight) it currently strikes along
var _check_position := Vector3.ZERO  ## where it was STUCK_CHECK_TICKS ago
var _check_left := STUCK_CHECK_TICKS
var _detour_left := 0
var _detour_direction := Vector2.ZERO
var _detour_flip := 1.0  ## alternates, so it tries the other side the next time
var _commit_left := 0
var _streak := 0
var _since_detour := 1000
var _was_attacking := false
var _retreat_left := 0
var _flee_left := 0
var _fled := false


func think(fighter: Fighter, body: SimBody, bodies: Dictionary, fighters: Dictionary, rng: RandomNumberGenerator, may_attack: bool = true) -> SimInput:
	var input := _decide(fighter, body, bodies, fighters, rng, may_attack)
	return _steer_around_obstacles(input, body)


## Walking straight at a target can end against a rock or a wall: when a monster that is trying to move
## makes almost no progress, it walks sideways around the obstacle. If it is still stuck soon after, it
## keeps going the same way for longer (a wall can be wide); for a moment after a detour it does not
## step back toward where it came from, so it cannot just return to the same spot.
func _steer_around_obstacles(input: SimInput, body: SimBody) -> SimInput:
	if _detour_left > 0:
		_detour_left -= 1
		input.move = _detour_direction
		input.aim = Vector2.ZERO
		_check_left = STUCK_CHECK_TICKS
		_check_position = body.position
		if _detour_left == 0:
			_commit_left = COMMIT_TICKS
		return input
	_since_detour += 1
	if _commit_left > 0:
		_commit_left -= 1
		var back := input.move.dot(_detour_direction)
		if back < 0.0:
			input.move -= _detour_direction * back  # do not walk back the way it detoured
	if input.move.length() < 0.1:
		_check_left = STUCK_CHECK_TICKS
		_check_position = body.position
		return input
	_check_left -= 1
	if _check_left <= 0:
		var moved := Vector2(body.position.x - _check_position.x, body.position.z - _check_position.z).length()
		if moved < STUCK_PROGRESS:
			var heading := input.move.normalized()
			if _since_detour < STREAK_WINDOW and _detour_direction != Vector2.ZERO:
				_streak += 1  # still stuck soon after a detour: keep the same way, for longer
				if _streak >= 4:
					_detour_direction = -_detour_direction
					_streak = 0
			else:
				_streak = 0
				_detour_direction = Vector2(-heading.y, heading.x) * _detour_flip
				_detour_flip = -_detour_flip
			_detour_left = DETOUR_TICKS * (1 << mini(_streak, 3))
			_since_detour = 0
		_check_left = STUCK_CHECK_TICKS
		_check_position = body.position
	return input


## Taunts this monster onto fighter `by` for `ticks`. Overlapping taunts do not add up: the longer remaining
## one wins (GDD races 5). Not a control effect, so control immunity does not apply (works on the boss too).
func taunt(by: int, ticks: int) -> bool:
	if ticks <= 0 or (taunt_left > ticks and taunt_target != by):
		return false
	taunt_target = by
	taunt_left = maxi(taunt_left, ticks)
	return true


## The fighter this monster is forced to attack, or -1 (no taunt, it ran out, or the taunter is down or gone).
func taunted_by(fighter: Fighter, fighters: Dictionary) -> int:
	if taunt_left <= 0 or not fighters.has(taunt_target):
		return -1
	var other: Fighter = fighters[taunt_target]
	return taunt_target if other.team != fighter.team and other.is_alive() else -1


func _decide(fighter: Fighter, body: SimBody, bodies: Dictionary, fighters: Dictionary, rng: RandomNumberGenerator, may_attack: bool) -> SimInput:
	var input := SimInput.new()
	if taunt_left > 0:
		taunt_left -= 1
		if taunt_left == 0:
			taunt_target = -1
	if cooldown > 0:
		cooldown -= 1
	_phase += 0.03
	if fighter.state == Fighter.State.ATTACK:
		_was_attacking = true
	if fighter.state != Fighter.State.IDLE:
		return input
	if _was_attacking:
		_was_attacking = false
		_retreat_left = retreat_ticks

	var target_id := -1
	var nearest := INF
	for id in fighters:
		var other: Fighter = fighters[id]
		if other.team == fighter.team or not other.is_alive():
			continue
		var distance := body.position.distance_to(bodies[id].position)
		if distance < nearest:
			nearest = distance
			target_id = id
	var taunter := taunted_by(fighter, fighters)
	if taunter >= 0:
		target_id = taunter
	if target_id < 0:
		return input

	var offset: Vector3 = bodies[target_id].position - body.position
	if not _fled and flee_ticks > 0 and fighter.hp < fighter.max_hp() * flee_hp:
		_fled = true
		_flee_left = flee_ticks
	if _flee_left > 0:  # run away from the player (facing the way it runs)
		_flee_left -= 1
		var from := Vector2(offset.x, offset.z)
		input.move = -from.normalized() if from.length() > 0.001 else Vector2(-1.0, 0.0)
		input.run = true
		return input
	if _retreat_left > 0:  # hop back from the player, still facing it
		_retreat_left -= 1
		var away := Vector2(offset.x, offset.z)
		input.move = -away.normalized() if away.length() > 0.001 else Vector2(-1.0, 0.0)
		input.aim = _strike_axis(away)
		return input
	if keep_range > 0.0:
		_keep_distance(input, fighter, body, bodies[target_id], offset, may_attack, rng)
		return input
	if not may_attack:
		_wait(input, offset)
		return input

	# Its turn: pick which of the eight directions to strike along (the one nearest the player,
	# kept while the player stays within DIRECTION_KEEP_DEGREES of it so it does not flicker between
	# two directions), walk to a spot on that line at striking distance, and attack when ready.
	var flat := Vector2(offset.x, offset.z)
	var axis := _strike_axis(flat)
	var along := flat.dot(axis)
	var across := absf(flat.dot(Vector2(-axis.y, axis.x)))
	var reach := attack_range * 0.8
	if along <= reach and along >= attack_min_range and across <= HIT_LANE_TOLERANCE:
		input.aim = axis
		if cooldown <= 0:
			_press_attack(input, fighter, rng)
			cooldown = rng.randi_range(cooldown_min, cooldown_max)
		return input

	if flat.length() < attack_min_range:
		input.move = -flat.normalized() if flat.length() > 0.001 else Vector2(-1.0, 0.0)  # too close for its attack: back off
		return input
	# The spot to strike from: on the chosen line through the player, at a distance it can hit from.
	var strike_from := clampf(along, attack_min_range + APPROACH_MARGIN, reach - APPROACH_MARGIN)  # (inside the reach by more than ARRIVE_DISTANCE)
	var to_spot := flat - axis * strike_from
	if to_spot.length() > ARRIVE_DISTANCE:
		input.move = to_spot.normalized()
	if to_spot.length() <= ARRIVE_DISTANCE or flat.length() <= reach + FACE_WHILE_STEPPING:
		input.aim = axis  # close in: keep facing the player while stepping into place (no turning with each small step)
	return input


## A ranged monster's turn: hold keep_range (back off, close in, drift sideways), face the player,
## escape when cornered, and shoot when it may and the line is clear.
func _keep_distance(input: SimInput, fighter: Fighter, body: SimBody, target: SimBody, offset: Vector3, may_attack: bool, rng: RandomNumberGenerator) -> void:
	if _escape_left > 0:
		_escape_left -= 1
	var flat := Vector2(offset.x, offset.z)
	var distance := flat.length()
	var toward := flat / distance if distance > 0.001 else Vector2(1.0, 0.0)
	var side := Vector2(-toward.y, toward.x)
	input.aim = toward
	if escape_input != "" and distance < escape_range and _escape_left <= 0:
		_escape_left = escape_cooldown
		_press(input, escape_input)  # (faces the player and blinks backwards)
		return
	var clear := _clear_line(body, target)
	if may_attack and cooldown <= 0 and clear and distance >= attack_min_range and distance <= attack_range:
		_press_attack(input, fighter, rng)
		cooldown = rng.randi_range(cooldown_min, cooldown_max)
		return
	if distance < retreat_range:
		input.move = -toward + side * signf(sin(_phase)) * 0.35  # back off at an angle (not straight into a wall)
	elif distance > keep_range + WAIT_BAND:
		input.move = toward
	elif not clear:
		input.move = side * signf(sin(_phase))  # a wall in the way: step sideways for a clear line
	else:
		var drift := sin(_phase * 1.7) * strafe
		if absf(drift) > 0.12:
			input.move = side * drift
	if input.move.length() > 1.0:
		input.move = input.move.normalized()


## True when no wall stands between its chest and the target's (sampled every half meter).
func _clear_line(body: SimBody, target: SimBody) -> bool:
	if world == null:
		return true
	var from := body.position + Vector3.UP * body.height * 0.6
	var to := target.position + Vector3.UP * target.height * 0.6
	var steps := int(from.distance_to(to) / 0.5)
	for i in range(1, steps):
		var point := from.lerp(to, float(i) / float(steps))
		for solid in world.solids:
			if solid.has_point(point):
				return false
	return true


func _press(input: SimInput, which: String) -> void:
	match which:
		"heavy":
			input.heavy = true
		"special":
			input.special = true
		_:
			input.light = true


## The direction (a unit vector, one of eight) a monster strikes along toward a target at `flat`.
## It keeps its previous choice while the target stays near it, so a player standing right between
## two directions does not make it twitch from one to the other.
func _strike_axis(flat: Vector2) -> Vector2:
	if flat.length() < 0.001:
		return _axis if _axis != Vector2.ZERO else Vector2(1.0, 0.0)
	if _axis != Vector2.ZERO and absf(rad_to_deg(_axis.angle_to(flat))) <= DIRECTION_KEEP_DEGREES:
		return _axis
	_axis = Vector2(Combat.direction_from(flat)).normalized()
	return _axis


## Not its turn to attack: hold a ring around the player at wait_range instead of piling on,
## drifting slowly around it, and face the player (on the nearest of the eight directions) when still.
func _wait(input: SimInput, offset: Vector3) -> void:
	var flat := Vector2(offset.x, offset.z)
	var distance := flat.length()
	var toward := flat / distance if distance > 0.001 else Vector2(1.0, 0.0)
	if distance < wait_range - WAIT_BAND:
		input.move = -toward  # too close: back off
	elif distance > wait_range + WAIT_BAND:
		input.move = toward
	var drift := sin(_phase) * CIRCLE_SPEED  # wander around the player while waiting
	if absf(drift) > 0.15:
		input.move += Vector2(-toward.y, toward.x) * drift
	if input.move.length() < 0.05:
		input.aim = _strike_axis(flat)  # standing: face the player


func _press_attack(input: SimInput, fighter: Fighter, rng: RandomNumberGenerator) -> void:
	# A monster has at most one skill with a cooldown, so an empty cooldown list means it is ready.
	if skill_chance > 0 and fighter.cooldowns.is_empty() and rng.randi_range(1, 100) <= skill_chance:
		input.special = true
		return
	match attack_input:
		"heavy":
			input.heavy = true
		"special":
			input.special = true
		_:
			input.light = true
