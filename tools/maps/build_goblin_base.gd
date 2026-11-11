extends SceneTree
## Visual geometry and map collision originate from the same JSON boxes.
const MAPS=["goblin_base_gate","goblin_base_courtyard","goblin_base_quarry","goblin_base_chief","goblin_base_rest"]
var groups:Dictionary
var materials:Dictionary
func _initialize()->void:call_deferred("run")
func piece(mesh:Mesh,pos:Vector3,role:String,rotation:Vector3=Vector3.ZERO)->void:
 var basis=Basis.from_euler(rotation)
 groups[role].append_from(mesh,0,Transform3D(basis,pos))
func box(pos:Vector3,size:Vector3,role:String,rotation:Vector3=Vector3.ZERO)->void:
 var mesh=BoxMesh.new();mesh.size=size;piece(mesh,pos,role,rotation)
func cone(pos:Vector3,lower:float,upper:float,height:float,role:String)->void:
 var mesh=CylinderMesh.new();mesh.radial_segments=6;mesh.rings=1;mesh.top_radius=upper;mesh.bottom_radius=lower;mesh.height=height;piece(mesh,pos,role)
func rock(pos:Vector3,size:Vector3)->void:
 var mesh=SphereMesh.new();mesh.radius=.5;mesh.height=1;mesh.radial_segments=6;mesh.rings=2
 groups["stone"].append_from(mesh,0,Transform3D(Basis.from_scale(size),pos))
var kit_groups:Dictionary
var kit_meshes:Dictionary
## Obstacle dressing (tools/blender/build_goblin_base_dressing.py): each piece encloses the UNIT collider box, so
## scaling it to the obstacle AABB (x1.03, faces never z-fight) hides StageView's plain collider box completely.
const DRESSING=["goblin_crate","goblin_stoneblock","goblin_logwall"]
func dress(index:int,pos:Vector3,size:Vector3)->void:
 var long_side=maxf(size.x,size.z);var short_side=minf(size.x,size.z)
 var kind="goblin_crate" if index%2==1 else "goblin_stoneblock"
 if long_side/short_side>=1.8:kind="goblin_logwall"
 elif size.y/long_side>=1.6:kind="goblin_stoneblock"  # tall and narrow: a stone pillar
 var yaw=PI if index%3==0 else 0.0
 var local=Vector3(size.x,size.y,size.z)
 if kind=="goblin_logwall" and size.z>size.x:yaw=PI*.5;local=Vector3(size.z,size.y,size.x)  # (the log axis is x)
 var foot=Vector3(pos.x,pos.y-size.y*.5,pos.z)
 if not kit_groups.has(kind):kit_groups[kind]=[]
 kit_groups[kind].append(Transform3D(Basis(Vector3.UP,yaw)*Basis.from_scale(local*Vector3(1.03,1.02,1.03)),foot))
func kit(name:String,pos:Vector3,yaw:float=0,scale_factor:float=1)->void:
 if not kit_groups.has(name):kit_groups[name]=[]
 kit_groups[name].append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale_factor),pos))
func run()->void:
 if DisplayServer.get_name()=="headless":push_error("Use native rendering: dummy renderer cannot serialize MultiMesh transforms");quit(1);return
 if "--terrain-only" in OS.get_cmdline_user_args():
  var report=JSON.parse_string(FileAccess.get_file_as_string("res://art/maps/goblin_base/manifest.json"))
  for id in MAPS:
   var scene=load("res://art/maps/goblin_base/"+id+".tscn").instantiate()
   var d=JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/"+id+".json"))
   preload("res://tools/maps/goblin_terrain.gd").apply(scene,float(d.bounds.half_width),float(d.bounds.half_depth),d)
   report[id].merge(preload("res://tools/maps/goblin_terrain.gd").stats(scene),true)
   report[id]["terrain"]="vertex-painted grass/dirt + MultiMesh grass tufts/ferns, no extra textures; visual floor duplicate hidden by GoblinGround"
   root.add_child(scene);await process_frame;await RenderingServer.frame_post_draw
   var packed=PackedScene.new();assert(packed.pack(scene)==OK);assert(ResourceSaver.save(packed,"res://art/maps/goblin_base/"+id+".tscn")==OK);scene.free()
  var f=FileAccess.open("res://art/maps/goblin_base/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
  print("GOBLIN TERRAIN BUILT: 5 maps, vertex grass/dirt, open floor, no texture/physics changes");quit();return
 DirAccess.make_dir_recursive_absolute("res://art/maps/goblin_base")
 var report={}
 DirAccess.make_dir_recursive_absolute("res://art/props/goblin_base/meshes")
 var catalogue:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://art/props/goblin_base/manifest.json"))
 var kit_directory: String = "kit_parts_optimized" if "--optimized" in OS.get_cmdline_user_args() else "kit_parts"
 for row in catalogue.parts:
  var name:String=row.id;var doc=GLTFDocument.new();var state=GLTFState.new()
  assert(doc.append_from_file("res://art_source/props/goblin_base/"+kit_directory+"/"+name+".glb",state)==OK)
  var source=doc.generate_scene(state)
  var mi=source if source is MeshInstance3D else source.find_children("*","MeshInstance3D",true,false)[0]
  var mesh:Mesh=mi.mesh
  for i in mesh.get_surface_count():
   var mat:StandardMaterial3D=mesh.surface_get_material(i)
   mat.albedo_texture=load("res://art/props/goblin_base/shared/relic_colour.png")
   mat.normal_texture=load("res://art/props/goblin_base/shared/relic_normal.png")
   mat.metallic_texture=load("res://art/props/goblin_base/shared/relic_mr.png");mat.roughness_texture=mat.metallic_texture
   mat.roughness=.95;mat.metallic=.25
  var path="res://art/props/goblin_base/meshes/"+name+".res";assert(ResourceSaver.save(mesh,path)==OK);kit_meshes[name]=load(path)
  row.authoring_glb="art_source/props/goblin_base/kit_parts/"+name+".glb";row.path=row.authoring_glb;row.runtime_path="meshes/"+name+".res";row.runtime_bytes=FileAccess.get_file_as_bytes(path).size()
  source.free()
 for name in DRESSING:
  var doc=GLTFDocument.new();var state=GLTFState.new()
  assert(doc.append_from_file("res://art_source/props/goblin_base/dressing/"+name+".glb",state)==OK)
  var source=doc.generate_scene(state);var mi:MeshInstance3D=source if source is MeshInstance3D else source.find_children("*","MeshInstance3D",true,false)[0]
  var mesh:Mesh=mi.mesh;var mat=StandardMaterial3D.new();mat.resource_name="Goblin_dressing";mat.vertex_color_use_as_albedo=true;mat.roughness=.92;mat.metallic_specular=.15
  mesh.surface_set_material(0,mat)
  var path="res://art/props/goblin_base/meshes/"+name+".res";assert(ResourceSaver.save(mesh,path)==OK);kit_meshes[name]=load(path);source.free()
 var catalogue_file=FileAccess.open("res://art/props/goblin_base/manifest.json",FileAccess.WRITE);catalogue_file.store_string(JSON.stringify(catalogue,"  "));catalogue_file.close()
 for id in MAPS:
  var d:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/"+id+".json"))
  var root_node=Node3D.new();root_node.name=id;groups={};materials={};kit_groups={}
  var colours={"wood":Color("51473d"),"soil":Color("363d32"),"stone":Color("555c5d"),"dark":Color("30372f"),"fire":Color("b78551")}
  for role in colours:
   var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);groups[role]=st
   var mat=StandardMaterial3D.new();mat.resource_name="Goblin_"+role;mat.albedo_color=colours[role];mat.roughness=.9;materials[role]=mat
  var w=float(d.bounds.half_width);var depth=float(d.bounds.half_depth)
  var skirt=CylinderMesh.new();skirt.radial_segments=16;skirt.rings=1;skirt.top_radius=1;skirt.bottom_radius=1;skirt.height=.3
  groups["soil"].append_from(skirt,0,Transform3D(Basis.from_scale(Vector3(w+8,1,depth+8)),Vector3(0,-.166,0)))
  for i in range(d.solids.size()):
   var solid=d.solids[i];var pos=Vector3(solid.center[0],solid.center[1],solid.center[2]);var size=Vector3(solid.size[0],solid.size[1],solid.size[2])
   if i==0:box(pos,size,"soil")
   else:dress(i,pos,size)
  box(Vector3(0,.007,0),Vector3(2,.012,depth*2),"dark")
  var portals:Array=d.get("exit_portals",[[-4.8,.05,-depth+2],[4.8,.05,-depth+2]])
  var gate_x=[]
  for portal in portals:
   gate_x.append(float(portal[0]));kit("gate",Vector3(portal[0],0,-depth-1.5))
  for i in range(int(w*2/2.0)+1):
   var x=-w+i*2.0;var gap=false
   for gx in gate_x:
    if absf(x-gx)<2:gap=true
   if not gap:kit("palisade",Vector3(x,0,-depth-1.5))
  for side in [-1,1]:
   # Side cover is scenery outside the playable limits; leave the south side clear for camera.
   for i in range(2):kit("palisade",Vector3(side*(w+1.8),0,-depth+4+i*6.8),side*PI*.5)
   if id!="goblin_base_chief" or side==1:kit("hut",Vector3(side*(w+4.2),0,-depth*.1),-side*PI*.5)
   kit("tower",Vector3(side*(w+2.2),0,-depth-2.8))
   kit("corner",Vector3(side*(w+.8),0,-depth-1.8),-side*PI*.25)
   kit("banner",Vector3(side*(w+.9),0,depth*.65))
   if side==1:kit("crate",Vector3(side*(w+3.0),0,depth*.4))
  kit("weapon_rack",Vector3(-w-3.0,0,-depth*.5),PI*.5)
  if id=="goblin_base_chief":
   box(Vector3(0,.25,-depth-2.8),Vector3(6,.5,3),"stone")
   kit("hut",Vector3(0,.5,-depth-2.8),0,1.3)
   for x in [-3.5,3.5]:kit("banner",Vector3(x,0,-depth-1.5))
  elif id=="goblin_base_quarry":
   for i in range(5):cone(Vector3(-w+i*w*.5,.7,-depth-3.8),2,.8,1.4,"stone")
  if d.has("campfire"):
   var p=d.campfire;cone(Vector3(p[0],p[1]+.3,p[2]),.4,0,.6,"fire");kit("cauldron",Vector3(w+3.5,0,0),0,.7)
  var tris=0;var draws=0
  for role in groups:
   var mesh:ArrayMesh=groups[role].commit()
   if mesh==null or mesh.get_surface_count()==0:continue
   mesh.surface_set_material(0,materials[role]);var arrays=mesh.surface_get_arrays(0);tris+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size())/3;draws+=1
   var mi=MeshInstance3D.new();mi.name=role;mi.mesh=mesh;root_node.add_child(mi);mi.owner=root_node
  for name in kit_groups:
   var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=kit_meshes[name];mm.instance_count=kit_groups[name].size()
   for i in mm.instance_count:mm.set_instance_transform(i,kit_groups[name][i])
   for surface in mm.mesh.get_surface_count():tris+=mm.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3*mm.instance_count;draws+=1
   var mi=MultiMeshInstance3D.new();mi.name=name;mi.multimesh=mm;root_node.add_child(mi);mi.owner=root_node
  # Semantic markers are generated from the same gameplay data, never guessed from scenery.
  var marker=Node3D.new();marker.name="spawn";marker.position=Vector3(d.spawn[0],d.spawn[1],d.spawn[2]);root_node.add_child(marker);marker.owner=root_node
  for i in d.enemy_spawns.size():
   marker=Node3D.new();marker.name="enemy_%d"%i;var p=d.enemy_spawns[i].position;marker.position=Vector3(p[0],p[1],p[2]);root_node.add_child(marker);marker.owner=root_node
  for i in portals.size():
   marker=Node3D.new();marker.name="exit_portal_%d"%i;var p=portals[i];marker.position=Vector3(p[0],p[1],p[2]);root_node.add_child(marker);marker.owner=root_node
  if d.has("campfire"):
   marker=Node3D.new();marker.name="campfire";var p=d.campfire;marker.position=Vector3(p[0],p[1],p[2]);root_node.add_child(marker);marker.owner=root_node
  preload("res://tools/maps/goblin_terrain.gd").apply(root_node,w,depth,d)
  var measured=preload("res://tools/maps/goblin_terrain.gd").stats(root_node);tris=measured.triangles_instanced;draws=measured.draw_surfaces
  root.add_child(root_node)
  await process_frame
  await RenderingServer.frame_post_draw
  for child in root_node.get_children():
   if child is MultiMeshInstance3D:assert(child.multimesh.buffer.size()==child.multimesh.instance_count*12)
  var packed=PackedScene.new();assert(packed.pack(root_node)==OK);assert(ResourceSaver.save(packed,"res://art/maps/goblin_base/"+id+".tscn")==OK)
  report[id]={"triangles_instanced":tris,"draw_surfaces":draws,"textures":"one shared kit colour1024/normal512/MR512","collision_source":"data/maps/"+id+".json"}
  root_node.free()
 var f=FileAccess.open("res://art/maps/goblin_base/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "))
 print("GOBLIN BASE BUILT ",report);quit()
