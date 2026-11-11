extends RefCounted
## Server-side progress contract for the single-arena Goblin encounter.
## This object does not create enemies or grant loot: the room authority must do
## those operations and persist this state with the associated run atomically.

const LAST_WAVE := 11
const CHEST_WAVES := [3, 6, 9]
const FIGHTING := "fighting"
const CHEST := "chest"
const REST := "rest"
const BOSS := "boss"
const COMPLETE := "complete"

var wave := 1
var phase := FIGHTING
var opened_chests: Array[int] = []


## Called only after the authority confirms all enemies in this wave are dead.
## Repeated calls cannot skip a wave or grant a second chest.
func finish_wave(cleared_wave: int) -> bool:
	if phase != FIGHTING or cleared_wave != wave:
		return false
	if wave in CHEST_WAVES:
		phase = CHEST
	elif wave == LAST_WAVE:
		phase = REST
	else:
		wave += 1
	return true


## The caller grants each eligible player's reward in the same authoritative
## transaction/checkpoint as this transition; clients cannot choose a reward.
func open_chest() -> bool:
	if phase != CHEST or wave not in CHEST_WAVES or wave in opened_chests:
		return false
	opened_chests.append(wave)
	wave += 1
	phase = FIGHTING
	return true


func leave_rest() -> bool:
	if phase != REST:
		return false
	phase = BOSS
	return true


func finish_boss() -> bool:
	if phase != BOSS:
		return false
	phase = COMPLETE
	return true


func to_dict() -> Dictionary:
	return {"v": 1, "wave": wave, "phase": phase, "opened_chests": opened_chests.duplicate()}


static func from_dict(raw: Dictionary):
	if int(raw.get("v", 0)) != 1 or not _is_integer(raw.get("wave")) or not raw.get("opened_chests") is Array:
		return null
	var w := int(raw.wave)
	var p := str(raw.get("phase", ""))
	if w < 1 or w > LAST_WAVE or p not in [FIGHTING, CHEST, REST, BOSS, COMPLETE]:
		return null
	if (p == CHEST and w not in CHEST_WAVES) or (p in [REST, BOSS, COMPLETE] and w != LAST_WAVE):
		return null
	var seen: Array[int] = []
	for raw_wave in raw.opened_chests:
		if not _is_integer(raw_wave) or int(raw_wave) not in CHEST_WAVES or int(raw_wave) >= w or int(raw_wave) in seen:
			return null
		seen.append(int(raw_wave))
	for milestone in CHEST_WAVES:
		if milestone < w and milestone not in seen:
			return null
	var progress = load("res://logic/goblin_wave_progress.gd").new()
	progress.wave = w
	progress.phase = p
	progress.opened_chests = seen
	return progress


static func _is_integer(value) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))
