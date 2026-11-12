extends RefCounted
## A bag: a limited number of slots holding equipment (one piece per slot), plus gold and materials,
## which take no slot (Boss 2026-11-13: materials are an unlimited counter per material id; only items
## use slots). The run bag a player carries into a stage and the camp stash are both Inventories.
## Old saves need no migration: `materials` was always saved as {id: count}; it simply stops filling slots.
## EXTENDING: new kinds of things to carry (potions, keys) are new arrays here and a rule in slots_used().

const Item := preload("res://logic/item.gd")

const DEFAULT_STACK := 99
const MATERIAL_MAX := 1_000_000_000  ## a safety ceiling for one material's counter (effectively unlimited)

var capacity := 0  ## number of slots
var items: Array[Item] = []
var materials: Dictionary = {}  ## material id -> count
var gold := 0

var _stack_sizes: Dictionary  ## material id -> camp.json "stack": how many one transfer / one grid cell shows (no slot use)


func _init(slot_capacity: int, material_stack_sizes: Dictionary = {}) -> void:
	capacity = slot_capacity
	_stack_sizes = material_stack_sizes


func stack_size(material_id: String) -> int:
	return maxi(1, int(_stack_sizes.get(material_id, DEFAULT_STACK)))


## Only items use slots; materials are a counter (Boss 2026-11-13).
func slots_used() -> int:
	return items.size()


func free_slots() -> int:
	return capacity - slots_used()


func is_empty() -> bool:
	return items.is_empty() and materials.is_empty() and gold == 0


## Adds a piece of equipment. Returns false (and adds nothing) when the bag is full.
func add_item(item: Item) -> bool:
	if free_slots() < 1:
		return false
	items.append(item)
	return true


## Removes the item at `index` and returns it (null if there is none).
func take_item(index: int) -> Item:
	if index < 0 or index >= items.size():
		return null
	var item: Item = items[index]
	items.remove_at(index)
	return item


## How many more of a material fit: materials take no slot, so only the counter's ceiling limits it.
func room_for(material_id: String) -> int:
	return maxi(0, MATERIAL_MAX - material_count(material_id))


## Adds up to `count` of a material; returns how many were really added (all of it, below MATERIAL_MAX).
func add_material(material_id: String, count: int) -> int:
	var added := mini(maxi(count, 0), room_for(material_id))
	if added > 0:
		materials[material_id] = int(materials.get(material_id, 0)) + added
	return added


func material_count(material_id: String) -> int:
	return int(materials.get(material_id, 0))


## Takes up to `count` of a material out; returns how many were taken.
func remove_material(material_id: String, count: int) -> int:
	var taken := mini(maxi(count, 0), material_count(material_id))
	if taken > 0:
		var left := material_count(material_id) - taken
		if left > 0:
			materials[material_id] = left
		else:
			materials.erase(material_id)
	return taken


## cost = {"gold": int, "materials": {id: count}}
func can_afford(cost: Dictionary) -> bool:
	if gold < int(cost.get("gold", 0)):
		return false
	var needed: Dictionary = cost.get("materials", {})
	for id in needed:
		if material_count(str(id)) < int(needed[id]):
			return false
	return true


## Pays a cost if it can be afforded (all or nothing).
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	gold -= int(cost.get("gold", 0))
	var needed: Dictionary = cost.get("materials", {})
	for id in needed:
		remove_material(str(id), int(needed[id]))
	return true


## Empties the bag (everything carried is lost). Returns what was lost.
func clear_loot() -> Dictionary:
	var lost := {"items": items.size(), "gold": gold, "materials": materials.duplicate()}
	items.clear()
	materials.clear()
	gold = 0
	return lost


func to_dict() -> Dictionary:
	return {"v": 1, "capacity": capacity, "gold": str(gold), "materials": materials.duplicate(),
		"items": items.map(func(item): return item.to_dict())}


## Stack sizes are rule data, supplied by the caller rather than saved.
static func from_dict(d: Dictionary, stacks: Dictionary = {}):
	if int(d.get("v", 0)) != 1:
		return null
	var bag = load("res://logic/inventory.gd").new(int(d["capacity"]), stacks)
	bag.gold = int(d["gold"])
	for key in d["materials"]:
		bag.materials[str(key)] = int(d["materials"][key])
	for raw in d["items"]:
		var item = Item.from_dict(raw)
		if item == null:
			return null
		bag.items.append(item)
	return bag
