"""Standalone preparation for campfire_assets_split.fbx; preserves actual loose components."""
import bpy,json,math,sys,struct,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2];SOURCE=ROOT.parent/'assets/campfire_assets_split.fbx';EDIT=ROOT/'art_source/props/campfire_workshop';OUT=ROOT/'art/props/campfire_workshop';OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'tools/blender'));from build_orc_kit import glb_external_image
NAMES=['stone_large','log_long','stone_small','log_short','stump','firewood_crossed','log_round','flame','firewood_stack_upper','grass','firewood_stack_lower']
SCALE=4.0
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.fbx(filepath=str(SOURCE));bpy.context.view_layer.update()
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
if len(objects)!=1:raise RuntimeError('Source mesh layout changed; re-inspect before mapping component IDs')
o=objects[0];bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='LOOSE');bpy.ops.object.mode_set(mode='OBJECT')
ordered=sorted([o for o in bpy.context.scene.objects if o.type=='MESH'],key=lambda o:sum(v.co.x for v in o.data.vertices)/len(o.data.vertices))
if len(ordered)!=len(NAMES):raise RuntimeError('Expected eleven actual loose components')
for i,o in enumerate(ordered):o.name=f'component_{i:02d}'
for im in list(bpy.data.images):
 if not im.size[0]:continue
 im.name=Path(im.name).stem;cap=512 if any(t in im.name.lower() for t in ['normal','metallic','roughness','occlusion']) else 1024
 if max(im.size)>cap:im.scale(round(im.size[0]*cap/max(im.size)),round(im.size[1]*cap/max(im.size)))
 im.filepath_raw=str(EDIT/(im.name+'.png'));im.file_format='PNG';im.save();payload=Path(im.filepath_raw).read_bytes();im.pack(data=payload,data_len=len(payload))
parts={};metadata=[]
for i,name in enumerate(NAMES):
 o=bpy.data.objects[f'component_{i:02d}'];o.name=name;pts=[v.co.copy() for v in o.data.vertices];lo=Vector([min(p[j] for p in pts) for j in range(3)]);hi=Vector([max(p[j] for p in pts) for j in range(3)]);pivot=Vector(((hi.x+lo.x)*.5,(hi.y+lo.y)*.5,lo.z));o.data.transform(Matrix.Scale(SCALE,4)@Matrix.Translation(-pivot));o.location=(0,0,0);o.data.calc_loop_triangles();o['component_id']='campfire_'+name;o['source_component']=i;parts[name]=o;metadata.append({'id':name,'triangles':len(o.data.loop_triangles),'dimensions_blender_xyz':list((hi-lo)*SCALE),'pivot':'bottom_center'})
# Source flame keeps its albedo, with restrained emission, no added texture.
flame=parts['flame'];m=flame.data.materials[0].copy();m.name='campfire_original_flame';flame.data.materials[0]=m
bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');link=next((l for l in m.node_tree.links if l.to_node==bs and l.to_socket.name=='Base Color'),None)
if link:m.node_tree.links.new(link.from_socket,bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.35

def export(path,objects):
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_animations=False,export_lights=False,export_cameras=False)
def externalize(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);binary=raw[28+n:];mapping={}
 for i,img in enumerate(doc.get('images',[])):
  name=img.get('name',f'image_{i}');filename='campfire_'+Path(name).stem+'.png';bv=doc['bufferViews'][img['bufferView']];offset=bv.get('byteOffset',0);(OUT/filename).write_bytes(binary[offset:offset+bv['byteLength']]);mapping[Path(name).stem]=filename
 glb_external_image(str(path),mapping)
export(OUT/'campfire_components.glb',parts.values());externalize(OUT/'campfire_components.glb')
for name,o in parts.items():export(OUT/(name+'.glb'),[o]);externalize(OUT/(name+'.glb'))
# Save reusable source; all pieces have matching actual source relative scale and ground pivots.
bpy.ops.wm.save_as_mainfile(filepath=str(EDIT/'campfire_components.blend'))
levels=[]
for level in [1,2,3]:
 for o in list(bpy.context.scene.objects):
  if o not in parts.values():bpy.data.objects.remove(o,do_unlink=True)
 for o in parts.values():o.hide_render=True;o.hide_set(True)
 instances=[];placements=[]
 def put(name,loc=(0,0,0),angle=0,scale=1):
  src=parts[name];o=src.copy();o.data=src.data;bpy.context.collection.objects.link(o);o.name=f'L{level}_{name}_{len(instances):02d}';o.hide_render=False;o.hide_set(False);o.location=loc;o.rotation_euler.z=angle;o.scale=(scale,scale,scale);instances.append(o);placements.append({'component':name,'position_blender':list(loc),'rotation_z':angle,'scale':scale});return o
 radius={1:.95,2:1.2,3:1.45}[level];count={1:8,2:10,3:12}[level]
 for i in range(count):
  a=math.tau*i/count;name='stone_small' if i%3 else 'stone_large';put(name,(radius*math.cos(a),radius*math.sin(a),0),a, .86 if name=='stone_large' else 1.0)
 put('firewood_crossed',scale={1:1,2:1.12,3:1.3}[level]);put('flame',(0,0,.13),scale={1:1,2:1.2,3:1.5}[level])
 if level>=2:
  put('firewood_crossed',(.15,.08,.12),.6,.88)
 if level==3:
  # Larger ring built from the same stones; no change of palette/era.
  for i in range(8):
   a=math.tau*i/8;put('stone_small',(1.64*math.cos(a),1.64*math.sin(a),.02),a,.85)
 seat_radius={1:2.0,2:2.45,3:2.85}[level]
 for a in ([math.pi] if level==1 else [math.pi,0] if level==2 else [math.pi,0,math.pi/2]):
  put('log_long',(seat_radius*math.cos(a),seat_radius*math.sin(a),0),a+math.pi/2,1.0)
 put('stump',(-.9,-seat_radius+.25,0),0,1)
 if level>=2:
  for x in [0,.38]:
   put('firewood_stack_lower',(x+.6,seat_radius-.15,0),0,1)
   put('firewood_stack_upper',(x+.6,seat_radius-.15,.16),0,1)
 if level==3:
  put('stump',(-1.8,-2.15,0),.2,1);put('log_short',(-1.65,2.0,0),.35,1)
 for i in range(3+level*2):
  a=math.tau*i/(3+level*2)+.2;r=seat_radius+.35;put('grass',(r*math.cos(a),r*math.sin(a),0),a,.65)
 path=OUT/f'campfire_level_{level}.glb';export(path,instances);externalize(path)
 report={'level':level,'id':f'campfire_level_{level}','placements':placements,'triangles':sum(len(o.data.loop_triangles) for o in instances),'fire_anchor_godot':[0,.25,0],'gameplay_unlocks':'not configured; visual proposal only'};levels.append(report);(OUT/f'campfire_level_{level}.json').write_text(json.dumps(report,indent=2)+'\n')
 # Review-only ground and lamps are excluded from asset exports.
 groundmat=bpy.data.materials.new('ReviewGround');groundmat.use_nodes=True;groundmat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.055,.09,.085,1)
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025));bpy.context.object.data.materials.append(groundmat)
 s=bpy.context.scene;s.world=bpy.data.worlds.new('ReviewWorld');s.world.color=(.24,.24,.24)
 for pos,power,size in [((2,-5,8),1100,7),((-5,-1,5),800,6)]:
  bpy.ops.object.light_add(type='AREA',location=pos);lamp=bpy.context.object;lamp.data.energy=power;lamp.data.size=size;lamp.rotation_euler=(Vector((0,0,.3))-lamp.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.light_add(type='POINT',location=(0,0,.65));bpy.context.object.data.energy=35+level*12;bpy.context.object.data.color=(1,.4,.08);bpy.context.object.data.shadow_soft_size=.8
 bpy.ops.object.camera_add(location=(7,-10,8));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.25))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=9.3;s.camera=cam
 s.render.engine='CYCLES';s.cycles.samples=16;s.cycles.use_denoising=True;s.cycles.max_bounces=3;s.render.threads_mode='FIXED';s.render.threads=4;s.render.resolution_x=1280;s.render.resolution_y=960;s.render.resolution_percentage=100
 bpy.ops.wm.save_as_mainfile(filepath=str(EDIT/f'campfire_level_{level}.blend'));s.render.filepath=str(EDIT/f'campfire_level_{level}.png');bpy.ops.render.render(write_still=True)
manifest={'id':'campfire_modular_01','source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'source_bytes':SOURCE.stat().st_size,'source_triangles':sum(p['triangles'] for p in metadata),'parts':metadata,'scale_from_source':SCALE,'texture_caps':{'albedo':1024,'normal':512,'metallic_roughness':512},'levels':[{k:v for k,v in l.items() if k!='placements'} for l in levels],'status':'prepared assets and native visual proposal, not placed in Hub or deployed'}
(OUT/'asset.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('CAMPFIRE_READY',json.dumps({'source_triangles':manifest['source_triangles'],'parts':len(parts),'level_triangles':[l['triangles'] for l in levels]}),flush=True)
