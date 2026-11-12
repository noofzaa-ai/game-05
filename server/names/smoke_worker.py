#!/usr/bin/env python3
"""Run the actual standalone Godot validator over loopback; never prints credentials."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import runpy
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def prepare(destination):
    shutil.copytree(ROOT / 'logic', destination / 'logic')
    folder = destination / 'server/names'
    folder.mkdir(parents=True)
    shutil.copytree(ROOT / 'server/profile', destination / 'server/profile')
    shutil.copytree(ROOT / 'server/shared', destination / 'server/shared')
    for sub in ('items', 'camp', 'cosmetics'):
        shutil.copytree(ROOT / 'data' / sub, destination / 'data' / sub, ignore=shutil.ignore_patterns('*.import', '*.uid'))
    for name in ('name_rules.gd', 'worker.gd'):
        shutil.copy2(ROOT / 'server/names' / name, folder / name)
    runpy.run_path(str(ROOT / 'server/shared/godot_class_cache.py'))['prepare'](destination)
    (destination / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="zorx-name-validator"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='zorx-name-worker-') as folder:
        root = Path(folder)
        prepare(root)
        token = secrets.token_urlsafe(32)
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
        env = dict(os.environ, ZORX_NAMES_TOKEN=token, ZORX_NAMES_PORT=str(port), ZORX_NAMES_BIND='127.0.0.1')
        with (root / 'stdout').open('w') as out, (root / 'stderr').open('w') as err:
            process = subprocess.Popen([args.godot, '--headless', '--path', str(root), '--script', 'res://server/names/worker.gd'], env=env, stdout=out, stderr=err)
            try:
                def request(payload=None, auth=True, path='/validate-name', method='POST', raw=None):
                    body = raw if raw is not None else json.dumps(payload, ensure_ascii=False).encode() if payload is not None else None
                    headers = {'Content-Type': 'application/json'}
                    if auth: headers['Authorization'] = 'Bearer ' + token
                    req = urllib.request.Request(f'http://127.0.0.1:{port}' + path, data=body, headers=headers, method=method)
                    try: response = urllib.request.urlopen(req, timeout=5)
                    except urllib.error.HTTPError as error: response = error
                    with response: return response.code, json.loads(response.read())
                for _ in range(100):
                    if process.poll() is not None: raise RuntimeError('worker exited before readiness')
                    try:
                        if request(path='/healthz', method='GET')[0] == 200: break
                    except OSError: pass
                    time.sleep(.05)
                else: raise RuntimeError('readiness timeout')
                checks = [
                    ('unauthorized caller rejected', request({'v': 1, 'name': 'Hero'}, auth=False)[0] == 401),
                    ('existing shared name rule and trim', request({'v': 1, 'name': ' Hero '})[1] == {'v': 1, 'ok': True, 'name': 'Hero', 'canonical': 'hero'}),
                    ('Thai name accepted', request({'v': 1, 'name': 'หมาป่าแดง'})[1]['ok']),
                    ('too-short name rejected', request({'v': 1, 'name': 'x'})[1].get('error') == 'too_short'),
                    ('forged identity rejected', request({'v': 1, 'name': 'Hero', 'user_id': 'forged'})[1].get('error') == 'invalid_payload'),
                    ('invalid JSON rejected', request(raw=b'{broken')[0] == 400),
                    ('oversize payload rejected', request(raw=b'x' * 524289)[0] == 413),
                    ('unknown route rejected', request(path='/other')[0] == 404),
                ]
                with socket.create_connection(('127.0.0.1', port), timeout=5) as s:
                    s.sendall(('POST /validate-name HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 2\r\nAuthorization: Bearer ' + token + '\r\n\r\n{}').encode())
                    checks.append(('ambiguous duplicate headers rejected', s.recv(4096).startswith(b'HTTP/1.1 400')))
                for label, good in checks: print(('PASS ' if good else 'FAIL ') + label)
                if not all(good for _, good in checks): raise RuntimeError('worker checks failed')
            finally:
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
        assert not (root / 'stderr').read_text(), 'Godot stderr must be empty'
        assert token not in (root / 'stdout').read_text(), 'credentials must never be logged'
        print('PASS standalone worker: 9 HTTP checks; stderr empty; credentials withheld')


if __name__ == '__main__':
    main()
