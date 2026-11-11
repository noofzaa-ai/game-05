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

const NAME_MIN := 2
const NAME_MAX := 16

## The catalog items the starter gear is (data/items/catalog.json); a missing one is a plain piece.
const STARTER_LOOKS := {"weapon": "blade_01", "shirt": "scout_vest", "shoes": "scout_boots"}

var vault: Inventory = Inventory.new(0)  ## Storage NPC bank; old profiles start empty
var stash: Inventory
var loadout: Loadout
var camp_level := 1
var diamonds := int(preload("res://logic/mall.gd").config().initial_diamonds)
var mall_owned: Array = []
var farm: Dictionary = {}
var facility_levels: Dictionary = {}  ## facility id -> built level (0 = not built)
## The character's own looks: part -> chosen id (logic/cosmetic_options.gd); a missing part = its default.
var relics: Dictionary = preload("res://logic/relics.gd").initial()
var appearance: Dictionary = {}
var armor_migration_version := 0
var starter_armor_kit_version := 0
var starter_weapon_kit_version := 0
var beta_kit_version := 0
var bonus_stash_slots := 0
var skill_build: Dictionary = {}  ## IDs only; validated by skill_build.gd on the authority.
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
	profile.loadout = Loadout.new(item_rules)
	profile.facility_levels = camp.start_levels.duplicate()
	profile.stash.gold = int(camp.starter.get("gold", 0))
	for id in camp.starter.get("materials", {}):
		profile.stash.add_material(str(id), int(camp.starter["materials"][id]))
	profile.loadout.equip(ItemSystem.create_item(item_rules, "starter-weapon", "weapon", 1, rng, "blade", STARTER_LOOKS["weapon"]))
	profile.loadout.equip(ItemSystem.create_item(item_rules, "starter-shirt", "shirt", 2, rng, "", STARTER_LOOKS["shirt"]))
	profile.loadout.equip(ItemSystem.create_item(item_rules, "starter-shoes", "shoes", 0, rng, "", STARTER_LOOKS["shoes"]))
	profile.ensure_starter_weapons(item_rules, rng)
	profile.ensure_starter_armor(item_rules, rng)
	profile.armor_migration_version = 2
	profile.skill_build = preload("res://logic/skill_build.gd").initial("blade")
	return profile


## One starter per missing weapon family, once per account. Earned gear is never removed.
func ensure_starter_weapons(item_rules: ItemRules, rng: RandomNumberGenerator) -> void:
	if starter_weapon_kit_version >= 1:
		return
	var owned := {}
	var equipped_weapon = loadout.item_at("weapon", 0)
	if equipped_weapon != null and not equipped_weapon.destroyed:
		owned[equipped_weapon.weapon_type] = true
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
	for item in loadout.items():
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


## Wears the stash item at `stash_index` in its slot (position `slot_index` for paired slots). The
## piece that was there goes back to the stash. Returns false if it cannot be done.
func equip_from_stash(stash_index: int, slot_index: int = 0) -> bool:
	if stash_index < 0 or stash_index >= stash.items.size():
		return false
	var item: Item = stash.items[stash_index]
	var old := loadout.item_at(item.slot, slot_index)
	if not loadout.equip(item, slot_index):
		return false
	stash.items.remove_at(stash_index)
	if old != null:
		stash.items.append(old)  # takes the slot the new item just left, so it always fits
	return true


## Takes a worn piece off into the stash. Returns false if the stash is full or nothing is worn there.
func unequip_to_stash(slot_id: String, slot_index: int = 0) -> bool:
	if loadout.item_at(slot_id, slot_index) == null or stash.free_slots() < 1:
		return false
	stash.items.append(loadout.unequip(slot_id, slot_index))
	return true


func to_dict() -> Dictionary:
	# blink_mode is not a real persisted choice (from_dict always normalizes it back to "auto";
	# logic/commands.gd rejects any other value) - match that here so to_dict()/from_dict() round-trip
	# exactly even for a profile whose appearance was never set up through the character creator.
	var saved_appearance := appearance.duplicate()
	saved_appearance["blink_mode"] = "auto"
	return {"v": 1, "stash": stash.to_dict(), "vault": vault.to_dict(), "loadout": loadout.to_dict(),
		"diamonds": diamonds, "mall_owned": mall_owned.duplicate(), "farm": farm.duplicate(true), "camp_level": camp_level, "facility_levels": facility_levels.duplicate(),
		"appearance": saved_appearance, "name": name, "created": created,
		"armor_migration_version": armor_migration_version, "starter_armor_kit_version": starter_armor_kit_version, "starter_weapon_kit_version": starter_weapon_kit_version, "beta_kit_version": beta_kit_version, "bonus_stash_slots": bonus_stash_slots,
		"skill_build": skill_build.duplicate(true), "relics": relics.duplicate(true), "card_deck": card_deck.duplicate(true)}


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
	p.loadout = Loadout.from_dict(d["loadout"], item_rules)
	if p.stash == null or p.loadout == null:
		return null
	p.camp_level = int(d["camp_level"])
	p.farm = d.get("farm",{}).duplicate(true)
	for key in d["facility_levels"]:
		p.facility_levels[str(key)] = int(d["facility_levels"][key])
	# Adopt the new baseline only for missing/unbuilt core facilities. Preserve earned levels.
	for id in camp.progression_facilities:
		p.facility_levels[id] = maxi(1, int(p.facility_levels.get(id, 0)))
	p.appearance = d["appearance"].duplicate()
	p.appearance["blink_mode"] = "auto"
	p.diamonds = int(d.get("diamonds",p.diamonds))
	if p.diamonds < 0: return null
	if not d.get("mall_owned",[]) is Array: return null
	p.mall_owned.assign(d.get("mall_owned",[]))
	# Existing equipped cosmetics remain owned; the introductory balance is granted once.
	if not d.has("mall_owned"):
		for part in ["fashion","fashion_hat","fashion_back"]:
			var id := str(p.appearance.get(part,"none"))
			if id != "none": p.mall_owned.append(part+":"+id)
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
	if d.has("skill_build"):
		if not d.skill_build is Dictionary: return null
		p.skill_build = d.skill_build.duplicate(true)
		if p.skill_build.has("v"): p.skill_build["v"] = int(p.skill_build["v"])  # plain JSON loses int vs float
	else:
		var weapon = p.loadout.item_at("weapon", 0)
		p.skill_build = preload("res://logic/skill_build.gd").initial(weapon.weapon_type if weapon != null else "")
	return p
