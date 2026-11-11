"""Preserve supplied rigs; normalize to1.5m and add light Idle/Walk clips."""
import bpy,math,json,sys,hashlib,struct
from pathlib import Path
from mathutils import Matrix,Vector,Quaternion
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).parent));from build_orc_kit import glb_external_image
OUT=ROOT/'art/npcs/workshops';SOURCE=ROOT/'art_source/npcs/workshops';OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
for name in ['bs_refine','bs_upgrade']:
 bpy.ops.wm.read_factory_settings(use_empty=True);src=ROOT.parent/'assets'/(name+'.fbx');bpy.ops.import_scene.fbx(filepath=str(src));bpy.context.view_layer.update()
 objs=list(bpy.context.scene.objects);meshes=[o for o in objs if o.type=='MESH'];arm=next(o for o in objs if o.type=='ARMATURE')
 pts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices];lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);scale=1.5/(hi.z-lo.z)
 wrapper=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(wrapper)
 for o in objs:
  if o.parent is None:o.parent=wrapper
 wrapper.matrix_world=Matrix.Scale(scale,4)@Matrix.Translation(Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z)))
 for im in list(bpy.data.images):
  if not im.size[0]:continue
  im.name=name+'_'+Path(im.name).stem;cap=512 if any(t in im.name for t in ['normal','metallic','roughness']) else 1024
  if max(im.size)>cap:im.scale(round(im.size[0]*cap/max(im.size)),round(im.size[1]*cap/max(im.size)))
  im.filepath_raw=str(SOURCE/(im.name+'.png'));im.file_format='PNG';im.save();data=Path(im.filepath_raw).read_bytes();im.pack(data=data,data_len=len(data))
 # Relax the arms from the supplied A-pose through pose transforms, without replacing rest bones.
 for pb in arm.pose.bones:pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion();pb.location=(0,0,0)
 for side,sign in [('Left',1),('Right',-1)]:
  for suffix,direction in [('Arm',(sign*.12,-.03,-1)),('ForeArm',(sign*.07,-.16,-1))]:
   pb=arm.pose.bones.get(side+suffix)
   if not pb:continue
   bpy.context.view_layer.update();head=pb.head.copy();current=(pb.tail-pb.head).normalized();delta=current.rotation_difference(Vector(direction).normalized());m=(delta@pb.matrix.to_quaternion()).to_matrix().to_4x4();m.translation=head;pb.matrix=m
 bpy.context.view_layer.update();neutral={pb.name:pb.rotation_quaternion.copy() for pb in arm.pose.bones};scene=bpy.context.scene;scene.render.fps=24
 axes={pb.name:pb.bone.matrix_local.to_quaternion().inverted()@Vector((1,0,0)) for pb in arm.pose.bones}
 for clip,frames in [('Idle',48),('Walk',40)]:
  arm.animation_data_create();action=bpy.data.actions.new(clip);arm.animation_data.action=action
  for frame in range(frames+1):
   phase=2*math.pi*frame/frames
   for pb in arm.pose.bones:
    pb.rotation_quaternion=neutral[pb.name].copy();pb.location=(0,0,0)
    amount=0.0
    if clip=='Walk':
     side=1 if pb.name.startswith('Left') else -1;wave=math.sin(phase+(0 if side==1 else math.pi))
     if pb.name.endswith('UpLeg'):amount=.24*wave
     elif pb.name.endswith('Leg'):amount=-.27*max(0,-wave)
     elif pb.name.endswith('Foot'):amount=.07*wave
     elif pb.name.endswith('Arm'):amount=-.16*wave
     elif pb.name.endswith('ForeArm'):amount=.035*wave
     elif pb.name=='Spine2':amount=.018*math.sin(phase)
    elif pb.name in ['Spine2','Head']:amount=.012*math.sin(phase)
    pb.rotation_quaternion=Quaternion(axes[pb.name],amount)@pb.rotation_quaternion
    pb.keyframe_insert(data_path='rotation_quaternion',frame=frame)
  track=arm.animation_data.nla_tracks.new();track.name=clip;track.strips.new(clip,0,action);arm.animation_data.action=None
 scene.frame_set(0);bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
 path=OUT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_frame_range=False,export_force_sampling=True,export_extras=True,export_lights=False,export_cameras=False)
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);binary=raw[28+n:];mapping={}
 for img in doc.get('images',[]):
  fn=img['name']+'.png';bv=doc['bufferViews'][img['bufferView']];off=bv.get('byteOffset',0);(OUT/fn).write_bytes(binary[off:off+bv['byteLength']]);mapping[Path(img['name']).stem]=fn
 glb_external_image(str(path),mapping)
 report={'id':name,'height_m':1.5,'source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),'bones':len(arm.data.bones),'clips':[a.get('name') for a in doc.get('animations',[])],'source_rig_preserved':True,'motion':'in place, gentle procedural FK walk; no foot-contact IK','texture_caps':{'albedo':1024,'normal':512,'metallic_roughness':512}}
 (OUT/(name+'.json')).write_text(json.dumps(report,indent=2)+'\n');print('WORKSHOP_NPC',json.dumps(report),flush=True)
