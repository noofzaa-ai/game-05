extends SceneTree
## Godot's native FBX importer avoids changing project Blender versions; original stays untouched.
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source:=ProjectSettings.globalize_path("res://../../assets/farm.fbx").simplify_path()
 var importer=ClassDB.instantiate("FBXDocument")
 assert(importer!=null)
 var state=ClassDB.instantiate("FBXState")
 var error:int=importer.append_from_file(source,state)
 assert(error==OK,"FBX import failed")
 var node:Node3D=importer.generate_scene(state)
 assert(node!=null)
 var bounds:=AABB();var first:=true;var triangles:=0
 for mesh in node.find_children("*","MeshInstance3D",true,false):
  var transform:Transform3D=mesh.transform;var parent=mesh.get_parent()
  while parent!=node:transform=parent.transform*transform;parent=parent.get_parent()
  var box:AABB=transform*mesh.get_aabb();bounds=box if first else bounds.merge(box);first=false
  for surface in mesh.mesh.get_surface_count():
   var arrays:Array=mesh.mesh.surface_get_arrays(surface)
   triangles+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size())/3
 var factor:float=4.8/bounds.size.x
 var wrapper:=Node3D.new();wrapper.name="FarmHouse";wrapper.add_child(node)
 node.position=-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
 node.scale=Vector3.ONE*factor
 var exporter:=GLTFDocument.new();var output:=GLTFState.new()
 assert(exporter.append_from_scene(wrapper,output)==OK)
 DirAccess.make_dir_recursive_absolute("res://art/props/farm_house")
 assert(exporter.write_to_filesystem(output,"res://art/props/farm_house/farm_house.glb")==OK)
 var report:={"source":source,"converter":"Godot "+Engine.get_version_info().string+" native FBXDocument","triangles":triangles,"source_size":bounds.size,"game_size":bounds.size*factor,"width_m":4.8,"foot_y":0}
 var file:=FileAccess.open("res://art/props/farm_house/asset.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
 print("FARM CONVERT ",JSON.stringify(report))
 wrapper.free();quit()
