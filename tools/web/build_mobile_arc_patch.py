#!/usr/bin/env python3
"""Ship only Boss-approved compact mobile action/skill arc on the current live baseline."""
import argparse,datetime,gzip,hashlib,json,re,shutil
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries,raw,pack_files
ROOT=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();base=a.baseline.resolve();out=a.output.resolve();out.mkdir(exist_ok=True,parents=True)
m=json.loads((base/'packs.json').read_text());old_core=m['core'];old_build=m['build'];files=entries(raw(base/old_core));original=dict(files)
paths=['client/mobile_controls.gd','client/mobile_combat_layout.gd','client/skills/skill_hud.gd','client/skills/round_skill_button.gd']
removed=[]
for name in paths:
 for suffix in ['c','.remap']:
  if name+suffix in files:removed.append(name+suffix);files.pop(name+suffix)
 files[name]=(ROOT/('tools/web/mobile_arc_patch.gd' if name=='client/mobile_controls.gd' else name)).read_bytes()
now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'));meta=dict(m['source'],baseline_build=old_build,patch_paths=paths,source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'));files['data/ui/build_info.json']=(json.dumps(meta,indent=2)+'\n').encode()
for name,value in original.items():
 if name not in paths+removed+['data/ui/build_info.json']:assert files[name]==value,name
packed=pack_files(out,files,'/Applications/Godot.app/Contents/MacOS/Godot');assert entries(packed)==files
web=out/'web';shutil.copytree(base,web,dirs_exist_ok=True);digest=hashlib.sha256(packed).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(packed,compresslevel=9,mtime=0));(web/old_core).unlink()
seed='|'.join([m['engine'].split('.')[1],digest]+[p['file'] for p in m['packs']]);build=hashlib.sha256(seed.encode()).hexdigest()[:12];m.update(build=build,core=core,core_bytes=(web/core).stat().st_size,source=meta);(web/'packs.json').write_text(json.dumps(m,indent=2)+'\n')
page=(web/'play.html').read_text().replace(old_build,build);page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda x:x[1]+str(len(packed)),page);(web/'play.html').write_text(page)
assert all((web/p['file']).read_bytes()==(base/p['file']).read_bytes() for p in m['packs'])
report=dict(build=build,baseline=old_build,paths=paths,removed_compiled=removed,unrelated_entries_and_all_content_identical=True,core_gzip_delta=m['core_bytes']-json.loads((base/'packs.json').read_text())['core_bytes']);(out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
