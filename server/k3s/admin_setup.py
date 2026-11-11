#!/usr/bin/env python3
"""Run ON k3s host: share a dedicated admin key internally; never print/export values."""
import base64,json,secrets,subprocess,os
from pathlib import Path
import yaml
BASE=Path('/home/wiyazard/deployment/game-test/zorx-staging')
NS='zorx-staging'

def kubectl(*args,data=None):
 r=subprocess.run(['kubectl','-n',NS,*args],input=data,text=True,capture_output=True)
 if r.returncode:raise RuntimeError('kubectl admin setup failed; inspect locally without printing Secret data')
 return r.stdout

def save_private(path,docs):
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 os.fchmod(fd,0o600)
 with os.fdopen(fd,'w') as f:yaml.safe_dump_all(docs,f,sort_keys=False)

def main():
 config=json.loads((BASE/'admin-config.json').read_text())
 emails=config['emails']
 if not isinstance(emails,list) or not emails or any(not isinstance(e,str) or '@' not in e for e in emails):raise ValueError('emails must be a nonempty array')
 emails=json.dumps([e.strip().lower() for e in emails],separators=(',',':'))
 runtime=json.loads(kubectl('get','secret','zorx-names-runtime','-o','json'))
 landing=json.loads(kubectl('get','secret','landing-auth','-o','json'))
 base=json.loads(kubectl('get','secret','nakama-config','-o','json'))
 unpack=lambda v:base64.b64decode(v).decode()
 pack=lambda v:base64.b64encode(v.encode()).decode()
 cfg=yaml.safe_load(unpack(runtime['data']['runtime.yml']))
 entries=cfg['runtime'].get('env',[])
 env=dict(x.split('=',1) for x in entries)
 token=env.get('ZORX_ADMIN_TOKEN') or secrets.token_urlsafe(48)
 env.update(ZORX_ADMIN_TOKEN=token,ZORX_ADMIN_EMAILS=emails)
 cfg['runtime']['env']=[k+'='+v for k,v in env.items()]
 runtime['data']['runtime.yml']=pack(yaml.safe_dump(cfg,sort_keys=False))
 nakama=yaml.safe_load(unpack(base['data']['config.yml']))
 landing['data'].update({k:pack(v) for k,v in {'ZORX_ADMIN_TOKEN':token,'ZORX_ADMIN_EMAILS':emails,'ZORX_ADMIN_HTTP_KEY':nakama['runtime']['http_key']}.items()})
 for item in [runtime,landing]:
  item['metadata']={'name':item['metadata']['name'],'namespace':NS}
  item.pop('stringData',None)
 # Maintain apply-only manifests in the existing fixed directory.
 save_private(BASE/'admin-secret.yaml',[runtime])
 save_private(BASE/'landing-secret.yaml',[landing])
 secret_path=BASE/'secret.yaml'
 if secret_path.exists():
  docs=list(yaml.safe_load_all(secret_path.read_text()))
  replacements={x['metadata']['name']:x for x in [runtime,landing]}
  docs=[replacements.get(d.get('metadata',{}).get('name'),d) if d and d.get('kind')=='Secret' else d for d in docs]
  save_private(secret_path,docs)
 kubectl('apply','-f','-',data=yaml.safe_dump_all([runtime,landing],sort_keys=False))
 print('Admin allowlist and dedicated service key configured in zorx-staging; no values exported')

if __name__=='__main__':main()
