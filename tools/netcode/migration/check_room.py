#!/usr/bin/env python3
"""Actual Room/session correctness gate with fixture admission; never Web acceptance."""
from pathlib import Path
import argparse,json,runpy,shutil,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[3]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--case',choices=['solo','coop','epoch','reconnect','quiet-states','pause','companion','companion-delay','diagnostics'],default='solo');args=parser.parse_args()
 stage=Path(tempfile.mkdtemp(prefix='zorx-netfox-room-check-',dir='/private/tmp'))
 runpy.run_path(str(ROOT/'server/rooms/smoke.py'))['prepare'](stage)
 for folder in ['client/session','client/online','addons/com.heroiclabs.nakama']:
  shutil.copytree(ROOT/folder,stage/folder)
 shutil.copy2(ROOT/'client/graphics_options.gd',stage/'client/graphics_options.gd')
 runpy.run_path(str(ROOT/'server/shared/godot_class_cache.py'))['prepare'](stage)
 (stage/'tests').mkdir();shutil.copy2(ROOT/'tests/netfox_room_integration.gd',stage/'tests/netfox_room_integration.gd')
 logs=ROOT/'build/netfox-migration';logs.mkdir(exist_ok=True)
 (logs/('room-'+args.case+'-context.json')).write_text(json.dumps({'path':str(stage),'fixture':'admission only; production Room and session source'}))
 base=['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(stage),'--script','res://tests/netfox_room_integration.gd','--']
 if args.case!='solo':base+=['--'+args.case]
 processes=[];handles=[];results=[]
 try:
  server_log=logs/(args.case+'-server.log');h=server_log.open('w');handles.append(h)
  server=subprocess.Popen(base+['--server'],stdout=h,stderr=subprocess.STDOUT);processes.append(('server',server,server_log))
  deadline=time.monotonic()+120
  while 'INTEGRATION listening 0' not in server_log.read_text():
   if server.poll() is not None or time.monotonic()>deadline:raise RuntimeError('server readiness failed: '+server_log.read_text()[-2500:])
   time.sleep(.1)
  for side,extra in [('client1',[])]+([('client2',['--slot2'])] if args.case=='coop' else []):
   path=logs/(args.case+'-'+side+'.log');h=path.open('w');handles.append(h)
   processes.append((side,subprocess.Popen(base+extra,stdout=h,stderr=subprocess.STDOUT),path))
  for side,p,path in processes:
   try:p.wait(timeout=150)
   except subprocess.TimeoutExpired:p.kill();p.wait()
   s=path.read_text();marker='NETFOX ROOM SERVER' if side=='server' else 'NETFOX ROOM CLIENT'
   bad=p.returncode!=0 or 'SCRIPT ERROR' in s or 'past the history limit' in s or 'ready_state != STATE_OPEN' in s or 'Attempt to disconnect a nonexistent' in s or 'Node not found:' in s or 'Invalid packet received' in s or marker not in s
   results.append({'side':side,'exit':p.returncode,'passed':not bad})
   print(side,'PASS' if not bad else 'FAIL',s[-2200:] if bad else '\n'.join(x for x in s.splitlines() if marker in x),flush=True)
 finally:
  for side,p,path in processes:
   if p.poll() is None:p.kill();p.wait()
  for h in handles:h.close()
 (logs/('room-'+args.case+'-result.json')).write_text(json.dumps(results,indent=2))
 raise SystemExit(0 if results and all(r['passed'] for r in results) else 1)
if __name__=='__main__':main()
