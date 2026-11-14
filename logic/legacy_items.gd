extends RefCounted
## One-time conversion of the old game's items in a save (Boss 2026-11-13: "remove everything from the old item system";
## docs/po_defaults.md "Remove legacy item system"). The catalog now holds only race gear (tools/items/build_race_gear.py),
## so a saved piece whose item_id the catalog no longer knows (blade_01..07, the Ash/Obsidian/Royal armour, the neutral
## starter_* pieces, round_shield, the older scout/aegis/knight/sentinel ids, plain armour with no id) becomes the race
## piece of the SAME slot and tier. Kept as they are: the instance id, tier, enhancement level, refine level, upgrade
## count, every substat (quality, boosts, upgrade bonus), durability and the destroyed flag. Changed: item_id, and the
## main stat / weapon type to the new catalog piece's (the same per slot as the old armour after armor_migration v2).
## Race: the wearing card's race; an unworn piece (stash, vault, run bag) takes the first squad card's race.
## Class (whose look and set the piece is): a worn piece takes the wearing card's class (so it still fits that card); an
## unworn weapon takes the class of its weapon family, unworn armour the class of its old armour weight (frozen below).
## A PLAIN piece (item_id "", made before the catalog) of these slots converts only in the flagged profile pass: the run-bag
## pass (no flag) leaves plain pieces alone, since a plain piece still made today (a rule book with an empty catalog,
## tests) must round-trip unchanged.
## Pure rules, no RNG: every authority converting the same save makes the same items. Idempotent: a converted piece is a
## catalog item, so a second pass changes nothing (safe for saves that lose the version flag on the way).

const CardDeck := preload("res://logic/card_deck.gd")

const VERSION := 1  ## Profile.legacy_item_version after the conversion
## The slots whose legacy pieces have a race piece.
const ARMOR_SLOTS: Array[String] = ["shirt", "pants", "armband", "shoes"]
## Frozen from the last catalog with legacy items (git fdf9fbb data/items/catalog.json): weapon family -> class.
## Weapon types no class holds any more (fists, dagger, ...) count as the Sword & Shield blade.
const WEAPON_CLASS := {"blade": "sword_shield", "greatsword": "greatsword", "longbow": "longbow", "magic": "magic"}
## Frozen: old armour weight -> the class whose race armour has that weight (heavy: Sword & Shield, also Greatsword).
const WEIGHT_CLASS := {"heavy": "sword_shield", "light": "longbow", "cloth": "magic"}
## Frozen: the weight token in an old armour id (armor_<style>_<token>_<slot>, starter_<token>_<slot>). An id with no
## token here (scout_vest, aegis_cuirass, knight_*, sentinel_*, a plain piece) was heavy (armor_migration v2 mapped it
## to Ash Knight steel or Obsidian/Royal gold).
const WEIGHT_TOKENS := {"_steel_": "heavy", "_gold_": "heavy", "_heavy_": "heavy", "_leather_": "light", "_light_": "light", "_cloth_": "cloth"}


## Converts every legacy piece the profile holds (each card's worn gear, the stash, the vault) once, then sets
## profile.legacy_item_version. Returns how many pieces changed.
static func convert_profile(profile, rules) -> int:
	if int(profile.legacy_item_version) >= VERSION:
		return 0
	var changed := 0
	for card in profile.card_gear:
		var worn = profile.card_gear[card]["loadout"]
		if worn == null:
			continue
		var race := CardDeck.gear_race(profile.card_deck, str(card))
		for item in worn._equipped.values():
			if convert_item(item, rules, race, str(card), true):
				changed += 1
	for bag in [profile.stash, profile.vault]:
		changed += convert_items(bag.items, rules, first_race(profile.card_deck), true)
	profile.legacy_item_version = VERSION
	return changed


## Unworn pieces (stash, vault, a saved run bag) with `race`. Returns how many changed.
static func convert_items(items: Array, rules, race: String, include_plain: bool = false) -> int:
	var changed := 0
	for item in items:
		if convert_item(item, rules, race, "", include_plain):
			changed += 1
	return changed


## The race of the first squad card (else the first class card): the race of an unworn legacy piece.
static func first_race(deck: Dictionary) -> String:
	var squad: Array = deck.get("squad", [])
	var card := str(squad[0]) if not squad.is_empty() else str(CardDeck.classes()[0])
	return CardDeck.gear_race(deck, card)


## True when `item` is a legacy piece (its slot has race pieces, its item_id is not a catalog item; a plain piece with
## item_id "" only when `include_plain`).
static func is_legacy(item, rules, include_plain: bool = false) -> bool:
	if item == null or not rules.catalog.entry(item.item_id).is_empty() or (item.item_id.is_empty() and not include_plain):
		return false
	return item.slot == "weapon" or item.slot == "offhand" or ARMOR_SLOTS.has(item.slot)


## The race piece id a legacy `item` becomes for `race` (worn by class `card`, "" = unworn); "" when none.
static func target(item, rules, race: String, card: String) -> String:
	if item.slot == "offhand":
		return rules.catalog.race_shield(race)
	var class_id := card
	if class_id.is_empty() or not WEAPON_CLASS.values().has(class_id):
		class_id = str(WEAPON_CLASS.get(item.weapon_type, "sword_shield")) if item.slot == "weapon" else str(WEIGHT_CLASS[weight_of(item.item_id)])
	return rules.catalog.race_piece(race, class_id, item.slot)


## The old armour weight of a legacy id (frozen WEIGHT_TOKENS; default heavy).
static func weight_of(old_id: String) -> String:
	for token in WEIGHT_TOKENS:
		if ("_" + old_id + "_").contains(token):
			return str(WEIGHT_TOKENS[token])
	return "heavy"


## Turns a legacy `item` into its race piece in place. Returns false for a catalog item or no target.
static func convert_item(item, rules, race: String, card: String, include_plain: bool = false) -> bool:
	if not is_legacy(item, rules, include_plain):
		return false
	var piece_id := target(item, rules, race, card)
	var entry: Dictionary = rules.catalog.entry(piece_id)
	if entry.is_empty() or str(entry["slot"]) != item.slot:
		return false
	item.item_id = piece_id
	if not str(entry.get("main_stat", "")).is_empty():
		item.main_stat = str(entry["main_stat"])
	item.weapon_type = str(entry["weapon_type"]) if item.slot == "weapon" else ""
	return true
