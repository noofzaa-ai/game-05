#!/usr/bin/env python3
"""Apply only the approved Skill menu icon to an exact deployed split-PCK baseline."""
import argparse,datetime,gzip,hashlib,json,re,shutil,subprocess
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries,raw,pack_files
ROOT=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
base=args.baseline.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True);m=json.loads((base/'packs.json').read_text());old_build=m['build'];old_core=m['core'];files=entries(raw(base/old_core));original=dict(files)
# Keep the deployed compiled hub as the parent; do not import unrelated workspace hub changes.
assert 'client/hub.gdc' in files and 'client/hub_skill_baseline.gdc' not in files
files['client/hub_skill_baseline.gdc']=files.pop('client/hub.gdc');files.pop('client/hub.gd.remap');files['client/hub.gd']=(ROOT/'tools/web/skill_icon_hub_patch.gd').read_bytes()
files['client/hub_skill_baseline.gd.remap']=b'[remap]\n\npath="res://client/hub_skill_baseline.gdc"\n'
files['client/skill_menu_icon.gd']=(ROOT/'client/skill_menu_icon.gd').read_bytes()
path='assets/ui/hub_shortcuts/skill.png.import';files[path]=(ROOT/path).read_bytes()
for source in re.findall(r'"(res://\.godot/imported/[^"\n]+)"',files[path].decode()):
 name=source.removeprefix('res://');files[name]=(ROOT/name).read_bytes()
now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'));commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
meta=dict(m['source'],baseline_build=old_build,commit=commit,short_commit=commit[:12],dirty=True,patch_paths=['client/hub.gd','client/skill_menu_icon.gd',path],source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
files['data/ui/build_info.json']=(json.dumps(meta,indent=2)+'\n').encode()
for name,data in original.items():
 if name not in ['client/hub.gdc','client/hub.gd.remap','data/ui/build_info.json']:assert files[name]==data,name
packed=pack_files(out,files,'/Applications/Godot.app/Contents/MacOS/Godot');assert entries(packed)==files
web=out/'web';shutil.copytree(base,web,dirs_exist_ok=True);digest=hashlib.sha256(packed).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(packed,compresslevel=9,mtime=0));(web/old_core).unlink()
seed='|'.join([m['engine'].split('.')[1],digest]+[p['file'] for p in m['packs']]);build=hashlib.sha256(seed.encode()).hexdigest()[:12]
m.update(build=build,core=core,core_bytes=(web/core).stat().st_size,source=meta,built=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M UTC'));(web/'packs.json').write_text(json.dumps(m,indent=2)+'\n')
page=(web/'play.html').read_text().replace(old_build,build);page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda x:x[1]+str(len(packed)),page);(web/'play.html').write_text(page)
assert all((web/p['file']).read_bytes()==(base/p['file']).read_bytes() for p in m['packs'])
report=dict(build=build,baseline_build=old_build,added_download_bytes=m['core_bytes']-json.loads((base/'packs.json').read_text())['core_bytes'],unrelated_entries_and_content_unchanged=True,source=commit)
(out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
