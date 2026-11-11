extends RefCounted
## Offline vertex-painted terrain + opaque MultiMesh grass tufts: shared draws, no textures, alpha, runtime noise or collision.
static func stats(scene:Node3D)->Dictionary:
 var triangles=0;var draws=0
 for node in scene.get_children():
  var mesh:Mesh=null;var copies=1
  if node is MeshInstance3D:mesh=node.mesh
  elif node is MultiMeshInstance3D:mesh=node.multimesh.mesh;copies=node.multimesh.instance_count
  if mesh==null:continue
  for i in mesh.get_surface_count():
   var a=mesh.surface_get_arrays(i)
   triangles+=int((a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3)*copies;draws+=1
 return {"triangles_instanced":triangles,"draw_surfaces":draws}

static func colour(x:float,z:float,noise:FastNoiseLite)->Color:
 var n=noise.get_noise_2d(x,z)
 var path=1.0-smoothstep(1.1,3.3,absf(x+sin(z*.27)*.7))
 var dirt=clampf(path*.9+smoothstep(.05,.55,n)*.6,0,1)
 return Color("59613b").lerp(Color("756044"),dirt).lerp(Color("414c2e"),clampf(-n*.6,0,.3))

static func apply(scene:Node3D,w:float,depth:float,d:Dictionary={})->void:
 for name in ["soil","dark","Ground","Grass"]:
  var old=scene.get_node_or_null(NodePath(name))
  if old!=null:scene.remove_child(old);old.free()
 var noise=FastNoiseLite.new();noise.seed=631;noise.frequency=.28;noise.fractal_octaves=2
 var plane=PlaneMesh.new();plane.size=Vector2(2,2);plane.subdivide_width=40;plane.subdivide_depth=32
 var arrays=plane.get_mesh_arrays();var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var colours=PackedColorArray()
 for i in points.size():
  var u=points[i].x;var v=points[i].z
  points[i]=Vector3(u*sqrt(1-v*v*.5)*(w+8),0,v*sqrt(1-u*u*.5)*(depth+8))
  colours.append(colour(points[i].x,points[i].z,noise))
 arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_COLOR]=colours
 var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var material=StandardMaterial3D.new();material.resource_name="Goblin_Grass_Dirt";material.vertex_color_use_as_albedo=true;material.roughness=1
 mesh.surface_set_material(0,material)
 var ground=MeshInstance3D.new();ground.name="Ground";ground.mesh=mesh;ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 # (ToonStyle runs while the builder renders and its material is baked into the scene: a flat floor gets toon
 # shading but no ink outline pass, which was a second whole-floor draw that only ever showed under the floor.)
 ground.set_meta("toon_no_outline",true);scene.add_child(ground);ground.owner=scene
 scatter_grass(scene,w,depth,d)
 split_back_row(scene,depth)

## One MultiMesh is culled as a whole, so the palisade's back row (behind the north fence line) and its side
## pieces were always drawn together. Split them: from the south half of the arena the back row is off-screen.
static func split_back_row(scene:Node3D,depth:float)->void:
 var node=scene.get_node_or_null("palisade") as MultiMeshInstance3D
 if node==null or scene.get_node_or_null("palisade_sides")!=null:return
 var back:Array=[];var sides:Array=[];var mm:MultiMesh=node.multimesh
 for i in mm.instance_count:
  var t=mm.get_instance_transform(i)
  if t.origin.z< -depth:back.append(t)
  else:sides.append(t)
 if back.is_empty() or sides.is_empty():return
 for pair in [[node,back],[null,sides]]:
  var target:MultiMeshInstance3D=pair[0]
  if target==null:target=MultiMeshInstance3D.new();target.name="palisade_sides";scene.add_child(target);target.owner=scene
  var out=MultiMesh.new();out.transform_format=MultiMesh.TRANSFORM_3D;out.mesh=mm.mesh;out.instance_count=pair[1].size()
  for i in pair[1].size():out.set_instance_transform(i,pair[1][i])
  target.multimesh=out

## Grass: the verdant_reach painted-vertex tuft/fern props (18/64 tri, opaque, no texture) as one MultiMesh each,
## saved as shared .res next to the kit meshes. Tufts gather at obstacle feet and along the palisade/sides, a light
## scatter elsewhere; the central dirt path, spawn, exits, rest spots and campfire stay clear.
const GRASS_SOURCES={"GrassTufts":["res://art/maps/verdant_reach/props/grass.glb","grass_tuft",Color(1,1,.92)],"Ferns":["res://art/maps/verdant_reach/props/fern.glb","fern",Color(.9,.95,.85)]}
static func prop_mesh(key:String)->Mesh:
 var row:Array=GRASS_SOURCES[key];var path="res://art/props/goblin_base/meshes/"+str(row[1])+".res"
 var doc=GLTFDocument.new();var state=GLTFState.new();assert(doc.append_from_file(row[0],state)==OK)
 var source=doc.generate_scene(state);var mi:MeshInstance3D=source if source is MeshInstance3D else source.find_children("*","MeshInstance3D",true,false)[0]
 var mesh:ArrayMesh=ArrayMesh.new();var arrays=mi.mesh.surface_get_arrays(0);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var mat=StandardMaterial3D.new();mat.resource_name="Goblin_"+str(row[1]);mat.vertex_color_use_as_albedo=true;mat.vertex_color_is_srgb=false  # (COLOR_0 is linear; same convention as the ground)
 mat.albedo_color=row[2];mat.roughness=1;mat.metallic_specular=.1;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mesh.surface_set_material(0,mat)
 source.free();assert(ResourceSaver.save(mesh,path)==OK);return load(path)

static func scatter_grass(scene:Node3D,w:float,depth:float,d:Dictionary)->void:
 for name in GRASS_SOURCES:
  var old=scene.get_node_or_null(NodePath(name))
  if old!=null:scene.remove_child(old);old.free()
 var rng=RandomNumberGenerator.new();rng.seed=3110+str(d.get("id","")).hash()%1000
 var clear:Array=[]  # [centre, radius]
 if d.has("spawn"):clear.append([Vector2(d.spawn[0],d.spawn[2]),1.4])
 for p in d.get("exit_portals",[]):clear.append([Vector2(p[0],p[2]),1.6])
 for p in d.get("rest_points",[]):
  var at=p.get("position",p) if p is Dictionary else p
  if at is Array and at.size()>=3:clear.append([Vector2(at[0],at[2]),1.2])
 if d.has("campfire"):clear.append([Vector2(d.campfire[0],d.campfire[2]),1.8])
 var solids:Array=d.get("solids",[]).slice(1)
 var ok=func(x:float,z:float)->bool:
  if absf(x+sin(z*.27)*.7)<1.9:return false  # the dirt path (see colour())
  if Vector2(x/(w+5.5),z/(depth+5)).length()>.95:return false
  for c in clear:
   if Vector2(x,z).distance_to(c[0])<c[1]:return false
  for s in solids:  # not inside an obstacle's dressing
   if absf(x-s.center[0])<s.size[0]*.5+.05 and absf(z-s.center[2])<s.size[2]*.5+.05:return false
  return true
 var tufts:Array=[];var ferns:Array=[]
 for s in solids:  # obstacle feet: the dressing sits in grass, not on a bare floor
  var hx=s.size[0]*.5;var hz=s.size[2]*.5
  for k in rng.randi_range(6,9):
   var a=rng.randf()*TAU;var r=rng.randf_range(.08,.4)
   var x=s.center[0]+cos(a)*(hx+r);var z=s.center[2]+sin(a)*(hz+r)
   x=clampf(x,s.center[0]-hx-.45,s.center[0]+hx+.45);z=clampf(z,s.center[2]-hz-.45,s.center[2]+hz+.45)
   if ok.call(x,z):tufts.append([x,z,rng.randf_range(1.0,1.5)])
  if rng.randf()<.6:
   var a=rng.randf()*TAU;var x=s.center[0]+cos(a)*(hx+.35);var z=s.center[2]+sin(a)*(hz+.35)
   if ok.call(x,z):ferns.append([x,z,rng.randf_range(.6,.85)])
 for i in 70:  # palisade foot (north) and the side edges
  var x:float;var z:float
  if i<34:x=rng.randf_range(-w-1,w+1);z=-depth+rng.randf_range(-1.2,.7)
  else:x=(w+rng.randf_range(-.7,1.8))*(1 if i%2 else -1);z=rng.randf_range(-depth,depth)
  if not ok.call(x,z):continue
  if rng.randf()<.12:ferns.append([x,z,rng.randf_range(.6,.85)])
  else:tufts.append([x,z,rng.randf_range(.9,1.5)])
 for i in 95:  # light scatter in small clumps over the open floor and the rim
  var cx=rng.randf_range(-w-4,w+4);var cz=rng.randf_range(-depth-3,depth+3)
  for k in rng.randi_range(1,3):
   var x=cx+rng.randf_range(-.4,.4);var z=cz+rng.randf_range(-.4,.4)
   if ok.call(x,z):tufts.append([x,z,rng.randf_range(.8,1.3)])
 for key in GRASS_SOURCES:
  var rows:Array=tufts if key=="GrassTufts" else ferns
  if rows.is_empty():continue
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=prop_mesh(key);mm.instance_count=rows.size()
  for i in rows.size():
   var r:Array=rows[i];mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(r[2],r[2]*rng.randf_range(.85,1.15),r[2])),Vector3(r[0],0,r[1])))
  var node=MultiMeshInstance3D.new();node.name=key;node.multimesh=mm;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  scene.add_child(node);node.owner=scene
