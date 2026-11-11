#!/usr/bin/env python3
"""Align the kit's angled rail pieces along X for repeatable fence placement."""
import json,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
asset=ROOT/'art/props/modular_wall/modular_wall.glb';g=Glb(asset)
if g.j['asset'].get('extras',{}).get('wall_rails_aligned'):sys.exit(0)
meta=json.loads((asset.parent/'asset.json').read_text())
for name in ['Rail','ShortRail','CrossRail']:
 node=next(n for n in g.j['nodes'] if n.get('name')==name);p=g.j['meshes'][node['mesh']]['primitives'][0];points=g.read(p['attributes']['POSITION']).copy();xz=points[:,[0,2]]
 _,vectors=np.linalg.eigh(np.cov(xz.T));axis=vectors[:,-1]
 if axis[0]<0:axis=-axis
 c,s=axis;rotation=np.array([[c,0,s],[0,1,0],[-s,0,c]],dtype='<f4')
 for role in ['POSITION','NORMAL','TANGENT']:
  if role not in p['attributes']:continue
  ai=p['attributes'][role];rows=g.read(ai).copy();rows[:,:3]=rows[:,:3]@rotation.T
  if role=='POSITION':
   lo=rows.min(0);hi=rows.max(0);pivot=(lo+hi)*.5;pivot[1]=lo[1];rows-=pivot
   g.j['accessors'][ai]['min']=rows.min(0).tolist();g.j['accessors'][ai]['max']=rows.max(0).tolist();meta['parts'][name]['size_m']=(hi-lo).tolist()
  g.new[ai]=rows
g.j['asset'].setdefault('extras',{})['wall_rails_aligned']=True
tmp=asset.with_suffix('.tmp.glb');g.save(tmp);tmp.replace(asset);meta['glb_bytes']=asset.stat().st_size;(asset.parent/'asset.json').write_text(json.dumps(meta,indent=2)+'\n');print(json.dumps(meta['parts']['Rail']))
