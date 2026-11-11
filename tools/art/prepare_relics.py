#!/usr/bin/env python3
"""Extract reviewed Relic components, preserving UVs and shared budgeted PBR textures.
Run prepare_relic_source.gd first; original FBX and source images remain untouched.
"""
import copy,hashlib,io,json,sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
source=ROOT/'art_source/relics/relic_native.glb';g=Glb(source);p=g.j['meshes'][0]['primitives'][0];pos=g.read(p['attributes']['POSITION'])*100;idx=g.read(p['indices']).reshape(-1);parents=list(range(len(pos)));weld={}
def find(i):
 while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
 return i
def union(a,b):parents[find(a)]=find(b)
for i,v in enumerate(pos):
 key=tuple(np.round(v,5))
 if key in weld:union(i,weld[key])
 else:weld[key]=i
for a,b,c in idx.reshape(-1,3):union(int(a),int(b));union(int(a),int(c))
components={}
for face,tri in enumerate(idx.reshape(-1,3)):components.setdefault(find(int(tri[0])),[]).append(face)
parts=sorted(components.values(),key=len,reverse=True);assert len(parts)==28 and sum(map(len,parts))==50000
out=ROOT/'art/relics';shared=out/'shared';shared.mkdir(parents=True,exist_ok=True)
colour=g.j['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index'];normal=g.j['materials'][0]['normalTexture']['index']
for texture,name in [(colour,'relic_colour'),(normal,'relic_normal')]:
 data=g.image_bytes(g.j['textures'][texture]['source']);im=Image.open(io.BytesIO(data));im.thumbnail((1024,1024) if texture==colour else (512,512),Image.Resampling.LANCZOS);im.save(shared/(name+'.png'),optimize=True)
folder=ROOT/'art_source/relics/data_maps'
def channel(role):
 image=Image.open(next(folder.glob('*_'+role+'.png*'))).convert('RGB');image.thumbnail((512,512),Image.Resampling.LANCZOS);return image.getchannel('R')
r,m=channel('roughness'),channel('metallic');Image.merge('RGB',(Image.new('L',r.size,255),r,m)).save(shared/'relic_mr.png',optimize=True)
# Confirmed against native component contact sheet, never substitute fragments for absent designs.
selection={1:19,2:18,5:2,6:14,7:15,8:25,11:7,12:5,13:6,14:22,15:8,16:17,17:13,18:9,19:3,20:1}
names=['Forest Runestone','Explorer Compass','Heart of the Grove','Antler Diadem','Frost Hourglass','Ice Pendant','Ember Chalice','Volcanic Hammer','Winged Sun Emblem','Royal Crown','War Horn','Horned Skull Totem','Arcane Lantern','Crystal Key','Scarab Seal','Anubis Jar','Void Gate','Spirit Lantern','Navigator Chest','Forest Skull Mask']
rows=[]
for number in range(1,21):
 row={'id':'relic_%02d'%number,'reference_number':number,'display_name':names[number-1],'icon':'res://art/relics/icons/relic_%02d.png'%number,'model':'','status':'source_model_incomplete' if number in [3,4] else 'source_pair_needs_separation','perk':None}
 if number in selection:
  component=selection[number];faces=parts[component];old=idx.reshape(-1,3)[faces].reshape(-1);used,remap=np.unique(old,return_inverse=True);points=pos[used];lo=points.min(0);hi=points.max(0);pivot=(lo+hi)*.5;pivot[1]=lo[1];factor=1/float((hi-lo)[1]);clone=copy.deepcopy(g);prim={'attributes':{},'material':0}
  for role,ai in p['attributes'].items():
   values=g.read(ai)[used].copy()
   if role=='POSITION':values=(values*100-pivot)*factor
   aa=g.j['accessors'][ai];prim['attributes'][role]=clone.add_accessor(values,aa['type'],aa['componentType'],role=='POSITION')
  prim['indices']=clone.add_accessor(remap.astype('<u2').reshape(-1,1),'SCALAR',5123)
  clone.j['meshes']=[{'name':row['id'],'primitives':[prim]}];clone.j['nodes']=[{'name':row['id'],'mesh':0}];clone.j['scenes']=[{'nodes':[0]}];clone.j['scene']=0
  clone.j['materials']=[{'name':'RelicMutedPBR','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'baseColorFactor':[.85,.85,.85,1],'metallicRoughnessTexture':{'index':2},'metallicFactor':.35,'roughnessFactor':1},'normalTexture':{'index':1,'scale':1}}]
  clone.j['textures']=[{'source':i} for i in range(3)];clone.j['images']=[{'name':n,'uri':'../shared/'+n+'.png'} for n in ['relic_colour','relic_normal','relic_mr']];clone.new_images={}
  models=out/'models';models.mkdir(exist_ok=True);path=models/(row['id']+'.glb');clone.save(path)
  row.update(model='res://art/relics/models/'+path.name,status='prepared_from_source',source_component=component,triangles=len(faces),height_m=1.0,model_bytes=path.stat().st_size)
 rows.append(row)
catalog={'version':1,'purpose':'Relic asset preparation only; no acquisition, ownership, perk stats or equipment grants','source_fbx':'/Users/user/godot-project/assets/relic.fbx','source_sha256':hashlib.sha256((ROOT.parent.parent/'assets/relic.fbx').read_bytes()).hexdigest(),'source_triangles':50000,'disconnected_components':28,'relics':rows}
dest=ROOT/'data/relics';dest.mkdir(parents=True,exist_ok=True);(dest/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n');print('RELIC PREPARED:16 source models; 03/04 incomplete and09/10 joined flagged for review')
