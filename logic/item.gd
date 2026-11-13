extends RefCounted
const StateCodec := preload("res://logic/state_codec.gd")
## One piece of equipment. Plain data: which slot, tier, enhancement level, main stat and rolled
## sub stats. Values are computed from the rules on demand, so changing the rule book rebalances
## every existing item without touching saved items.
## EXTENDING: per-item data that must be saved (affixes, set ids) goes here.

const ItemRules := preload("res://logic/item_rules.gd")

var id := ""
var slot := ""
var tier := 0  ## index into rules.tiers
var upgrade_count := 0  ## total Upgrade attempts, including new rows
var refine_level := 0  ## separate from legacy enhancement, no substat boosts
var level := 0  ## enhancement level, 0..rules.max_level
var main_stat := ""
var weapon_type := ""  ## weapons only: names the combat style this weapon gives (for example "blade")
var item_id := ""  ## which catalog item it is (data/items/catalog.json): its name, model and set; "" = a plain piece
var substats: Array[Dictionary] = []  ## {"stat": String, "quality": float 0..1, "boosts": int}
var destroyed := false  ## set when an enhancement attempt breaks the item
var durability := 100.0  ## wears down with use; below some level the item's stats drop (see ItemRules.durability_factor)
var max_durability := 100.0


func main_value(rules: ItemRules) -> float:
	return base_value(rules) * (1.0 + rules.main_bonus_per_level * float(level) + float(rules.refine.get("bonus_per_level", 0.0)) * float(refine_level))


func base_value(rules: ItemRules) -> float:
	var kind := str(rules.catalog.entry(item_id).get("armor_class",""))
	var multiplier := float(rules.armor.get("class_base_multipliers",{}).get(kind,{}).get(main_stat,1.0))
	return rules.main_base(main_stat,tier)*multiplier


func substat_value(index: int, rules: ItemRules) -> float:
	var sub := substats[index]
	var base := rules.substat_base_value(sub["stat"], sub["quality"], tier)
	return base * (1.0 + rules.substat_boost_step * float(sub["boosts"])) + float(sub.get("upgrade_bonus", 0.0))


func durability_ratio() -> float:
	return clampf(durability / maxf(max_durability, 0.0001), 0.0, 1.0)


## Worn out completely: it still counts, but at its reduced stats, until repaired.
func is_broken_down() -> bool:
	return durability <= 0.0


## Everything this item adds to a character: stat name -> value (main stat plus all sub stats),
## reduced when the item is badly worn.
func stat_totals(rules: ItemRules) -> Dictionary:
	var totals := {main_stat: main_value(rules)}
	for index in substats.size():
		var stat: String = substats[index]["stat"]
		totals[stat] = totals.get(stat, 0.0) + substat_value(index, rules)
	var factor := rules.durability_factor(durability_ratio())
	if factor < 1.0:
		for stat in totals:
			totals[stat] *= factor
	return totals


func duplicate_item() -> Object:
	var copy = get_script().new()
	copy.id = id
	copy.slot = slot
	copy.tier = tier
	copy.level = level
	copy.refine_level = refine_level
	copy.upgrade_count = upgrade_count
	copy.main_stat = main_stat
	copy.weapon_type = weapon_type
	copy.item_id = item_id
	copy.destroyed = destroyed
	copy.durability = durability
	copy.max_durability = max_durability
	for sub in substats:
		copy.substats.append(sub.duplicate())
	return copy


## HP scale 100 (2026-11-13): every HP/ATK number in data was divided by 10. Main and substat values come
## from the rules, but a substat's upgrade_bonus is a saved amount: an item saved before the change (no
## "stat_scale" key) has the bonus of these stats divided by OLD_STAT_SCALE once, on load.
const STAT_SCALE := 2  ## 1 = before the HP scale change (no key in old saves), 2 = HP scale 100
const OLD_STAT_SCALE := 10.0
const SCALED_STATS: Array[String] = ["HP", "ATK", "HPREGEN"]


## Versioned owned data only; computed stats always come from current rules.
func to_dict() -> Dictionary:
	return {"v": 1, "stat_scale": STAT_SCALE, "id": id, "slot": slot, "tier": tier, "level": level,
		"upgrade_count": upgrade_count, "refine_level": refine_level, "main_stat": main_stat, "weapon_type": weapon_type, "item_id": item_id,
		"substats": substats.map(func(sub): return {"stat": sub["stat"], "quality": StateCodec.float_text(sub["quality"]), "boosts": sub["boosts"], "upgrade_bonus": StateCodec.float_text(float(sub.get("upgrade_bonus", 0.0)))}), "destroyed": destroyed,
		"durability": StateCodec.float_text(durability), "max_durability": StateCodec.float_text(max_durability)}


static func from_dict(d: Dictionary):
	if int(d.get("v", 0)) != 1:
		return null
	var item = load("res://logic/item.gd").new()
	for key in ["id", "slot", "main_stat", "weapon_type", "item_id"]:
		item.set(key, str(d[key]))
	for key in ["tier", "level"]:
		item.set(key, int(d[key]))
	item.refine_level = int(d.get("refine_level", 0))
	item.upgrade_count = int(d.get("upgrade_count", 0))
	item.destroyed = bool(d["destroyed"])
	item.durability = StateCodec.float_value(d["durability"])
	item.max_durability = StateCodec.float_value(d["max_durability"])
	for sub in d["substats"]:
		item.substats.append({"stat": str(sub["stat"]), "quality": StateCodec.float_value(sub["quality"]), "boosts": int(sub["boosts"]), "upgrade_bonus": StateCodec.float_value(sub.get("upgrade_bonus", "0"))})
	if int(d.get("stat_scale", 1)) < STAT_SCALE:  # saved before HP scale 100: rescale the saved upgrade amounts once
		for sub in item.substats:
			if SCALED_STATS.has(str(sub["stat"])):
				sub["upgrade_bonus"] = float(sub["upgrade_bonus"]) / OLD_STAT_SCALE
	preload("res://logic/armor_migration.gd").apply(item)
	return item
