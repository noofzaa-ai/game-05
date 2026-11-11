#!/usr/bin/env python3
"""Run interactively ON k3s host after deploying Guest-capable images. Never echo secrets."""
import base64, getpass, json, secrets, subprocess, os, sys
from pathlib import Path
import yaml
NS='zorx-staging'
BASE=Path('/home/wiyazard/deployment/game-test/zorx-staging')
def kubectl(*args,data=None):
    result=subprocess.run(['kubectl','-n',NS,*args],input=data,text=True,capture_output=True)
    if result.returncode: raise RuntimeError('Guest configuration failed; inspect server privately')
    return result.stdout
def main():
    runtime=json.loads(kubectl('get','secret','zorx-names-runtime','-o','json'))
    landing=json.loads(kubectl('get','secret','landing-auth','-o','json'))
    unpack=lambda value:base64.b64decode(value).decode()
    captcha=(unpack(landing.get('data',{}).get('TURNSTILE_SECRET_KEY','')) if '--existing-turnstile' in sys.argv or '--prepare' in sys.argv else getpass.getpass('Turnstile Secret key (hidden): ')).strip()
    if len(captcha)<20 and '--prepare' not in sys.argv: raise ValueError('Missing Turnstile Secret key in landing-auth')
    pack=lambda value:base64.b64encode(value.encode()).decode()
    cfg=yaml.safe_load(unpack(runtime['data']['runtime.yml']))
    env=dict(entry.split('=',1) for entry in cfg['runtime'].get('env',[]))
    signing=env.get('ZORX_GUEST_SECRET') or secrets.token_urlsafe(48)
    env.update(ZORX_GUEST_ENABLED='1',ZORX_GUEST_SECRET=signing)
    cfg['runtime']['env']=[key+'='+value for key,value in env.items()]
    runtime['data']['runtime.yml']=pack(yaml.safe_dump(cfg,sort_keys=False))
    landing['data'].update({key:pack(value) for key,value in dict(
        ZORX_GUEST_ENABLED='1',ZORX_GUEST_SECRET=signing,
        TURNSTILE_SITE_KEY='0x4AAAAAAFfYmmETLpxucNy3').items()})
    if captcha: landing['data']['TURNSTILE_SECRET_KEY']=pack(captcha)
    for item in [runtime,landing]:
        item['metadata']={'name':item['metadata']['name'],'namespace':NS}
        item.pop('stringData',None)
    for filename,items in [('guest-secret.yaml',[runtime]),('landing-secret.yaml',[landing])]:
        fd=os.open(BASE/filename,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
        os.fchmod(fd,0o600)
        with os.fdopen(fd,'w') as stream: yaml.safe_dump_all(items,stream,sort_keys=False)
    secret_path=BASE/'secret.yaml'
    if secret_path.exists():
        docs=list(yaml.safe_load_all(secret_path.read_text()))
        replacements={item['metadata']['name']:item for item in [runtime,landing]}
        docs=[replacements.get(doc.get('metadata',{}).get('name'),doc) if doc and doc.get('kind')=='Secret' else doc for doc in docs]
        fd=os.open(secret_path,os.O_WRONLY|os.O_TRUNC,0o600);os.fchmod(fd,0o600)
        with os.fdopen(fd,'w') as stream:yaml.safe_dump_all(docs,stream,sort_keys=False)
    kubectl('apply','-f','-',data=yaml.safe_dump_all([runtime,landing],sort_keys=False))
    print('Guest secrets configured. Restart Nakama first, then landing after both Guest-capable images are deployed.')
if __name__=='__main__':main()
