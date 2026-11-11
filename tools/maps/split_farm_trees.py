#!/usr/bin/env python3
"""Split complete pines beside the Lv2 farm into one hideable mesh; preserve existing art."""
import copy,json,math,struct
from pathlib import Path
FORMATS={5126:('f',4),5125:('I',4),5123:('H',2),5121:('B',1)}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
def split_farm_trees(path,apply=True,rect=(10,25,-12,6),flat=(11.5,23.5,-9,3.5),group_name="FarmBoundaryTrees"):
 path=Path(path);data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+size]);raw=data[28+size:]
 if any(n.get('name')==group_name for n in g['nodes']):return {'already_split':True}
 assert not any(g.get(k) for k in ['skins','animations','images'])
 def read(ai):
  a=g['accessors'][ai];v=g['bufferViews'][a['bufferView']];fmt,unit=FORMATS[a['componentType']];width=WIDTH[a['type']];stride=v.get('byteStride',unit*width);start=v.get('byteOffset',0)+a.get('byteOffset',0)
  return [struct.unpack_from('<'+fmt*width,raw,start+i*stride) for i in range(a['count'])]
 node=next(n for n in g['nodes'] if n.get('name')=='camp_paint');assert not node.get('matrix') and not node.get('translation') and not node.get('scale')
 mesh=g['meshes'][node['mesh']];assert len(mesh['primitives'])==1
 primitive=mesh['primitives'][0];positions=read(primitive['attributes']['POSITION']);colors=read(primitive['attributes']['COLOR_0']);indices=[r[0] for r in read(primitive['indices'])]
 # Weld for classification only. Actual exported attributes and seams are copied byte-for-byte.
 weld={};canonical=[];parent={}
 for row in positions:
  key=tuple(round(x,4) for x in row);index=weld.setdefault(key,len(weld));canonical.append(index);parent[index]=index
 def find(x):
  while parent[x]!=x:parent[x]=parent[parent[x]];x=parent[x]
  return x
 def union(a,b):parent[find(a)]=find(b)
 for i in range(0,len(indices),3):
  a,b,c=[canonical[j] for j in indices[i:i+3]];union(a,b);union(a,c)
 groups={}
 for i in range(0,len(indices),3):groups.setdefault(find(canonical[indices[i]]),[]).append(i)
 components=[]
 for faces in groups.values():
  vertices={indices[i+j] for i in faces for j in range(3)}
  lo=[min(positions[v][k] for v in vertices) for k in range(3)];hi=[max(positions[v][k] for v in vertices) for k in range(3)]
  center=[(a+b)*.5 for a,b in zip(lo,hi)];span=[b-a for a,b in zip(lo,hi)]
  color=[sum(colors[v][k] for v in vertices)/len(vertices) for k in range(3)]
  components.append(dict(faces=faces,center=center,span=span,lo=lo,color=color))
 # Flatten only the connected terrain, never roofs, foliage or props.
 terrain=max(components,key=lambda c:len(c['faces']))
 terrain_ids={indices[i+j] for i in terrain['faces'] for j in range(3)}
 leaves=[]
 for c in components:
  x,y,z=c['center'];sx,sy,sz=c['span'];r,green,b=c['color']
  if len(c['faces'])==6 and .5<sx<7 and .5<sz<7 and sy>.65 and green>r*1.25 and green>b*.6:leaves.append(c)
 trees=[]
 for leaf in leaves:
  match=next((t for t in trees if math.hypot(t[0]-leaf['center'][0],t[1]-leaf['center'][2])<.3),None)
  if match:match[2].append(leaf)
  else:trees.append([leaf['center'][0],leaf['center'][2],[leaf]])
 selected=set();report=[]
 for x,z,crowns in trees:
  if not (rect[0]<=x<=rect[1] and rect[2]<=z<=rect[3]):continue
  trunks=[c for c in components if math.hypot(c['center'][0]-x,c['center'][2]-z)<.3 and c['span'][0]<.85 and c['span'][2]<.85 and c['span'][1]>.65 and len(c['faces'])==10 and c['lo'][1]<min(q['lo'][1] for q in crowns)]
  assert len(crowns)==3 and len(trunks)==1,(x,z,len(crowns),len(trunks))
  for c in crowns+trunks:selected.update(c['faces'])
  report.append([round(x,2),round(z,2)])
 assert selected,'No complete pines found'
 # Clear small rocks/bushes from plots and their entrance with the same level gate.
 for c in components:
  x,y,z=c['center']
  if c is not terrain and flat[0]<=x<=flat[1] and flat[2]<=z<=flat[3] and y<2 and max(c['span'])<4:
   selected.update(c['faces'])
 stats={'trees':len(report),'triangles_hidden':len(selected),'triangles_total':len(indices)//3,'positions':report}
 print(json.dumps(stats))
 if not apply:return stats
 g=copy.deepcopy(g);buffer=bytearray(raw)
 def compact(faces):
  used=[];remap={};new_indices=[]
  for face in faces:
   for old in indices[face:face+3]:
    if old not in remap:remap[old]=len(used);used.append(old)
    new_indices.append(remap[old])
  out=copy.deepcopy(primitive);out['attributes']={}
  def add(old_ai,rows,component=None):
   original=g['accessors'][old_ai];a=copy.deepcopy(original);a.pop('min',None);a.pop('max',None);a.pop('byteOffset',None)
   if component:a['componentType']=component
   a['count']=len(rows);fmt,unit=FORMATS[a['componentType']];width=WIDTH[a['type']]
   while len(buffer)%4:buffer.append(0)
   start=len(buffer)
   for row in rows:buffer.extend(struct.pack('<'+fmt*width,*row))
   a['bufferView']=len(g['bufferViews']);g['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':len(buffer)-start})
   if a['type']=='VEC3':a['min']=[min(row[k] for row in rows) for k in range(3)];a['max']=[max(row[k] for row in rows) for k in range(3)]
   index=len(g['accessors']);g['accessors'].append(a);return index
  for key,ai in primitive['attributes'].items():
   values=read(ai)
   if key=='POSITION':
    values=list(values)
    for i in used:
     x,y,z=values[i]
     if i in terrain_ids:
      distance=max(flat[0]-x,x-flat[1],flat[2]-z,z-flat[3],0)
      blend=max(0,1-distance/2)
      values[i]=(x,y*(1-blend),z)
   out['attributes'][key]=add(ai,[values[i] for i in used])
  out['indices']=add(primitive['indices'],[(i,) for i in new_indices],5123 if len(used)<65536 else 5125)
  return out
 g['meshes'][node['mesh']]['primitives']=[compact([i for i in range(0,len(indices),3) if i not in selected])]
 mi=len(g['meshes']);g['meshes'].append({'name':group_name,'primitives':[compact(sorted(selected))]})
 ni=len(g['nodes']);g['nodes'].append({'name':group_name,'mesh':mi})
 g['scenes'][g.get('scene',0)]['nodes'].append(ni)
 # Strip orphaned buffers left by the split; other scenery accessors retain exact original bytes.
 ais=sorted({ai for m in g['meshes'] for p in m['primitives'] for ai in list(p['attributes'].values())+[p['indices']]});amap={old:i for i,old in enumerate(ais)}
 views=sorted({g['accessors'][i]['bufferView'] for i in ais});vmap={old:i for i,old in enumerate(views)};packed=bytearray();new_views=[]
 for vi in views:
  v=copy.deepcopy(g['bufferViews'][vi]);start=v.get('byteOffset',0)
  while len(packed)%4:packed.append(0)
  v['byteOffset']=len(packed);packed.extend(buffer[start:start+v['byteLength']]);new_views.append(v)
 g['accessors']=[g['accessors'][i] for i in ais]
 for a in g['accessors']:a['bufferView']=vmap[a['bufferView']]
 for m in g['meshes']:
  for p in m['primitives']:p['indices']=amap[p['indices']];p['attributes']={k:amap[v] for k,v in p['attributes'].items()}
 g['bufferViews']=new_views;g['buffers']=[{'byteLength':len(packed)}];g['asset'].setdefault('extras',{})[group_name+'_clearance']=stats
 text=json.dumps(g,separators=(',',':')).encode()
 while len(text)%4:text+=b' '
 while len(packed)%4:packed.append(0)
 result=struct.pack('<III',0x46546c67,2,12+8+len(text)+8+len(packed))+struct.pack('<II',len(text),0x4e4f534a)+text+struct.pack('<II',len(packed),0x004e4942)+packed
 backup=Path(__file__).resolve().parents[2]/'.cache/camp_hub_before_farm_trees.glb';backup.parent.mkdir(exist_ok=True)
 if not backup.exists():backup.write_bytes(data)
 path.write_bytes(result);return stats
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('--apply',action='store_true');a=p.parse_args()
 split_farm_trees(Path(__file__).resolve().parents[2]/'art/maps/camp_hub/camp_hub.glb',a.apply)
