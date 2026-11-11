#!/usr/bin/env python3
"""Prepare small floating Goblin Relics, preserve UV seams; originals remain outside export."""
import copy,ctypes,json,sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
source=ROOT/'art_source/props/goblin_base';out=ROOT/'art/relics/goblin';(out/'models').mkdir(exist_ok=True);(out/'shared').mkdir(exist_ok=True)
lib=ctypes.CDLL('/Applications/Blender.app/Contents/Resources/lib/libmeshoptimizer.dylib');simplify=lib.meshopt_simplifyWithAttributes;simplify.restype=ctypes.c_size_t;simplify.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_float,ctypes.c_uint,ctypes.c_void_p]
# UV and normal-aware error metric; permissive seam collapses allow the 1000tri trial budget.
# API/flag verified against zeux/meshoptimizer src/meshoptimizer.h (MIT).
for name,cap in [('relic_colour',512),('relic_normal',256),('relic_mr',256)]:
 im=Image.open(source/'shared'/(name+'.png'));im.thumbnail((cap,cap),Image.Resampling.LANCZOS);im.save(out/'shared'/(name+'.png'),optimize=True)
report={}
for name in ['goblin_medallion','goblin_lantern']:
 g=Glb(source/'parts'/(name+'.glb'));p=g.j['meshes'][0]['primitives'][0];v=np.ascontiguousarray(g.read(p['attributes']['POSITION']),dtype='<f4');indices=np.ascontiguousarray(g.read(p['indices']).reshape(-1),dtype='<u4');dest=np.empty_like(indices);error=ctypes.c_float()
 attrs=np.ascontiguousarray(np.hstack([g.read(p['attributes']['NORMAL']),g.read(p['attributes']['TEXCOORD_0'])]),dtype='<f4');weights=np.array([.1,.1,.1,.25,.25],dtype='<f4')
 count=simplify(dest.ctypes.data,indices.ctypes.data,len(indices),v.ctypes.data,len(v),12,attrs.ctypes.data,20,weights.ctypes.data,5,None,3000,.1,32,ctypes.byref(error));idx=dest[:count];used,remap=np.unique(idx,return_inverse=True)
 primitive={'attributes':{},'material':0}
 for role,ai in p['attributes'].items():
  a=g.j['accessors'][ai];values=g.read(ai)[used].copy()
  if role=='POSITION':
   lo=values.min(0);hi=values.max(0);pivot=(lo+hi)*.5;pivot[1]=lo[1];values=(values-pivot)*(.15/float(hi[1]-lo[1]))
  primitive['attributes'][role]=g.add_accessor(values,a['type'],a['componentType'],role=='POSITION')
 primitive['indices']=g.add_accessor(remap.astype('<u2').reshape(-1,1),'SCALAR',5123)
 g.j['meshes']=[{'name':name,'primitives':[primitive]}]
 g.save(out/'models'/(name+'.glb'))
 assert count//3<=1000
 report[name]={'source_triangles':len(indices)//3,'runtime_triangles':count//3,'simplification_error':error.value,'bytes':(out/'models'/(name+'.glb')).stat().st_size,'height_m':.15}
(out/'runtime.json').write_text(json.dumps({'models':report,'textures':{'colour':512,'normal':256,'mr':256},'geometry':'meshoptimizer UV/normal-aware permissive simplification,1000tri cap; native visual comparison required','no_source_modification':True},indent=2)+'\n');print(report)
