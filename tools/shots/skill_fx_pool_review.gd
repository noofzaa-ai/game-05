extends SceneTree
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1280,720)
 var scene=Node3D.new();root.add_child(scene)
 var camera=Camera3D.new();scene.add_child(camera);camera.position=Vector3(3,3,5);camera.look_at(Vector3.ZERO);camera.current=true
 var presenter=load("res://client/skills/presenter.gd").new();scene.add_child(presenter)
 await presenter.warm_build(load("res://logic/skill_build.gd").initial("blade"),Vector3.ZERO)
 var times=[];var ids={};var nodes_before=presenter.find_children("*","",true,false).size()
 for i in 12:
  var started:=Time.get_ticks_usec();presenter.event({"kind":"burst","skill":"fireball","position":Vector3.ZERO,"radius":1.0});times.append((Time.get_ticks_usec()-started)/1000.0)
  for fx in presenter.get_children():
   if fx.visible and fx.has_method("_sample"):
    ids[fx.get_instance_id()]=true;fx.elapsed=fx.duration;fx._process(0)
  await process_frame
 times.sort()
 print("POOL CAST MS p50=",times[6]," max=",times[-1]," unique instances=",ids.size()," node count=",nodes_before,"/",presenter.find_children("*","",true,false).size()," idle=",presenter._idle_count)
 print("POOL CREATED=",presenter.pool_created," REUSED=",presenter.pool_reused)
 quit()
