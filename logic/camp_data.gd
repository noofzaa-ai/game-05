extends RefCounted
## The camp rule book, loaded from data/camp/camp.json by camp_data_loader.gd: materials, bag sizes,
## repair prices, camp levels, facilities and camp skills. No numbers live in code.
## EXTENDING: a new facility, material or camp skill is an edit to camp.json; a new kind of facility
## effect is a key in `effect_total()` callers (see camp.gd) and an entry in the loader's EFFECT_KEYS.

var materials: Dictionary = {}  ## material id -> {"name", "stack", "color"}
var run_slots := 0  ## slots of the run bag before any facility adds more
var bank_slots := 20  ## separate persistent Storage, equipment/materials only
var stash_slots := 0  ## slots of the camp stash before any facility adds more
var rest_heal_fraction := 0.0  ## a rest point heals this fraction of max HP
var repair: Dictionary = {}  ## {"normal", "broken": {"gold_per_point", "materials_per_point"}, "tier_multiplier": Array, "facility"}
var camp_levels: Array[Dictionary] = []  ## upgrades to level 2, 3...: {"level", "cost": {"gold", "materials"}}
var facilities: Dictionary = {}  ## id -> {"name", "function", "levels": [{"camp_level", "cost", "effects"}]}
var progression_max_level := 0  ## 0 = no extra cap; preserve legacy data above the active cap
var progression_facilities: Array[String] = []  ## core facilities that gate the next camp level
var start_levels: Dictionary = {}  ## facility id -> the level a new player already has
var skills: Array[Dictionary] = []  ## {"id", "name", "camp_level", "summary", "stats": {stat: flat bonus}}
var starter: Dictionary = {}  ## {"gold", "materials"} a new player starts with
var errors: Array[String] = []  ## filled by the loader; empty means the data is valid


func is_valid() -> bool:
	return errors.is_empty()


func max_camp_level() -> int:
	var configured := 1 + camp_levels.size()
	return mini(configured, progression_max_level) if progression_max_level > 0 else configured


## What the facility's level `level` (1-based) gives: {} for level 0 or an unknown facility.
func level_data(facility_id: String, level: int) -> Dictionary:
	if not facilities.has(facility_id) or level < 1 or level > facilities[facility_id]["levels"].size():
		return {}
	return facilities[facility_id]["levels"][level - 1]


## The sum of one effect (for example "stash_slots") over every built level of every facility.
func effect_total(facility_levels: Dictionary, effect: String) -> float:
	var total := 0.0
	for facility_id in facilities:
		for level in range(1, int(facility_levels.get(facility_id, 0)) + 1):
			total += float(level_data(facility_id, level).get("effects", {}).get(effect, 0.0))
	return total
