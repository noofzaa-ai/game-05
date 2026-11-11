extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var importer=ClassDB.instantiate("FBXDocument");var state=ClassDB.instantiate("FBXState")
 assert(importer.append_from_file(ProjectSettings.globalize_path("res://../../assets/wall_modular.fbx").simplify_path(),state)==OK)
 var node=importer.generate_scene(state)
 for mesh in node.find_children("*","MeshInstance3D",true,false):
  print("WALL MESH ",mesh.name," ",mesh.transform," bounds ",mesh.get_aabb())
  for i in mesh.mesh.get_surface_count():print("MATERIAL ",mesh.mesh.surface_get_material(i))
 var doc=GLTFDocument.new();var out=GLTFState.new();assert(doc.append_from_scene(node,out)==OK)
 DirAccess.make_dir_recursive_absolute("res://art/props/modular_wall")
 assert(doc.write_to_filesystem(out,"res://art/props/modular_wall/modular_wall.glb")==OK)
 node.free();quit()
