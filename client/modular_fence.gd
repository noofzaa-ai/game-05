extends RefCounted
## One shared imported mesh, batched per enclosure. Layout also owns the walk blockers.
const ASSET="res://art/props/modular_wall/modular_wall.glb"
const WIDTH=2.046575
const DEPTH=.5
const HEIGHT=1.35

static var _camp_materials:Dictionary={}
static func _camp_material(source:StandardMaterial3D)->ShaderMaterial:
 var key:=source.get_instance_id()
 if _camp_materials.has(key):return _camp_materials[key]
 var shader:=Shader.new()
 shader.code="""shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D colour_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D packed_mr : filter_linear_mipmap_anisotropic;
void fragment() {
 vec3 colour=texture(colour_map,UV).rgb;
 float grey=dot(colour,vec3(0.2126,0.7152,0.0722));
 ALBEDO=mix(vec3(grey),colour,0.55)*vec3(1.10,1.04,1.00);
 NORMAL_MAP=texture(normal_map,UV).rgb;
 NORMAL_MAP_DEPTH=1.0;
 vec3 mr=texture(packed_mr,UV).rgb;
 ROUGHNESS=max(0.8,mr.g);
 METALLIC=mr.b*0.35;
 SPECULAR=0.15;
}
"""
 var material:=ShaderMaterial.new();material.shader=shader
 material.set_shader_parameter("colour_map",source.albedo_texture)
 material.set_shader_parameter("normal_map",source.normal_texture)
 material.set_shader_parameter("packed_mr",source.roughness_texture)
 _camp_materials[key]=material
 return material

static func training_segments()->Array:
 return [[Vector3(-25,0,-2),Vector3(-11,0,-2)], [Vector3(-25,0,11),Vector3(-11,0,11)], [Vector3(-25,0,-2),Vector3(-25,0,11)], [Vector3(-11,0,-2),Vector3(-11,0,4.7)], [Vector3(-11,0,6.9),Vector3(-11,0,11)]]
static func farm_segments(edge:float)->Array:
 var left:=edge-.2;var right:=edge+8.7
 return [[Vector3(left,0,-8.6),Vector3(right,0,-8.6)], [Vector3(left,0,2.2),Vector3(right,0,2.2)], [Vector3(right,0,-8.6),Vector3(right,0,2.2)], [Vector3(left,0,-8.6),Vector3(left,0,-4.5)], [Vector3(left,0,-2.1),Vector3(left,0,2.2)]]
static func collision_boxes(segments:Array)->Array[AABB]:
 var result:Array[AABB]=[]
 for line in segments:
  var a:Vector3=line[0];var b:Vector3=line[1]
  var lo:=a.min(b)-Vector3(DEPTH*.5,0,DEPTH*.5)
  var size:Vector3=(a-b).abs()+Vector3(DEPTH,HEIGHT,DEPTH)
  result.append(AABB(lo,size))
 return result
static func _batch(parent:Node3D,mesh:Mesh,transforms:Array[Transform3D],label:String)->void:
 var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=mesh;batch.instance_count=transforms.size()
 for i in transforms.size():batch.set_instance_transform(i,transforms[i])
 var visual:=MultiMeshInstance3D.new();visual.name=label;visual.multimesh=batch
 visual.material_override=_camp_material(mesh.surface_get_material(0) as StandardMaterial3D)
 visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(visual)
static func build(parent:Node3D,segments:Array)->void:
 var source:Node3D=load(ASSET).instantiate()
 var rail:MeshInstance3D=source.find_child("Rail",true,false)
 var post:MeshInstance3D=source.find_child("Post",true,false)
 assert(rail!=null and post!=null)
 var rails:Array[Transform3D]=[];var posts:Array[Transform3D]=[];var placed:Dictionary={}
 for line in segments:
  var a:Vector3=line[0];var b:Vector3=line[1];var delta:=b-a
  var count:=maxi(1,roundi(delta.length()/WIDTH))
  var rotation:=Basis(Vector3.UP,-atan2(delta.z,delta.x))
  var basis:=rotation.scaled_local(Vector3(delta.length()/count/WIDTH,1,1))
  for i in count:
   rails.append(Transform3D(basis,a.lerp(b,(i+.5)/count)+Vector3(0,.3,0)))
  for i in count+1:
   var at:=a.lerp(b,float(i)/count);var key:=Vector2(at.x,at.z).snapped(Vector2.ONE*.01)
   if not placed.has(key):
    placed[key]=true;posts.append(Transform3D(rotation,at))
 var group:=Node3D.new();group.name="ModularFence";parent.add_child(group)
 _batch(group,rail.mesh,rails,"Rails");_batch(group,post.mesh,posts,"Posts")
 source.free()
