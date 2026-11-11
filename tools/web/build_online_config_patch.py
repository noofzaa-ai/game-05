#!/usr/bin/env python3
"""Emergency scoped patch: swap in data/online.local.json over a verified split-PCK Web
baseline. Fixes a build that shipped with online disabled because it was exported from a
fresh git worktree that never had the gitignored local connection config copied into it
(see entity-prune-20261102-1). Changes nothing else; all other bytes byte-identical."""
import argparse,datetime,gzip,hashlib,json,os,re
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries,raw,pack_files
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();base=a.baseline.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
m=json.loads((base/'packs.json').read_text());oldbuild=m['build'];oldcore=m['core'];original=entries(raw(base/oldcore));files=dict(original)
paths=['data/online.local.json']
for name in paths:
 for key in [name,name+'c',name+'.remap']:files.pop(key,None)
 files[name]=(ROOT/name).read_bytes()
now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'))
m['source']=dict(m['source'],baseline_build=oldbuild,patch_paths=paths,source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
files['data/ui/build_info.json']=(json.dumps(m['source'],indent=2)+'\n').encode()
for key,value in original.items():
 if key not in [p+s for p in paths for s in ['', 'c', '.remap']]+['data/ui/build_info.json']:assert files[key]==value,key
packed=pack_files(out,files,'/Applications/Godot.app/Contents/MacOS/Godot');assert entries(packed)==files
web=out/'web';web.mkdir(exist_ok=True)
for source in base.iterdir():
 if source.is_file() and source.name not in [oldcore,'packs.json','play.html']:os.link(source,web/source.name)
digest=hashlib.sha256(packed).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(packed,compresslevel=9,mtime=0))
seed='|'.join([m['engine'].split('.')[1],digest]+[p['file'] for p in m['packs']]);build=hashlib.sha256(seed.encode()).hexdigest()[:12]
m.update(build=build,core=core,core_bytes=(web/core).stat().st_size);(web/'packs.json').write_text(json.dumps(m,indent=2)+'\n')
page=(base/'play.html').read_text().replace(oldbuild,build);page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda x:x[1]+str(len(packed)),page);(web/'play.html').write_text(page)
report={'build':build,'baseline':oldbuild,'paths':paths,'unrelated_core_and_content_identical':True,'core_delta_bytes':m['core_bytes']-json.loads((base/'packs.json').read_text())['core_bytes']};(out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
