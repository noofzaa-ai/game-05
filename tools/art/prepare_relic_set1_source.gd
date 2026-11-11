extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var importer=ClassDB.instantiate("FBXDocument");var state=ClassDB.instantiate("FBXState")
 assert(importer.append_from_file(ProjectSettings.globalize_path("res://../../assets/relic_set1.fbx").simplify_path(),state)==OK)
 var node=importer.generate_scene(state)
 for mesh in node.find_children("*","MeshInstance3D",true,false):
  var tris:=0
  for i in mesh.mesh.get_surface_count():
   var arrays:Array=mesh.mesh.surface_get_arrays(i)
   tris+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size())/3
  print("RELIC MESH ",mesh.name," transform ",mesh.transform," bounds ",mesh.get_aabb()," tri ",tris)
 var doc=GLTFDocument.new();var out=GLTFState.new();assert(doc.append_from_scene(node,out)==OK)
 assert(doc.write_to_filesystem(out,"res://art_source/relic_set1/native.glb")==OK)
 node.free();quit()
