extends RefCounted
## Builds the eleven-wave roster from the existing Goblin Journey tuning.
## The authority remains responsible for spawning and rewarding these entries.

const Progress := preload("res://logic/goblin_wave_progress.gd")
const MINIBOSS_TYPE := "goblin_knight"
const MINIBOSS_HP_MULT := 1.8
const MINIBOSS_POISE_MULT := 1.5


static func build(journey_data, wave: int) -> Dictionary:
	if journey_data == null or wave < 1 or wave > Progress.LAST_WAVE or journey_data.stages.size() < Progress.LAST_WAVE:
		return {}
	var fight: Dictionary = journey_data.stages[wave - 1]
	var entries: Array = []
	for group in fight.get("enemies", []):
		for _i in int(group.get("count", 0)):
			entries.append({"type": str(group.get("type", "")), "level": int(group.get("level", fight.get("level", 1))), "hp_scale": float(fight.get("power", 1.0)), "atk_scale": float(fight.get("power", 1.0)), "miniboss": false})
	if wave in Progress.CHEST_WAVES:
		# An additional, visibly identifiable knight is the milestone miniboss;
		# never mark the ordinary enemies or the final Chief as a reward source.
		entries.append({"type": MINIBOSS_TYPE, "level": int(fight.get("level", 1)), "hp_scale": float(fight.get("power", 1.0)) * MINIBOSS_HP_MULT, "atk_scale": float(fight.get("power", 1.0)), "poise_scale": MINIBOSS_POISE_MULT, "miniboss": true})
	return {"wave": wave, "chest_after_clear": wave in Progress.CHEST_WAVES, "enemies": entries}


## Spawn a prepared wave into an existing authoritative simulation. IDs are
## allocated monotonically by the caller and may never reuse a dead fighter ID.
## Validate the entire wave before creating anything to avoid half a roster.
static func spawn(sim, map, roster: Dictionary, first_id: int, coop_hp_scale: float = 1.0) -> Array:
	if sim == null or sim.combat == null or map == null or first_id < 1 or coop_hp_scale <= 0.0:
		return []
	var entries: Array = roster.get("enemies", [])
	if entries.is_empty():
		return []
	for i in entries.size():
		if sim.fighters.has(first_id + i) or sim.bodies.has(first_id + i) or not sim.combat.enemies.has(str(entries[i].get("type", ""))):
			return []
	var spots: Array = map.enemy_spawns.map(func(s): return s["position"])
	if spots.is_empty():
		spots = [map.spawn + Vector3(6.0, 0.0, -6.0)]
	var ids: Array = []
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var id := first_id + i
		var position: Vector3 = spots[i % spots.size()] + Vector3(1.5 * float(i / spots.size()), 0.0, 0.0)
		sim.add_enemy(id, position, str(entry.type), int(entry.level))
		var fighter = sim.fighters[id]
		fighter.stats["HP"] *= float(entry.hp_scale) * coop_hp_scale
		fighter.stats["ATK"] *= float(entry.atk_scale)
		fighter.hp = fighter.max_hp()
		fighter.max_poise *= float(entry.get("poise_scale", 1.0))
		fighter.poise = fighter.max_poise
		ids.append(id)
	return ids
