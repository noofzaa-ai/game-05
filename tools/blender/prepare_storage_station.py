"""Convert supplied storage station to an embedded GLB with 1024 color / 512 data maps; source FBX remains untouched."""
import bpy,sys,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
source=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else ROOT.parent/'assets/storage_item.fbx'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(source))
objects=list(bpy.context.scene.objects)
meshes=[o for o in objects if o.type=='MESH']
points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)])
factor=4.8/(hi.x-lo.x)
wrapper=bpy.data.objects.new('StorageStation',None);bpy.context.collection.objects.link(wrapper)
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
  image.pack();images.append({'name':image.name,'size':list(image.size)})
out=ROOT/'art/props/storage_station';out.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(out/'storage_station.glb'),export_format='GLB',export_animations=False)
report={'source':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),'game_size_xyz':[float((hi-lo).x*factor),float((hi-lo).z*factor),float((hi-lo).y*factor)],'textures':images,'texture_budget':{'base_color':1024,'normal':512,'metallic_roughness':512}}
(out/'asset.json').write_text(json.dumps(report,indent=2)+'\n')
print("STORAGE_REPORT",json.dumps(report))
