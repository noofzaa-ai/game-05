extends "res://client/hub_world_training_baseline.gd"
const TrainingScene=preload("res://art/maps/camp_hub/camp_training.glb")
const Fence=preload("res://client/modular_fence.gd")
func _ready()->void:
 super._ready()
 half_extents.x=maxf(half_extents.x,25.5)
func _refresh_farm(level:int)->void:
 super._refresh_farm(level)
 if level<2:_farm_extension=null
 half_extents.x=maxf(half_extents.x,25.5)
 if is_instance_valid(_farm_extension):Fence.build(_farm_extension,Fence.farm_segments(_base_half_extents.x))

func _load_scene() -> bool:
 if not ResourceLoader.exists("res://art/maps/camp_hub/camp_training.glb"):
  push_error("camp hub scenery is missing: " + "res://art/maps/camp_hub/camp_training.glb")
  return false
 var packed := load("res://art/maps/camp_hub/camp_training.glb") as PackedScene
 if packed == null:
  return false
 var scene: Node3D = packed.instantiate()
 add_child(scene)
 for node in scene.get_children():
  var name := str(node.name)
  if node is MeshInstance3D:
   if name=="FarmBoundaryTrees": _farm_boundary_trees=node
   _prepare_mesh(node as MeshInstance3D)
  elif node is Node3D:
   var xf: Transform3D = (node as Node3D).transform
   if name == "bounds":
    var s := xf.basis.get_scale()
    half_extents = Vector2(s.x, s.z)
   elif name.begins_with("col_"):
    var half := xf.basis.get_scale()
    if name not in ["col_forge", "col_anvil", "col_counter", "col_weapon_rack"]:
     solids.append(AABB(xf.origin - half, half * 2.0))
   else:
    spots[name] = xf.origin
 var trees=scene.find_child("TrainingBoundaryTrees",true,false)
 if trees!=null:trees.hide()
 solids.append_array(Fence.collision_boxes(Fence.training_segments()))
 return true


## The glTF import leaves vertex colours off (they would render white); the glow materials glow.

func farm_boundaries() -> Array[AABB]:
 var result: Array[AABB] = []
 if _base_half_extents == Vector2.ZERO: return result
 var edge := _base_half_extents.x
 # West training clearing is always open; other forest edges remain blocked.
 result.append(AABB(Vector3(-edge-20,-1,-60),Vector3(20,8,58)))
 result.append(AABB(Vector3(-edge-20,-1,11),Vector3(20,8,49)))
 if is_instance_valid(_farm_extension):
  result.append_array(preload("res://client/modular_fence.gd").collision_boxes(preload("res://client/modular_fence.gd").farm_segments(edge)))
  result.append(AABB(Vector3(edge, -1, -60), Vector3(12, 8, 51.5)))
  result.append(AABB(Vector3(edge, -1, 2.5), Vector3(12, 8, 66)))
 else:result.append(AABB(Vector3(edge,-1,-60),Vector3(20,8,120)))
 return result
