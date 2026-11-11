"""Native visual review of mummy rest shape and articulated pose; no animation export."""
import bpy,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art_source/monsters/mummy/review';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art_source/monsters/mummy/mummy_rigged.blend'))
rig=bpy.data.objects['mummy_rig'];rig.scale=(2/rig['authored_height_m'],)*3
sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=16
sc.world=bpy.data.worlds.new('Mummy review');sc.world.color=(.25,.25,.25)
sc.render.resolution_x=600;sc.render.resolution_y=720;sc.render.resolution_percentage=100
sc.view_settings.view_transform='AgX'
for loc,power,size in [((3,-4,6),650,5),((-3,2,4),500,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=power;bpy.context.object.data.size=size
bpy.ops.object.camera_add();cam=bpy.context.object;sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=2.65
for name,loc in [('front',(0,-6,1.1)),('side',(6,0,1.1)),('back',(0,6,1.1)),('pose',(3,-6,1.5)),('pose_back',(3,6,1.4))]:
 if name.startswith('pose'):
  for n,angles in {'head':(0,0,-18),'chest':(6,0,5),'upper_arm.L':(28,0,-15),'forearm.L':(60,0,0),'upper_arm.R':(20,0,12),'forearm.R':(35,0,0),'thigh.L':(26,0,0),'shin.L':(-40,0,0),'foot.L':(10,0,0),'thigh.R':(-8,0,0),'bandage_upper.L':(8,0,0),'bandage_lower.L':(-8,0,0)}.items():
   b=rig.pose.bones[n];b.rotation_mode='XYZ';b.rotation_euler=tuple(math.radians(a) for a in angles)
 bpy.context.view_layer.update()
 cam.location=loc;cam.rotation_euler=(Vector((0,0,1.03))-cam.location).to_track_quat('-Z','Y').to_euler()
 sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
print('MUMMY_REVIEW',OUT,flush=True)
