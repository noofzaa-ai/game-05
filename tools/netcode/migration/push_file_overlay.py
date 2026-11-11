#!/usr/bin/env python3
"""Append a bounded source-only OCI layer to a verified existing room image.
Avoids exporting hundreds of MB of unchanged base layers on a disk-constrained machine.
"""
import argparse,datetime,gzip,hashlib,io,json,tarfile,urllib.request as U,urllib.parse as P
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--tag',required=True);p.add_argument('--record',type=Path,required=True);p.add_argument('--file',type=Path);p.add_argument('--web-dir',type=Path);a=p.parse_args()
ROOT=Path(__file__).resolve().parents[3]
assert bool(a.file)!=bool(a.web_dir)
if a.web_dir:
 web=a.web_dir.resolve();assert web.is_relative_to(Path('/private/tmp'))
 m=json.loads((web/'packs.json').read_text());core=m['core'];assert core.startswith('core.') and core.endswith('.pck.wasm') and '/' not in core
 sources=[('usr/share/nginx/html/'+name,web/name) for name in [core,'packs.json','play.html']]
 assert sum(source.stat().st_size for _,source in sources)<40_000_000
 repository='zorx-web'
else:
 source=a.file.resolve();assert source==ROOT/'logic/companions/brain.gd'
 sources=[('project/logic/companions/brain.gd',source)];repository='zorx-room-worker'
origin='http://127.0.0.1:30505';repo='/v2/'+repository
assert a.base.startswith('wiyazard:30500/'+repository+':') and '@sha256:' in a.base
base_tag,expected=a.base.split(repository+':',1)[1].split('@',1)
def digest(b):return 'sha256:'+hashlib.sha256(b).hexdigest()
def req(path,method='GET',body=None,headers=None):
 parts=P.urlsplit(path);url=origin+(parts.path if parts.scheme else path)+(('?'+parts.query) if parts.scheme and parts.query else '')
 with U.urlopen(U.Request(url,data=body,method=method,headers=headers or {}),timeout=120) as r:return r.read(),dict(r.headers)
def upload(data):
 d=digest(data)
 try:req(repo+'/blobs/'+d,'HEAD');return d
 except U.HTTPError as e:
  if e.code!=404:raise
 _,h=req(repo+'/blobs/uploads/','POST',b'');loc=h.get('Location') or h.get('location')
 req(loc+('&' if '?' in loc else '?')+'digest='+d,'PUT',data,{'Content-Type':'application/octet-stream'})
 return d
media='application/vnd.docker.distribution.manifest.v2+json'
raw,_=req(repo+'/manifests/'+base_tag,headers={'Accept':media});assert digest(raw)==expected,'Base changed: refuse overlay'
manifest=json.loads(raw);config_raw,_=req(repo+'/blobs/'+manifest['config']['digest']);assert digest(config_raw)==manifest['config']['digest'];config=json.loads(config_raw)
archive=io.BytesIO();hashes={}
with tarfile.open(fileobj=archive,mode='w') as tar:
 for name,source in sources:
  contents=source.read_bytes();hashes[name]=hashlib.sha256(contents).hexdigest()
  info=tarfile.TarInfo(name);info.size=len(contents);info.mode=0o644;info.mtime=0;tar.addfile(info,io.BytesIO(contents))
layer_raw=archive.getvalue();compressed=gzip.compress(layer_raw,mtime=0)
now=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
config['created']=now;config['rootfs']['diff_ids'].append(digest(layer_raw));config.setdefault('history',[]).append({'created':now,'created_by':'zorx scoped companion behaviour overlay'})
env=config.setdefault('config',{}).setdefault('Env',[]);env[:]=[e for e in env if not e.startswith('ZORX_WORKER_RELEASE=')];env.append('ZORX_WORKER_RELEASE='+a.tag)
config_raw=json.dumps(config,separators=(',',':')).encode()
manifest['layers'].append({'mediaType':'application/vnd.docker.image.rootfs.diff.tar.gzip','size':len(compressed),'digest':upload(compressed)})
manifest['config']={'mediaType':'application/vnd.docker.container.image.v1+json','size':len(config_raw),'digest':upload(config_raw)}
raw=json.dumps(manifest,separators=(',',':')).encode();req(repo+'/manifests/'+a.tag,'PUT',raw,{'Content-Type':media})
fetched,_=req(repo+'/manifests/'+a.tag,headers={'Accept':media});assert fetched==raw
record={'image':'wiyazard:30500/'+repository+':'+a.tag+'@'+digest(raw),'base_image':a.base,'verified':True,'file_sha256':hashes,'patch_bytes':len(compressed),'registry_upload_endpoint':origin}
a.record.parent.mkdir(parents=True,exist_ok=True);a.record.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
