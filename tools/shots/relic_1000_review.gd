extends SceneTree
func _initialize()->void:call_deferred("run")
func title(text:String,at:Vector3,size:int=36)->void:
 var label=Label3D.new();label.text=text;label.position=at;label.font_size=size;label.pixel_size=.004;label.no_depth_test=true;root.add_child(label)
func run()->void:
 root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i.ZERO
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("24363c");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.85;root.add_child(env)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);root.add_child(light)
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,1.2,12);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.5;camera.current=true
 for row in range(2):
  var name="goblin_medallion" if row==0 else "goblin_lantern";var y=1.55-row*1.7
  title("MEDALLION" if row==0 else "LANTERN",Vector3(-3.5,y+1.12,.1))
  for column in range(3):
   var angle=[0,45,90][column]
   title(["FRONT","3/4","SIDE"][column],Vector3(-2.8+column*2.8,y+1.05,.1))
   for version in range(2):
    var path="res://art_source/props/goblin_base/parts/"+name+".glb" if version==0 else "res://art/relics/goblin/models/"+name+".glb"
    var doc=GLTFDocument.new();var state=GLTFState.new();assert(doc.append_from_file(path,state)==OK);var model=doc.generate_scene(state);root.add_child(model)
    model.scale=Vector3.ONE*5;model.position=Vector3(-3.45+column*2.8+version*1.28,y,0);model.rotation_degrees.y=angle
    var tris=0;var meshes=model.find_children("*","MeshInstance3D",true,false)
    if model is MeshInstance3D:meshes.push_front(model)
    for mesh in meshes:
     for surface in mesh.mesh.get_surface_count():tris+=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3
    if version==1:assert(tris<=1000)
    title(("SOURCE" if version==0 else "1000 BUDGET")+"\n%d tri"%tris,model.position+Vector3(0,-.22,.1),30)
 for frame in range(8):await process_frame
 root.scaling_3d_scale=1;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/relic-1000-comparison.png")
 print("RELIC1000 VISUAL PASS: source vs1000candidatetri, front45side, original materials/UV,1000hardcap")
 quit()
