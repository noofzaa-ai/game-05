extends SceneTree
const Presenter=preload("res://client/skills/presenter.gd")
const Fighter=preload("res://logic/fighter.gd")
const Body=preload("res://logic/sim_body.gd")
const Graphics=preload("res://client/graphics_options.gd")
class OlderStage extends Node3D:
 var _views: Dictionary={}
func _initialize()->void:call_deferred("_run")
func _run()->void:
 assert(load("res://client/stage_view.gd")!=null)
 var presenter=Presenter.new();root.add_child(presenter)
 var fighter=Fighter.new();fighter.skill_view={"statuses":{}}
 var body=Body.new();var view:=Node3D.new();view.set_script(preload("res://client/fighter_view.gd"));view.monster_model_path="res://art/monsters/goblin/goblin.glb";view.monster_model_height=1.8;root.add_child(view)
 var fighters:={100:fighter};var bodies:={100:body};var views:={100:view}
 var before: bool=Graphics.enabled("combat_vfx")
 Graphics._values["combat_vfx"]=true
 for status in ["burn","bleed","freeze","chill","shock","stun"]:
  fighter.skill_view.statuses[status]={"remaining":120}
 presenter.update_from(fighters,bodies,views)
 assert(presenter._active.size()==6)
 var ids:={}
 for key in presenter._active:
  var fx=presenter._active[key];ids[key]=fx.get_instance_id()
  assert(fx.playing and fx.loop_effect and fx.player!=null)
  assert(fx.visual!=null and fx.duration>0)
 view.position=Vector3(4,.2,-3)
 presenter.update_from(fighters,bodies,views)
 for key in ids:
  assert(presenter._active[key].position==view.position)
  assert(presenter._active[key].get_instance_id()==ids[key])
 var stun=presenter._active["100:status:stun"]
 var short_offset: float=stun.visual.position.y
 view.status_visual_size=Vector3(2,3.2,2);view.monster_model_height=3.2;view.remove_meta("status_vfx_size")
 presenter.update_from(fighters,bodies,views)
 assert(stun.visual.position.y>short_offset)
 fighter.skill_view.statuses.clear()
 presenter.update_from(fighters,bodies,views)
 assert(presenter._active.is_empty())
 for entries in presenter._pool.values():
  for fx in entries:assert(not fx.visible and not fx.playing and not fx.is_processing())
 fighter.skill_view.statuses={"stun":{}}
 presenter.update_from(fighters,bodies,views)
 assert(presenter._active["100:status:stun"].get_instance_id()==ids["100:status:stun"])
 assert(presenter._active["100:status:stun"].elapsed==0)
 bodies.clear();presenter.update_from(fighters,bodies,views)
 assert(presenter._active.is_empty())
 bodies[100]=body;presenter.update_from(fighters,bodies,views)
 Graphics._values["combat_vfx"]=false;presenter.update_from(fighters,bodies,views)
 assert(presenter._active.is_empty())
 Graphics._values["combat_vfx"]=before
 var old_stage:=OlderStage.new();old_stage._views=views;root.add_child(old_stage)
 var compatible=Presenter.new();old_stage.add_child(compatible)
 Graphics._values["combat_vfx"]=true
 compatible.update_from(fighters,bodies)
 assert(compatible._active.size()==1)
 view.position=Vector3(7,0,-4)
 await process_frame
 assert(compatible._active["100:status:stun"].position==view.position,"Old Stage's two-argument update follows final rendered position")
 Graphics._values["combat_vfx"]=before
 print("STATUS VFX PASS: six real scenes, snapshot lifetime, simultaneous statuses, rendered-position follow, measured size, head anchor, pooled stop/reuse, despawn, graphics off")
 quit()
