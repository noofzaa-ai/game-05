#!/usr/bin/env python3
"""Update only one verified candidate image and its existing remote manifest image line."""
from pathlib import Path
import argparse,json,shlex,subprocess
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('kind',choices=['rooms','web','nakama']);p.add_argument('record');p.add_argument('--tag',required=True);a=p.parse_args()
image=json.loads((ROOT/a.record).read_text())['image'];repo='zorx-room-worker' if a.kind=='rooms' else 'zorx-nakama' if a.kind=='nakama' else 'zorx-web'
assert image.startswith('wiyazard:30500/'+repo+':'+a.tag+'@sha256:')
filename='headless.yaml' if a.kind=='rooms' else 'deployment.yaml' if a.kind=='nakama' else 'game.yaml'
script='''from pathlib import Path
import re,shutil
p=Path.home()/"deployment/game-test/zorx-staging"/FILENAME
old=p.read_text()
new,n=re.subn(r"(?m)^(\\s*image:\\s*)wiyazard:30500/REPO:[^\\s#]+",lambda m:m[1]+IMAGE,old)
assert n==1,n
backup=p.with_name(p.name+".before-"+TAG+".bak")
if not backup.exists():shutil.copy2(p,backup)
p.write_text(new)
print(p.name+": image synced; other settings preserved")
'''.replace('FILENAME',repr(filename)).replace('REPO',repo).replace('IMAGE',repr(image)).replace('TAG',repr(a.tag))
ssh=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','UserKnownHostsFile=/tmp/zorx-release-known-hosts','wiyazard@100.78.133.27']
subprocess.run(ssh+['python3 -'],input=script,text=True,check=True)
dep='headless' if a.kind=='rooms' else 'nakama' if a.kind=='nakama' else 'game-test';container='rooms' if a.kind=='rooms' else 'nakama' if a.kind=='nakama' else 'game-test'
subprocess.run(ssh+['kubectl -n zorx-staging set image deployment/'+dep+' '+shlex.quote(container+'='+image)+' && kubectl -n zorx-staging rollout status deployment/'+dep+' --timeout=150s'],check=True,timeout=180)
