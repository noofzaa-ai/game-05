extends SceneTree
const Relics := preload("res://logic/relics.gd")
const Commands := preload("res://logic/commands.gd")
func _initialize() -> void:
	var manager=preload("res://server/rooms/manager.gd").new()
	var p=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,RandomNumberGenerator.new())
	var legacy: Dictionary=p.to_dict();legacy.erase("relics")
	var migrated=preload("res://logic/profile.gd").from_dict(legacy,manager.rules,manager.camp)
	assert(migrated!=null and migrated.relics==Relics.initial())
	p.relics.owned=[{"id":"boss-drop-1","relic":"fixture_relic"},{"id":"boss-drop-2","relic":"fixture_relic_2"}]
	var context={"profile":p,"rules":manager.rules,"camp":manager.camp,"location":"camp"}
	var rng=RandomNumberGenerator.new()
	assert(Commands.apply(context,{"type":"relic_equip","relic":"boss-drop-1","slot":0},rng).ok)
	assert(p.relics.equipped==["boss-drop-1","",""])
	var before: Dictionary=p.to_dict()
	assert(not Commands.apply(context,{"type":"relic_equip","relic":"forged","slot":0},rng).ok)
	for slot in [-1,1,2,3]:assert(not Commands.apply(context,{"type":"relic_equip","relic":"boss-drop-2","slot":slot},rng).ok)
	assert(p.to_dict()==before)
	context.location="stage"
	assert(not Commands.apply(context,{"type":"relic_equip","relic":"boss-drop-2","slot":0},rng).ok)
	assert(p.to_dict()==before)
	context.location="camp"
	assert(Commands.apply(context,{"type":"relic_equip","relic":"boss-drop-2","slot":0},rng).ok)
	assert(p.relics.owned.size()==2 and p.relics.equipped[0]=="boss-drop-2")
	var restored=preload("res://logic/profile.gd").from_dict(p.to_dict(),manager.rules,manager.camp)
	assert(restored!=null and restored.relics==p.relics)
	var cache=preload("res://server/rooms/snapshot_cache.gd").new();cache.begin()
	var first: Dictionary=cache.profile(p)
	assert(Commands.apply(context,{"type":"relic_equip","relic":"","slot":0},rng).ok)
	var second: Dictionary=cache.profile(p)
	assert(first.relics.equipped[0]=="boss-drop-2" and second.relics.equipped[0]=="")
	var bad: Dictionary=p.to_dict();bad.relics.equipped[1]="boss-drop-1"
	assert(preload("res://logic/profile.gd").from_dict(bad,manager.rules,manager.camp)==null)
	print("RELIC SLOT PASS: legacy migration,3slots/1active,owned-only equip,replace/unequip,camp-only,save roundtrip,cache invalidation,locked-slot tamper rejection")
	quit()
