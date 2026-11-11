extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var source=preload("res://data/perf/scenario.gd").new()
 var session=preload("res://client/session/local_session.gd").new(source.profile,source.rules,source.camp)
 var panel=preload("res://client/skill_panel.gd").new()
 root.add_child(panel);panel.setup(source.profile,session)
 var chosen:=""
 for node in panel.tree.nodes:
  if ZorxBuildCalc.can_allocate(panel.tree,panel._tree_state(),node.id).is_empty():chosen=node.id;break
 assert(not chosen.is_empty())
 panel._node_id=chosen;panel._describe_node();assert(not panel._allocate.disabled)
 panel._allocate.pressed.emit()
 await process_frame
 assert(chosen in panel.draft.allocated)
 panel._submit("save",panel.draft)
 assert(not panel._busy)
 assert(chosen in source.profile.skill_build.allocated)
 source.profile.stash.gold=100000
 var gold:int=source.profile.stash.gold
 panel._reset_pressed();panel._reset_pressed()
 assert(not panel._busy)
 assert(source.profile.skill_build.start=="")
 assert(source.profile.stash.gold==gold-int(preload("res://logic/skill_build.gd").config().reskill_gold))
 panel._page=1;panel._render()
 assert(panel._body.get_child_count()==1)
 for kind in ["shape","effect"]:
  for file in DirAccess.get_files_at("res://art/ui/skills/128/gems_"+kind):
   if file.ends_with(".png"):assert(panel._icon("gems_"+kind,file.get_basename())!=null)
 assert(load("res://client/skill_window.gd")!=null)
 for i in range(3):await process_frame
 print("SKILL PANEL PASS: select/allocate/save/reset cost/slots tab/window compilation")
 quit()
