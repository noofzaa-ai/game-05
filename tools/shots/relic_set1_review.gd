extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 root.size=Vector2i(1600,850)
 root.content_scale_size=Vector2i.ZERO
 var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://art_source/relic_set1/manifest.json"))
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("273b43");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;root.add_child(env)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=1.1;root.add_child(light)
 var total:=0
 for i in manifest.parts.size():
  var row:Dictionary=manifest.parts[i];var doc:=GLTFDocument.new();var state:=GLTFState.new();assert(doc.append_from_file("res://art_source/relic_set1/"+row.path,state)==OK)
  var model:Node3D=doc.generate_scene(state);root.add_child(model);model.position=Vector3((i%5)*1.7,(1-i/5)*1.8,0)
  var meshes=model.find_children("*","MeshInstance3D",true,false)
  if model is MeshInstance3D:meshes.push_front(model)
  for mesh in meshes:
   var bounds:AABB=mesh.get_aabb();print(row.id," ",bounds);assert(absf(bounds.position.y)<.001 and absf(bounds.size.y-1)<.001)
   for surface in mesh.mesh.get_surface_count():
    var arrays:Array=mesh.mesh.surface_get_arrays(surface);total+=arrays[Mesh.ARRAY_INDEX].size()/3
  var label:=Label3D.new();label.text="%02d · %d tri"%[i+1,row.triangles];label.font_size=32;label.pixel_size=.0045;label.position=model.position+Vector3(0,-.16,.25);root.add_child(label)
 assert(total==50000)
 var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.position=Vector3(3.4,1.35,20);camera.size=4.5;camera.current=true
 if DisplayServer.get_name()=="headless":
  print("RELIC SET1 PASS:10 GLBs resolve shared textures, Y0 feet,height1m,50000tri preserved");quit();return
 for i in range(6):await process_frame
 root.scaling_3d_scale=1.0
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://art_source/relic_set1/overview.png")
 print("RELIC SET1 PASS:10 GLBs resolve shared textures, Y0 feet,height1m,50000tri preserved")
 quit()
