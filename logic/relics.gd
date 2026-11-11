extends RefCounted
## Owned instances and loadout only. Effect definitions are a separate authored decision.
const SLOT_COUNT := 3
const UNLOCKED_SLOTS := 1
static func initial() -> Dictionary:
	return {"v":1,"owned":[],"equipped":["","",""]}

static func decode(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size()!=3 or value.get("v")!=1 or not value.get("owned") is Array or not value.get("equipped") is Array: return {}
	if value.owned.size()>512 or value.equipped.size()!=SLOT_COUNT: return {}
	var ids := {}
	for item in value.owned:
		if not item is Dictionary or item.size()!=2 or not item.has_all(["id","relic"]): return {}
		if not item.id is String or not item.relic is String or item.id.is_empty() or item.id.length()>96 or item.relic.is_empty() or item.relic.length()>64 or ids.has(item.id): return {}
		ids[item.id]=true
	var worn := {}
	for slot in SLOT_COUNT:
		var id = value.equipped[slot]
		if not id is String: return {}
		if id.is_empty(): continue
		if slot>=UNLOCKED_SLOTS or not ids.has(id) or worn.has(id): return {}
		worn[id]=true
	var result: Dictionary = value.duplicate(true)
	result["v"] = int(result["v"])  # plain JSON loses int vs float
	return result

static func equip(profile, instance: String, slot: int) -> Dictionary:
	if slot<0 or slot>=UNLOCKED_SLOTS: return {"ok":false,"error":"relic_slot_locked"}
	if not instance.is_empty() and not profile.relics.owned.any(func(item):return item.id==instance): return {"ok":false,"error":"relic_not_owned"}
	profile.relics.equipped[slot]=instance
	return {"ok":true,"changed":true}

static var _data: Dictionary = {}
static func data() -> Dictionary:
	if _data.is_empty():
		var path := "res://data/relics/catalog.json"
		if FileAccess.file_exists(path):
			var value = JSON.parse_string(FileAccess.get_file_as_string(path))
			if value is Dictionary: _data=value
	return _data

static func catalog() -> Dictionary:
	return data().get("items",{})

## Called only by authoritative monster-death loot. No command can grant an instance.
static func roll(enemy: String, rng: RandomNumberGenerator) -> Array:
	var rule: Dictionary=data().get("boss_drops",{}).get(enemy,{})
	if rule.is_empty(): return []
	var pool: Array=rule.get("pool",[])
	if pool.is_empty() or rng.randf()>=float(rule.get("chance",0)): return []
	var result: Array=[]
	for n in int(rule.get("count",1)):
		var instance := "relic-%d-%d"%[rng.seed,rng.state]
		var relic: String=str(pool[rng.randi_range(0,pool.size()-1)])
		if catalog().has(relic):result.append({"id":instance,"relic":relic})
	return result

## Read only owned, equipped definitions; unknown IDs never activate gameplay or visuals.
static func equipped_types(value:Dictionary) -> Array[String]:
	var result:Array[String]=[]
	for instance in value.get("equipped",[]).slice(0,UNLOCKED_SLOTS):
		for entry in value.get("owned",[]):
			if entry.id==instance and catalog().has(entry.relic) and not entry.relic in result:result.append(entry.relic)
	return result
