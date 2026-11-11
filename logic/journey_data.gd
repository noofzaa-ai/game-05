extends RefCounted
## A JOURNEY (one PvE "ด่าน"): 12 stages in a row, the player picks the next stage from a few random
## choices after each one. This holds the journey's data, read from data/journeys/*.json; the rules
## that use it are in journey.gd. A broken file never crashes the game: `errors` is filled instead.
## EXTENDING: a new journey = a new JSON file. A new node type = a weight here + a branch in journey.gd.

const DATA_DIR := "res://data/journeys/"
const SUPPORTED_VERSION := 1
const CHOICE_TYPES: Array[String] = ["combat", "challenge", "treasure"]  ## what the random choices can be

var id := ""
var display_name := ""
var stage_count := 12
## Wave mode (Boss 2026-11-10, auto-battler): the whole journey is ONE fight on one map: `stages` are its
## waves in order (the last one is the boss wave), each arriving when the field is clear; no portals, no
## camps. `wave_count_scale` multiplies every non-boss monster count (1.5 = half as many again).
var wave_mode := false
var wave_count_scale := 1.0
var wave_power_scale := 1.0  ## multiplies every wave monster's HP and ATK on top of the stage power (waves have no camps in between)
var wave_heal_fraction := 0.0  ## how much of their max HP the living players get back as each wave arrives
var choice_count := 3  ## how many next stages the player picks from
var first_camp_stages: Array[int] = []  ## the first camp lands on one of these (picked at random)
var last_camp_stage := 11  ## the second camp: always here (right before the boss)
var camp_heal_fraction := 1.0  ## a camp heals this fraction of max HP
var camp_banks_bag := false  ## true = at a camp the run bag can be stored in the stash (safe from death)
var node_weights: Dictionary = {}  ## choice type -> weight
var combat_maps: Array[String] = []  ## map ids a combat stage is played on (their enemy spawn spots are reused)
var boss_map := ""
## Optional (2026-10-13, exit portals): the safe rest map a camp stage is played on ("" = the client
## falls back to a fight map with no monsters), and the small fight arenas preferred over combat_maps.
## Only arenas whose map file exists and is valid with enemy spawn spots are kept (load_by_id), so the
## journey keeps working while the arena maps are still being built.
var camp_map := ""
var arena_maps: Array[String] = []
var boss: Dictionary = {}  ## {"hp_mult", "poise_mult", "label"}: how the boss stands out from its base type
var challenge_reward: Dictionary = {}  ## {"table": enemy type whose loot table is rolled, "level_bonus": int, "rolls": int}
var treasure: Dictionary = {}  ## {"min_tier": tier id, "tier_weights": {tier id: weight}}
## One entry per stage (index 0 = stage 1): {"level", "power", "enemies": [{"type", "count", "level"?, "boss"?}],
## "challenge": same shape or {}}. power scales the monsters' HP and ATK (below 1 = gentler than the base numbers).
var stages: Array[Dictionary] = []
var errors: Array[String] = []


func is_valid() -> bool:
	return errors.is_empty()


static func load_by_id(journey_id: String, enemy_types: Array = []) -> RefCounted:
	var path := DATA_DIR + journey_id + ".json"
	if not FileAccess.file_exists(path):
		var missing = load("res://logic/journey_data.gd").new()
		missing.errors.append("journey file not found: %s" % path)
		return missing
	var data = parse(FileAccess.get_file_as_string(path), enemy_types)
	data.arena_maps.assign(data.arena_maps.filter(func(map_id): return _usable_fight_map(str(map_id))))
	return data


## The maps a combat or challenge stage is drawn from: the arenas if any are ready, else combat_maps.
func fight_map_pool() -> Array[String]:
	return arena_maps if not arena_maps.is_empty() else combat_maps


static func _usable_fight_map(map_id: String) -> bool:
	var map = load("res://logic/map_loader.gd").load_by_id(map_id)
	return map.is_valid() and map.modes.has("pve") and not map.enemy_spawns.is_empty()


## `enemy_types` (the monster ids in the combat data) lets it check every monster named; empty skips that.
static func parse(text: String, enemy_types: Array = []) -> RefCounted:
	var data = load("res://logic/journey_data.gd").new()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		data.errors.append("invalid JSON or not an object")
		return data
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		data.errors.append("unsupported version")
	data.id = str(root.get("id", ""))
	data.display_name = str(root.get("name", data.id))
	data.stage_count = int(root.get("stage_count", 12))
	data.wave_mode = bool(root.get("wave_mode", false))
	data.wave_count_scale = maxf(0.1, float(root.get("wave_count_scale", 1.0)))
	data.wave_power_scale = maxf(0.05, float(root.get("wave_power_scale", 1.0)))
	data.wave_heal_fraction = clampf(float(root.get("wave_heal_fraction", 0.0)), 0.0, 1.0)
	data.choice_count = int(root.get("choices", 3))
	for stage in root.get("first_camp_stages", []):
		data.first_camp_stages.append(int(stage))
	data.last_camp_stage = int(root.get("last_camp_stage", data.stage_count - 1))
	data.camp_heal_fraction = float(root.get("camp_heal_fraction", 1.0))
	data.camp_banks_bag = bool(root.get("camp_banks_bag", false))
	data.node_weights = root.get("node_weights", {})
	for map_id in root.get("combat_maps", []):
		data.combat_maps.append(str(map_id))
	data.boss_map = str(root.get("boss_map", ""))
	data.camp_map = str(root.get("camp_map", ""))
	for map_id in root.get("arena_maps", []):
		data.arena_maps.append(str(map_id))
	data.boss = root.get("boss", {})
	data.challenge_reward = root.get("challenge_reward", {})
	data.treasure = root.get("treasure", {})
	for stage in root.get("stages", []):
		data.stages.append(stage)

	if data.stage_count < 3 or data.choice_count < 1:
		data.errors.append("stage_count must be at least 3 and choices at least 1")
	if data.stages.size() != data.stage_count:
		data.errors.append("stages must have one entry per stage (%d)" % data.stage_count)
	if data.first_camp_stages.is_empty() or data.first_camp_stages.any(func(s): return s < 2 or s >= data.last_camp_stage):
		data.errors.append("first_camp_stages must be stages between 2 and last_camp_stage")
	if data.last_camp_stage >= data.stage_count:
		data.errors.append("last_camp_stage must come before the boss stage")
	for type in data.node_weights:
		if not CHOICE_TYPES.has(str(type)):
			data.errors.append("unknown node type in node_weights: %s" % type)
	if not data.node_weights.has("combat") or float(data.node_weights["combat"]) <= 0.0:
		data.errors.append("node_weights.combat must be positive")
	if data.combat_maps.is_empty() or data.boss_map.is_empty():
		data.errors.append("combat_maps and boss_map are required")
	if str(data.treasure.get("min_tier", "")).is_empty() or typeof(data.treasure.get("tier_weights")) != TYPE_DICTIONARY:
		data.errors.append("treasure needs min_tier and tier_weights")
	for index in data.stages.size():
		var stage: Dictionary = data.stages[index]
		data._check_fight(stage, "stages[%d]" % index, enemy_types)
		if not stage.get("challenge", {}).is_empty():
			data._check_fight(stage["challenge"], "stages[%d].challenge" % index, enemy_types)
	if not data.stages.is_empty() and not data.stages[-1].get("enemies", []).any(func(e): return bool(e.get("boss", false))):
		data.errors.append("the last stage must have an enemy with \"boss\": true")
	return data


func _check_fight(fight: Dictionary, label: String, enemy_types: Array) -> void:
	if int(fight.get("level", 0)) < 1 or float(fight.get("power", 0.0)) <= 0.0:
		errors.append("%s needs level >= 1 and power > 0" % label)
	for enemy in fight.get("enemies", []):
		if int(enemy.get("count", 0)) < 1:
			errors.append("%s: every enemy needs count >= 1" % label)
		if not enemy_types.is_empty() and not enemy_types.has(str(enemy.get("type", ""))):
			errors.append("%s: unknown enemy type %s" % [label, enemy.get("type", "")])
