"""Convert supplied forge to an embedded GLB with 1024 color / 512 data maps; source FBX remains untouched."""
import bpy,sys,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
source=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else ROOT.parent/'assets/backsmith_fire.fbx'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(source))
objects=list(bpy.context.scene.objects)
meshes=[o for o in objects if o.type=='MESH']
points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)])
factor=5.0/(hi.x-lo.x)
wrapper=bpy.data.objects.new('BlacksmithForge',None);bpy.context.collection.objects.link(wrapper)
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
out=ROOT/'art/props/blacksmith_forge';out.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(out/'blacksmith_forge.glb'),export_format='GLB',export_animations=False)
report={'source':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),'game_size_xyz':[float((hi-lo).x*factor),float((hi-lo).z*factor),float((hi-lo).y*factor)],'textures':images,'texture_budget':{'base_color':1024,'normal':512,'metallic_roughness':512}}
(out/'asset.json').write_text(json.dumps(report,indent=2)+'\n')
if '--render' not in sys.argv:
 print('FORGE_REPORT',json.dumps(report));raise SystemExit(0)
# Review-only render; cameras/lights are added after GLB export.
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=16
scene.render.resolution_x=900;scene.render.resolution_y=700;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('ReviewWorld');scene.world.color=(0.25,0.25,0.25)
camera_data=bpy.data.cameras.new('Review');camera=bpy.data.objects.new('Review',camera_data);scene.collection.objects.link(camera)
camera.location=(7,-10,7);target=Vector((0,0,1.15));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.type='ORTHO';camera_data.ortho_scale=7.5;scene.camera=camera
for name,pos,power,size in [('Key',(2,-3,5),700,4),('Fill',(-3,-1,2),450,3)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;lamp=bpy.data.objects.new(name,data);scene.collection.objects.link(lamp);lamp.location=pos;lamp.rotation_euler=(target-lamp.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath='/tmp/blacksmith-forge-asset.png';bpy.ops.render.render(write_still=True)
print('FORGE_REPORT',json.dumps(report))
