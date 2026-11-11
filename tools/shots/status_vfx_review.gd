extends SceneTree
var subjects:Array=[]
var effects:Array=[]
var page:Node3D
var statuses:=["burn","bleed","freeze","chill","shock","stun"]
func _initialize()->void:call_deferred("_run")
func text(value:String,at:Vector2,size:int=24,color:Color=Color.WHITE)->void:
 var label:=Label.new();label.text=value;label.position=at;label.add_theme_font_size_override("font_size",size);label.modulate=color;label.name="ReviewLabel";label.add_to_group("review_labels");root.add_child(label)
func _run()->void:
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1440,640)
 var env:=WorldEnvironment.new();var setting:=Environment.new();setting.background_mode=Environment.BG_COLOR;setting.background_color=Color("172630");setting.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;setting.ambient_light_color=Color.WHITE;setting.ambient_light_energy=.8;env.environment=setting;root.add_child(env)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);root.add_child(light)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10;camera.position=Vector3(0,5.5,11);camera.current=true;root.add_child(camera);camera.look_at(Vector3(0,1.2,0))
 for group in range(6):
  page=Node3D.new();root.add_child(page);effects.clear()
  text(statuses[group].to_upper()+" / GODOT NATIVE / MCP TRIAL",Vector2(30,15),26,Color("ffd787"))
  for col in range(3):text(["SMALL 0.9m","NORMAL 1.8m","BOSS 3.2m / WIDE"][col],Vector2(430+col*205,65),18)
  for row in range(1):
   var status:String=statuses[group]
   # Status name is shown in the header.
   for col in range(3):
    var height:float=[.9,1.8,3.2][col];var width:float=[.5,.9,2.0][col]
    var holder:=Node3D.new();holder.position=Vector3((col-1)*3.2,0,0);page.add_child(holder)
    var monster=load("res://client/fighter_view.gd").new();monster.monster_model_path="res://art/monsters/goblin_chief/goblin_chief.glb" if col==2 else "res://art/monsters/goblin/goblin.glb";monster.monster_model_height=height;monster.show_health_bar=false;holder.add_child(monster)
    if col==2:monster.scale.x=1.25;monster.scale.z=1.25
    var disk:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=width*.7+.2;cylinder.bottom_radius=cylinder.top_radius;cylinder.height=.03;disk.mesh=cylinder;var mat:=StandardMaterial3D.new();mat.albedo_color=Color("304750");disk.material_override=mat;holder.add_child(disk)
    var fx=load("res://client/skills/status_effect.gd").new();fx.status=status;holder.add_child(fx);fx.loop_effect=true
    var dimensions: Vector3=monster.status_visual_size*monster.scale.abs()
    fx.fit_body(dimensions.y,maxf(dimensions.x,dimensions.z));fx.play_effect();fx.set_process(false);effects.append(fx)
  for i in range(12):await process_frame
  for phase in [.4,.9,1.5]:
   for fx in effects:fx.elapsed=phase;fx._sample()
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://build/status-vfx-trial-%d-%d.png"%[group+1,int(phase*100)])
  for child in root.get_children():
   if child.is_in_group("review_labels"):child.queue_free()
  page.queue_free();await process_frame
 print("STATUS VFX NATIVE REVIEW: six effects x three monster sizes x three phases rendered")
 quit()
