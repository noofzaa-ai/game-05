extends SceneTree
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1280,720)
 var world=Node3D.new();root.add_child(world)
 var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(4,4,6);camera.look_at(Vector3.ZERO);camera.current=true
 var fx=load("res://art/skill_system/skills/fireball.tscn").instantiate()
 var t=Time.get_ticks_usec();world.add_child(fx);fx.free_on_finish=false;fx.play_effect()
 print("FX PLAY MS ",(Time.get_ticks_usec()-t)/1000.0," NODES ",fx.find_children("*","",true,false).size())
 var samples=[]
 for i in 80:
  var started=Time.get_ticks_usec();await process_frame
  samples.append((Time.get_ticks_usec()-started)/1000.0)
  if i==30:print("DRAW ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
 samples.sort();print("FRAME P50 ",samples[40]," P95 ",samples[76])
 quit()
