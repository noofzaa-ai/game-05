extends RefCounted
## One trip into a stage. The player carries a run bag; what monsters drop goes into it at once, but
## it only becomes the player's (moves to the camp stash) when they bring it back to camp. If the
## player dies, carried loot is secured in the camp stash (worn gear still wears down). Pure rules: the
## simulation (game_sim.gd) calls loot_into_bag() and death() as things happen in the stage.
## EXTENDING: rest points (re-organise mid-stage, heal, retreat) are more functions here.

const CampData := preload("res://logic/camp_data.gd")
const Camp := preload("res://logic/camp.gd")
const Inventory := preload("res://logic/inventory.gd")
const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")
const Loadout := preload("res://logic/loadout.gd")
const Profile := preload("res://logic/profile.gd")
const Stats := preload("res://logic/stats.gd")

var profile: Profile
var camp: CampData
var bag: Inventory
var died := false
var used_rests: Array[String] = []  ## rest points already used on this trip
var skill_cooldowns: Dictionary = {}  ## remaining seconds, carried across maps in the same run


static func start(player: Profile, camp_data: CampData) -> RefCounted:
	var run = load("res://logic/run.gd").new()
	run.profile = player
	run.camp = camp_data
	var stacks := {}
	for id in camp_data.materials:
		stacks[id] = camp_data.materials[id]["stack"]
	run.bag = Inventory.new(Camp.bag_slots(player, camp_data), stacks)
	return run


func loadout() -> Loadout:
	return profile.loadout



## The character's stats for this run: worn gear (as worn down) plus the camp skills.
func stats(item_rules: ItemRules) -> Dictionary:
	var totals := Stats.totals(item_rules, loadout().items())
	var bonus := Camp.skill_bonus(profile, camp)
	for stat in bonus:
		totals[stat] = float(totals.get(stat, 0.0)) + float(bonus[stat])
	return totals


## Puts a drop ({"gold", "materials", "items"} from Loot.roll) in the bag. What does not fit is lost
## on the ground. Returns {"gold", "materials": stored, "items": stored, "lost_items": Array[Item],
## "lost_materials": {id: count}}.
func loot_into_bag(drop: Dictionary) -> Dictionary:
	var result := {"gold": int(drop["gold"]), "materials": {}, "items": [], "lost_items": [], "lost_materials": {}}
	bag.gold += int(drop["gold"])
	for id in drop["materials"]:
		var wanted := int(drop["materials"][id])
		var added := bag.add_material(str(id), wanted)
		if added > 0:
			result["materials"][id] = added
		if added < wanted:
			result["lost_materials"][id] = wanted - added
	for item in drop["items"]:
		if bag.add_item(item):
			result["items"].append(item)
		else:
			result["lost_items"].append(item)
	return result


## Throws away the bag item at `index` (a player choice). Returns false if there is none.
func discard_item(index: int) -> bool:
	return bag.take_item(index) != null


## Wears the bag item at `bag_index`; the piece that was there goes into the bag.
func equip_from_bag(bag_index: int, slot_index: int = 0) -> bool:
	if bag_index < 0 or bag_index >= bag.items.size():
		return false
	var item: Item = bag.items[bag_index]
	var old := loadout().item_at(item.slot, slot_index)
	if not loadout().equip(item, slot_index):
		return false
	bag.items.remove_at(bag_index)
	if old != null:
		bag.items.append(old)
	return true


## Takes a worn piece off into the run bag (at a rest point). Allowed only while the bag has a free
## slot. Returns {"ok": bool, "reason": String}; reasons: "nothing_worn" (the slot position is empty),
## "bag_full" (no free slot), "trip_over" (the player has fallen).
func unequip_to_bag(slot_id: String, slot_index: int = 0) -> Dictionary:
	if died:
		return {"ok": false, "reason": "trip_over"}
	if loadout().item_at(slot_id, slot_index) == null:
		return {"ok": false, "reason": "nothing_worn"}
	if bag.free_slots() < 1:
		return {"ok": false, "reason": "bag_full"}
	bag.items.append(loadout().unequip(slot_id, slot_index))
	return {"ok": true, "reason": ""}


## A rest point works once per trip.
func rest_available(point_id: String) -> bool:
	return not died and not used_rests.has(point_id)


## Death secures carried loot in the stash, including overflow; returns zero losses.
## Repeated finalization must never grant the same loot twice.
func death() -> Dictionary:
	if died:
		return {"items": 0, "gold": 0, "materials": {}}
	died = true
	profile.stash.gold += bag.gold
	profile.stash.items.append_array(bag.items)
	for id in bag.materials:
		profile.stash.materials[id] = profile.stash.material_count(str(id)) + int(bag.materials[id])
	# Preserve earned loot even when the normal stash capacity was already full.
	profile.stash.capacity = maxi(profile.stash.capacity, profile.stash.slots_used())
	bag.clear_loot()
	return {"items": 0, "gold": 0, "materials": {}}


## Brings the bag back to camp: gold and whatever fits (materials, then equipment) move to the
## stash. Anything that does not fit stays in the bag for the player to sort out. A run that ended in
## death has already secured its loot in the stash.
## Returns {"gold": int, "materials": {id: count}, "items": int, "left_items": int, "left_materials": {id: count}}.
func return_to_camp() -> Dictionary:
	var summary := {"gold": bag.gold, "materials": {}, "items": 0, "left_items": 0, "left_materials": {}}
	profile.stash.gold += bag.gold
	bag.gold = 0
	for id in bag.materials.keys():
		var moved := profile.stash.add_material(str(id), bag.material_count(str(id)))
		bag.remove_material(str(id), moved)
		if moved > 0:
			summary["materials"][id] = moved
	while not bag.items.is_empty() and profile.stash.free_slots() >= 1:
		profile.stash.add_item(bag.take_item(0))
		summary["items"] += 1
	summary["left_items"] = bag.items.size()
	summary["left_materials"] = bag.materials.duplicate()
	return summary


func discard_loot() -> Dictionary:
	return bag.clear_loot()

func to_dict(include_profile: bool = true) -> Dictionary:
	var data := {"v": 1, "bag": bag.to_dict(), "died": died, "used_rests": used_rests.duplicate(), "skill_cooldowns":skill_cooldowns.duplicate(true)}
	if include_profile: data["profile"] = profile.to_dict()
	return data


## An optional existing profile preserves shared ownership when restoring a Journey/session.
static func from_dict(d: Dictionary, rules: ItemRules, camp_data: CampData, player = null):
	if int(d.get("v", 0)) != 1:
		return null
	if player == null:
		player = Profile.from_dict(d["profile"], rules, camp_data)
	if player == null:
		return null
	var trip = start(player, camp_data)
	trip.bag = Inventory.from_dict(d["bag"], trip.bag._stack_sizes)
	if trip.bag == null:
		return null
	# A run bag saved before the legacy items were removed (Boss 2026-11-13): its pieces become race pieces of the first
	# squad card's race (logic/legacy_items.gd; no flag needed, a converted piece is never converted again).
	var LegacyItems = preload("res://logic/legacy_items.gd")
	LegacyItems.convert_items(trip.bag.items, rules, LegacyItems.first_race(player.card_deck))
	# Relics were removed (Boss 2026-11-14): a run saved before that may still hold "relic_loot"; it is ignored.
	trip.died = bool(d["died"])
	trip.used_rests.assign(d["used_rests"])
	trip.skill_cooldowns = d.get("skill_cooldowns",{}).duplicate(true)
	return trip
