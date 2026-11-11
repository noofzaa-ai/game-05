"""Promote reviewed oval geometry while retaining original rig and animation bytes."""
import copy,json,shutil,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DRAFT=ROOT/'art/characters/chibi-oval-b'
BACKUP=ROOT/'art_source/characters/chibi-oval-b/original'
def read(path):
 b=path.read_bytes();n=struct.unpack_from('<I',b,12)[0]
 return json.loads(b[20:20+n]),bytearray(b[28+n:])
def save(path,j,b):
 j['buffers'][0]['byteLength']=len(b)
 raw=json.dumps(j,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);b+=b'\0'*((-len(b))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(b))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(b),0x004e4942)+b)
def backup(path):
 out=BACKUP/path.relative_to(ROOT);out.parent.mkdir(parents=True,exist_ok=True)
 if not out.exists():shutil.copy2(path,out)
 return out
base=ROOT/'art/characters/chibi-studio/chibi_base_animated.glb'
original=backup(base);j,blob=read(original);d,db=read(DRAFT/'oval_b.glb')
assert [[j['nodes'][x]['name'] for x in skin['joints']] for skin in j['skins']]==[[d['nodes'][x]['name'] for x in skin['joints']] for skin in d['skins']]
original_animations=copy.deepcopy(j.get('animations'))
original_nodes=copy.deepcopy(j['nodes']);original_skins=copy.deepcopy(j['skins']);original_blob=bytes(blob)
mat_names={m.get('name'):i for i,m in enumerate(j.get('materials',[]))}
accessors={};views={}
def accessor(index):
 if index in accessors:return accessors[index]
 a=copy.deepcopy(d['accessors'][index]);assert 'sparse' not in a
 vi=a['bufferView']
 if vi not in views:
  v=copy.deepcopy(d['bufferViews'][vi]);start=v.get('byteOffset',0);data=db[start:start+v['byteLength']]
  blob.extend(b'\0'*((-len(blob))%4));v['buffer']=0;v['byteOffset']=len(blob);blob.extend(data)
  views[vi]=len(j['bufferViews']);j['bufferViews'].append(v)
 a['bufferView']=views[vi];accessors[index]=len(j['accessors']);j['accessors'].append(a)
 return accessors[index]
by_name={n.get('name'):n for n in d['nodes'] if 'mesh' in n}
changed=[]
for node in j['nodes']:
 if 'mesh' not in node:continue
 name=node.get('name','')
 if name not in ('Face','Nose','Mouth','Brow.L','Brow.R','Eye inset.L','Eye inset.R','Eyelid.L','Eyelid.R') and not node.get('extras',{}).get('studio_hair_style'):continue
 dn=by_name[name]
 for key in ('matrix','translation','rotation','scale'):assert node.get(key)==dn.get(key),(name,key)
 mesh=copy.deepcopy(d['meshes'][dn['mesh']])
 for p in mesh['primitives']:
  p['attributes']={k:accessor(v) for k,v in p['attributes'].items()}
  if 'indices' in p:p['indices']=accessor(p['indices'])
  if 'material' in p:p['material']=mat_names[d['materials'][p['material']]['name']]
 j['meshes'][node['mesh']]=mesh;changed.append(name)
# Original skeleton, socket nodes, skins and animation descriptors/data remain exact.
assert j['nodes']==original_nodes and j['skins']==original_skins and j.get('animations')==original_animations
assert bytes(blob[:len(original_blob)])==original_blob
j.setdefault('extras',{})['head_shape_revision']='oval_b_continuous_20261020'
save(base,j,blob)
files=[]
for group,pattern in [('faces','face_*.glb'),('hair','*.glb')]:
 for target in sorted((ROOT/'art/items'/group).glob(pattern)):
  fitted=DRAFT/target.name
  if not fitted.exists():raise RuntimeError('Missing fitted '+str(target))
  backup(target);shutil.copy2(fitted,target);files.append(str(target.relative_to(ROOT)))
report={'base_meshes':changed,'animation_count_preserved':len(original_animations),'rig_nodes_skins_unchanged':True,'original_binary_prefix_unchanged':True,'fitted_assets':files}
(ROOT/'art_source/characters/chibi-oval-b/promotion.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
