#!/usr/bin/env python3
"""Ground-only visual overlay; retain all live gameplay and existing packs."""
import argparse,datetime,gzip,hashlib,json,os,re,shutil
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries,raw,pack_files
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 out=a.output;out.mkdir(parents=True,exist_ok=True);base=a.baseline;m=json.loads((base/'packs.json').read_text());oldbuild=m['build'];oldcore=m['core'];old=entries(raw(base/oldcore));files=dict(old)
 name='client/stage_view.gd';source=files[name].decode();assert 'func _build_stage' not in source
 files[name]=(source+'\nfunc _build_stage(map)->void:\n\tsuper._build_stage(map)\n\tpreload("res://client/goblin_ground.gd").apply(self,map)\n').encode()
 files['client/goblin_ground.gd']=(ROOT/'client/goblin_ground.gd').read_bytes()
 now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'));meta=dict(m['source'],baseline_build=oldbuild,patch_paths=[name,'client/goblin_ground.gd','art/maps/goblin_base/*.tscn'],source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
 files['data/ui/build_info.json']=(json.dumps(meta,indent=2)+'\n').encode()
 assert all(files[k]==v for k,v in old.items() if k not in [name,'data/ui/build_info.json'])
 godot='/Applications/Godot.app/Contents/MacOS/Godot';core=pack_files(out,files,godot);assert entries(core)==files
 web=out/'web';shutil.copytree(base,web,copy_function=lambda src,dst:shutil.copy2(src,dst) if Path(src).name in ['packs.json','play.html'] else os.link(src,dst))
 core_name='core.'+hashlib.sha256(core).hexdigest()[:12]+'.pck.wasm';(web/core_name).write_bytes(gzip.compress(core,mtime=0));(web/oldcore).unlink()
 folder=out/'terrain';folder.mkdir(exist_ok=True);assets={p.relative_to(ROOT).as_posix():p.read_bytes() for p in (ROOT/'art/maps/goblin_base').glob('*.tscn')}
 data=pack_files(folder,assets,godot);assert entries(data)==assets
 filename='goblin-ground.'+hashlib.sha256(data).hexdigest()[:12]+'.pck.wasm';compressed=gzip.compress(data,mtime=0);(web/filename).write_bytes(compressed)
 pack=dict(name='goblin-ground',format='',file=filename,bytes=len(compressed),raw_bytes=len(data));m['packs'].append(pack)
 build=hashlib.sha256('|'.join([m['engine'],core_name]+[p['file'] for p in m['packs']]).encode()).hexdigest()[:12]
 m.update(build=build,core=core_name,core_bytes=(web/core_name).stat().st_size,source=meta);(web/'packs.json').write_text(json.dumps(m,indent=2)+'\n')
 page=(web/'play.html').read_text().replace(oldbuild,build);page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda x:x[1]+str(len(core)),page);(web/'play.html').write_text(page)
 for p in json.loads((base/'packs.json').read_text())['packs']:assert (web/p['file']).read_bytes()==(base/p['file']).read_bytes()
 report=dict(build=build,baseline=oldbuild,unrelated_core_and_packs_identical=True,asset_pack=pack,download_delta=m['core_bytes']-json.loads((base/'packs.json').read_text())['core_bytes']+len(compressed))
 (out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
