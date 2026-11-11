"""Bind supplied mummy without changing shape/UVs. Blender -b --factory-startup -P this.py.
Source defaults to ../assets/mummy.glb; optional -- source.glb. No production clips overwritten.
Blender forward -Y / glTF +Z; uniformly fitted to the 1.80m player height, feet at zero.
"""
import bpy, bmesh, math, json, hashlib, sys
from pathlib import Path
import numpy as np
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
SRC=Path(ARGS[0]) if ARGS else ROOT.parent/'assets/mummy.glb'
OUT=ROOT/'art/monsters/mummy';SOURCE=ROOT/'art_source/monsters/mummy'
OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
if len(meshes)!=1 or any(o.type=='ARMATURE' for o in bpy.context.scene.objects):raise RuntimeError('Expected one unrigged source mesh')
body=meshes[0];body.name='mummy'
bpy.context.view_layer.objects.active=body;body.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
P=np.array([v.co[:] for v in body.data.vertices]);original=P.copy();lo=P.min(0);hi=P.max(0)
CX=float((lo[0]+hi[0])/2)
# Anatomical landmarks fitted to this authored A-pose (metres).
def p(x,y,z):return (CX+x,y,z)
J={
 'root':(p(0,0,0),p(0,0,.1),None),
 'hips':(p(0,.02,.47),p(0,.02,.57),'root'),
 'spine':(p(0,.02,.57),p(0,.02,.70),'hips'),
 'chest':(p(0,.02,.70),p(0,.02,.81),'spine'),
 'neck':(p(0,.02,.81),p(0,.015,.87),'chest'),
 'head':(p(0,.015,.87),p(0,.015,1.075),'neck'),
}
for side,sign in [('L',1),('R',-1)]:
 def q(x,y,z):return p(sign*x,y,z)
 J.update({
  'clavicle.'+side:(q(.035,.02,.80),q(.15,.02,.80),'chest'),
  'upper_arm.'+side:(q(.15,.02,.80),q(.24,.022,.64),'clavicle.'+side),
  'forearm.'+side:(q(.24,.022,.64),q(.319,.005,.48),'upper_arm.'+side),
  'hand.'+side:(q(.319,.005,.48),q(.34,-.005,.375),'forearm.'+side),
  'attach_weapon.'+side:(q(.336,-.012,.425),q(.336,-.075,.425),'hand.'+side),
  'thigh.'+side:(q(.095,.025,.47),q(.131,.018,.285),'hips'),
  'shin.'+side:(q(.131,.018,.285),q(.145,.025,.085),'thigh.'+side),
  'foot.'+side:(q(.145,.025,.085),q(.145,-.075,.025),'shin.'+side),
  'toe.'+side:(q(.145,-.075,.025),q(.145,-.14,.025),'foot.'+side),
  'bandage_upper.'+side:(q(.15,.09,.78),q(.16,.12,.585),'upper_arm.'+side),
  'bandage_lower.'+side:(q(.229,.085,.62),q(.225,.115,.475),'forearm.'+side),
 })
arm=bpy.data.armatures.new('mummy_rig');rig=bpy.data.objects.new('mummy_rig',arm);bpy.context.collection.objects.link(rig)
body.select_set(False);rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
for name,(head,tail,parent) in J.items():
 bone=arm.edit_bones.new(name);bone.head=head;bone.tail=tail
 if parent:bone.parent=arm.edit_bones[parent];bone.use_connect=(bone.parent.tail-bone.head).length<1e-5
 bone.align_roll(Vector((0,0,1)) if name.startswith(('foot','toe','attach_weapon')) else Vector((0,-1,0)))
 bone.use_deform=not name.startswith(('root','attach_weapon'))
bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True;arm.display_type='OCTAHEDRAL'
# Surface components distinguish arm shells from hanging wraps and torso at the armpit.
bm=bmesh.new();bm.from_mesh(body.data);seen=set();regions={}
for vertex in bm.verts:
 if vertex.index in seen:continue
 stack=[vertex];seen.add(vertex.index);ids=[]
 while stack:
  v=stack.pop();ids.append(v.index)
  for edge in v.link_edges:
   other=edge.other_vert(v)
   if other.index not in seen:seen.add(other.index);stack.append(other)
 pts=P[ids];mn=pts.min(0);mx=pts.max(0);ax=np.abs(pts[:,0]-CX)
 region='body'
 if mn[2]>.90 or (mn[2]>.80 and mx[2]>1.02):region='head'
 elif ax.min()>.19 or (ax.min()>.09 and mn[2]>.55 and mx[2]<.86 and ax.max()>.18):region='arm'
 if mn[1]>.065 and mn[2]>.45:region='wrap'
 if ax.min()>.11 and ax.max()<.21 and mn[2]>.57 and mx[2]<.80 and mx[1]>.12:region='wrap'
 for i in ids:regions[i]=region
bm.free()
def smooth(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)
def segment_dist(v,name):
 a=np.array(J[name][0]);b=np.array(J[name][1]);d=b-a;t=np.clip(np.dot(v-a,d)/np.dot(d,d),0,1)
 return float(np.linalg.norm(v-(a+t*d)))
def nearest(v,names,width=.045):
 distances=np.array([segment_dist(v,n) for n in names]);d=distances.min()
 w=np.exp(-((distances-d)/width)**2*2)
 return {n:float(x) for n,x in zip(names,w) if x>.001}
names=[b.name for b in arm.bones if b.use_deform];weights=[]
for i,v in enumerate(P):
 x,y,z=v;ax=abs(x-CX);side='L' if x>CX else 'R';region=regions[i]
 if region=='head' or z>=.91:w={'head':1.}
 elif region=='wrap' or (y>.075 and ax>.20 and ax<.25 and .46<z<.64):
  w={('bandage_upper.' if z>.57 and ax<.21 else 'bandage_lower.')+side:1.}
 elif region=='arm':
  w=nearest(v,['clavicle.'+side,'upper_arm.'+side,'forearm.'+side,'hand.'+side],.042)
 elif z<.47:
  w=nearest(v,['hips','thigh.'+side,'shin.'+side,'foot.'+side,'toe.'+side],.035)
  if z>.425:
   blend=smooth(.425,.485,z);w['hips']=w.get('hips',0)+blend*sum(w.values())
 else:
  chain=[('hips',.49),('spine',.625),('chest',.755),('neck',.845),('head',.91)]
  if z<=chain[0][1]:w={chain[0][0]:1.}
  elif z>=chain[-1][1]:w={'head':1.}
  else:
   for (a,za),(b,zb) in zip(chain,chain[1:]):
    if za<=z<=zb:
     t=smooth(za,zb,z);w={a:1-t,b:t};break
  # Shoulder seam shares its torso/arm boundary without lower-arm bleed.
  if .75<z<.855 and ax>.09:
   t=smooth(.09,.16,ax)*smooth(.75,.79,z)
   a=nearest(v,['clavicle.'+side,'upper_arm.'+side],.04)
   total=sum(a.values());w={n:value*(1-t) for n,value in w.items()}
   for n,value in a.items():w[n]=w.get(n,0)+t*value/total
 w=dict(sorted(w.items(),key=lambda p:-p[1])[:4]);total=sum(w.values());weights.append({n:value/total for n,value in w.items() if value/total>1e-6})
# UV/material seam duplicates must share exactly the same skin weights to remain closed.
seams={}
for i,v in enumerate(P):seams.setdefault(tuple(np.round(v,6)),[]).append(i)
for ids in seams.values():
 if len(ids)<2:continue
 w={}
 for i in ids:
  for n,value in weights[i].items():w[n]=w.get(n,0)+value
 w=dict(sorted(w.items(),key=lambda p:-p[1])[:4]);total=sum(w.values());w={n:value/total for n,value in w.items()}
 for i in ids:weights[i]=w.copy()
for group in list(body.vertex_groups):body.vertex_groups.remove(group)
groups={n:body.vertex_groups.new(name=n) for n in names}
for i,w in enumerate(weights):
 for n,value in w.items():groups[n].add([i],value,'REPLACE')
body.parent=rig;modifier=body.modifiers.new('Mummy skin','ARMATURE');modifier.object=rig;modifier.use_deform_preserve_volume=False
# Bounded derivatives only; original source untouched. Never enlarge a smaller map.
for image in bpy.data.images:
 if not image.size[0]:continue
 cap=512 if any(s in image.name.lower() for s in ('normal','metallic','roughness','occlusion')) else 1024
 largest=max(image.size)
 if largest>cap:image.scale(round(image.size[0]*cap/largest),round(image.size[1]*cap/largest))
 image.pack()
body.data.calc_loop_triangles();tri=len(body.data.loop_triangles)
assert np.array_equal(original,np.array([v.co[:] for v in body.data.vertices]))
assert all(abs(sum(w.values())-1)<1e-5 and 1<=len(w)<=4 for w in weights)
# Bake one uniform transform into mesh and rest skeleton together. Skin groups stay unchanged.
source_height=float(hi[2]-lo[2]);target_height=1.8;fit_scale=target_height/source_height
fit=Matrix.Scale(fit_scale,4) @ Matrix.Translation(Vector((0,0,-float(lo[2]))))
body.data.transform(fit);arm.transform(fit)
J={n:(tuple(fit@Vector(h)),tuple(fit@Vector(t)),parent) for n,(h,t,parent) in J.items()}
P=np.array([v.co[:] for v in body.data.vertices]);lo=P.min(0);hi=P.max(0)
rig['asset_id']='monster_mummy_01';rig['rig_version']=2
rig['source_height_m']=source_height;rig['uniform_fit_scale']=fit_scale
rig['forward']='Blender -Y / glTF +Z';rig['authored_height_m']=float(hi[2]-lo[2])
bpy.context.scene.render.fps=30
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'mummy_rigged.blend'))
for o in bpy.context.scene.objects:o.select_set(o in [body,rig])
bpy.ops.export_scene.gltf(filepath=str(OUT/'mummy.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_all_influences=False,export_extras=True,export_yup=True)
metadata={'id':'monster_mummy_01','version':2,'source':str(SRC),'source_sha256':hashlib.sha256(SRC.read_bytes()).hexdigest(),'triangles':tri,'vertices':len(P),'bones':len(J),'deform_bones':len(names),'max_influences':4,'height_m':float(hi[2]-lo[2]),'source_height_m':source_height,'uniform_fit_scale':fit_scale,'bounds_blender':{'min':lo.tolist(),'max':hi.tolist()},'texture_sizes':{image.name:list(image.size) for image in bpy.data.images if image.size[0]},'animations':[],'landmarks':{n:{'head':h,'tail':t,'parent':parent} for n,(h,t,parent) in J.items()},'weights':'anatomical regions + distance blend; coincident UV seams unified; dedicated loose-wrap bones','integration':'asset only; map/spawn integration pending'}
(OUT/'mummy.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('MUMMY_RIGGED',json.dumps({k:metadata[k] for k in ['triangles','bones','deform_bones','height_m']}),flush=True)
