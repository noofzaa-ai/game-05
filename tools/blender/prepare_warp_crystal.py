"""Prepare supplied warp crystal to an embedded GLB with 1024 color / 512 data maps; source FBX remains untouched."""
import bpy,bmesh,sys,json,hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
source=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else ROOT.parent/'assets/crystal.fbx'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(source))
objects=list(bpy.context.scene.objects)
meshes=[o for o in objects if o.type=='MESH']
points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)])
factor=4.8/(hi.x-lo.x)
wrapper=bpy.data.objects.new('WarpCrystal',None);bpy.context.collection.objects.link(wrapper)
for obj in objects:
 if obj.parent is None:
  matrix=obj.matrix_world.copy();obj.parent=wrapper;obj.matrix_world=matrix
wrapper.matrix_world=Matrix.Scale(factor,4)@Matrix.Translation(Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z)))
images=[]
for image in bpy.data.images:
 if image.size[0] and image.size[1]:
  largest=max(image.size)
  cap=512 if any(role in image.name.lower() for role in ("normal", "metallic", "roughness", "occlusion")) else 1024
  if largest>cap: image.scale(round(image.size[0]*cap/largest),round(image.size[1]*cap/largest))
  if cap == 1024:
   # Recolour blue stone, retaining cyan crystals/runes and painted shading.
   pixels=np.array(image.pixels[:],dtype=np.float32).reshape(-1,4)
   rgb=pixels[:,:3]
   weight=np.clip((rgb[:,2]-rgb[:,1]-.025)/.075,0,1)
   weight*=np.clip((rgb[:,2]-rgb[:,0]-.025)/.075,0,1)
   luminance=rgb@np.array([.2126,.7152,.0722],dtype=np.float32)
   stone=np.clip(.19+np.sqrt(luminance)*.68,0,1)[:,None]*np.array([1.0,.965,.90])
   rgb[:]=rgb*(1-weight[:,None])+stone*weight[:,None]
   image.pixels.foreach_set(pixels.ravel());image.update()
  image.pack();images.append({'name':image.name,'size':list(image.size)})
bpy.context.view_layer.update()
# Isolate the tall disconnected central diamond, preserving all faces/UV/materials.
rotors=[]
for ob in meshes:
 points=[ob.matrix_world@v.co for v in ob.data.vertices]
 parents=list(range(len(points))); by_position={}
 def find(i):
  while parents[i]!=i: parents[i]=parents[parents[i]]; i=parents[i]
  return i
 def union(a,b): parents[find(a)]=find(b)
 for i,point in enumerate(points):
  key=tuple(round(v,4) for v in point)
  if key in by_position: union(i,by_position[key])
  else: by_position[key]=i
 for face in ob.data.polygons:
  for index in face.vertices[1:]: union(face.vertices[0],index)
 groups={}
 for i in range(len(points)): groups.setdefault(find(i),set()).add(i)
 for indices in groups.values():
  ps=[points[i] for i in indices]
  low=Vector([min(v[k] for v in ps) for k in range(3)])
  high=Vector([max(v[k] for v in ps) for k in range(3)])
  size=high-low
  if size.z>2.5 and size.x<1.7 and size.y<1.0 and abs((low.x+high.x)/2)<.3 and low.z>.3:
   rotors.append((ob,indices,(low+high)/2))
if len(rotors)!=1: raise RuntimeError('Expected exactly one tall central crystal; review source before export')
ob,indices,pivot=rotors[0]
part=bpy.data.objects.new('CrystalRotor',ob.data.copy());bpy.context.collection.objects.link(part)
part.parent=ob.parent;part.matrix_world=ob.matrix_world.copy()
for target,keep in [(part,True),(ob,False)]:
 bm=bmesh.new();bm.from_mesh(target.data);bm.verts.ensure_lookup_table()
 remove=[v for v in bm.verts if (v.index in indices)!=keep]
 bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(target.data);bm.free()
local_pivot=part.matrix_world.inverted()@pivot
part.data.transform(Matrix.Translation(-local_pivot))
part.matrix_world=part.matrix_world@Matrix.Translation(local_pivot)
part['warp_rotor']=True
out=ROOT/'art/props/warp_crystal';out.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(out/'warp_crystal.glb'),export_format='GLB',export_animations=False)
report={'source':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes+[part]),'game_size_xyz':[float((hi-lo).x*factor),float((hi-lo).z*factor),float((hi-lo).y*factor)],'textures':images,'texture_budget':{'base_color':1024,'normal':512,'metallic_roughness':512},'rotor_pivot_game':[float(pivot.x),float(pivot.z),float(-pivot.y)],'rotor_node':'CrystalRotor'}
(out/'asset.json').write_text(json.dumps(report,indent=2)+'\n')
print("CRYSTAL_REPORT",json.dumps(report))
