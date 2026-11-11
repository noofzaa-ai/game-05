extends RefCounted
## What a character is wearing: which item sits in which slot position (for example the second ring).
## EXTENDING: set bonuses or slot restrictions are checked in equip().

const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")

var rules: ItemRules
var _equipped: Dictionary = {}  ## "slot:index" -> Item


func _init(item_rules: ItemRules) -> void:
	rules = item_rules


## Puts an item in its slot at `index` (0 for single slots, 0 or 1 for pairs). Returns false if the
## slot does not exist, the index is out of range, or the item has been destroyed.
func equip(item: Item, index: int = 0) -> bool:
	var slot := rules.slot(item.slot)
	if slot.is_empty() or index < 0 or index >= int(slot["count"]) or item.destroyed:
		return false
	_equipped[_key(item.slot, index)] = item
	return true


func unequip(slot_id: String, index: int = 0) -> Item:
	var key := _key(slot_id, index)
	var item: Item = _equipped.get(key)
	_equipped.erase(key)
	return item


func item_at(slot_id: String, index: int = 0) -> Item:
	return _equipped.get(_key(slot_id, index))


## The combat style given by the equipped weapon (its weapon_type), or "fists" with no weapon.
## `known_styles` are the styles that exist in the combat data; an unknown weapon type falls back to fists.
func weapon_style(known_styles: Array) -> String:
	var weapon := item_at("weapon", 0)
	if weapon != null and not weapon.destroyed and known_styles.has(weapon.weapon_type):
		return weapon.weapon_type
	return "fists"


## Worn items that still exist (a destroyed item stops counting).
func items() -> Array[Item]:
	var worn: Array[Item] = []
	for item in _equipped.values():
		if not item.destroyed:
			worn.append(item)
	return worn


static func _key(slot_id: String, index: int) -> String:
	return "%s:%d" % [slot_id, index]


func to_dict() -> Dictionary:
	var entries := {}
	for key in _equipped:
		entries[key] = _equipped[key].to_dict()
	return {"v": 1, "equipped": entries}


static func from_dict(d: Dictionary, item_rules: ItemRules):
	if int(d.get("v", 0)) != 1:
		return null
	var worn = load("res://logic/loadout.gd").new(item_rules)
	for key in d["equipped"]:
		var item = Item.from_dict(d["equipped"][key])
		if item == null:
			return null
		# Preserve destroyed entries too: equip() deliberately refuses those.
		worn._equipped[str(key)] = item
	return worn
