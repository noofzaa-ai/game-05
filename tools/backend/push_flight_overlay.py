#!/usr/bin/env python3
"""Append a reviewed release directory to an immutable internal game image.

Reuses existing registry layers; useful when the build host cannot hold another
full image. Overlay paths and hashes are recorded for release verification.
"""
import argparse, datetime, gzip, hashlib, io, json, tarfile
import urllib.request as U
import urllib.parse as P
from pathlib import Path

def digest(data): return 'sha256:'+hashlib.sha256(data).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--base',required=True);ap.add_argument('--tag',required=True)
    ap.add_argument('--overlay',type=Path,required=True);ap.add_argument('--record',type=Path,required=True)
    a=ap.parse_args()
    assert a.base.startswith('wiyazard:30500/') and '@sha256:' in a.base
    image,expected=a.base.split('@');repository=image.split('/',1)[1].split(':',1)[0]
    assert repository in ['zorx-web','zorx-room-worker','zorx-nakama']
    origin='http://wiyazard:30500';repo='/v2/'+repository
    def request(path,method='GET',data=None,headers=None):
        parts=P.urlsplit(path)
        url=origin+(parts.path if parts.scheme else path)+(('?'+parts.query) if parts.scheme and parts.query else '')
        with U.urlopen(U.Request(url,data=data,method=method,headers=headers or {}),timeout=55) as r:
            return r.read(),dict(r.headers)
    def upload(data):
        value=digest(data)
        try: request(repo+'/blobs/'+value,'HEAD');return value
        except U.HTTPError as e:
            if e.code!=404:raise
        _,headers=request(repo+'/blobs/uploads/','POST',b'')
        location=headers.get('Location') or headers.get('location')
        request(location+('&' if '?' in location else '?')+'digest='+value,'PUT',data,{'Content-Type':'application/octet-stream'})
        return value
    media='application/vnd.docker.distribution.manifest.v2+json'
    raw,_=request(repo+'/manifests/'+expected,headers={'Accept':media});assert digest(raw)==expected
    manifest=json.loads(raw);raw,_=request(repo+'/blobs/'+manifest['config']['digest'])
    assert digest(raw)==manifest['config']['digest'];config=json.loads(raw)
    archive=io.BytesIO();files={}
    with tarfile.open(fileobj=archive,mode='w') as tar:
        for path in sorted(a.overlay.rglob('*')):
            if not path.is_file():continue
            assert not path.is_symlink();name=path.relative_to(a.overlay).as_posix()
            allowed_worker={'project/runtime/diagnostics/flight_recorder.gd', 'project/runtime/netfox/transmitter.gd', 'project/server/rooms/netfox/service.gd', 'project/runtime/diagnostics/report_codec.gd', 'project/runtime/netfox/actor.gd', 'project/runtime/netfox/input_frame.gd', 'project/logic/net/input_inbox.gd', 'project/runtime/netfox/synchronizer.gd'}
            assert name.startswith('usr/share/nginx/html/') if repository=='zorx-web' else name in allowed_worker if repository=='zorx-room-worker' else name=='opt/zorx/modules/index.js' 
            content=path.read_bytes();assert len(content)<20*1024*1024
            info=tarfile.TarInfo(name);info.size=len(content);info.mode=0o644;info.mtime=0
            tar.addfile(info,io.BytesIO(content));files[name]=digest(content)
    assert files
    layer=archive.getvalue();compressed=gzip.compress(layer,mtime=0)
    now=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
    config['created']=now;config['rootfs']['diff_ids'].append(digest(layer))
    config.setdefault('history',[]).append({'created':now,'created_by':'zorx diagnostic flight recorder release'})
    if repository=='zorx-room-worker':
        env=config.setdefault('config',{}).setdefault('Env',[])
        env[:]=[v for v in env if not v.startswith('ZORX_WORKER_RELEASE=')];env.append('ZORX_WORKER_RELEASE='+a.tag)
    raw=json.dumps(config,separators=(',',':')).encode()
    manifest['layers'].append({'mediaType':'application/vnd.docker.image.rootfs.diff.tar.gzip','size':len(compressed),'digest':upload(compressed)})
    manifest['config']={'mediaType':'application/vnd.docker.container.image.v1+json','size':len(raw),'digest':upload(raw)}
    raw=json.dumps(manifest,separators=(',',':')).encode()
    request(repo+'/manifests/'+a.tag,'PUT',raw,{'Content-Type':media})
    fetched,_=request(repo+'/manifests/'+a.tag,headers={'Accept':media});assert fetched==raw
    record={'image':'wiyazard:30500/'+repository+':'+a.tag+'@'+digest(raw),'base_image':a.base,
            'verified':True,'patch_bytes':len(compressed),'files':files}
    a.record.write_text(json.dumps(record,indent=2)+'\n');print(record['image'])

if __name__=='__main__':main()
