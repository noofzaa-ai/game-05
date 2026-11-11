extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var source=preload("res://data/perf/scenario.gd").new()
 var build=preload("res://logic/skill_build.gd")
 var session=preload("res://client/session/local_session.gd").new(source.profile,source.rules,source.camp)
 source.profile.skill_build=build.initial("blade")
 var slots: Array=source.profile.skill_build.skills.duplicate(true)
 var gold:int=source.profile.stash.gold
 var rng=RandomNumberGenerator.new();rng.seed=789
 var bow=preload("res://logic/item_system.gd").create_item(source.rules,"test-bow", "weapon",0,rng,"bow","bow_01")
 source.profile.stash.add_item(bow)
 var result:Dictionary=session.command({"type":"equip","item":bow.id,"index":0,"source":"stash"})
 print("equip result ",result)
 assert(result.get("ok",false))
 assert(source.profile.skill_build.start=="bow" and source.profile.skill_build.allocated==["start_bow"])
 assert(source.profile.skill_build.skills==slots and source.profile.stash.gold==gold)
 assert(build.ready_for_run(source.profile))
 var tree=load(build.ROOT+"tree/full_tree.tres").duplicate(true);tree.build()
 var run=ZorxRunState.new();run.allocated.assign(source.profile.skill_build.allocated);run.points=12
 for node in tree.nodes:
  if ZorxBuildCalc.can_allocate(tree,run,node.id).is_empty():source.profile.skill_build.allocated.append(node.id);break
 assert(not build.can_equip(source.profile,"hammer"))
 assert(build.can_equip(source.profile,"bow"))
 assert(load("res://client/skills/tree_canvas.gd")!=null)
 print("UNSPENT TREE PASS: actual equip follows start, slots/gold preserved, invested cross-family blocked")
 quit()
