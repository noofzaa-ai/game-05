#!/usr/bin/env python3
"""Approved original-theme Relic UI and donor NPC standing pose only."""
import argparse,datetime,gzip,hashlib,json,os,re,shutil
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries,raw,pack_files
ROOT=Path(__file__).resolve().parents[2]
PATCH=['client/relic_panel.gd','client/relic_ui/lock.gd','client/relic_ui/showcase.gd','client/relic_master_pose.gd','client/hub_npc.gd']
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();base=a.baseline;out=a.output;out.mkdir(parents=True,exist_ok=True)
 m=json.loads((base/'packs.json').read_text());oldbuild=m['build'];oldcore=m['core'];old=entries(raw(base/oldcore));files=dict(old)
 assert files['client/hub_npc.gd'].startswith(b'extends "res://client/hub_npc_relic_baseline.gd"')
 for name in PATCH:
  for suffix in ['', 'c', '.remap']:files.pop(name+suffix,None)
  source=ROOT/('tools/web/relic_patch/hub_npc.gd' if name=='client/hub_npc.gd' else name);files[name]=source.read_bytes()
 assert b'bevel_style' not in files['client/relic_panel.gd']
 assert b'Ink.window_style()' in files['client/relic_panel.gd'] and b'Ink.panel_style()' in files['client/relic_panel.gd']
 allowed=set(PATCH+['data/ui/build_info.json'])
 for name in PATCH:allowed.update([name+'c',name+'.remap'])
 assert all(files[k]==v for k,v in old.items() if k not in allowed)
 now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'));metadata=dict(m['source'],baseline_build=oldbuild,patch_paths=PATCH,source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
 files['data/ui/build_info.json']=(json.dumps(metadata,indent=2)+'\n').encode()
 packed=pack_files(out,files,'/Applications/Godot.app/Contents/MacOS/Godot');assert entries(packed)==files
 web=out/'web';shutil.copytree(base,web,copy_function=lambda src,dst:shutil.copy2(src,dst) if Path(src).name in ['packs.json','play.html'] else os.link(src,dst))
 digest=hashlib.sha256(packed).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(packed,compresslevel=9,mtime=0));(web/oldcore).unlink()
 build=hashlib.sha256('|'.join([m['engine'],core]+[p['file'] for p in m['packs']]).encode()).hexdigest()[:12]
 m.update(build=build,core=core,core_bytes=(web/core).stat().st_size,source=metadata);(web/'packs.json').write_text(json.dumps(m,indent=2)+'\n')
 page=(web/'play.html').read_text().replace(oldbuild,build);page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda x:x[1]+str(len(packed)),page);(web/'play.html').write_text(page)
 for p in m['packs']:assert (web/p['file']).read_bytes()==(base/p['file']).read_bytes()
 assert (web/m['engine']).read_bytes()==(base/m['engine']).read_bytes()
 report=dict(build=build,baseline=oldbuild,paths=PATCH,unrelated_core_identical=True,content_and_engine_identical=True,no_custom_frame_shipped=True,download_delta=m['core_bytes']-json.loads((base/'packs.json').read_text())['core_bytes'])
 (out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
