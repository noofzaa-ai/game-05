extends RefCounted
## Equipment TIER-UP (Boss 2026-11-16; design/gdd/race-gear-sets.md "Tier-up path"). Replaces the old substat Upgrade
## (logic/upgrade.gd is retired). A level-1 piece (a starter piece, instance id "starter-...") becomes the level-15
## piece of its slot for the card that holds it: the weapon of the CARD's race x class, class armour of the card's class.
## Paths, cost and the on/off switch are data (data/items/tier_up.json). Kept exactly: tier, durability ratio, refine
## level, enhancement level, substats, upgrade counter, socketed relic. The instance id changes (no "starter-" prefix,
## so the card-level gate of the equip command now applies to the piece).
##
## Reasons: not_configured, not_eligible, already_level (the piece is already level 15), no_card, wrong_weapon_family, wrong_armour_class, slot_closed,
## card_level_too_low, not_enough_gold. (stash_full never happens: the piece is changed in place, it takes no slot.)
const Profile := preload("res://logic/profile.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const CardProgress := preload("res://logic/card_progress.gd")

const CONFIG_PATH := "res://data/items/tier_up.json"
const NEW_ID_PREFIX := "tier-up-"


## data/items/tier_up.json, {} if missing or broken.
static func config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return data if data is Dictionary else {}


## The card (class id) wearing `item`, "" when it is not worn.
static func wearing_card(p, item) -> String:
	for card in p.card_gear:
		var worn = p.card_gear[card]["loadout"]
		if worn != null and worn.items().has(item):
			return str(card)
	return ""


## The level the piece counts as: a starter piece is level 1, anything else its catalog req_level.
static func piece_level(item, rules) -> int:
	return 1 if str(item.id).begins_with(Profile.STARTER_ID_PREFIX) else rules.catalog.req_level(item.item_id)


## What tier-up would do to `item` for card `card_hint` (used when the piece is not worn; a worn piece uses its wearer).
## {"ok", "reason", "card", "target" (catalog id or ""), "cost" (gold), "need_level", "card_level"}; ok = may be done now.
## "reason" is "" when ok. The UI shows target/need_level/card_level/cost even when it is refused.
static func quote(p, rules, item, card_hint: String = "") -> Dictionary:
	var out := {"ok": false, "reason": "not_eligible", "card": "", "target": "", "cost": 0, "need_level": 0, "card_level": 0, "main_mul": 1.0}
	var cfg := config()
	if cfg.is_empty() or not bool(cfg.get("enabled", false)) or not cfg.get("paths") is Dictionary:
		out["reason"] = "not_configured"
		return out
	out["cost"] = int(cfg.get("cost_gold", 0))
	if item == null or item.destroyed or not (cfg["paths"] as Dictionary).has(item.slot):
		return out
	var card := wearing_card(p, item)
	if card.is_empty():
		card = card_hint
	if card.is_empty() or not p.has_card(card) or not CardDeck.has_race(p.card_deck, card):
		out["reason"] = "no_card"
		return out
	out["card"] = card
	out["card_level"] = CardProgress.level_of(p.card_deck, card)
	var target := str(cfg["paths"][item.slot]).format({"race": CardDeck.race_of(p.card_deck, card), "class": card})
	if rules.catalog.entry(target).is_empty() or str(rules.catalog.entry(target).get("slot", "")) != item.slot:
		return out
	out["target"] = target
	out["need_level"] = rules.catalog.req_level(target)
	out["main_mul"] = rules.catalog.level_mul(int(out["need_level"]))  ## the main stat gain shown to the player
	var problem := Profile.slot_problem(card, item, rules)  # the piece must be one this card can wear at all
	if not problem.is_empty():
		out["reason"] = problem
		return out
	if piece_level(item, rules) >= int(out["need_level"]):
		out["reason"] = "already_level"  # already the level-15 piece (or higher): the UI says just that
		return out
	if int(out["card_level"]) < int(out["need_level"]):
		out["reason"] = "card_level_too_low"
		return out
	if p.stash.gold < int(out["cost"]):
		out["reason"] = "not_enough_gold"
		return out
	out["ok"] = true
	out["reason"] = ""
	return out


## Does it. {"ok": true, "item": new id, "from": old id, "item_id", "card", "cost"} or {"ok": false, "reason"}.
static func apply(p, rules, item, card_hint: String = "") -> Dictionary:
	var offer := quote(p, rules, item, card_hint)
	if not offer["ok"]:
		return {"ok": false, "reason": offer["reason"]}
	var old_id: String = item.id
	var taken := {}
	for list in p.worn_lists() + [p.stash.items, p.vault.items]:
		for other in list:
			taken[other.id] = true
	var base := NEW_ID_PREFIX + old_id.trim_prefix(Profile.STARTER_ID_PREFIX)
	var new_id := base
	var n := 2
	while taken.has(new_id):
		new_id = "%s-%d" % [base, n]
		n += 1
	var entry: Dictionary = rules.catalog.entry(offer["target"])
	p.stash.gold -= int(offer["cost"])
	item.id = new_id
	item.item_id = str(offer["target"])
	if item.slot == "weapon":
		item.weapon_type = str(entry.get("weapon_type", item.weapon_type))
	if not str(entry.get("main_stat", "")).is_empty():
		item.main_stat = str(entry["main_stat"])
	return {"ok": true, "item": new_id, "from": old_id, "item_id": item.item_id, "card": offer["card"], "cost": int(offer["cost"])}
