extends Node3D
## Small untextured low-poly straw target; no gameplay state or collision ownership.
var monster_model_path:=""
var _parts:Dictionary={}
var _body:Node3D
var _impact:=0.0
func _ready()->void:
 set_meta("status_vfx_size",Vector3(1.05,1.8,.7))
 _body=Node3D.new();add_child(_body)
 _cylinder(Vector3(0,.72,0),.1,.1,1.45,Color("65462c"))
 _cylinder(Vector3(0,.09,0),.38,.46,.18,Color("525858"))
 _cylinder(Vector3(0,1.12,0),.35,.3,.65,Color("b99b58"))
 _cylinder(Vector3(0,1.18,0),.09,.09,1.4,Color("755737"),Vector3(0,0,PI/2))
 for side in [-1,1]:
  _cylinder(Vector3(side*.48,1.18,0),.14,.17,.34,Color("c8aa62"),Vector3(0,0,PI/2))
 var head:=SphereMesh.new();head.radius=.235;head.height=.47;head.radial_segments=8;head.rings=3
 _part(head,Vector3(0,1.66,0),Color("cfb77a"))
 var pad:=CylinderMesh.new();pad.top_radius=.24;pad.bottom_radius=.24;pad.height=.035;pad.radial_segments=12
 _part(pad,Vector3(0,1.15,.31),Color("824a34"),Vector3(PI/2,0,0))
 for radius in [.16,.07]:
  var ring:=TorusMesh.new();ring.inner_radius=radius-.015;ring.outer_radius=radius+.015;ring.rings=12;ring.ring_segments=3
  _part(ring,Vector3(0,1.15,.34),Color("e5cd8e"),Vector3(PI/2,0,0))
 for x in [-.085,.085]:
  var eye:=SphereMesh.new();eye.radius=.026;eye.height=.052;eye.radial_segments=6;eye.rings=2
  _part(eye,Vector3(x,1.7,.215),Color("302b22"))
 for y in [.91,1.4]:
  var rope:=TorusMesh.new();rope.inner_radius=.29;rope.outer_radius=.32;rope.rings=8;rope.ring_segments=3
  _part(rope,Vector3(0,y,0),Color("68512f"))
 for index in range(7):
  var straw:=BoxMesh.new();straw.size=Vector3(.045,.17,.035)
  _part(straw,Vector3((index-3)*.08,.76,.15),Color("d3b670"),Vector3(0,0,(index-3)*.06))
 for color in _parts:
  var mesh:=MeshInstance3D.new();mesh.mesh=_parts[color].commit()
  var mat:=StandardMaterial3D.new();mat.albedo_color=Color.WHITE;mat.vertex_color_use_as_albedo=true;mat.roughness=1;mesh.material_override=mat
  _body.add_child(mesh)
 var tag:=Label3D.new();tag.text="TRAINING";tag.position.y=2.1;tag.font_size=24;tag.pixel_size=.008;tag.billboard=BaseMaterial3D.BILLBOARD_ENABLED;tag.modulate=Color("d6c18c");add_child(tag)
func _part(mesh:Mesh,at:Vector3,color:Color,rotation:Vector3=Vector3.ZERO)->void:
 var key:="painted_straw"
 if not _parts.has(key):
  var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);_parts[key]=surface
 var arrays:=mesh.surface_get_arrays(0)
 var colors:=PackedColorArray();colors.resize(arrays[Mesh.ARRAY_VERTEX].size());colors.fill(color)
 arrays[Mesh.ARRAY_COLOR]=colors
 var painted:=ArrayMesh.new();painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 _parts[key].append_from(painted,0,Transform3D(Basis.from_euler(rotation),at))
func _cylinder(at:Vector3,top:float,bottom:float,height:float,color:Color,rotation:Vector3=Vector3.ZERO)->void:
 var mesh:=CylinderMesh.new();mesh.top_radius=top;mesh.bottom_radius=bottom;mesh.height=height;mesh.radial_segments=8
 _part(mesh,at,color,rotation)
func flash()->void:_impact=.15
func _process(delta:float)->void:
 _impact=maxf(0,_impact-delta);_body.rotation.z=sin(_impact*90)*_impact*.25
