extends RefCounted
## The equipment rule book, loaded from data/items/rules.json by item_rules_loader.gd:
## stats, tiers, slots, stat values per tier, enhancement odds. No numbers live in code.
## EXTENDING: a new stat/tier/slot is an edit to rules.json (keep every table the right size; the
## loader reports mistakes in `errors`). A new kind of rule is a new field here plus a loader line.

const ItemCatalog := preload("res://logic/item_catalog.gd")
const OUTCOMES: Array[String] = ["success", "stay", "down", "break"]

var stat_ids: Array[String] = []
var stat_base: Dictionary = {}  ## stat -> value a character has with no equipment
var stat_unit: Dictionary = {}  ## stat -> "flat" or "percent" (display only)
var tiers: Array[Dictionary] = []  ## {"id", "color", "substat_count"} in rank order, lowest first
var slots: Array[Dictionary] = []  ## {"id", "count", "main_stat", "classes": [] = open to every class}
var main_by_tier: Dictionary = {}  ## stat -> Array[float], one value per tier
var substat_range: Dictionary = {}  ## stat -> Vector2(min, max) at the lowest tier
var tier_multiplier: Array[float] = []  ## sub stat values are multiplied by this per tier
var substat_boost_step := 0.0  ## each enhancement boost adds this fraction of the sub stat's value
var durability_max := 100.0  ## durability of a new item
var durability_full_above := 0.3  ## fraction of max durability at or above which stats are full
var durability_broken_factor := 0.5  ## the stat multiplier of an item at 0 durability
var armor_wear_per_full_hp := 0.0  ## see rules.json: wear of every worn non-weapon item per max-HP of damage taken
var weapon_wear_per_hit := 0.0
var death_wear := 0.0
var refine: Dictionary = {}
var upgrade: Dictionary = {}
var mobility: Dictionary = {}
var armor: Dictionary = {}
var max_level := 0
var main_bonus_per_level := 0.0  ## main stat gains this fraction of its base per enhancement level
var odds_by_level: Dictionary = {}  ## target level (int) -> {outcome: probability}
var protection: Dictionary = {}  ## outcome -> outcome it becomes when a protection item is used
var catalog = ItemCatalog.new()  ## ItemCatalog: the named items and set bonuses (empty for rules parsed from text alone)
var errors: Array[String] = []  ## filled by the loader; empty means the rules are valid


func is_valid() -> bool:
	return errors.is_empty()


## Whether class card `class_id` may wear slot `slot_id` (data/items/rules.json "classes"; no list = every class).
## Boss 2026-11-11: the offhand (shield) slot is Sword & Shield only.
func slot_open_for(slot_id: String, class_id: String) -> bool:
	var classes: Array = slot(slot_id).get("classes", [])
	return classes.is_empty() or classes.has(class_id)


func slot(id: String) -> Dictionary:
	for entry in slots:
		if entry["id"] == id:
			return entry
	return {}


## The stat multiplier of an item at `ratio` of its max durability (1 = pristine, 0 = fully worn).
func durability_factor(ratio: float) -> float:
	if ratio >= durability_full_above:
		return 1.0
	return lerpf(durability_broken_factor, 1.0, clampf(ratio / durability_full_above, 0.0, 1.0))


func total_slot_count() -> int:
	var total := 0
	for entry in slots:
		total += int(entry["count"])
	return total


func main_base(stat: String, tier: int) -> float:
	return main_by_tier[stat][tier]


## Value of a sub stat roll. `quality` is 0..1 inside the stat's range; it is kept on the item so a
## lucky roll stays lucky when the item's tier goes up.
func substat_base_value(stat: String, quality: float, tier: int) -> float:
	var range_for_stat: Vector2 = substat_range[stat]
	return lerpf(range_for_stat.x, range_for_stat.y, quality) * tier_multiplier[tier]
