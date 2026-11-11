#!/usr/bin/env python3
"""Prepare ten goblin scenery pieces pieces outside runtime export; original FBX untouched."""
import copy,hashlib,io,json,sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
folder=ROOT/'art_source/props/goblin_base';g=Glb(folder/'gobbin_base_native.glb');primitive=g.j['meshes'][0]['primitives'][0];positions=g.read(primitive['attributes']['POSITION'])*100;indices=g.read(primitive['indices']).reshape(-1);parents=list(range(len(positions)));weld={}
def find(i):
 while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
 return i
def union(a,b):parents[find(a)]=find(b)
for i,v in enumerate(positions):
 key=tuple(np.round(v,5))
 if key in weld:union(i,weld[key])
 else:weld[key]=i
for a,b,c in indices.reshape(-1,3):union(int(a),int(b));union(int(a),int(c))
components={}
for i,triangle in enumerate(indices.reshape(-1,3)):components.setdefault(find(int(triangle[0])),[]).append(i)
assert len(components)==14
parts=[]
for faces in components.values():
 points=positions[np.unique(indices.reshape(-1,3)[faces])];lo=points.min(0);hi=points.max(0);parts.append(dict(faces=faces,lo=lo,hi=hi,center=(lo+hi)*.5))
majors=[c for c in parts if len(c['faces'])>1500 and c['center'][2]>-.25]
minor=[c for c in parts if not (len(c['faces'])>1500 and c['center'][2]>-.25)]
assert len(majors)==10
for c in minor:
 parent=min(majors,key=lambda m:float(np.linalg.norm((c['center']-m['center'])[:2])))
 parent['faces'].extend(c['faces']);parent['lo']=np.minimum(parent['lo'],c['lo']);parent['hi']=np.maximum(parent['hi'],c['hi']);parent['center']=(parent['lo']+parent['hi'])*.5
parts=sorted(majors,key=lambda c:(0 if c['center'][1]>.27 else 1,float(c['center'][0])))
names=['hut','gate','palisade','corner','tower','cauldron','crate','drum','weapon_rack','banner']
heights=[3.4,3.4,2.1,2.1,4.2,2.0,1.4,1.2,1.8,3.0]
runtime=ROOT/'art/props/goblin_base';runtime.mkdir(parents=True,exist_ok=True)
shared=runtime/'shared';shared.mkdir(exist_ok=True)
material=g.j['materials'][0]
for role,name,cap in [('baseColorTexture','relic_colour',1024),('normalTexture','relic_normal',512)]:
 t=material['pbrMetallicRoughness'][role] if role=='baseColorTexture' else material[role];data=g.image_bytes(g.j['textures'][t['index']]['source']);image=Image.open(io.BytesIO(data));image.thumbnail((cap,cap),Image.Resampling.LANCZOS);image.save(shared/(name+'.png'),optimize=True)
def channel(role):
 image=Image.open(next((folder/'gobbin_base').glob('*_'+role+'.png*'))).convert('RGB');image.thumbnail((512,512),Image.Resampling.LANCZOS);return image.getchannel('R')
r,m=channel('roughness'),channel('metallic');Image.merge('RGB',(Image.new('L',r.size,255),r,m)).save(shared/'relic_mr.png',optimize=True)
import shutil
(folder/'kit_shared').mkdir(exist_ok=True)
for image in shared.glob('*.png'):shutil.copy2(image,folder/'kit_shared'/image.name)
rows=[];dest=folder/'kit_parts';dest.mkdir(exist_ok=True)
for n,c in enumerate(parts,1):
 used,remapped=np.unique(indices.reshape(-1,3)[c['faces']].reshape(-1),return_inverse=True);lo,hi=c['lo'],c['hi'];pivot=(lo+hi)*.5;pivot[1]=lo[1];factor=heights[n-1]/float((hi-lo)[1]);out=copy.deepcopy(g);p={'attributes':{},'material':0}
 for role,ai in primitive['attributes'].items():
  values=g.read(ai)[used].copy()
  if role=='POSITION':values=(values*100-pivot)*factor
  a=g.j['accessors'][ai];p['attributes'][role]=out.add_accessor(values,a['type'],a['componentType'],role=='POSITION')
 p['indices']=out.add_accessor(remapped.astype('<u2').reshape(-1,1),'SCALAR',5123)
 name=names[n-1];out.j['meshes']=[{'name':name,'primitives':[p]}];out.j['nodes']=[{'name':name,'mesh':0}];out.j['scenes']=[{'nodes':[0]}];out.j['scene']=0
 out.j['materials']=[{'name':'RelicOriginalPBR','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicRoughnessTexture':{'index':2},'metallicFactor':1,'roughnessFactor':1},'normalTexture':{'index':1,'scale':1}}]
 out.j['textures']=[{'source':i} for i in range(3)];out.j['images']=[{'name':name,'uri':'../kit_shared/'+name+'.png'} for name in ['relic_colour','relic_normal','relic_mr']];out.new_images={};path=dest/(name+'.glb');out.save(path)
 rows.append(dict(id=name,path='parts/'+path.name,triangles=len(c['faces']),bytes=path.stat().st_size,height_m=heights[n-1],foot_y=0,source_center=c['center'].tolist(),source_bounds_size=(hi-lo).tolist(),normalization_scale=factor))
source=ROOT.parent.parent/'assets/gobbin_base.fbx'
manifest=dict(source=str(source),source_bytes=source.stat().st_size,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),status='prepared_for_goblin_base_maps',converter='Godot4.7.2 native FBXDocument; welded connected-component split; original MR restored',ordering='front view: upper row left-to-right, then lower row left-to-right',parts=rows,source_triangles=50000,exported_triangles=sum(r['triangles'] for r in rows),texture_budget={'colour':1024,'normal':512,'metallic_roughness':512},original_source_untouched=True)
assert manifest['exported_triangles']==50000
(runtime/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps({'pieces':len(rows),'triangles':manifest['exported_triangles'],'model_bytes':sum(r['bytes'] for r in rows),'shared_texture_bytes':sum(p.stat().st_size for p in shared.glob('*.png'))},indent=2))
