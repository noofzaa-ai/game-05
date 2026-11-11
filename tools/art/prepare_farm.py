#!/usr/bin/env python3
"""Rebuild farm derivative from native Godot FBX export and preserved original FBX data maps."""
import argparse,subprocess,sys,json,io,hashlib
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/skills'))
from shrink_skills import Glb
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--godot',default='/Applications/Godot.app/Contents/MacOS/Godot');ap.add_argument('--use-existing-export',action='store_true');args=ap.parse_args()
source=ROOT.parent.parent/'assets/farm.fbx'
if not args.use_existing_export:subprocess.run([args.godot,'--headless','--path',str(ROOT),'--script','res://tools/art/prepare_farm.gd'],check=True,timeout=120)
asset=ROOT/'art/props/farm_house/farm_house.glb'
subprocess.run([sys.executable,str(ROOT/'tools/art/apply_texture_budget.py'),str(asset)],check=True)
rough=Image.open(ROOT/'art_source/props/farm_house/source_roughness.png').convert('RGB');metal=Image.open(ROOT/'art_source/props/farm_house/source_metallic.png').convert('RGB')
rough.thumbnail((512,512),Image.Resampling.LANCZOS);metal.thumbnail((512,512),Image.Resampling.LANCZOS);assert rough.size==metal.size
image=Image.merge('RGB',(Image.new('L',rough.size,255),rough.getchannel('R'),metal.getchannel('R')));buffer=io.BytesIO();image.save(buffer,format='PNG',optimize=True)
g=Glb(asset);index=next((i for i,row in enumerate(g.j.get('images',[])) if row.get('name')=='farm_mr'),len(g.j.setdefault('images',[])))
if index==len(g.j['images']):g.j['images'].append({'name':'farm_mr','mimeType':'image/png','bufferView':0})
g.j['images'][index]['bufferView']=0;g.new_images[index]=(buffer.getvalue(),'image/png')
texture=next((i for i,row in enumerate(g.j.get('textures',[])) if row.get('source')==index),len(g.j.setdefault('textures',[])))
if texture==len(g.j['textures']):g.j['textures'].append({'source':index})
for mat in g.j['materials']:
 pbr=mat.setdefault('pbrMetallicRoughness',{});pbr.update(metallicRoughnessTexture={'index':texture},metallicFactor=1,roughnessFactor=1)
 if 'normalTexture' in mat:mat['normalTexture']['scale']=1
staging=asset.with_suffix('.tmp.glb');g.save(staging);staging.replace(asset)
subprocess.run([sys.executable,str(ROOT/'tools/art/apply_texture_budget.py'),str(asset),'--report',str(ROOT/'build/farm-texture-budget-final.json')],check=True)
report=json.loads((asset.parent/'asset.json').read_text());report.update(source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),source_bytes=source.stat().st_size,glb_bytes=asset.stat().st_size,texture_budget={'color':1024,'normal':512,'metallic_roughness':512},normal_strength=1,placement_preview={'position':[24,0,-3.3],'rotation_y_degrees':-90,'live_placement':False},data_maps='Original FBX embedded PNGs; MR packed G=roughness, B=metallic; native importer omitted these bindings so restored explicitly')
(asset.parent/'asset.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
