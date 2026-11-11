extends RefCounted
## The combat rule book, loaded from data/combat/combat.json by combat_data_loader.gd:
## global rules, fighting styles, every move, and enemy types. Adding a move or an enemy is a
## data edit, not a code change.
## EXTENDING: a new field on moves/enemies is read here and in the loader; code that uses it
## goes in combat.gd.

var coop: Dictionary = {}  ## optional co-op configuration, never applied in solo
var rules: Dictionary = {}  ## defense_constant, min_damage, down_ticks, wakeup_invulnerable_ticks, default_stats
var styles: Dictionary = {}  ## style id -> {"ground_light", "ground_heavy", "air_light"} (move ids)
var moves: Dictionary = {}  ## move id -> Dictionary (see combat_data_loader.gd for the fields)
var enemies: Dictionary = {}  ## enemy id -> {"style", "color", "model", "model_height", "stats", "ai"}
var weapons: Dictionary = {}  ## weapon id -> {"name", "summary", "color", "params", "ultimate_skill"} (the style with the same id holds its moves)
## The imported skill packs (data/combat/ultimates.json): {"knobs", "skills" (id -> the pack's facts),
## "defaults" (weapon type -> skill id), "by_element"}. Empty when the file is missing.
var ultimates: Dictionary = {}
var weapon_ids: Array[String] = []  ## the player's weapons, in the order of weapons.json
var projectiles: Dictionary = {}  ## projectile id -> {"look", "speed", "range", "radius", "pierce", "gravity", "lift", "homing", "walls", "aim_cone"} (projectiles.gd)
var areas: Dictionary = {}  ## ground area id -> {"look", "radius", "delay", "active", "height", "range", "aim_cone", "guardable"} (projectiles.gd)
var effects: Dictionary = {}  ## effect id -> {"name", "kind", "color", "duration", "max_stacks", "stats", "dot_power", "heal_percent", "control", "break_on_damage"}
var errors: Array[String] = []  ## filled by the loader; empty means the data is valid


func is_valid() -> bool:
	return errors.is_empty()


## Stats with every missing stat filled in from the default stats.
func full_stats(partial: Dictionary) -> Dictionary:
	var result: Dictionary = rules["default_stats"].duplicate()
	for stat in partial:
		result[stat] = float(partial[stat])
	return result


## A monster's stats at `level` (1 = the base numbers in the data): each scaled stat grows by its
## per-level fraction for every level above 1.
func enemy_stats(enemy_type: String, level: int = 1) -> Dictionary:
	var stats: Dictionary = enemies[enemy_type]["stats"].duplicate()
	var scaling: Dictionary = rules["enemy_level_scaling"]
	for stat in scaling:
		stats[stat] = float(stats[stat]) * (1.0 + float(scaling[stat]) * float(maxi(level, 1) - 1))
	return stats


## What a weapon is like to use, for the equipment screens: the seconds one light hit takes on
## average (a faster attack speed shortens it), and the reach, damage, push and stun of its first
## light and its heavy attack. `attack_speed_stat` is the wearer's ATKSPD stat (percent).
func weapon_stats(weapon_id: String, attack_speed_stat: float = 0.0) -> Dictionary:
	if not styles.has(weapon_id):
		return {}
	var factor := maxf(0.1, 1.0 + attack_speed_stat / 100.0)
	var light_ticks := 0.0
	for key in ["light_1", "light_2", "light_3"]:
		light_ticks += float(move_length("%s_%s" % [weapon_id, key]))
	light_ticks /= 3.0
	var light: Dictionary = moves[styles[weapon_id]["ground_light"]]
	var heavy: Dictionary = moves[styles[weapon_id]["ground_heavy"]]
	var light_offset: Vector3 = light["hit_offset"]
	var light_size: Vector3 = light["hit_size"]
	var reach: float = light_offset.x + light_size.x * .5
	if not light["melee"] and not light["spawns"].is_empty():
		var shot: String = str(light["spawns"][0].get("projectile",""))
		if projectiles.has(shot):reach=float(projectiles[shot]["range"])
	return {
		"light_seconds": light_ticks / 60.0 / factor,
		"heavy_seconds": float(move_length(styles[weapon_id]["ground_heavy"])) / 60.0 / factor,
		"reach": reach,
		"width": light_size.z,
		"light_power": float(light["power"]),
		"heavy_power": float(heavy["power"]),
		"knockback": float(heavy["knockback"]),
		"stun": int(heavy["hitstun"]),
	}


## Total ticks a move lasts at normal attack speed.
func move_length(move_id: String) -> int:
	var move: Dictionary = moves[move_id]
	return int(move["startup"]) + int(move["active"]) + int(move["recovery"])
