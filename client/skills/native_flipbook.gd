extends RefCounted
## Lossless timeline folding for authored eight-phase sprites. Never changes gameplay.
## Parent transform tracks remain native; mutually exclusive phase meshes share one node.
static func fold(root: Node) -> Dictionary:
 var players:=root.find_children("*","AnimationPlayer",true,false)
 if players.size()!=1:return {"groups":0}
 var player: AnimationPlayer=players[0]
 var names: Array[StringName]=[]
 for name in player.get_animation_list():
  if name!=&"RESET":names.append(name)
 if names.size()!=1:return {"groups":0}
 var clip: StringName=names[0]
 var original: Animation=player.get_animation(clip)
 var anim: Animation=original.duplicate()
 var base: Node=player.get_node(player.root_node)
 var tracks: Dictionary={}
 for track in anim.get_track_count():
  if anim.track_get_type(track)==Animation.TYPE_SCALE_3D:
   var node=base.get_node_or_null(NodePath(anim.track_get_path(track).get_concatenated_names()))
   if node!=null:tracks[node]=track
 var groups:=0
 var remove: Array[int]=[]
 for parent in root.find_children("*","Node3D",true,false):
  if not is_instance_valid(parent):continue
  var phases: Array[MeshInstance3D]=[]
  for child in parent.get_children():
   if child is MeshInstance3D and " phase " in str(child.name):phases.append(child)
  if phases.size()!=8 or parent.get_child_count()!=8:continue
  var valid:=true
  var times: Array[float]=[0.0]
  for child in phases:
   if child.mesh.get_surface_count()!=1 or child.get_child_count()!=0:valid=false;break
   if not child.position.is_equal_approx(phases[0].position) or not child.quaternion.is_equal_approx(phases[0].quaternion):valid=false;break
   if tracks.has(child):
    var track: int=tracks[child]
    if anim.track_get_interpolation_type(track)!=Animation.INTERPOLATION_NEAREST:valid=false;break
    for key in anim.track_get_key_count(track):times.append(anim.track_get_key_time(track,key))
  if not valid:continue
  times.sort()
  var timeline:=PackedFloat64Array()
  var frames:=PackedInt32Array()
  var last: int=-999
  for time in times:
   var frame: int=-1
   for index in phases.size():
    var child: MeshInstance3D=phases[index]
    var value: Vector3=anim.scale_track_interpolate(tracks[child],time) if tracks.has(child) else child.scale
    if value.abs().max_axis_index()>=0 and value.abs()[value.abs().max_axis_index()]>.01:
     if not value.is_equal_approx(Vector3.ONE) or frame!=-1:valid=false;break
     frame=index
   if not valid:break
   if frame!=last:timeline.append(time);frames.append(frame);last=frame
  if not valid:continue
  var meshes: Array[Mesh]=[]
  for child in phases:
   meshes.append(child.mesh)
   if tracks.has(child):remove.append(tracks[child])
  var keep: MeshInstance3D=phases[0]
  keep.scale=Vector3.ONE;keep.visible=false
  keep.set_meta("flipbook_meshes",meshes);keep.set_meta("flipbook_times",timeline);keep.set_meta("flipbook_indices",frames)
  for index in range(1,phases.size()):phases[index].free()
  groups+=1
 remove.sort();remove.reverse()
 for track in remove:anim.remove_track(track)
 # RESET refers to removed children and is never part of this playback contract.
 for lib_name in player.get_animation_library_list():
  var source:=player.get_animation_library(lib_name)
  var library:=AnimationLibrary.new()
  for name in source.get_animation_list():
   if name==&"RESET":continue
   library.add_animation(name,anim if (str(lib_name)+"/"+str(name)).trim_prefix("/")==str(clip) else source.get_animation(name))
  player.remove_animation_library(lib_name);player.add_animation_library(lib_name,library)
 _clean(root)
 return {"groups":groups,"old_tracks":original.get_track_count(),"tracks":anim.get_track_count(),"nodes":root.find_children("*","",true,false).size()}

static func _clean(node: Node) -> void:
 if node.get_script()!=null and node.get_script().resource_path.ends_with("/effect_player.gd"):node.set_script(null)
 for child in node.get_children():_clean(child)

static func own(node: Node, root: Node) -> void:
 if node!=root:node.owner=root
 node.scene_file_path=""
 for child in node.get_children():own(child,root)
