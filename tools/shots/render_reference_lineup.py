import bpy,math,json
from mathutils import Vector
from pathlib import Path
ROOT=Path('/Users/user/godot-project/test01');GAME=ROOT/'zorx';OUT=GAME/'art_source/characters/reference_size_review'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=16;sc.cycles.use_denoising=True
sc.render.resolution_x=2100;sc.render.resolution_y=920;sc.render.resolution_percentage=100
sc.world.color=(.23,.23,.23)
rows=[('Merchant',GAME/'art/npcs/merchant.glb',.825),('Bank',GAME/'art/npcs/storage.glb',1),('NEW PLAYER',ROOT/'art/characters/mmorpg-reference-base/red_jacket/reference_character_red_jacket.glb',None),('Refine',GAME/'art/npcs/workshops/bs_refine.glb',1),('Upgrade',GAME/'art/npcs/workshops/bs_upgrade.glb',1),('Tailor',GAME/'art/npcs/tailor.glb',.825),('Quest Board',GAME/'art/npcs/quest_board.glb',2)]
def mat(name,col):
 m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);return m
white=mat('Warm white',(.85,.85,.81));gold=mat('Target gold',(1,.65,.17));floor=mat('Floor',(.085,.11,.14))
def text(body,pos,size,material):
 c=bpy.data.curves.new('label','FONT');c.body=body;c.align_x='CENTER';c.size=size
 o=bpy.data.objects.new(body,c);sc.collection.objects.link(o);o.location=pos;o.rotation_euler=(math.pi/2,0,0);o.data.materials.append(material)
def bounds(objects):
 deps=bpy.context.evaluated_depsgraph_get();points=[]
 for o in objects:
  if o.type!='MESH':continue
  ev=o.evaluated_get(deps);me=ev.to_mesh();points.extend(ev.matrix_world@v.co for v in me.vertices);ev.to_mesh_clear()
 return Vector(tuple(min(v[i] for v in points) for i in range(3))),Vector(tuple(max(v[i] for v in points) for i in range(3)))
report=[]
for idx,(name,path,scale) in enumerate(rows):
 old=set(sc.objects);bpy.ops.import_scene.gltf(filepath=str(path));objs=list(set(sc.objects)-old)
 for o in objs:
  if o.animation_data:o.animation_data_clear()
  if o.type=='ARMATURE':
   o.data.pose_position='REST'
 # Imports contain no preview lights/cameras; use only actual meshes for measurements.
 meshes=[o for o in objs if o.type=='MESH' and not o.name.startswith('Icosphere')];lo,hi=bounds(meshes)
 parent=bpy.data.objects.new(name,None);sc.collection.objects.link(parent)
 for o in objs:
  if o.parent not in objs:o.parent=parent
 if scale is None:scale=1.35/(hi.z-lo.z)
 parent.scale=(scale,scale,scale);bpy.context.view_layer.update();lo,hi=bounds(meshes)
 parent.location.x=(idx-3)*1.65-(lo.x+hi.x)/2;parent.location.y=-(lo.y+hi.y)/2;parent.location.z=-lo.z
 height=hi.z-lo.z
 text(name,((idx-3)*1.65,-.5,-.27),.17,gold if name=='NEW PLAYER' else white)
 text(f'{height*100:.0f} cm',((idx-3)*1.65,-.5,-.49),.15,gold if name=='NEW PLAYER' else white)
 report.append({'name':name,'height_m':height,'scale':scale,'source':str(path)})
# Height guides behind the row.
for h in [.5,1,1.35,1.5,2,2.5,3]:
 bpy.ops.mesh.primitive_cube_add(size=1,location=(0,.6,h));o=bpy.context.object;o.scale=(12,.008,.008 if h!=1.35 else .014);o.data.materials.append(gold if h==1.35 else mat('grid'+str(h),(.17,.21,.25)))
 text(f'{h*100:.0f}',(-6.25,.55,h-.04),.13,white)
# No floor surface below the baseline: preserve readable labels.
text('NEW HERO 135 cm  /  CURRENT CAMP NPC SCALES',(0,.55,3.65),.23,white)
text('Same ground plane - orthographic view - outfit / hair included',(0,.55,3.35),.14,white)
for pos,power,size in [((0,-7,7),1800,8),((5,1,5),1400,6)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(0,-22,4));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,1.5))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=13.6;sc.camera=cam
sc.render.filepath=str(OUT/'hero135_vs_current_npcs.png');bpy.ops.render.render(write_still=True)
(OUT/'measurements.json').write_text(json.dumps(report,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'lineup.blend'))
