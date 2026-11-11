extends RefCounted
## A character's physical state in the simulation. `position` is the point at the feet, centered
## in x and z. Plain data: no nodes, no meshes.
## EXTENDING: put new per-character state here (health, facing, current move, ...).

const HALF_WIDTH := 0.4
const HALF_DEPTH := 0.4
const HEIGHT := 1.8  ## the usual body height; a monster may be shorter or taller (`height`)

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var grounded := false
var move_speed_multiplier := 1.0  ## from the MOVESPD stat (see stats.gd); 1.0 = base walking speed
var height := HEIGHT  ## how tall the body (and so the area hits land on) is; set per monster from its data
var knockback := Vector2.ZERO  ## push from hits (x, z); added to walking and fades every tick


func aabb() -> AABB:
	return AABB(
		Vector3(position.x - HALF_WIDTH, position.y, position.z - HALF_DEPTH),
		Vector3(HALF_WIDTH * 2.0, height, HALF_DEPTH * 2.0)
	)


## How far the body reaches below and above `position` along an axis (0 = x, 1 = y, 2 = z).
func extent(axis: int) -> Vector2:
	match axis:
		0:
			return Vector2(-HALF_WIDTH, HALF_WIDTH)
		1:
			return Vector2(0.0, height)
		_:
			return Vector2(-HALF_DEPTH, HALF_DEPTH)
