#!/usr/bin/env python3
"""Separate the FBX kit's eight welded pieces without changing UVs, normals or textures."""
import json,copy,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
asset=ROOT/'art/props/modular_wall/modular_wall.glb';g=Glb(asset)
if g.j['asset'].get('extras',{}).get('wall_split'):sys.exit(0)
p=g.j['meshes'][0]['primitives'][0];pos=g.read(p['attributes']['POSITION']);idx=g.read(p['indices']).reshape(-1);parent=list(range(len(pos)));weld={}
def find(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
def union(a,b):parent[find(a)]=find(b)
for i,v in enumerate(pos):
 key=tuple(round(float(x),6) for x in v)
 if key in weld:union(i,weld[key])
 else:weld[key]=i
for a,b,c in idx.reshape(-1,3):union(int(a),int(b));union(int(a),int(c))
components={}
for f,tri in enumerate(idx.reshape(-1,3)):components.setdefault(find(int(tri[0])),[]).append(f)
parts=sorted(components.values(),key=len,reverse=True);assert [len(x) for x in parts]==[558,521,458,448,448,324,289,76]
names=['Corner','DoubleGate','CrossRail','Rail','ShortRail','LanternPost','Gate','Post'];factor=1.35/float((pos[[int(i) for f in parts[7] for i in idx[f*3:f*3+3]]].max(0)-pos[[int(i) for f in parts[7] for i in idx[f*3:f*3+3]]].min(0))[1]);meshes=[];nodes=[];report={}
for name,faces in zip(names,parts):
 old=idx.reshape(-1,3)[faces].reshape(-1);used,remapped=np.unique(old,return_inverse=True);points=pos[used];lo=points.min(0);hi=points.max(0);pivot=(lo+hi)*.5;pivot[1]=lo[1]
 primitive={'attributes':{},'material':p['material']}
 for role,ai in p['attributes'].items():
  rows=g.read(ai)[used].copy()
  if role=='POSITION':rows=(rows-pivot)*factor
  a=g.j['accessors'][ai];primitive['attributes'][role]=g.add_accessor(rows,a['type'],a['componentType'],role=='POSITION')
 primitive['indices']=g.add_accessor(remapped.astype('<u2').reshape(-1,1),'SCALAR',5123)
 meshes.append({'name':name,'primitives':[primitive]});nodes.append({'name':name,'mesh':len(meshes)-1})
 report[name]={'triangles':len(faces),'size_m':[float(v) for v in (hi-lo)*factor]}
g.j['meshes']=meshes;g.j['nodes']=[{'name':'ModularWallKit','children':list(range(1,9))}]+[{**n,'mesh':i} for i,n in enumerate(nodes)];g.j['scenes']=[{'nodes':[0]}];g.j['scene']=0;g.j['asset'].setdefault('extras',{})['wall_split']=True
tmp=asset.with_suffix('.tmp.glb');g.save(tmp);tmp.replace(asset)
meta=json.loads((asset.parent/'asset.json').read_text());[meta.pop(key,None) for key in ('width_m','height_m','depth_m')]
meta.update(parts=report,glb_bytes=asset.stat().st_size,placement='Rail and Post separately batched; open entrances');(asset.parent/'asset.json').write_text(json.dumps(meta,indent=2)+'\n');print(json.dumps(report,indent=2))
