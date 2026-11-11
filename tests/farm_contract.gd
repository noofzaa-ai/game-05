extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new()
 var p=source.profile;p.camp_level=2;p.stash.gold=100
 var farm=preload("res://logic/farm.gd")
 assert(farm.apply(p,{"type":"farm_seed","plot":0,"crop":"carrot"},100).ok)
 assert(p.stash.gold==80)
 assert(farm.apply(p,{"type":"farm_plant","plot":0,"crop":"carrot"},100).ok)
 assert(not farm.apply(p,{"type":"farm_harvest","plot":0},999).ok)
 assert(farm.apply(p,{"type":"farm_harvest","plot":0},1000).ok)
 assert(not farm.apply(p,{"type":"farm_harvest","plot":0},1000).ok)
 assert(p.farm.produce.carrot==3)
 var restored=preload("res://logic/profile.gd").from_dict(p.to_dict(),source.rules,source.camp)
 assert(restored!=null and restored.farm==p.farm)
 var runner=preload("res://server/profile/runner.gd").new()
 assert(runner.ALLOWED.has("farm_plant"))
 var state: Dictionary={"profile":p,"rules":source.rules,"camp":source.camp,"location":"camp","now":1000}
 var commands=preload("res://logic/commands.gd")
 var rng=RandomNumberGenerator.new()
 assert(not commands.apply(state,{"type":"farm_seed","plot":0,"crop":"carrot","now":1},rng).ok)
 var gold:int=p.stash.gold
 p.camp_level=1
 assert(not commands.apply(state,{"type":"farm_seed","plot":0,"crop":"carrot"},rng).ok)
 assert(p.stash.gold==gold)
 p.camp_level=2
 assert(not farm.apply(p,{"type":"farm_seed","plot":4,"crop":"carrot"},1000).ok)
 assert(not farm.apply(p,{"type":"farm_seed","plot":0,"crop":"invented"},1000).ok)
 assert(load("res://client/farm_panel.gd")!=null)
 assert(load("res://client/hub.gd")!=null)
 print("FARM PASS: seed cost, planting, trusted timing, single harvest, persistence and UI compile")
 quit()
