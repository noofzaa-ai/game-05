#!/usr/bin/env python3
"""Add status VFX to the existing Gem release, preserving all unrelated shipped entries."""
import argparse,datetime,gzip,hashlib,json,re,shutil,subprocess
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries,raw,pack_files
ROOT=Path(__file__).resolve().parents[2]
SCRIPTS=('client/skills/presenter.gd','client/skills/status_effect.gd')
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 baseline=a.baseline.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
 godot='/Applications/Godot.app/Contents/MacOS/Godot';m=json.loads((baseline/'packs.json').read_text());old_build=m['build'];old_core=m['core'];files=entries(raw(baseline/old_core));original=dict(files)
 for name in SCRIPTS:
  files.pop(name+'.remap',None);files.pop(name[:-3]+'.gdc',None);files[name]=(ROOT/name).read_bytes()
 commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip();now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'))
 metadata=dict(m['source'],commit=commit,short_commit=commit[:12],dirty=True,baseline_build=old_build,patch_paths=list(SCRIPTS),source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
 files['data/ui/build_info.json']=(json.dumps(metadata,indent=2)+'\n').encode()
 data=pack_files(out,files,godot);assert entries(data)==files
 for name,value in original.items():
  if name not in ['client/skills/presenter.gd.remap','client/skills/presenter.gdc','data/ui/build_info.json']:assert files[name]==value,name
 web=out/'web';shutil.copytree(baseline,web,dirs_exist_ok=True)
 digest=hashlib.sha256(data).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(data,compresslevel=9,mtime=0))
 assets={'status_vfx':{},'status_vfx.s3tc':{},'status_vfx.etc2':{}}
 for source in (ROOT/'art/skill_system/status_vfx').rglob('*'):
  if not source.is_file():continue
  relative=source.relative_to(ROOT).as_posix()
  if source.suffix=='.scn':assets['status_vfx'][relative]=source.read_bytes()
  if source.suffix=='.import':
   assets['status_vfx'][relative]=source.read_bytes()
   for path in set(re.findall(r'"(res://\.godot/imported/[^"\n]+)"',source.read_text())):
    name=path.removeprefix('res://');group='status_vfx.s3tc' if '.s3tc.' in name else 'status_vfx.etc2' if '.etc2.' in name else 'status_vfx'
    assets[group][name]=(ROOT/name).read_bytes()
 for group,values in assets.items():
  folder=out/group;folder.mkdir(exist_ok=True);packed=pack_files(folder,values,godot);assert entries(packed)==values
  file=group+'.'+hashlib.sha256(packed).hexdigest()[:12]+'.pck.wasm';(web/file).write_bytes(gzip.compress(packed,compresslevel=9,mtime=0))
  m['packs'].append(dict(name=group,format=group.split('.')[1] if '.' in group else '',file=file,bytes=(web/file).stat().st_size,raw_bytes=len(packed)))
 seed='|'.join([m['engine'].split('.')[1],digest]+[p['file'] for p in m['packs']]);build=hashlib.sha256(seed.encode()).hexdigest()[:12]
 m.update(build=build,core=core,core_bytes=(web/core).stat().st_size,source=metadata,built=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M UTC'))
 (web/'packs.json').write_text(json.dumps(m,indent=2)+'\n');page=(web/'play.html').read_text().replace(old_build,build)
 page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda match:match[1]+str(len(data)),page);(web/'play.html').write_text(page);(web/old_core).unlink()
 report=dict(build=build,baseline=old_build,source=commit,core_bytes=m['core_bytes'],added_packs=m['packs'][-3:],unrelated_core_and_content_unchanged=True)
 (out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
