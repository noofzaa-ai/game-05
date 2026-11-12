extends RefCounted
## One player's input for one simulation tick.
## EXTENDING: add a field here for every new action (attack, block, ...). The client fills it
## from keyboard/touch, the simulation only reads it, so any client (or a bot, or the network) works.

var captured_at_ms:=-1 # Local trace metadata only; never encoded or used by gameplay.
var move := Vector2.ZERO  ## x: left/right, y: depth (positive = toward the camera)
var jump := false  ## true only on the tick the jump was pressed
var light := false  ## true only on the tick the light attack button was pressed
var heavy := false  ## true only on the tick the heavy attack button was pressed
var aim := Vector2.ZERO  ## optional: where to face (x, z). Zero = face the way the fighter is moving. Used by enemy AI and aim assist.
var run := false  ## true on EVERY tick the run button is held (needs energy, see combat.gd)
var guard := false  ## true on EVERY tick the guard button is held down (hold to guard)
var dodge := false  ## true only on the tick the dodge button was pressed
var special := false  ## true only on the tick the special skill button was pressed
var ultimate := false  ## true only on the tick the ultimate button was pressed
var skill_slot := -1  ## 0..3, -1 = no cast; server resolves all skill/Gem data.
var aim_distance := 8.0  ## metres along bounded aim direction, never a client hit position.

static func wire_size() -> int:
	return 7  ## with the skill slot and aim distance (class skills)


## An independent copy (the simulation adjusts inputs, for example to add aim assist, without
## touching the caller's object).
func duplicate_input() -> RefCounted:
	var copy = get_script().new()
	copy.captured_at_ms=captured_at_ms
	copy.move = move
	copy.jump = jump
	copy.light = light
	copy.heavy = heavy
	copy.aim = aim
	copy.run = run
	copy.guard = guard
	copy.dodge = dodge
	copy.special = special
	copy.ultimate = ultimate
	copy.skill_slot = skill_slot
	copy.aim_distance = aim_distance
	return copy


## Network gap fallback: held controls only; no one-shot combat/skill edges.
func held_controls() -> RefCounted:
	var held=get_script().new()
	held.captured_at_ms=captured_at_ms
	held.move=move;held.aim=aim;held.aim_distance=aim_distance
	held.run=run;held.guard=guard
	return held


## Wire v1: eight button bits, then signed move.x/y and aim.x/y (5 bytes).
## This boundary is opt-in until LocalSession (M1-6) uses it for both offline and online play.
const BUTTONS := ["jump", "light", "heavy", "run", "guard", "dodge", "special", "ultimate"]

func encode() -> PackedByteArray:
	var bytes := PackedByteArray([0, 0, 0, 0, 0])
	if wire_size() == 7:
		bytes.resize(7)
		bytes[5] = skill_slot + 1 if skill_slot >= 0 and skill_slot < 4 else 0
		bytes[6] = roundi(clampf(aim_distance, 0, 25.5) * 10) if is_finite(aim_distance) else 0
	for i in BUTTONS.size():
		if get(BUTTONS[i]):
			bytes[0] |= 1 << i
	var safe_move := _wire_axes(move)
	var safe_aim := _wire_axes(aim)
	var axes := [safe_move.x, safe_move.y, safe_aim.x, safe_aim.y]
	for i in axes.size():
		var value := float(axes[i])
		bytes[i + 1] = (roundi(clampf(value, -1.0, 1.0) * 127.0) if is_finite(value) else 0) & 255
	return bytes


## Reject malformed packets rather than silently interpreting missing buttons/axes.
static func decode(bytes: PackedByteArray):
	if bytes.size() != wire_size():
		return null
	var result = load("res://logic/sim_input.gd").new()
	for i in BUTTONS.size():
		result.set(BUTTONS[i], bool(bytes[0] & (1 << i)))
	var axes: Array[float] = []
	for i in range(1, 5):
		var value := int(bytes[i])
		if value == 128:
			return null
		axes.append(float(value - 256 if value > 127 else value) / 127.0)
	result.move = Vector2(axes[0], axes[1])
	result.aim = Vector2(axes[2], axes[3])
	if bytes.size() == 7:
		if bytes[5] > 4: return null
		result.skill_slot = int(bytes[5]) - 1
		result.aim_distance = float(bytes[6]) / 10.0
	return result


## Aim often arrives as a world-space offset. Preserve its direction when bounding it.
static func _wire_axes(vector: Vector2) -> Vector2:
	var clean := Vector2(vector.x if is_finite(vector.x) else 0.0, vector.y if is_finite(vector.y) else 0.0)
	return clean / maxf(1.0, maxf(absf(clean.x), absf(clean.y)))
