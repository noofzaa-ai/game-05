extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 for id in ["gobbin_base","gobbin_relic"]:
  var importer=ClassDB.instantiate("FBXDocument");var state=ClassDB.instantiate("FBXState")
  assert(importer.append_from_file(ProjectSettings.globalize_path("res://../../assets/"+id+".fbx").simplify_path(),state)==OK)
  var node=importer.generate_scene(state)
  for mesh in node.find_children("*","MeshInstance3D",true,false):print(id," ",mesh.name," ",mesh.transform," ",mesh.get_aabb())
  var doc=GLTFDocument.new();var out=GLTFState.new();assert(doc.append_from_scene(node,out)==OK)
  assert(doc.write_to_filesystem(out,"res://art_source/props/goblin_base/"+id+"_native.glb")==OK)
  node.free()
 quit()
