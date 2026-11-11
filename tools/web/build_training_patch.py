#!/usr/bin/env python3
"""Ship approved training, fences and camp clearance on the verified live icon release."""
import argparse,datetime,gzip,hashlib,json,re,shutil,subprocess
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries,raw,pack_files
ROOT=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();base=a.baseline.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
m=json.loads((base/'packs.json').read_text());old_core=m['core'];old_build=m['build'];files=entries(raw(base/old_core));original=dict(files)
for path,alias in [('client/hub_world','client/hub_world_training_baseline'),('client/mobile_controls','client/mobile_training_baseline')]:
 files[alias+'.gdc']=files.pop(path+'.gdc');files.pop(path+'.gd.remap');files[alias+'.gd.remap']=('[remap]\n\npath="res://'+alias+'.gdc"\n').encode()
for name in ['hub','hub_world','mobile_controls']:files['client/'+name+'.gd']=(ROOT/'tools/web/training_patch'/ (name+'.gd')).read_bytes()
paths=['client/training_arena.gd','client/training_dummy.gd','client/modular_fence.gd','logic/training_ground.gd','logic/training_skill_system.gd']
for name in paths:files[name]=(ROOT/name).read_bytes()
assets={'training':{},'training.s3tc':{},'training.etc2':{}}
for rel in ['art/maps/camp_hub/camp_training.glb.import','art/props/modular_wall/modular_wall.glb.import']+[p.relative_to(ROOT).as_posix() for p in (ROOT/'art/props/modular_wall').glob('*.png.import')]:
 assets['training'][rel]=(ROOT/rel).read_bytes()
 for path in set(re.findall(r'"(res://\.godot/imported/[^"\n]+)"',(ROOT/rel).read_text())):
  name=path.removeprefix('res://');group='training.s3tc' if '.s3tc.' in name else 'training.etc2' if '.etc2.' in name else 'training';assets[group][name]=(ROOT/name).read_bytes()
# Capture dependencies used by the native generated scenes (no source FBX/high-res textures).
for group,values in assets.items():
 (out/group).mkdir(exist_ok=True)
 packed=pack_files(out/group,values,'/Applications/Godot.app/Contents/MacOS/Godot');assert entries(packed)==values
 filename=group+'.'+hashlib.sha256(packed).hexdigest()[:12]+'.pck.wasm';values={'name':group,'format':group.split('.')[1] if '.' in group else '', 'file':filename,'bytes':len(gzip.compress(packed,compresslevel=9,mtime=0)),'raw_bytes':len(packed)}
 assets[group]=(values,gzip.compress(packed,compresslevel=9,mtime=0))
now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'));meta=dict(m['source'],baseline_build=old_build,patch_paths=paths+['client/hub.gd','client/hub_world.gd','client/mobile_controls.gd'],source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
files['data/ui/build_info.json']=(json.dumps(meta,indent=2)+'\n').encode();data=pack_files(out,files,'/Applications/Godot.app/Contents/MacOS/Godot');assert entries(data)==files
web=out/'web';shutil.copytree(base,web,dirs_exist_ok=True);digest=hashlib.sha256(data).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(data,compresslevel=9,mtime=0));(web/old_core).unlink()
for desc,packed in assets.values():(web/desc['file']).write_bytes(packed);m['packs'].append(desc)
seed='|'.join([m['engine'].split('.')[1],digest]+[p['file'] for p in m['packs']]);build=hashlib.sha256(seed.encode()).hexdigest()[:12]
m.update(build=build,core=core,core_bytes=(web/core).stat().st_size,source=meta);(web/'packs.json').write_text(json.dumps(m,indent=2)+'\n');page=(web/'play.html').read_text().replace(old_build,build);page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda x:x[1]+str(len(data)),page);(web/'play.html').write_text(page)
changed={'client/hub.gd','client/hub_world.gdc','client/hub_world.gd.remap','client/mobile_controls.gdc','client/mobile_controls.gd.remap','data/ui/build_info.json'}
for name,value in original.items():
 if name not in changed:assert files[name]==value,name
print(json.dumps(dict(build=build,baseline=old_build,packs=[x[0] for x in assets.values()]),indent=2))
