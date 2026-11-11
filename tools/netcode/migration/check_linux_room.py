#!/usr/bin/env python3
"""Exact candidate Linux image + native session correctness; fixture auth, no user data."""
from pathlib import Path
import json,os,subprocess,time,re
ROOT=Path(__file__).resolve().parents[3];LOG=ROOT/'build/netfox-migration'
stage=Path(json.loads((LOG/'room-coop-context.json').read_text())['path'])
name='zorx-netfox-linux-contract'
image='wiyazard:30500/zorx-room-worker:netfox-20261028-1'
subprocess.run(['docker','run','--rm','-d','--name',name,'--platform','linux/amd64','-p','127.0.0.1:19479:8061','-e','ZORX_TEST_BIND=0.0.0.0','--tmpfs','/tmp:uid=10001,gid=10001','--mount','type=bind,src='+str(ROOT/'tests/netfox_room_integration.gd')+',dst=/project/tests/netfox_room_integration.gd,readonly','--entrypoint','/usr/local/bin/godot',image,'--headless','--path','/project','--script','res://tests/netfox_room_integration.gd','--','--server'],check=True,capture_output=True)
try:
 deadline=time.monotonic()+40
 while True:
  out=subprocess.check_output(['docker','logs',name],stderr=subprocess.STDOUT,text=True)
  if 'INTEGRATION listening 0' in out:break
  if time.monotonic()>deadline:raise RuntimeError(out[-3000:])
  time.sleep(.2)
 cmd=['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(stage),'--script','res://tests/netfox_room_integration.gd']
 # Copy exact current client test; production session source already copied by co-op check.
 import shutil
 shutil.copy2(ROOT/'tests/netfox_room_integration.gd',stage/'tests/netfox_room_integration.gd')
 with (LOG/'linux-client.log').open('w') as log:
  result=subprocess.run(cmd,env=dict(os.environ,ZORX_TEST_ROOM_URL='ws://127.0.0.1:19479'),stdout=log,stderr=subprocess.STDOUT,timeout=40)
 out=subprocess.check_output(['docker','logs',name],stderr=subprocess.STDOUT,text=True);(LOG/'linux-server.log').write_text(out)
 client=(LOG/'linux-client.log').read_text()
 rejections=re.search(r'"rejected_input_packets": (\d+)',client)
 good=rejections is not None and int(rejections[1])==0 and result.returncode==0 and 'NETFOX ROOM CLIENT' in client and 'SCRIPT ERROR' not in client+out and 'Node not found:' not in client+out
 print('LINUX ROOM', 'PASS' if good else 'FAIL', '\n'.join(x for x in client.splitlines() if 'NETFOX ROOM CLIENT' in x),flush=True)
 if not good:print(client[-2500:],out[-2500:])
 (LOG/'linux-result.json').write_text(json.dumps({'passed':good,'image':image,'purpose':'exact Linux image correctness; no Web/WAN/account acceptance'},indent=2))
 raise SystemExit(0 if good else 1)
finally:
 subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
