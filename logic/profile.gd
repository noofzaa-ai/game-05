extends RefCounted
## Everything a player owns for good: the camp stash (and the gold in it), what the character is
## wearing, the camp level and the level of each facility. What is in a run bag is NOT here until the
## player brings it back to camp (see run.gd). Pure data plus the camp-side moves of equipment.
## EXTENDING: saved player data (unlocked stages, cosmetics) are new fields here; saving and loading
## the profile is a server job (the client never talks to the database).

const CampData := preload("res://logic/camp_data.gd")
const Inventory := preload("res://logic/inventory.gd")
const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")
const CardDeck := preload("res://logic/card_deck.gd")

## Appearance parts of the removed old-model fashion and face / hair-style lists (Boss 2026-11-13); dropped from saves on load.
const LEGACY_FASHION_PARTS: Array[String] = ["face", "hair_style", "hair_color", "fashion", "fashion_display", "fashion_hat", "fashion_back", "wear_shirt", "wear_pants", "wear_shoes", "wear_head", "wear_hair", "wear_mask"]

const NAME_MIN := 2
const NAME_MAX := 16

## The catalog items the starter gear is (data/items/catalog.json); a missing one is a plain piece.
const STARTER_LOOKS := {"weapon": "blade_01", "shirt": "scout_vest", "shoes": "scout_boots"}

var vault: Inventory = Inventory.new(0)  ## Storage NPC bank; old profiles start empty
var stash: Inventory
## Per-card gear (Boss 2026-11-11, docs/tech/per_card_gear_plan.md): class id -> {"loadout": Loadout,
## }. Each class card wears its own equipment slots (an old save's per-card "skill_build" is dropped on load);
## stash, vault, gold and materials stay shared by the whole account. An item is in the stash/vault OR worn
## by exactly one card (logic/commands.gd rejects any id seen twice).
var card_gear: Dictionary = {}
## Transition stand-in (until plan step 7): the lead card's worn gear (lead_card()). The sim,
## runs and online rooms still read this; per-card code uses loadout_of(card).
var loadout: Loadout:
	get:
		var gear = card_gear.get(lead_card())
		return gear["loadout"] if gear != null else null
	set(value):
		_lead_gear()["loadout"] = value
var camp_level := 1
var diamonds := int(preload("res://logic/mall.gd").config().initial_diamonds)
## Mall pieces owned, one "part:id" entry per purchase (logic/mall.gd). Only parts the Mall still sells are
## kept: the old fashion copies are refunded on load (Boss 2026-11-13, Mall.refund_legacy).
var mall_owned: Array = []
var farm: Dictionary = {}
var facility_levels: Dictionary = {}  ## facility id -> built level (0 = not built)
## The character's own looks: part -> chosen id (logic/cosmetic_options.gd); a missing part = its default.
var relics: Dictionary = preload("res://logic/relics.gd").initial()
var appearance: Dictionary = {}
var armor_migration_version := 0
var starter_armor_kit_version := 0
var starter_weapon_kit_version := 0
var starter_shield_kit_version := 0  ## 1 = the offhand starter shield was granted (ensure_starter_shields)
var beta_kit_version := 0
## 2 = the old per-run skill tree was turned into card levels (logic/skill_tree.gd migrate_old_builds, skill-tree.md 5).
var tree_migration_version := 0
var bonus_stash_slots := 0
## One class card per class, each customised on its own, plus the squad of the next fight (logic/card_deck.gd).
var card_deck: Dictionary = preload("res://logic/card_deck.gd").initial(preload("res://logic/cosmetic_options.gd").load_default())
var name := ""  ## the character's name, set when the player creates the character
var created := false  ## false until the player has made the character (the game opens the creator first)


## A brand new player: the starter gold and materials, a small starting set of gear worn, and the
## facilities a new camp already has.
static func new_player(item_rules: ItemRules, camp: CampData, rng: RandomNumberGenerator) -> RefCounted:
	var profile = load("res://logic/profile.gd").new()
	var stacks := {}
	for id in camp.materials:
		stacks[id] = camp.materials[id]["stack"]
	profile.stash = Inventory.new(camp.stash_slots, stacks)
	profile.vault = Inventory.new(camp.bank_slots, stacks)
	profile.card_gear["sword_shield"] = {"loadout": Loadout.new(item_rules)}
	profile.facility_levels = camp.start_levels.duplicate()
	profile.stash.gold = int(camp.starter.get("gold", 0))
	for id in camp.starter.get("materials", {}):
		profile.stash.add_material(str(id), int(camp.starter["materials"][id]))
	# The Sword & Shield card wears the original starter set (same ids and rolls as before cards had gear).
	var first: Loadout = profile.card_gear["sword_shield"]["loadout"]
	first.equip(ItemSystem.create_item(item_rules, "starter-weapon", "weapon", 1, rng, "blade", STARTER_LOOKS["weapon"]))
	first.equip(ItemSystem.create_item(item_rules, "starter-shirt", "shirt", 2, rng, "", STARTER_LOOKS["shirt"]))
	first.equip(ItemSystem.create_item(item_rules, "starter-shoes", "shoes", 0, rng, "", STARTER_LOOKS["shoes"]))
	profile.ensure_starter_weapons(item_rules, rng)
	profile.ensure_starter_armor(item_rules, rng)
	profile.ensure_starter_cards(item_rules)
	profile.ensure_starter_shields(item_rules)
	profile.armor_migration_version = 2
	profile.tree_migration_version = 2  # a new player has no old tree to convert
	# Boss 2026-11-13: each new card gets its own eyes and makeup. A child RNG seeded from the creation RNG's
	# state keeps it deterministic per seed without consuming draws the rest of the game relies on.
	var looks_rng := RandomNumberGenerator.new()
	looks_rng.seed = hash([rng.state, "starter_card_looks"])
	CardDeck.vary_starter_looks(profile.card_deck, preload("res://logic/cosmetic_options.gd").load_default(), looks_rng)
	return profile


## The card the transition stand-in (`loadout`) and card-less commands use: the Sword & Shield
## card, which holds the account's pre-card gear and build. Fixed (not squad[0]) so the online rooms and
## the sim, which still read `loadout` until plan step 4, see the same character whatever
## order the squad is in.
const LEAD_CARD := "sword_shield"


func lead_card() -> String:
	return LEAD_CARD


func _lead_gear() -> Dictionary:
	var card := lead_card()
	if not card_gear.has(card):
		card_gear[card] = {"loadout": null}
	return card_gear[card]


## True when `card` is a class card of this profile that has its own gear.
func has_card(card: String) -> bool:
	return card_gear.has(card) and card_deck.get("cards", {}).has(card)


## The card's worn gear (null for an unknown card). "" = the lead card.
func loadout_of(card: String = "") -> Loadout:
	var gear = card_gear.get(lead_card() if card.is_empty() else card)
	return gear["loadout"] if gear != null else null


## Every card's worn entries, destroyed ones included (one Array per card): for id-uniqueness scans.
func worn_lists() -> Array:
	var lists: Array = []
	for card in card_gear:
		if card_gear[card]["loadout"] != null:
			lists.append(card_gear[card]["loadout"]._equipped.values())
	return lists


## Every item any card wears that still exists.
func worn_items() -> Array:
	var worn: Array = []
	for card in card_gear:
		if card_gear[card]["loadout"] != null:
			worn.append_array(card_gear[card]["loadout"].items())
	return worn


## The weapon families a class card may hold (data/classes/<id>.json "weapon_families"; Boss 2026-11-11).
## A class file without the list falls back to its combat weapon id.
static func weapon_families(card: String) -> Array:
	var data: Dictionary = CardDeck.class_data(card)
	var families = data.get("weapon_families", [str(data.get("weapon", ""))])
	return families if families is Array else []


## Whether class card `card` may wear `item`: the weapon slot is restricted by class weapon families, and a
## slot listing "classes" in data/items/rules.json (offhand = Sword & Shield only) is closed to other classes.
## Pass the rules to check closed slots (slot_problem tells which rule failed).
static func card_can_wear(card: String, item: Item, item_rules: ItemRules = null) -> bool:
	return slot_problem(card, item, item_rules).is_empty()


## "" when `card` may wear `item`, else "slot_closed" (the class cannot use that slot) or "wrong_weapon_family".
static func slot_problem(card: String, item: Item, item_rules: ItemRules = null) -> String:
	if item_rules != null and not item_rules.slot_open_for(item.slot, card):
		return "slot_closed"
	if item.slot == "weapon" and not weapon_families(card).has(item.weapon_type):
		return "wrong_weapon_family"
	return ""


## The catalog item every class card that can use the offhand slot starts with (Boss 2026-11-11).
const STARTER_SHIELD := "round_shield"


## One-time starter shield (starter_shield_kit_version 1) for every class card whose offhand slot is open and
## empty (new players and old saves alike). Id "starter-offhand-v1-<class>"; fixed seed per class, so every
## authority that migrates the same save makes the same item. Once granted, an emptied slot stays empty.
func ensure_starter_shields(item_rules: ItemRules) -> void:
	if starter_shield_kit_version >= 1 or item_rules.slot("offhand").is_empty():
		return
	for card in CardDeck.classes():
		var worn = loadout_of(card)
		if worn == null or not item_rules.slot_open_for("offhand", card) or worn.item_at("offhand", 0) != null:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("starter-offhand-v1-" + card)
		var shield = ItemSystem.create_item(item_rules, "starter-offhand-v1-" + card, "offhand", 0, rng, "", STARTER_SHIELD)
		if shield != null:
			worn.equip(shield)
	starter_shield_kit_version = 1


static func item_rules_of(worn: Loadout) -> ItemRules:
	return worn.rules if worn != null else null


## One-time starter set for every class card that has no gear yet (new players, migrated saves, a class
## added later): a weapon of the class's first family + the starter shirt and shoes, and the class's initial
## skill build. Ids are "starter-card-v1-<class>-<slot>" (unique across all containers). Rolls use a fixed
## seed per class so every authority that migrates the same save makes the same items.
func ensure_starter_cards(item_rules: ItemRules) -> void:
	for card in CardDeck.classes():
		if card_gear.has(card):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("starter-card-v1-" + card)
		var worn := Loadout.new(item_rules)
		var families := weapon_families(card)
		var family := str(families[0]) if not families.is_empty() else ""
		var looks := {"weapon": family + "_01", "shirt": STARTER_LOOKS["shirt"], "shoes": STARTER_LOOKS["shoes"]}
		var tiers := {"weapon": 1, "shirt": 2, "shoes": 0}
		for slot in ["weapon", "shirt", "shoes"]:
			if slot == "weapon" and family.is_empty():
				continue
			var item = ItemSystem.create_item(item_rules, "starter-card-v1-%s-%s" % [card, slot], slot, tiers[slot], rng, family if slot == "weapon" else "", looks[slot])
			if item != null:
				worn.equip(item)
		var style := str(CardDeck.class_data(card).get("weapon", family))
		card_gear[card] = {"loadout": worn}


## One starter per missing weapon family, once per account. Earned gear is never removed.
func ensure_starter_weapons(item_rules: ItemRules, rng: RandomNumberGenerator) -> void:
	if starter_weapon_kit_version >= 1:
		return
	var owned := {}
	for item in worn_items():
		if item.slot == "weapon":
			owned[item.weapon_type] = true
	for item in stash.items + vault.items:
		if item.slot == "weapon" and not item.destroyed:
			owned[item.weapon_type] = true
	for family in ["blade"]:
		if not owned.has(family):
			stash.items.append(ItemSystem.create_item(item_rules, "starter-kit-v1-" + family, "weapon", 1, rng, family, family + "_01"))
	starter_weapon_kit_version = 1


## Bounded server-owned wardrobe grant, once per account; count worn pieces too.
func ensure_starter_armor(item_rules: ItemRules, rng: RandomNumberGenerator) -> void:
	if starter_armor_kit_version >= 1:
		return
	var owned := {}
	for item in stash.items + vault.items:
		if not item.destroyed:
			owned[item.item_id] = true
	for item in worn_items():
		owned[item.item_id] = true
	var ids: Array = item_rules.catalog.items.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = item_rules.catalog.items[id]
		if str(entry.get("set", "")) in item_rules.catalog.starter_armor_sets and not owned.has(id):
			stash.items.append(ItemSystem.create_item(item_rules, "starter-armor-v1-" + str(id), str(entry["slot"]), 1, rng, "", str(id)))
	starter_armor_kit_version = 1


## What is wrong with `text` as a character name: "" (nothing), "too_short", "too_long" or
## "bad_characters" (letters of any language, digits, spaces, _ and - are allowed; spaces at the ends
## do not count). Whether a name is already taken is the server's job.
static func name_problem(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.length() < NAME_MIN:
		return "too_short"
	if trimmed.length() > NAME_MAX:
		return "too_long"
	var allowed := RegEx.create_from_string("^[\\p{L}\\p{M}\\p{N}_ -]+$")
	if allowed.search(trimmed) == null or trimmed.contains("  "):
		return "bad_characters"
	return ""


## Finishes making the character with this name. Returns the name's problem ("" = done).
func create_character(new_name: String) -> String:
	var problem := name_problem(new_name)
	if problem.is_empty():
		name = new_name.strip_edges()
		created = true
	return problem


## Card `card` ("" = the lead card) wears the stash item at `stash_index` in its slot (position
## `slot_index` for paired slots). The piece that was there goes back to the stash. Returns false if it
## cannot be done (unknown card, bad slot, or a weapon family the card's class cannot hold).
func equip_from_stash(stash_index: int, slot_index: int = 0, card: String = "") -> bool:
	if stash_index < 0 or stash_index >= stash.items.size():
		return false
	var worn := loadout_of(card)
	var item: Item = stash.items[stash_index]
	if worn == null or not card_can_wear(lead_card() if card.is_empty() else card, item, item_rules_of(worn)):
		return false
	var old := worn.item_at(item.slot, slot_index)
	if not worn.equip(item, slot_index):
		return false
	stash.items.remove_at(stash_index)
	if old != null:
		stash.items.append(old)  # takes the slot the new item just left, so it always fits
	return true


## Takes a worn piece off into the stash. Returns false if the stash is full or nothing is worn there.
func unequip_to_stash(slot_id: String, slot_index: int = 0, card: String = "") -> bool:
	var worn := loadout_of(card)
	if worn == null or worn.item_at(slot_id, slot_index) == null or stash.free_slots() < 1:
		return false
	stash.items.append(worn.unequip(slot_id, slot_index))
	return true


func to_dict() -> Dictionary:
	# blink_mode is not a real persisted choice (from_dict always normalizes it back to "auto";
	# logic/commands.gd rejects any other value) - match that here so to_dict()/from_dict() round-trip
	# exactly even for a profile whose appearance was never set up through the character creator.
	var saved_appearance := appearance.duplicate()
	saved_appearance["blink_mode"] = "auto"
	var saved_gear := {}
	for card in card_gear:
		saved_gear[card] = {"loadout": card_gear[card]["loadout"].to_dict()}
	# "loadout" below is the lead card's copy, kept for readers that still need it
	# (server runner/rooms, plaza, admin); plan step 7 removes them. from_dict reads only "card_gear".
	return {"card_gear": saved_gear,
		"v": 1, "stash": stash.to_dict(), "vault": vault.to_dict(), "loadout": loadout.to_dict(),
		"diamonds": diamonds, "mall_owned": mall_owned.duplicate(), "farm": farm.duplicate(true), "camp_level": camp_level, "facility_levels": facility_levels.duplicate(),
		"appearance": saved_appearance, "name": name, "created": created,
		"armor_migration_version": armor_migration_version, "starter_armor_kit_version": starter_armor_kit_version, "starter_weapon_kit_version": starter_weapon_kit_version, "starter_shield_kit_version": starter_shield_kit_version, "beta_kit_version": beta_kit_version, "tree_migration_version": tree_migration_version, "bonus_stash_slots": bonus_stash_slots,
		"relics": relics.duplicate(true), "card_deck": card_deck.duplicate(true)}


static func from_dict(d: Dictionary, item_rules: ItemRules, camp: CampData):
	if int(d.get("v", 0)) != 1:
		return null
	var p = load("res://logic/profile.gd").new()
	var stacks := {}
	for key in camp.materials:
		stacks[key] = int(camp.materials[key]["stack"])
	p.stash = Inventory.from_dict(d["stash"], stacks)
	p.vault = Inventory.from_dict(d["vault"], stacks) if d.has("vault") else Inventory.new(camp.bank_slots, stacks)
	if p.vault == null: return null
	p.vault.capacity = camp.bank_slots
	if p.stash == null:
		return null
	p.camp_level = int(d["camp_level"])
	p.farm = d.get("farm",{}).duplicate(true)
	for key in d["facility_levels"]:
		p.facility_levels[str(key)] = int(d["facility_levels"][key])
	# Adopt the new baseline only for missing/unbuilt core facilities. Preserve earned levels.
	for id in camp.progression_facilities:
		p.facility_levels[id] = maxi(1, int(p.facility_levels.get(id, 0)))
	if not d["appearance"] is Dictionary: return null
	p.appearance = d["appearance"].duplicate()
	p.appearance["blink_mode"] = "auto"
	p.diamonds = int(d.get("diamonds",p.diamonds))
	if p.diamonds < 0: return null
	if not d.get("mall_owned",[]) is Array: return null
	# Old fashion removed (Boss 2026-11-13). Refund rule (logic/mall.gd refund_legacy): every saved copy of a
	# removed part pays back its old Mall price in diamonds, once (the save then holds no such entry). A save
	# from before mall_owned existed (its worn fashion was granted, not bought) gets nothing back.
	var refund: Dictionary = preload("res://logic/mall.gd").refund_legacy(d.get("mall_owned",[]))
	p.mall_owned.assign(refund["kept"])
	p.diamonds += int(refund["diamonds"])
	for part in LEGACY_FASHION_PARTS:
		p.appearance.erase(part)
	p.relics = preload("res://logic/relics.gd").decode(d.get("relics",preload("res://logic/relics.gd").initial()))
	if p.relics.is_empty(): return null
	p.name = str(d["name"])
	p.created = bool(d["created"])
	p.armor_migration_version = maxi(0,int(d.get("armor_migration_version",0)))
	p.starter_armor_kit_version = maxi(0, int(d.get("starter_armor_kit_version", 0)))
	p.starter_weapon_kit_version = maxi(0, int(d.get("starter_weapon_kit_version", 0)))
	p.beta_kit_version = maxi(0, int(d.get("beta_kit_version", 0)))
	p.bonus_stash_slots = clampi(int(d.get("bonus_stash_slots", 0)), 0, 1000)
	p.card_deck = preload("res://logic/card_deck.gd").repaired(d.get("card_deck"), preload("res://logic/cosmetic_options.gd").load_default())  # old saves get the starter cards
	var old_builds := {}  ## card -> the save's old skill_build (dropped after the level migration below)
	if d.has("card_gear"):
		if not d.card_gear is Dictionary: return null
		for card in d.card_gear:
			var entry = d.card_gear[card]
			if not entry is Dictionary or not entry.get("loadout") is Dictionary: return null
			var worn = Loadout.from_dict(entry["loadout"], item_rules)
			if worn == null: return null
			if entry.has("skill_build") and not entry["skill_build"] is Dictionary and entry["skill_build"] != null: return null
			p.card_gear[str(card)] = {"loadout": worn}  # a class no longer in data keeps its gear
			old_builds[str(card)] = entry.get("skill_build")  # the deleted per-card build: only the one-time level migration reads it
	else:
		# Migration (Boss 2026-11-11): the account's old worn gear and skill build go to the Sword & Shield card.
		if not d.get("loadout") is Dictionary: return null
		var worn = Loadout.from_dict(d["loadout"], item_rules)
		if worn == null: return null
		if d.has("skill_build") and not d["skill_build"] is Dictionary and d["skill_build"] != null: return null
		p.card_gear["sword_shield"] = {"loadout": worn}
		old_builds["sword_shield"] = d.get("skill_build")
	p.ensure_starter_cards(item_rules)  # the other cards (or a class added later) get a starter set once
	p.starter_shield_kit_version = maxi(0, int(d.get("starter_shield_kit_version", 0)))
	p.ensure_starter_shields(item_rules)  # old saves: the Sword & Shield card gets its starter shield once
	p.tree_migration_version = maxi(0, int(d.get("tree_migration_version", 0)))
	if p.tree_migration_version < 2:  # once: old per-run tree points become card levels (skill-tree.md 5)
		preload("res://logic/skill_tree.gd").migrate_old_builds(old_builds, p.card_deck)
		p.tree_migration_version = 2
	return p


