#!/usr/bin/env python3
"""Native Godot FBX conversion, original PBR maps and assets_spec budget for wall module."""
import argparse,hashlib,io,json,subprocess,sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/skills'))
from shrink_skills import Glb
ap=argparse.ArgumentParser();ap.add_argument('--use-existing-export',action='store_true');args=ap.parse_args()
asset=ROOT/'art/props/modular_wall/modular_wall.glb';source=ROOT.parent.parent/'assets/wall_modular.fbx'
if args.use_existing_export and Glb(asset).j['asset'].get('extras',{}).get('wall_split'):
 print('Existing split derivative is already prepared; omit --use-existing-export to rebuild from FBX.');sys.exit(0)
if not args.use_existing_export:
 subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(ROOT),'--script','res://tools/art/prepare_modular_wall.gd'],check=True,timeout=120)
subprocess.run([sys.executable,str(ROOT/'tools/art/apply_texture_budget.py'),str(asset)],check=True)
g=Glb(asset);p=g.j['meshes'][0]['primitives'][0];a=g.j['accessors'][p['attributes']['POSITION']]
lo=[v*100 for v in a['min']];hi=[v*100 for v in a['max']];factor=2.4/(hi[0]-lo[0]);height=(hi[1]-lo[1])*factor;depth=(hi[2]-lo[2])*factor
if not g.j['asset'].get('extras',{}).get('wall_normalized'):
 g.j['nodes'][0].update(name='ModularWall',scale=[factor]*3,translation=[-(lo[0]+hi[0])*.5*factor,-lo[1]*factor,-(lo[2]+hi[2])*.5*factor])
 g.j['asset'].setdefault('extras',{})['wall_normalized']=True
folder=ROOT/'art_source/props/modular_wall'
def channel(role):
 image=Image.open(next(folder.glob('*_'+role+'.png*'))).convert('RGB');image.thumbnail((512,512),Image.Resampling.LANCZOS);return image.getchannel('R')
rough,metal=channel('roughness'),channel('metallic');packed=Image.merge('RGB',(Image.new('L',rough.size,255),rough,metal));out=io.BytesIO();packed.save(out,format='PNG',optimize=True)
index=next((i for i,x in enumerate(g.j['images']) if x.get('name')=='wall_mr'),len(g.j['images']))
if index==len(g.j['images']):g.j['images'].append({'name':'wall_mr','mimeType':'image/png','bufferView':0})
g.j['images'][index]['bufferView']=0;g.new_images[index]=(out.getvalue(),'image/png')
t=len(g.j['textures']);g.j['textures'].append({'source':index})
for mat in g.j['materials']:
 mat['pbrMetallicRoughness'].update(metallicRoughnessTexture={'index':t},metallicFactor=1,roughnessFactor=1)
 if 'normalTexture' in mat:mat['normalTexture']['scale']=1
staging=asset.with_suffix('.tmp.glb');g.save(staging);staging.replace(asset)
subprocess.run([sys.executable,str(ROOT/'tools/art/apply_texture_budget.py'),str(asset)],check=True)
tri=sum(g.j['accessors'][p['indices']]['count']//3 for m in g.j['meshes'] for p in m['primitives'])
report=dict(source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),source_bytes=source.stat().st_size,glb_bytes=asset.stat().st_size,triangles=tri,width_m=2.4,height_m=height,depth_m=depth,foot_y=0,texture_budget=dict(color=1024,normal=512,metallic_roughness=512),converter='Godot 4.7.2 native FBXDocument; original embedded MR restored')
(asset.parent/'asset.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
subprocess.run([sys.executable,str(ROOT/'tools/art/split_modular_wall.py')],check=True)
subprocess.run([sys.executable,str(ROOT/'tools/art/align_modular_wall.py')],check=True)
