extends Node3D
## Native Studio bow: deform its authored string around the right-hand socket.
## Flying arrows are authoritative Projectiles; this node only draws the held arrow/string.
var weapon: Node3D
var skeleton: Skeleton3D
var right_bone := -1
var strings: Array = []
var markers: Dictionary = {}
var arrow: Node3D
var timings: Dictionary = {}

static func make_arrow() -> Node3D:
 var root:=Node3D.new()
 var wood:=StandardMaterial3D.new();wood.albedo_color=Color("65533b")
 var jade:=StandardMaterial3D.new();jade.albedo_color=Color("63d9b7");jade.metallic=.5;jade.roughness=.3
 var feather:=StandardMaterial3D.new();feather.albedo_color=Color("d8c798");feather.cull_mode=BaseMaterial3D.CULL_DISABLED
 var shaft:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=.002;cylinder.bottom_radius=.002;cylinder.height=.46;cylinder.radial_segments=6;shaft.mesh=cylinder;shaft.material_override=wood;shaft.rotation.x=PI*.5;shaft.position.z=.23;root.add_child(shaft)
 var tip:=MeshInstance3D.new();var cone:=CylinderMesh.new();cone.top_radius=0;cone.bottom_radius=.012;cone.height=.05;cone.radial_segments=4;tip.mesh=cone;tip.material_override=jade;tip.rotation.x=PI*.5;tip.position.z=.485;root.add_child(tip)
 for turn in [0.0,PI*.5]:
  var fin:=MeshInstance3D.new();var plane:=QuadMesh.new();plane.size=Vector2(.035,.055);fin.mesh=plane;fin.material_override=feather;fin.rotation=Vector3(PI*.5,0,turn);fin.position.z=.035;root.add_child(fin)
 return root

func setup(bow: Node3D, rig: Skeleton3D, hand: int, meta: Dictionary) -> void:
 weapon=bow;skeleton=rig;right_bone=hand;timings=meta
 for id in ["grip_main","string_nock","string_draw","string_top","string_bottom","effect_point","arrow_rest"]:
  markers[id]=weapon.find_child(id,true,false)
  if markers[id]==null:push_error("Native bow missing marker "+id);return
 for mesh in weapon.find_children("BowString*","MeshInstance3D",true,false):
  var original: ArrayMesh=mesh.mesh
  var surfaces: Array=[]
  for surface in original.get_surface_count():surfaces.append(original.surface_get_arrays(surface).duplicate(true))
  var mutable:=ArrayMesh.new()
  for arrays in surfaces:
   var dynamic: Array=[];dynamic.resize(Mesh.ARRAY_MAX);dynamic[Mesh.ARRAY_VERTEX]=arrays[Mesh.ARRAY_VERTEX];dynamic[Mesh.ARRAY_INDEX]=arrays[Mesh.ARRAY_INDEX]
   mutable.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,dynamic,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
  var material:=StandardMaterial3D.new();material.albedo_color=Color(.35,.83,.66);material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
  for surface in original.get_surface_count():mutable.surface_set_material(surface,material)
  mesh.mesh=mutable;strings.append({"mesh":mesh,"surfaces":surfaces})
 arrow=make_arrow();add_child(arrow);arrow.top_level=true;arrow.visible=false

func update_pose(active: Dictionary) -> void:
 if arrow==null or not is_instance_valid(weapon):return
 var clip: String=active.get("clip","")
 var time: float=active.get("time",0)
 var shooting:=clip in ["Bow_shoot","Bow_heavy"]
 var lab:=clip.begins_with("Lab_")
 var held: bool=(lab and bool(timings.get(clip,{}).get("held_arrow",false)) and time<float(timings.get(clip,{}).get("release_time_s",0))) or clip in ["StandBow","Bow_draw","bow_run","bow_dash"] or (shooting and time<float(timings.get(clip,{}).get("release_time_s",0)))
 var nock: Vector3=markers.string_nock.position
 var contact:=nock
 if held:
  var hand_world: Vector3=(skeleton.global_transform*skeleton.get_bone_global_pose(right_bone)).origin
  contact=weapon.to_local(hand_world)
 var height: float=absf(markers.string_top.position.y)
 for entry in strings:
  var mesh: MeshInstance3D=entry.mesh
  for surface in entry.surfaces.size():
   var original: Array=entry.surfaces[surface]
   var vertices: PackedVector3Array=(original[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
   for i in vertices.size():
    var local: Vector3=mesh.transform*vertices[i]
    var weight:=maxf(0,1-absf(local.y)/maxf(height,.001))
    vertices[i]=mesh.transform.affine_inverse()*(local+(contact-nock)*weight)
   mesh.mesh.surface_update_vertex_region(surface,0,vertices.to_byte_array())
 arrow.visible=held
 if held:
  arrow.global_transform=Transform3D(markers.effect_point.global_basis.orthonormalized(),weapon.to_global(contact))
