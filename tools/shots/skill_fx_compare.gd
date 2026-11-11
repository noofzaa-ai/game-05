extends SceneTree
const PROPS=["asset_path","projectile_path","beam_path","asset_scale","visual_offset","axis_scale","tint","override_tint","orbit_instances","orbit_radius"]
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(640,480)
 var world=Node3D.new();root.add_child(world)
 var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(3,3,5);camera.look_at(Vector3(0,.4,0));camera.current=true
 var report=[]
 for id in ["fire_ring","fireball","frost_armor","blood_shield","flame_dash","tesla_totem","storm_blades"]:
  for time in [.15,.35,.7]:
   var images=[]
   for old in [true,false]:
    var settings=load("res://art/skill_system/skills/"+id+".tscn").instantiate()
    var fx: Node3D
    fx=settings;fx.use_folded_frames=not old
    world.add_child(fx);fx.free_on_finish=false;fx.play_effect();fx.set_process(false);fx.elapsed=time
    if old:fx._process(0)
    else:fx._sample()
    await process_frame;await process_frame;await RenderingServer.frame_post_draw
    var image=root.get_texture().get_image();images.append(image)
    if id=="fireball" and is_equal_approx(time,.35):image.save_png("/tmp/skill-fireball-"+("before" if old else "after")+".png")
    fx.queue_free();await process_frame
   var a: PackedByteArray=images[0].get_data();var b: PackedByteArray=images[1].get_data();var changed:=0;var sum:=0
   for i in a.size():
    var delta:=absi(int(a[i])-int(b[i]));sum+=delta
    if delta>3:changed+=1
   var row={"skill":id,"time":time,"mean_channel_error":float(sum)/a.size(),"changed_channels_pct":float(changed)/a.size()*100}
   report.append(row);print("COMPARE ",row)
 var file=FileAccess.open("res://build/skill-fx-visual-comparison.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
 quit()
