extends SceneTree
func _initialize()->void:
 var source:Node3D=load("res://art/props/modular_wall/modular_wall.glb").instantiate()
 print("SOURCE ",source.transform)
 for mesh in source.find_children("*","MeshInstance3D",true,false):
  print("MESH ",mesh.transform," aabb ",mesh.get_aabb())
  var local=mesh.transform;var p=mesh.get_parent()
  while p!=null:
   print("PARENT ",p.name," ",p.transform);local=p.transform*local
   if p==source:break
   p=p.get_parent()
  print("FINAL ",local," BOUNDS ",local*mesh.get_aabb())
 source.free();quit()
