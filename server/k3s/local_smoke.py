#!/usr/bin/env python3
"""Isolated Docker check, no kubectl. Local TLS/WSS, migrations, device auth, restart and DB restore."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent

def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

render = load('render')
prepare = load('prepare_secrets')
NGINX = 'nginx:1.28-alpine'  # test-only TLS terminator, not a production ingress decision


def docker(*args, data=None):
    return subprocess.run(['docker', *args], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=120).stdout


def wait_for(check, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return check()
        except (subprocess.CalledProcessError, OSError, ValueError):
            time.sleep(.5)
    raise TimeoutError('local container readiness deadline exceeded')


def main():
    name = 'zorx-m3-check-' + secrets.token_hex(4)
    network = name + '-net'
    pg, nk, proxy = name + '-pg', name + '-nk', name + '-tls'
    containers, volumes = [], []
    with tempfile.TemporaryDirectory(prefix=name) as temp:
        root = Path(temp)
        certificates = root/'certificates'
        certificates.mkdir(mode=0o700)
        private = prepare.generate('staging')
        auth = private[0]['stringData']
        config = json.loads(private[1]['stringData']['config.yml'])
        (root/'config.yml').write_text(json.dumps(config))
        (root/'init.sql').write_text(auth['init.sql'])
        (root/'postgres.env').write_text('POSTGRES_USER=postgres\nPOSTGRES_DB=postgres\nPOSTGRES_PASSWORD='+auth['admin-password']+'\nPGDATA=/var/lib/postgresql/data/pgdata\n')
        os.chmod(root/'postgres.env',0o600)
        for file in ('config.yml','init.sql'): os.chmod(root/file,0o444)
        try:
            docker('network','create',network)
            for suffix, uid in [('pgdata',70),('nkdata',10001)]:
                volume = name + '-' + suffix
                docker('volume','create',volume)
                volumes.append(volume)
                docker('run','--rm','--user','0','-v',volume+':/owned','--entrypoint','sh',render.POSTGRES_IMAGE,'-c','chown '+str(uid)+':'+str(uid)+' /owned && chmod 700 /owned')
            def start(container, *args):
                containers.append(container)
                docker('run','-d','--name',container,'--network',network,*args)
            start(pg,'--network-alias','postgres','--user','70:70','--cap-drop','ALL',
                  '--env-file',str(root/'postgres.env'),'-v',name+'-pgdata:/var/lib/postgresql/data',
                  '-v',str(root/'init.sql')+':/docker-entrypoint-initdb.d/01-nakama.sql:ro',render.POSTGRES_IMAGE)
            wait_for(lambda: docker('exec',pg,'pg_isready','-U','postgres','-d','postgres'))
            mount = str(root/'config.yml')+':/run/nakama/config.yml:ro'
            common = ['--user','10001:10001','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges',
                      '--tmpfs','/tmp:uid=10001,gid=10001','-v',mount,'-v',name+'-nkdata:/nakama/data']
            docker('run','--rm','--network',network,*common,'--entrypoint','/nakama/nakama',render.NAKAMA_IMAGE,
                   'migrate','up','--config','/run/nakama/config.yml')
            print('PASS pinned Nakama migration with non-root/read-only restrictions')
            start(nk,'--network-alias','nakama',*common,'--entrypoint','/nakama/nakama',render.NAKAMA_IMAGE,'--config','/run/nakama/config.yml')
            wait_for(lambda: docker('exec',nk,'/nakama/nakama','healthcheck'))
            print('PASS Nakama healthcheck')
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=localhost',
                '-addext','subjectAltName=DNS:localhost,IP:127.0.0.1','-keyout',str(certificates/'tls.key'),'-out',str(certificates/'tls.crt')],
                check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            os.chmod(certificates/'tls.key',0o600)
            (root/'nginx.conf').write_text('''events {}
http { access_log off; server { listen 8443 ssl;
 ssl_certificate /cert/tls.crt; ssl_certificate_key /cert/tls.key;
 location / { proxy_pass http://nakama:7350; proxy_http_version 1.1;
 proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";
 proxy_set_header Host $host; proxy_read_timeout 3600s; } } }
''')
            start(proxy,'-p','127.0.0.1::8443','-v',str(root/'nginx.conf')+':/etc/nginx/nginx.conf:ro',
                  '-v',str(certificates)+':/cert:ro',NGINX)
            port = int(json.loads(docker('inspect',proxy))[0]['NetworkSettings']['Ports']['8443/tcp'][0]['HostPort'])
            context = ssl.create_default_context(cafile=str(certificates/'tls.crt'))
            device = 'zorx-m3-local-' + name
            def authenticate():
                request = urllib.request.Request('https://localhost:%d/v2/account/authenticate/device?create=true'%port,
                    data=json.dumps({'id':device}).encode(),headers={'Content-Type':'application/json','Authorization':'Basic '+base64.b64encode((config['socket']['server_key']+':').encode()).decode()})
                with urllib.request.urlopen(request,context=context,timeout=5) as response: return json.load(response)
            def account_id(token):
                request = urllib.request.Request('https://localhost:%d/v2/account'%port, headers={'Authorization':'Bearer '+token})
                with urllib.request.urlopen(request,context=context,timeout=5) as response: return json.load(response)['user']['id']
            session = wait_for(authenticate)
            initial_user = account_id(session['token'])
            assert session['created'] is True
            print('PASS device authentication through verified local HTTPS')
            ws_key = base64.b64encode(os.urandom(16)).decode()
            path = '/ws?' + urllib.parse.urlencode({'token':session['token'],'status':'false','lang':'en'})
            with socket.create_connection(('127.0.0.1',port),timeout=10) as raw:
                with context.wrap_socket(raw,server_hostname='localhost') as connection:
                    connection.sendall(('GET '+path+' HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: '+ws_key+'\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
                    assert connection.recv(4096).startswith(b'HTTP/1.1 101 ')
            print('PASS authenticated WSS upgrade through local TLS proxy')
            archive = docker('exec',pg,'pg_dump','-U','nakama','-d','nakama','--format=custom','--no-owner')
            docker('exec',pg,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c','CREATE DATABASE restore_local OWNER nakama')
            docker('exec','-i',pg,'pg_restore','-U','nakama','-d','restore_local','--single-transaction','--exit-on-error','--no-owner',data=archive)
            original = docker('exec',pg,'psql','-U','nakama','-d','nakama','-Atc','SELECT count(*) FROM users')
            restored = docker('exec',pg,'psql','-U','nakama','-d','restore_local','-Atc','SELECT count(*) FROM users')
            assert int(original)>0 and original==restored
            print('PASS real Postgres custom dump/restore into scratch database with matching user count')
            docker('restart',pg)
            wait_for(lambda:docker('exec',pg,'pg_isready','-U','postgres','-d','postgres'))
            docker('restart',nk)
            wait_for(lambda:docker('exec',nk,'/nakama/nakama','healthcheck'))
            again = wait_for(authenticate)
            assert not again.get('created', False) and account_id(again['token']) == initial_user
            print('PASS account persists across Postgres/Nakama restarts')
            print('LOCAL M3 SMOKE: 6 checks passed; no cluster or external storage touched')
        finally:
            for container in reversed(containers):
                subprocess.run(['docker','rm','-f',container],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            for volume in volumes:
                subprocess.run(['docker','volume','rm',volume],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            subprocess.run(['docker','network','rm',network],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)


if __name__ == '__main__': main()
