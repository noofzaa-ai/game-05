#!/usr/bin/env python3
"""Isolated API/engine compatibility gate; never a gameplay latency benchmark."""
from pathlib import Path
import subprocess,shutil,json,tempfile
ROOT=Path(__file__).resolve().parents[3]
STAGE=Path(tempfile.mkdtemp(prefix='zorx-netfox-compat-',dir='/private/tmp'))
VENDOR=ROOT/'tools/netcode/vendor/netfox-1.35.3'
for folder in ['addons']:
 shutil.copytree(VENDOR/folder,STAGE/folder)
for folder in ['logic','data']:
 shutil.copytree(ROOT/folder,STAGE/folder,ignore=shutil.ignore_patterns('*.png','*.webp','*.glb','*.blend','*.wav','*.ogg','*.mp3'))
project='''config_version=5
[application]
config/name="Zorx netfox compatibility only"
[autoload]
NetworkTime="*res://addons/netfox/network-time.gd"
NetworkTimeSynchronizer="*res://addons/netfox/network-time-synchronizer.gd"
NetworkRollback="*res://addons/netfox/rollback/network-rollback.gd"
NetworkEvents="*res://addons/netfox/network-events.gd"
NetworkPerformance="*res://addons/netfox/network-performance.gd"
[netfox]
time/tickrate=60
time/sync_to_physics=false
time/max_ticks_per_frame=8
time/suppress_offline_peer_warning=true
events/enabled=false
rollback/enabled=true
[rendering]
renderer/rendering_method="gl_compatibility"
[filesystem]
import/blender/enabled=false
'''
(STAGE/'project.godot').write_text(project)
shutil.copy2(ROOT/'tools/netcode/migration/netfox_contract.gd',STAGE/'contract.gd')
for name in ['actor_bridge.gd','bridge_input.gd','peer_contract.gd','admission_peer_contract.gd']:
 shutil.copy2(ROOT/'tools/netcode/migration'/name,STAGE/name)
shutil.copytree(ROOT/'server/rooms/netfox',STAGE/'server/rooms/netfox')
logs=ROOT/'build/netfox-migration';logs.mkdir(exist_ok=True)
report={'stage':str(STAGE),'vendor':json.loads((VENDOR/'VENDOR.json').read_text()),'purpose':'API compatibility with actual game shared sim, NOT performance or production acceptance','checks':[]}
for name,args in [('import',['--editor','--import','--quit']),('contract',['--script','res://contract.gd'])]:
 try:
  p=subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(STAGE)]+args,capture_output=True,text=True,timeout=90)
  s=p.stdout+p.stderr;(logs/(name+'.log')).write_text(s)
  failed='SCRIPT ERROR' in s or 'Parse Error' in s or p.returncode!=0
  report['checks'].append({'check':name,'exit':p.returncode,'script_errors':failed})
  print(name,p.returncode,'script_errors=',failed,flush=True)
  if failed:print(s[-5000:],flush=True);break
 except subprocess.TimeoutExpired as exc:
  s=(exc.stdout or b'')+(exc.stderr or b'');(logs/(name+'.log')).write_bytes(s);report['checks'].append({'check':name,'timeout':True});print(name,'timeout',flush=True);break
if len(report['checks'])==2 and all(not r.get('script_errors',True) for r in report['checks']):
 import time
 commands=['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(STAGE),'--script','res://peer_contract.gd','--']
 with (logs/'server.log').open('w') as out:
  server=subprocess.Popen(commands+['--server'],stdout=out,stderr=subprocess.STDOUT)
  try:
   time.sleep(.6)
   client=subprocess.run(commands,capture_output=True,text=True,timeout=18)
   (logs/'client.log').write_text(client.stdout+client.stderr)
   server.wait(timeout=18)
   for side,code in [('server',server.returncode),('client',client.returncode)]:
    content=(logs/(side+'.log')).read_text()
    report['checks'].append({'check':side+'_localhost_rpc','exit':code,'script_errors':code!=0 or 'SCRIPT ERROR' in content or 'ok=true' not in content})
  except subprocess.TimeoutExpired:
   report['checks'].append({'check':'localhost_rpc','timeout':True})
  finally:
   if server.poll() is None:server.terminate()
if len(report['checks'])==4 and all(not r.get('script_errors',True) for r in report['checks']):
 commands=['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(STAGE),'--script','res://admission_peer_contract.gd','--']
 with (logs/'auth-server.log').open('w') as out:
  server=subprocess.Popen(commands+['--server'],stdout=out,stderr=subprocess.STDOUT)
  try:
   time.sleep(.6)
   client=subprocess.run(commands,capture_output=True,text=True,timeout=14)
   (logs/'auth-client.log').write_text(client.stdout+client.stderr);server.wait(timeout=14)
   for side,code in [('auth-server',server.returncode),('auth-client',client.returncode)]:
    content=(logs/(side+'.log')).read_text()
    report['checks'].append({'check':side,'exit':code,'script_errors':code!=0 or 'SCRIPT ERROR' in content or 'PASS' not in content})
  except subprocess.TimeoutExpired:
   report['checks'].append({'check':'localhost_auth','timeout':True})
  finally:
   if server.poll() is None:server.terminate()
report['passed']=len(report['checks'])==6 and all(not r.get('script_errors',True) for r in report['checks'])
(logs/'compatibility.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
raise SystemExit(0 if report['passed'] else 1)
