extends Node3D
## Local presentation only: shared meshes/materials, no physics, lights, particles or network positions.
var _ids:Array=[]
var _parts:Array[Node3D]=[]
var _clock:=0.0
func _ready()->void:set_process(not _parts.is_empty())
func configure(ids:Array)->void:
 if ids==_ids:return
 _ids=ids.duplicate()
 for part in _parts:remove_child(part);part.queue_free()
 _parts.clear()
 for id in _ids.slice(0,3):
  var path:String=preload("res://logic/relics.gd").catalog().get(id,{}).get("model","")
  if path.is_empty() or not ResourceLoader.exists(path):continue
  var part:Node3D=load(path).instantiate();add_child(part);_parts.append(part)
  var meshes=part.find_children("*","MeshInstance3D",true,false)
  if part is MeshInstance3D:meshes.push_front(part)
  for mesh in meshes:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 set_process(not _parts.is_empty())
func _process(delta:float)->void:
 if not is_visible_in_tree():return
 _clock=fmod(_clock+minf(delta,.1),TAU*10)
 # Keep orbit world-up independent of actor facing/rig scale.
 global_basis=Basis.IDENTITY
 for i in _parts.size():
  var angle:=_clock*.6+float(i)*TAU/maxi(3,_parts.size())
  _parts[i].position=Vector3(cos(angle)*.64,.82+sin(angle*1.6)*.055,sin(angle)*.64)
  var camera=get_viewport().get_camera_3d()
  if camera!=null:
   var view:Vector3=camera.global_position-_parts[i].global_position
   _parts[i].global_rotation.y=atan2(view.x,view.z)
  else:_parts[i].rotation.y=0
