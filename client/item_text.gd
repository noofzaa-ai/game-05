extends RefCounted
## Words for equipment on the screens: its name with tier and enhancement, its stats, how worn it is.
## Display only; the numbers all come from logic/.

const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")
const InkUi := preload("res://client/ink_ui.gd")

const STAT_LABELS := {
	"HP": "HP", "ATK": "ATK", "DEF": "DEF", "ATKSPD": "ATK SPD", "MOVESPD": "MOVE SPD", "CRIRATE": "CRIT %", "CRIDMG": "CRIT DMG",
	"EFFECT_ACC": "EFFECT ACC", "EFFECT_RES": "EFFECT RES", "HPREGEN": "HP REGEN", "STAREGEN": "STA REGEN", "ULTREGEN": "ULT REGEN", "STAMINA": "STAMINA",
}


static func tier_color(item: Item, rules: ItemRules) -> Color:
	return InkUi.rarity_color(rules.tiers[item.tier]["color"])


## "Rare Golden Blossom Katana  +3": a catalog item's own name; a plain piece is named by its weapon
## type (weapons) or its slot.
static func title(item: Item, rules: ItemRules, weapon_names: Dictionary = {}) -> String:
	var kind: String = item.slot.capitalize()
	var base: Dictionary = rules.catalog.entry(item.item_id)
	if not base.is_empty():
		kind = base["name"]
	elif item.slot == "weapon" and not item.weapon_type.is_empty():
		kind = str(weapon_names.get(item.weapon_type, item.weapon_type.capitalize()))
	var text := "%s %s" % [str(rules.tiers[item.tier]["id"]).capitalize(), kind]
	if item.refine_level > 0:
		text += "  +%d" % item.refine_level
	elif item.level > 0:
		text += "  +%d" % item.level
	return text


## "Aegis Armor 3/5: DEF +9, HP +120 (4: EFFECT RES +6)": the item's set, how many pieces of it are
## worn (`worn_ids`: the worn items' item_id), the bonuses reached and the next one. "" for no set.
static func set_text(item: Item, rules: ItemRules, worn_ids: Array) -> String:
	var set_id: String = rules.catalog.entry(item.item_id).get("set", "")
	if set_id.is_empty():
		return ""
	var info: Dictionary = rules.catalog.sets[set_id]
	var count := int(rules.catalog.set_counts(worn_ids).get(set_id, 0))
	var pieces := 0
	for other in rules.catalog.items.values():
		if other["set"] == set_id:
			pieces += 1
	var reached: Array[String] = []
	var next := ""
	for bonus in info["bonuses"]:
		var words := "%s +%s" % [STAT_LABELS.get(bonus["stat"], bonus["stat"]), _number(bonus["value"])]
		if count >= bonus["pieces"]:
			reached.append(words)
		elif next.is_empty():
			next = "%d: %s" % [bonus["pieces"], words]
	var text := "%s %d/%d" % [info["name"], count, pieces]
	if not reached.is_empty():
		text += ": " + ", ".join(reached)
	if not next.is_empty():
		text += "  (%s)" % next
	return text


## "ATK 55 | HP +60, DEF +5": the main stat first, then the sub stats.
static func stats_line(item: Item, rules: ItemRules) -> String:
	var totals := item.stat_totals(rules)
	var main_text := "%s %s" % [STAT_LABELS.get(item.main_stat, item.main_stat), _number(float(totals.get(item.main_stat, 0.0)) - _substat_total(item, rules, item.main_stat))]
	var subs: Array[String] = []
	for index in item.substats.size():
		subs.append(substat_text(item, rules, index))
	return main_text if subs.is_empty() else "%s | %s" % [main_text, ", ".join(subs)]


## "Durability 80%" with a warning when the item is worn enough to lose stats.
static func durability_text(item: Item, rules: ItemRules) -> String:
	var percent := int(roundf(item.durability_ratio() * 100.0))
	if item.is_broken_down():
		return "BROKEN DOWN (stats halved)"
	if item.durability_ratio() < rules.durability_full_above:
		return "Worn %d%% (stats reduced)" % percent
	return "Durability %d%%" % percent


static func durability_color(item: Item, rules: ItemRules) -> Color:
	if item.is_broken_down():
		return InkUi.WEAR_BROKEN
	if item.durability_ratio() < rules.durability_full_above:
		return InkUi.WEAR_LOW
	return InkUi.WEAR_OK


## "120 gold, 5 Ore" for a cost dictionary ({"gold", "materials"}); material names come from the camp data.
static func cost_text(cost: Dictionary, materials: Dictionary) -> String:
	var parts: Array[String] = []
	if int(cost.get("gold", 0)) > 0:
		parts.append("%d gold" % int(cost["gold"]))
	var needed: Dictionary = cost.get("materials", {})
	for id in needed:
		parts.append("%d %s" % [int(needed[id]), str(materials.get(id, {}).get("name", id))])
	return "free" if parts.is_empty() else ", ".join(parts)


static func _substat_total(item: Item, rules: ItemRules, stat: String) -> float:
	var total := 0.0
	for index in item.substats.size():
		if item.substats[index]["stat"] == stat:
			total += item.substat_value(index, rules)
	return total * rules.durability_factor(item.durability_ratio())


static func _number(value: float) -> String:
	if absf(value - roundf(value)) < 0.00001: return str(int(roundf(value)))
	if absf(value) < 0.1: return String.num(value, 4).rstrip("0").trim_suffix(".")
	return String.num(snappedf(value, 0.1), 1)


static func base_text(item: Item, rules: ItemRules) -> String:
	var base := item.base_value(rules)
	var text := "Base %s  %s" % [STAT_LABELS.get(item.main_stat, item.main_stat), _number(base)]
	var bonus := item.main_value(rules) - base
	if bonus > 0.0:
		text += " (+%s)" % _number(bonus)
	var mobility := mobility_text(item,rules)
	return text + ("\n"+mobility if not mobility.is_empty() else "")


static func base_label(item: Item, rules: ItemRules) -> Label:
	var label := InkUi.label(base_text(item, rules), InkUi.GOLD, InkUi.FONT_HEADING)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bold := FontVariation.new()
	bold.base_font = InkUi.FONT
	bold.variation_embolden = 1.0
	label.add_theme_font_override("font", bold)
	return label


static func substat_text(item: Item, rules: ItemRules, index: int) -> String:
	var sub: Dictionary = item.substats[index]
	var factor := rules.durability_factor(item.durability_ratio())
	var bonus := float(sub.get("upgrade_bonus", 0.0)) * factor
	var base := item.substat_value(index, rules) * factor - bonus
	var text := "%s  +%s" % [STAT_LABELS.get(sub.stat, sub.stat), _number(base)]
	if bonus > 0.0: text += " (+%s)" % String.num(bonus, 4).rstrip("0").trim_suffix(".")
	return text


static func mobility_text(item: Item,rules: ItemRules) -> String:
	var kind := str(rules.catalog.entry(item.item_id).get("armor_class",""))
	if kind.is_empty(): return ""
	var config: Dictionary=rules.mobility
	var penalty := 100.0*float(config.get("slot_weights",{}).get(item.slot,0))*float(config.get("armor_penalties",{}).get(kind,0))
	return "%s · เดิน/วิ่ง −%s%% · ระยะแดช −%s%%" % [{"heavy":"เกราะหนัก","light":"เกราะเบา","cloth":"เกราะผ้า"}.get(kind,kind),_number(penalty),_number(penalty)]
