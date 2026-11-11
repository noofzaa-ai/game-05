#!/usr/bin/env python3
"""Patch only Gem UI into a verified deployed split-PCK baseline; keep other bytes unchanged."""
import argparse,datetime,gzip,hashlib,json,re,shutil,struct,subprocess
from pathlib import Path
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[2]
PATCH=('client/skill_panel.gd','client/skills/touch_scroll.gd')
def entries(data):
 assert struct.unpack_from('<I',data)[0]==0x43504447
 flags=struct.unpack_from('<I',data,20)[0];assert not flags&1
 base=struct.unpack_from('<Q',data,24)[0] if flags&2 else 0
 pos=struct.unpack_from('<Q',data,32)[0];count=struct.unpack_from('<I',data,pos)[0];pos+=4;result={}
 for _ in range(count):
  n=struct.unpack_from('<I',data,pos)[0];pos+=4;name=data[pos:pos+n].decode().rstrip('\0').removeprefix('res://');pos+=n
  off,size=struct.unpack_from('<QQ',data,pos);pos+=16;md5=data[pos:pos+16];pos+=16;entry_flags=struct.unpack_from('<I',data,pos)[0];pos+=4
  assert not entry_flags&1 and '..' not in Path(name).parts
  value=data[base+off:base+off+size];assert len(value)==size and hashlib.md5(value).digest()==md5,name
  result[name]=value
 return result
def raw(path):
 data=path.read_bytes();return gzip.decompress(data) if data[:2]==b'\x1f\x8b' else data
def pack_files(out,files,godot):
 folder=out/'core-files';folder.mkdir(exist_ok=True)
 for name,value in files.items():
  target=folder/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(value)
 (out/'entries.json').write_text(json.dumps(list(files)))
 project=out/'packer';project.mkdir(exist_ok=True);(project/'project.godot').write_text('[application]\nconfig/name="Zorx Gem patch packer"\n')
 script=out/'pack.gd';script.write_text('''extends SceneTree
func _initialize():
 var folder=OS.get_cmdline_user_args()[0]+"/"
 var pack:=PCKPacker.new()
 assert(pack.pck_start(folder+"core.pck")==OK)
 for path in JSON.parse_string(FileAccess.get_file_as_string(folder+"entries.json")):
  assert(pack.add_file("res://"+path,folder+"core-files/"+path)==OK)
 assert(pack.flush()==OK)
 print("GEM CORE PACKED")
 quit()
''')
 result=subprocess.run([godot,'--headless','--path',str(project),'--script',str(script),'--',str(out)],capture_output=True,text=True,timeout=90)
 (out/'pack.log').write_text(result.stdout+result.stderr);assert result.returncode==0 and 'GEM CORE PACKED' in result.stdout
 return (out/'core.pck').read_bytes()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--godot',default='/Applications/Godot.app/Contents/MacOS/Godot');a=ap.parse_args()
 out=a.output.resolve();out.mkdir(parents=True,exist_ok=True);baseline=a.baseline.resolve();m=json.loads((baseline/'packs.json').read_text())
 original=raw(baseline/m['core']);assert hashlib.sha256(original).hexdigest()[:12] in m['core']
 old=entries(original);changed=dict(old)
 for name in ['client/skill_panel.gdc','client/skill_panel.gd.remap']:changed.pop(name,None)
 for name in PATCH:changed[name]=(ROOT/name).read_bytes()
 commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip();now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'))
 metadata=dict(m['source'],commit=commit,short_commit=commit[:12],dirty=True,baseline_build=m['build'],patch_paths=list(PATCH),source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
 changed['data/ui/build_info.json']=(json.dumps(metadata,indent=2)+'\n').encode()
 packed=pack_files(out,changed,a.godot);verified=entries(packed)
 assert verified==changed
 for name,data in old.items():
  if name not in ['client/skill_panel.gdc','client/skill_panel.gd.remap','data/ui/build_info.json'] and name not in PATCH:assert verified[name]==data,name
 web=out/'web';shutil.copytree(baseline,web,dirs_exist_ok=True)
 digest=hashlib.sha256(packed).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(packed,compresslevel=9,mtime=0))
 seed='|'.join([m['engine'].split('.')[1],digest]+[p['file'] for p in m['packs']]);build=hashlib.sha256(seed.encode()).hexdigest()[:12]
 old_build=m['build'];old_core=m['core'];m.update(build=build,core=core,core_bytes=(web/core).stat().st_size,source=metadata,built=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M UTC'))
 (web/'packs.json').write_text(json.dumps(m,indent=2)+'\n')
 page=(web/'play.html').read_text().replace(old_build,build)
 page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda match:match[1]+str(len(packed)),page)
 (web/'play.html').write_text(page);(web/old_core).unlink()
 assert all((web/p['file']).read_bytes()==(baseline/p['file']).read_bytes() for p in m['packs'])
 assert (web/m['engine']).read_bytes()==(baseline/m['engine']).read_bytes()
 report=dict(baseline_build=old_build,build=build,source_commit=commit,changed_paths=list(PATCH)+['data/ui/build_info.json'],all_other_core_entries_identical=True,all_content_and_engine_identical=True,core_raw_bytes=len(packed),core_gzip_bytes=m['core_bytes'])
 (out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
