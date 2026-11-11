#!/usr/bin/env python3
"""Scope Phase1 companion UI to the exact live split-PCK baseline; no unrelated WIP."""
import argparse, datetime, gzip, hashlib, json, re, shutil
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries, raw, pack_files
ROOT=Path(__file__).resolve().parents[2]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    base=a.baseline.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    m=json.loads((base/'packs.json').read_text());old_build=m['build'];old_core=m['core'];files=entries(raw(base/old_core));original=dict(files)
    files['client/hub_companion_baseline.gd']=files['client/hub.gd']
    files['client/hub.gd']=b'''extends "res://client/hub_companion_baseline.gd"
var _adventurer
func _ready()->void:
 super._ready()
 _adventurer=preload("res://client/companions/camp_adventurer.gd").new()
 _adventurer.hub=self
 add_child(_adventurer)
 var invitations=preload("res://client/online/character_invitation.gd").new()
 invitations.hub=self
 add_child(invitations)
func has_open_panel()->bool:
 var invitations=get_meta("character_invitation") if has_meta("character_invitation") else null
 if is_instance_valid(invitations) and invitations.has_open_panel():return true
 if is_instance_valid(_adventurer) and is_instance_valid(_adventurer.panel):return true
 return super.has_open_panel()
'''
    files['client/game_state_companion_baseline.gdc']=files.pop('client/game_state.gdc')
    files['client/game_state_companion_baseline.gd.remap']=b'[remap]\npath="res://client/game_state_companion_baseline.gdc"\n'
    files.pop('client/game_state.gd.remap')
    files['client/game_state.gd']=b'''extends "res://client/game_state_companion_baseline.gd"
var _companion_netfox:=false
func attach_online_room(service,ticket:Dictionary):
 _companion_netfox=ticket.get("netfox_room",false) or ticket.get("companion_pending",false) or not ticket.get("companions",[]).is_empty()
 return super.attach_online_room(service,ticket)
func _netfox_requested()->bool:
 return _companion_netfox or super._netfox_requested()
'''
    paths=['client/online/character_invitation.gd','client/companions/camp_adventurer.gd','client/online/room_client.gd','client/online/room_panel.gd','logic/companions/roster.gd','logic/companions/navigation.gd','data/companions/roster.json']
    for name in paths:
        files.pop(name+'c',None);files.pop(name+'.remap',None);files[name]=(ROOT/name).read_bytes()
    now=datetime.datetime.now(ZoneInfo('Asia/Bangkok'))
    meta=dict(m['source'],baseline_build=old_build,patch_paths=paths+['client/hub.gd','client/game_state.gd'],source_modified=now.isoformat(),source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
    files['data/ui/build_info.json']=(json.dumps(meta,indent=2)+'\n').encode()
    allowed=set(paths+['client/hub.gd','client/game_state.gdc','client/game_state.gd.remap','client/online/room_client.gdc','client/online/room_client.gd.remap','client/online/room_panel.gdc','client/online/room_panel.gd.remap','data/ui/build_info.json'])
    for name,data in original.items():
        if name not in allowed:assert files[name]==data,name
    packed=pack_files(out,files,'/Applications/Godot.app/Contents/MacOS/Godot');assert entries(packed)==files
    web=out/'web';shutil.copytree(base,web,dirs_exist_ok=True)
    digest=hashlib.sha256(packed).hexdigest()[:12];core='core.'+digest+'.pck.wasm';(web/core).write_bytes(gzip.compress(packed,compresslevel=9,mtime=0));(web/old_core).unlink()
    seed='|'.join([m['engine'].split('.')[1],digest]+[p['file'] for p in m['packs']]);build=hashlib.sha256(seed.encode()).hexdigest()[:12]
    m.update(build=build,core=core,core_bytes=(web/core).stat().st_size,source=meta);(web/'packs.json').write_text(json.dumps(m,indent=2)+'\n')
    page=(web/'play.html').read_text().replace(old_build,build);page=re.sub(r'("index.pck"\s*:\s*)\d+',lambda x:x[1]+str(len(packed)),page);(web/'play.html').write_text(page)
    for p in m['packs']:assert (web/p['file']).read_bytes()==(base/p['file']).read_bytes()
    assert (web/m['engine']).read_bytes()==(base/m['engine']).read_bytes()
    report=dict(build=build,baseline=old_build,paths=paths,unrelated_core_engine_content_identical=True,llm_shipped=False,core_gzip_delta=m['core_bytes']-json.loads((base/'packs.json').read_text())['core_bytes'])
    (out/'patch-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
