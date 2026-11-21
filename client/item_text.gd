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
	return InkUi.rarity_color(rarity_key(item, rules))


## True for a boss-drop piece (catalog "boss" set: the boss sets and the boss weapons, Boss 2026-11-21).
static func is_boss_piece(item_id: String, rules: ItemRules) -> bool:
	return not str(rules.catalog.entry(item_id).get("boss", "")).is_empty()


## The rarity colour key of a piece: "boss" (boss gold) for a boss-drop piece whatever its tier, else the tier's key.
static func rarity_key(item: Item, rules: ItemRules) -> String:
	return rarity_key_for(item.item_id, item.tier, rules)


## The tier a piece shows: the top tier for a boss-drop piece (logic/boss_loot.gd shown_tier), else its own.
static func shown_tier(item: Item, rules: ItemRules) -> int:
	return load("res://logic/boss_loot.gd").shown_tier(rules, item.item_id, item.tier)


static func rarity_key_for(item_id: String, tier: int, rules: ItemRules) -> String:
	if is_boss_piece(item_id, rules):
		return InkUi.RARITY_BOSS
	return str(rules.tiers[clampi(tier, 0, rules.tiers.size() - 1)]["color"])


## The boss option of catalog item `item_id` in words ("" when it has none): "Boss option: 10% on hit: Weaken 3s
## (cooldown 8s)". Numbers from data/items/boss_options.json (logic/boss_procs.gd); words from client/card_tokens.gd.
static func boss_option_text(item_id: String) -> String:
	var BossProcs = load("res://logic/boss_procs.gd")
	var option: Dictionary = BossProcs.option(item_id)
	if option.is_empty():
		return ""
	var Tokens = load("res://client/card_tokens.gd")
	var name := str(BossProcs.status_name(str(option["status"]))[0 if Tokens.language == "th" else 1])
	return Tokens.t("boss_option") % [_number(float(option["chance"])), name, _number(float(option["duration"]) / 60.0), _number(float(option["icd"]) / 60.0)]


## "Rare Golden Blossom Katana  +3": a catalog item's own name; a plain piece is named by its weapon
## type (weapons) or its slot.
static func title(item: Item, rules: ItemRules, weapon_names: Dictionary = {}) -> String:
	var kind: String = item.slot.capitalize()
	var base: Dictionary = rules.catalog.entry(item.item_id)
	if not base.is_empty():
		kind = base["name"]
	elif item.slot == "weapon" and not item.weapon_type.is_empty():
		kind = str(weapon_names.get(item.weapon_type, item.weapon_type.capitalize()))
	var text := "%s %s" % [str(rules.tiers[shown_tier(item, rules)]["id"]).capitalize(), kind]
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


## The race gear set block (design/gdd/race-gear-sets.md 3.15) for `item` worn by a card of `race` x `class_id` wearing
## `worn_items` (Item objects): [{"text", "on"}], first the header "Viking War Gear 3/5", then one line per step
## ("2 pcs Kindled [on, rare]: ..."), then "Set option inactive: needs Viking" when the race does not match.
## [] for an item that is not a race piece. The on/off state and tier are written as words (not colour only).
## The numbers come from logic/race_sets.gd; strings from client/card_tokens.gd.
static func race_set_lines(item: Item, rules: ItemRules, worn_items: Array, race: String, class_id: String) -> Array:
	var Tokens = load("res://client/card_tokens.gd")
	var set_id: String = rules.catalog.entry(item.item_id).get("set", "")
	var info: Dictionary = rules.catalog.sets.get(set_id, {})
	if str(info.get("kind", "")) != "race":
		return []
	var items: Array = worn_items.filter(func(worn): return worn != null and rules.catalog.entry(worn.item_id).get("set", "") == set_id)
	if not items.any(func(worn): return worn.id == item.id):
		items.append(item)  # a piece in the stash: show the set as if it were worn
	var entry: Dictionary = {}
	for status in preload("res://logic/race_sets.gd").status(rules, items, race, class_id):
		if status["set_id"] == set_id:
			entry = status
	if entry.is_empty():
		return []
	var thai: bool = Tokens.language == "th"
	var name := str(info.get("name_th", info.get("name", set_id))) if thai else str(info.get("name", set_id))
	var lines: Array = [{"text": Tokens.t("set_race_line") % [name, int(entry["count"]), int(entry["total"])], "on": bool(entry["matched"])}]
	for step in entry["steps"]:
		var state: String = Tokens.t("set_step_on") if step["active"] else Tokens.t("set_step_off")
		lines.append({"text": Tokens.t("set_race_step") % [int(step["pieces"]), str(step["name"]), state, str(step["tier"]), str(step["text"])], "on": bool(step["active"])})
	if not bool(entry["matched"]):
		lines.append({"text": Tokens.t("set_needs_race") % Tokens.race_name(str(entry["race"])), "on": false})
	return lines


## The boss set block for `item` worn with `worn_items` (Item objects): [{"text", "on"}], the header "Mummy High Wizard's
## Regalia 3/6" then one line per step ("2 pcs Curse of the Sands [on, rare]: ATK +6%."). [] for a piece of no boss set.
## Numbers from logic/boss_loot.gd set_status; words from client/card_tokens.gd (the race set lines' format).
static func boss_set_lines(item: Item, rules: ItemRules, worn_items: Array) -> Array:
	var Tokens = load("res://client/card_tokens.gd")
	var set_id: String = rules.catalog.entry(item.item_id).get("set", "")
	var info: Dictionary = rules.catalog.sets.get(set_id, {})
	if str(info.get("kind", "")) != "boss":
		return []
	var items: Array = worn_items.filter(func(worn): return worn != null and rules.catalog.entry(worn.item_id).get("set", "") == set_id)
	if not items.any(func(worn): return worn.id == item.id):
		items.append(item)  # a piece in the stash: show the set as if it were worn
	var entry: Dictionary = {}
	for status in load("res://logic/boss_loot.gd").set_status(rules, items):
		if status["set_id"] == set_id:
			entry = status
	if entry.is_empty():
		return []
	var lines: Array = [{"text": Tokens.t("set_race_line") % [str(info.get("name", set_id)), int(entry["count"]), int(entry["total"])], "on": true}]
	for step in entry["steps"]:
		var state: String = Tokens.t("set_step_on") if step["active"] else Tokens.t("set_step_off")
		lines.append({"text": Tokens.t("set_race_step") % [int(step["pieces"]), str(step["name"]), state, str(step["tier"]), str(step["text"])], "on": bool(step["active"])})
	return lines


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
