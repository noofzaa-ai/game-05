#!/usr/bin/env python3
"""Build fresh per-face UVs for1000tri relics; bake textures without exporting Blender geometry."""
import copy,json,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
work=ROOT/'art_source/props/goblin_base/rebake1000';work.mkdir(exist_ok=True)
for name in ['goblin_medallion','goblin_lantern']:
 original=Glb(ROOT/'art_source/props/goblin_base/parts'/(name+'.glb'));g=Glb(ROOT/'art/relics/goblin/models'/(name+'.glb'));p=g.j['meshes'][0]['primitives'][0];indices=g.read(p['indices']).reshape(-1);position=g.read(p['attributes']['POSITION'])[indices].copy();faces=np.arange(len(indices),dtype='<u2').reshape(-1,3)
 tex=[];normal=[];tangent=[]
 for i,face in enumerate(faces):
  x,y=i%32,i//32;uv=np.array([[x*32+3,y*32+3],[x*32+29,y*32+3],[x*32+3,y*32+29]],dtype='<f4')/1024
  # glTF UV origin is top-left. Normal texture tangent basis follows uv increasing v.
  verts=position[face];edge1=verts[1]-verts[0];edge2=verts[2]-verts[0];n=np.cross(edge1,edge2);n/=max(np.linalg.norm(n),1e-12);t=edge1/max(np.linalg.norm(edge1),1e-12);b=np.cross(n,t);hand=1 if np.dot(b,edge2)>0 else -1
  tex.extend(uv.tolist());normal.extend([n.tolist()]*3);tangent.extend([list(t)+[hand]]*3)
 primitive={'attributes':{},'material':0}
 for role,values,kind in [('POSITION',position,'VEC3'),('NORMAL',normal,'VEC3'),('TANGENT',tangent,'VEC4'),('TEXCOORD_0',tex,'VEC2')]:primitive['attributes'][role]=g.add_accessor(np.array(values,dtype='<f4'),kind,5126,role=='POSITION')
 primitive['indices']=g.add_accessor(faces.reshape(-1,1),'SCALAR',5123);g.j['meshes']=[{'name':name,'primitives':[primitive]}]
 g.j['images']=[{'uri':'../baked/'+name+'_'+role+'.png'} for role in ['colour','normal','mr']]
 g.new_images={};g.save(work/(name+'_uv.glb'))
 sp=original.j['meshes'][0]['primitives'][0]
 data={'name':name,'positions':position.tolist(),'normals':normal,'tangents':tangent,'uv':tex,'source':{role:original.read(ai).tolist() for role,ai in sp['attributes'].items()},'source_indices':original.read(sp['indices']).reshape(-1,3).tolist()}
 (work/(name+'.json')).write_text(json.dumps(data,separators=(',',':'),default=lambda v:float(v)))
print(work)
