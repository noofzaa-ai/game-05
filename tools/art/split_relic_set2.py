#!/usr/bin/env python3
"""Prepare Set 2 at 15cm; keep disconnected accessory pieces with their parent relic."""
import copy,hashlib,io,json,sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
folder=ROOT/'art_source/relic_set2';g=Glb(folder/'native.glb');primitive=g.j['meshes'][0]['primitives'][0];positions=g.read(primitive['attributes']['POSITION'])*100;indices=g.read(primitive['indices']).reshape(-1);parents=list(range(len(positions)));weld={}
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
assert len(components)==12, "Source layout changed; inspect components before regrouping"
parts=[]
for faces in components.values():
 points=positions[np.unique(indices.reshape(-1,3)[faces])];lo=points.min(0);hi=points.max(0);parts.append(dict(faces=faces,lo=lo,hi=hi,center=(lo+hi)*.5))
# Two small disconnected details belong to bottom-row relics 1 and 4.
# Keep complete source geometry by grouping each with its nearest major piece.
majors=[c for c in parts if len(c['faces'])>1000]
minor=[c for c in parts if len(c['faces'])<=1000]
assert len(majors)==10 and len(minor)==2
for c in minor:
 parent=min(majors,key=lambda m:float(np.linalg.norm(c['center']-m['center'])))
 assert np.linalg.norm(c['center']-parent['center'])<.15
 parent['faces'].extend(c['faces']);parent['lo']=np.minimum(parent['lo'],c['lo']);parent['hi']=np.maximum(parent['hi'],c['hi']);parent['center']=(parent['lo']+parent['hi'])*.5
parts=majors
parts.sort(key=lambda c:(0 if c['center'][1]>.35 else 1,float(c['center'][0])))
shared=folder/'shared';shared.mkdir(exist_ok=True)
material=g.j['materials'][0]
for role,name,cap in [('baseColorTexture','relic_colour',1024),('normalTexture','relic_normal',512)]:
 t=material['pbrMetallicRoughness'][role] if role=='baseColorTexture' else material[role];data=g.image_bytes(g.j['textures'][t['index']]['source']);image=Image.open(io.BytesIO(data));image.thumbnail((cap,cap),Image.Resampling.LANCZOS);image.save(shared/(name+'.png'),optimize=True)
def channel(role):
 image=Image.open(next((folder/'source_maps').glob('*_'+role+'.png*'))).convert('RGB');image.thumbnail((512,512),Image.Resampling.LANCZOS);return image.getchannel('R')
r,m=channel('roughness'),channel('metallic');Image.merge('RGB',(Image.new('L',r.size,255),r,m)).save(shared/'relic_mr.png',optimize=True)
rows=[];dest=folder/'parts';dest.mkdir(exist_ok=True)
for n,c in enumerate(parts,1):
 used,remapped=np.unique(indices.reshape(-1,3)[c['faces']].reshape(-1),return_inverse=True);lo,hi=c['lo'],c['hi'];pivot=(lo+hi)*.5;pivot[1]=lo[1];factor=.15/float((hi-lo)[1]);out=copy.deepcopy(g);p={'attributes':{},'material':0}
 for role,ai in primitive['attributes'].items():
  values=g.read(ai)[used].copy()
  if role=='POSITION':values=(values*100-pivot)*factor
  a=g.j['accessors'][ai];p['attributes'][role]=out.add_accessor(values,a['type'],a['componentType'],role=='POSITION')
 p['indices']=out.add_accessor(remapped.astype('<u2').reshape(-1,1),'SCALAR',5123)
 name='relic_set2_%02d'%n;out.j['meshes']=[{'name':name,'primitives':[p]}];out.j['nodes']=[{'name':name,'mesh':0}];out.j['scenes']=[{'nodes':[0]}];out.j['scene']=0
 out.j['materials']=[{'name':'RelicOriginalPBR','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicRoughnessTexture':{'index':2},'metallicFactor':1,'roughnessFactor':1},'normalTexture':{'index':1,'scale':1}}]
 out.j['textures']=[{'source':i} for i in range(3)];out.j['images']=[{'name':name,'uri':'../shared/'+name+'.png'} for name in ['relic_colour','relic_normal','relic_mr']];out.new_images={};path=dest/(name+'.glb');out.save(path)
 rows.append(dict(id=name,path='parts/'+path.name,triangles=len(c['faces']),bytes=path.stat().st_size,height_m=.15,foot_y=0,source_center=c['center'].tolist(),source_bounds_size=(hi-lo).tolist(),normalization_scale=factor))
source=ROOT.parent.parent/'assets/relic_set2.fbx'
manifest=dict(source=str(source),source_bytes=source.stat().st_size,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),status='stored_only_not_in_game',converter='Godot4.7.2 native FBXDocument; welded connected-component split; original MR restored',ordering='front view: upper row left-to-right, then lower row left-to-right',parts=rows,source_triangles=50000,exported_triangles=sum(r['triangles'] for r in rows),texture_budget={'colour':1024,'normal':512,'metallic_roughness':512},original_source_untouched=True,source_connected_components=12,grouped_relic_count=10,accessory_grouping='two detached details preserved with nearest major relic, visually reviewed',geometry_optimization='not yet decimated; full-detail preparation retained',maximum_equipped_intent=3)
assert manifest['exported_triangles']==50000
(folder/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps({'pieces':len(rows),'triangles':manifest['exported_triangles'],'model_bytes':sum(r['bytes'] for r in rows),'shared_texture_bytes':sum(p.stat().st_size for p in shared.glob('*.png'))},indent=2))
