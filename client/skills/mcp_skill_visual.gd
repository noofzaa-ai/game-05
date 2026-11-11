extends Node3D
## Adapter only: geometry/material/animation come from the authenticated MCP bundle.
@export var asset_path: String
@export var projectile_path: String=""
@export var beam_path: String=""
@export var asset_scale: float=1.0
@export var visual_offset: Vector3=Vector3.ZERO
@export var axis_scale: Vector3=Vector3.ONE
@export var tint: Color=Color.WHITE
@export var override_tint: bool=false
@export var orbit_instances: int=1
@export var orbit_radius: float=.35
var autoplay: bool=false
var loop_effect: bool=false
var free_on_finish: bool=true
var effect_phase: String="impact"
var endpoint: Vector3=Vector3.ZERO
var beam_jitter: float=0
var visual: Node3D
var players: Array[AnimationPlayer]=[]
var player: AnimationPlayer
var clip: StringName
var elapsed: float=0
var duration: float=1
var playing: bool=false
var styled_materials: Array[ShaderMaterial]=[]
static var material_modes: Dictionary={}
static var repaired_shell: ArrayMesh
func _find_player(node: Node) -> AnimationPlayer:
 if node is AnimationPlayer:return node
 for child in node.get_children():
  var found:=_find_player(child)
  if found!=null:return found
 return null
signal finished
static var native_scenes: Dictionary={}
var _signature: String=""
var _playback: Array=[]
var _flipbooks: Array=[]
var _style_cache: Dictionary={}
var _shell_material: ShaderMaterial
@export var use_folded_frames: bool=true
@export var preserve_materials: bool=false
static var setup_last_us: int=0
static var setup_max_us: int=0

static func native_scene(path: String, folded: bool=true) -> PackedScene:
 var runtime:=path.get_base_dir()+"/runtime.scn"
 var actual:=runtime if folded and ResourceLoader.exists(runtime) else path
 if not native_scenes.has(actual):native_scenes[actual]=load(actual)
 return native_scenes[actual]

func play_effect() -> void:
 var setup_started:=Time.get_ticks_usec()
 var path:=asset_path
 if effect_phase=="projectile" and not projectile_path.is_empty():path=projectile_path
 if effect_phase=="beam" and not beam_path.is_empty():path=beam_path
 var signature:=path+":"+str(use_folded_frames)
 if visual==null or _signature!=signature:
  if visual!=null:visual.queue_free()
  _signature=signature
  var scene:=native_scene(path,use_folded_frames)
  if orbit_instances>1:
   visual=Node3D.new()
   for i in range(orbit_instances):
    var part: Node3D=scene.instantiate();part.position=Vector3(cos(i*TAU/orbit_instances),0,sin(i*TAU/orbit_instances))*orbit_radius;visual.add_child(part)
  elif "flame_dash/" in path:
   visual=Node3D.new()
   for i in range(3):
    var part: Node3D=scene.instantiate();part.position.z=(i-1)*.6;part.scale.z=.38;visual.add_child(part)
  elif "tesla_totem/" in path:
   visual=scene.instantiate()
   var core: Node3D=native_scene("res://art/skill_system/mcp_vfx/tesla_totem_projectile/effect.tscn",use_folded_frames).instantiate();core.scale=Vector3(.28,1.05,.28);core.position.y=.08;visual.add_child(core)
  else:visual=scene.instantiate()
  if visual.get_script()!=null:
   visual.set("autoplay",false);visual.set("free_on_finish",false)
  add_child(visual)
  styled_materials.clear();_flipbooks.clear();_style_cache.clear();_shell_material=null
  var modes:=_material_modes(path).duplicate()
  if "tesla_totem/" in path:modes.merge(_material_modes("res://art/skill_system/mcp_vfx/tesla_totem_projectile/effect.tscn"))
  _style_visual(visual,modes)
  if "fireball_projectile/" in path and DisplayServer.get_name()!="headless":_add_fire_glow(visual)
  visual.position=visual_offset
  visual.scale=axis_scale*asset_scale if effect_phase=="impact" or effect_phase=="persistent" else Vector3.ONE
  players.clear();_collect_players(visual)
  player=players[0] if not players.is_empty() else null
  if player==null:return
  _playback.clear()
  for index in players.size():
   var current: AnimationPlayer=players[index]
   var current_clip: StringName=&""
   for name in current.get_animation_list():
    if name!=&"RESET":current_clip=name;break
   if current_clip==&"":continue
   var groups: Array=[]
   for item in _flipbooks:
    var closest: AnimationPlayer
    var depth: int=-1
    for candidate in players:
     var root: Node=candidate.get_node(candidate.root_node)
     if root.is_ancestor_of(item.node) and root.get_path().get_name_count()>depth:
      closest=candidate;depth=root.get_path().get_name_count()
    if closest==current:groups.append(item)
   current.play(current_clip);current.advance(0);current.pause()
   _playback.append({"player":current,"length":current.get_animation(current_clip).length,"groups":groups,"offset":index*.31 if "flame_dash/" in asset_path or orbit_instances>1 else 0.0})
  duration=_playback[0].length if not _playback.is_empty() else 1.0
 if effect_phase=="beam":
  visual.quaternion=Quaternion(Vector3.UP,endpoint.normalized()) if endpoint.length()>.00001 else Quaternion.IDENTITY
  visual.scale=Vector3(1,endpoint.length(),1)
 elapsed=0;playing=true;_sample()
 if not get_meta("prewarm",false):
  setup_last_us=Time.get_ticks_usec()-setup_started;setup_max_us=maxi(setup_max_us,setup_last_us)

func stop_effect() -> void:playing=false
func _sample() -> void:
 for material in styled_materials:material.set_shader_parameter("effect_time",elapsed)
 for entry in _playback:
  var time: float=elapsed+entry.offset
  time=fmod(time,maxf(.001,entry.length)) if loop_effect else minf(time,entry.length)
  entry.player.seek(time,true)
  for item in entry.groups:
   var index: int=item.times.bsearch(time,false)-1
   var frame: int=item.indices[index] if index>=0 else -1
   if frame==item.last:continue
   item.last=frame;item.node.visible=frame>=0
   if frame>=0:
    item.node.mesh=item.meshes[frame]
    item.node.set_surface_override_material(0,item.materials[frame])
func _process(delta: float) -> void:
 if not playing or player==null:return
 elapsed+=delta;_sample()
 if not loop_effect and elapsed>=duration:
  playing=false
  if free_on_finish:
   if finished.get_connections().is_empty():queue_free()
   else:finished.emit()

func _material_modes(path: String) -> Dictionary:
 var glb_path:=path.get_base_dir()+"/effect.glb"
 if material_modes.has(glb_path):return material_modes[glb_path]
 var result: Dictionary={}
 var sidecar:=path.get_base_dir()+"/material_modes.json"
 if FileAccess.file_exists(sidecar):
  var parsed=JSON.parse_string(FileAccess.get_file_as_string(sidecar))
  if parsed is Dictionary:
   material_modes[glb_path]=parsed
   return parsed
 if FileAccess.file_exists(glb_path):
  var file:=FileAccess.open(glb_path,FileAccess.READ)
  file.seek(12);var length:=file.get_32();file.seek(20)
  var document: Dictionary=JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
  for material in document.get("materials",[]):result[material.get("name","")]=material.get("extras",{}).get("blendMode","normal")
 material_modes[glb_path]=result
 return result

func _shell_mesh() -> ArrayMesh:
 if repaired_shell!=null:return repaired_shell
 var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
 for ring in range(8):
  for segment in range(32):
   var corners: Array[Vector3]=[]
   for offset in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
    var phi: float=(ring+offset.y)*PI/16.0
    var theta: float=(segment+offset.x)*TAU/32.0
    corners.append(Vector3(sin(phi)*cos(theta),cos(phi),sin(phi)*sin(theta)))
   for index in ([0,3,2] if ring==0 else [0,2,1,0,3,2]):vertices.append(corners[index]);normals.append(corners[index])
 var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
 repaired_shell=ArrayMesh.new();repaired_shell.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 repaired_shell.surface_set_material(0,StandardMaterial3D.new())
 return repaired_shell

func _style_frame(mesh: Mesh, original: Material, modes: Dictionary) -> Dictionary:
 if preserve_materials:return {"mesh":mesh,"material":original}
 var key:=str(mesh.get_instance_id())+":"+str(original.get_instance_id())
 if _style_cache.has(key):return _style_cache[key]
 var result: Dictionary={"mesh":mesh,"material":original}
 var is_shell: bool=("blood_shield" in asset_path or "frost_armor" in asset_path) and original.resource_name.begins_with("ผิวโดมป้องกัน")
 if is_shell:
  result.mesh=_shell_mesh()
  if DisplayServer.get_name()!="headless":
   if _shell_material==null:
    _shell_material=ShaderMaterial.new();_shell_material.shader=preload("res://client/skills/energy_shell.gdshader");_shell_material.set_shader_parameter("energy_color",tint);styled_materials.append(_shell_material)
    if "frost_armor" in asset_path:_shell_material.set_shader_parameter("energy_color",Color(0.45,0.82,1.0));_shell_material.set_shader_parameter("rim_strength",0.75)
   result.material=_shell_material
 elif original is BaseMaterial3D and DisplayServer.get_name()!="headless":
  var material: BaseMaterial3D=original.duplicate()
  if override_tint:
   var recolor:=ShaderMaterial.new();recolor.shader=preload("res://client/skills/gem_tint.gdshader")
   recolor.set_shader_parameter("energy_color",tint);recolor.set_shader_parameter("source_alpha",material.albedo_color.a);recolor.set_shader_parameter("has_texture",material.albedo_texture!=null)
   if material.albedo_texture!=null:recolor.set_shader_parameter("sprite_texture",material.albedo_texture)
   result.material=recolor
  else:
   if "tesla_totem/" in asset_path and original.resource_name.begins_with("เสาพลัง"):
    var wide:=ArrayMesh.new();var arrays: Array=mesh.surface_get_arrays(0);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    for vertex in range(vertices.size()):vertices[vertex].x*=3.5
    arrays[Mesh.ARRAY_VERTEX]=vertices;wide.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.mesh=wide;material.albedo_color=tint
   if modes.get(original.resource_name)=="additive":material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
   if "flame_dash" in asset_path:
    var color:=material.albedo_color;color.a*=2.2 if original.resource_name.begins_with("เปลวระเบิด") else .55;material.albedo_color=color
   result.material=material
   if "fireball_projectile/" in _signature and modes.get(original.resource_name)!="additive":
    # The authored ball is two flat opaque cards that read as a flat orange coin from the board camera:
    # hide them; _add_fire_glow draws the ball as a hot glow at the same spot.
    material.albedo_color.a=0.0;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 _style_cache[key]=result
 return result

func _style_visual(node: Node,modes: Dictionary) -> void:
 if node is MeshInstance3D:
  var mesh_node: MeshInstance3D=node
  if node.has_meta("flipbook_meshes"):
   var meshes: Array=[];var materials: Array=[]
   for mesh in node.get_meta("flipbook_meshes"):
    var styled:=_style_frame(mesh,mesh.surface_get_material(0),modes);meshes.append(styled.mesh);materials.append(styled.material)
   _flipbooks.append({"node":node,"times":node.get_meta("flipbook_times"),"indices":node.get_meta("flipbook_indices"),"meshes":meshes,"materials":materials,"last":-999})
  else:
   for index in range(mesh_node.mesh.get_surface_count()):
    var original: Material=mesh_node.get_active_material(index)
    if original==null:continue
    var styled:=_style_frame(mesh_node.mesh,original,modes);mesh_node.mesh=styled.mesh;mesh_node.set_surface_override_material(index,styled.material)
 for child in node.get_children():_style_visual(child,modes)

func _collect_players(node: Node) -> void:
 if node is AnimationPlayer:players.append(node)
 if node.get_script()!=null and node is Node3D:node.set("autoplay",false);node.set("free_on_finish",false)
 for child in node.get_children():_collect_players(child)


## Fireball in flight: the ball is drawn as three camera-facing glows (orange halo, flame body, white-hot
## heart) where the authored ball sits. Same shader as client/effects.gd sprites (compiled at load); 3 quads.
func _add_fire_glow(root: Node3D) -> void:
 var centre:=Vector3.ZERO;var count:=0
 for mesh in root.find_children("*","MeshInstance3D",true,false):
  if mesh.mesh==null:continue
  centre+=root.global_transform.affine_inverse()*mesh.global_transform*mesh.mesh.get_aabb().get_center();count+=1
 if count>0:centre/=count
 for spec in [[1.9,Color(1.0,0.38,0.06,0.9)],[1.0,Color(1.0,0.62,0.18,1.0)],[0.5,Color(1.0,0.96,0.75,1.0)]]:
  var quad:=MeshInstance3D.new();quad.mesh=QuadMesh.new();quad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var glow:=ShaderMaterial.new();glow.shader=preload("res://client/vfx/vfx_sprite.gdshader")
  glow.set_shader_parameter("mode",0);glow.set_shader_parameter("billboard",1);glow.set_shader_parameter("color",spec[1])
  glow.set_shader_parameter("progress",0.0);glow.set_shader_parameter("opacity",1.0);glow.set_shader_parameter("pull",0.4)
  quad.material_override=glow;quad.scale=Vector3.ONE*float(spec[0]);quad.position=centre;quad.extra_cull_margin=2.0
  root.add_child(quad)
