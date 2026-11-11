#!/usr/bin/env python3
"""Run the private room worker as a real process; optional exact Linux Docker image."""
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

def prepare(root):
    shutil.copytree(ROOT / 'logic', root / 'logic')
    for sub in ('rooms', 'shared'):
        shutil.copytree(ROOT / 'server' / sub, root / 'server' / sub, ignore=shutil.ignore_patterns('__pycache__', '*.py', '*.md'))
    for sub in ('items', 'camp', 'combat', 'loot', 'journeys', 'maps', 'cosmetics', 'skill_system', 'companions'):
        shutil.copytree(ROOT / 'data' / sub, root / 'data' / sub, ignore=shutil.ignore_patterns('*.import', '*.uid'))
    shutil.copytree(ROOT / 'runtime/netfox', root / 'runtime/netfox')
    shutil.copytree(ROOT / 'runtime/diagnostics', root / 'runtime/diagnostics')
    for addon in ('netfox','netfox.internals'):
        shutil.copytree(ROOT / 'addons' / addon, root / 'addons' / addon)
    runpy.run_path(str(ROOT / 'server/shared/godot_class_cache.py'))['prepare'](root)
    (root / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="zorx-room-worker"\n[autoload]\n'+''.join(name+'="*res://'+path+'"\n' for name,path in [('NetworkTime','addons/netfox/network-time.gd'),('NetworkTimeSynchronizer','addons/netfox/network-time-synchronizer.gd'),('NetworkRollback','addons/netfox/rollback/network-rollback.gd'),('NetworkEvents','addons/netfox/network-events.gd'),('NetworkPerformance','addons/netfox/network-performance.gd')])+'[netfox]\ntime/tickrate=60\ntime/max_ticks_per_frame=8\nevents/enabled=false\nrollback/history_limit=64\nrollback/input_redundancy=4\nrollback/display_offset=0\nrollback/enable_diff_states=false\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--image', help='Existing local linux/amd64 room worker image; no push')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='zorx-room-smoke-') as folder:
        root = Path(folder); prepare(root)
        token = secrets.token_urlsafe(32)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        env = dict(os.environ, ZORX_WORKER_TOKEN=token, ZORX_WORKER_PORT=str(port), ZORX_WORKER_BIND='127.0.0.1')
        container = None
        with (root / 'stdout').open('w') as out, (root / 'stderr').open('w') as err:
            if args.image:
                container = 'zorx-room-smoke-' + secrets.token_hex(4)
                secret = root / 'worker.env'; secret.write_text('ZORX_WORKER_TOKEN=' + token + '\n'); secret.chmod(0o600)
                cmd = ['docker', 'run', '--rm', '--name', container, '--platform', 'linux/amd64', '-p', '127.0.0.1::8051', '--env-file', str(secret), '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--tmpfs', '/tmp:uid=10001,gid=10001', args.image]
            else:
                cmd = [args.godot, '--headless', '--path', str(root), '--script', 'res://server/rooms/worker.gd']
            process = subprocess.Popen(cmd, env=env, stdout=out, stderr=err)
            try:
                if container:
                    port_deadline = time.monotonic() + 30
                    while time.monotonic() < port_deadline:
                        found = subprocess.run(['docker', 'inspect', container], capture_output=True, text=True)
                        if found.returncode == 0:
                            value = json.loads(found.stdout)[0]['NetworkSettings']['Ports'].get('8051/tcp')
                            if value: port = int(value[0]['HostPort']); break
                        time.sleep(.05)
                    else: raise RuntimeError('room container port mapping timeout')
                def call(payload=None, auth=True, path='/rooms', method='POST'):
                    headers = {'Content-Type': 'application/json'}
                    if auth: headers['Authorization'] = 'Bearer ' + token
                    request = urllib.request.Request('http://127.0.0.1:' + str(port) + path, data=json.dumps(payload).encode() if payload is not None else None, headers=headers, method=method)
                    try: response = urllib.request.urlopen(request, timeout=5)
                    except urllib.error.HTTPError as error: response = error
                    with response: return response.code, json.loads(response.read())
                ready_deadline = time.monotonic() + 60
                while time.monotonic() < ready_deadline:
                    if process.poll() is not None: raise RuntimeError('room worker exited before readiness')
                    try:
                        if call(path='/healthz', method='GET')[0] == 200: break
                    except OSError: pass
                    time.sleep(.05)
                else: raise RuntimeError('room worker readiness timeout')
                checks = []
                def check(label, condition):
                    checks.append(condition); print(('PASS ' if condition else 'FAIL ') + label, flush=True)
                    if not condition: raise AssertionError(label)
                check('private metrics rejects missing token', call({'v':1},auth=False,path='/metrics')[0] == 401)
                check('private metrics exposes bounded counters', call({'v':1},path='/metrics')[1].get('rooms') == 0)
                check('maintenance closes admissions', call({'v':1,'enabled':True},path='/maintenance')[1].get('maintenance') is True and call({'v':1,'op':'create','room':'room-blocked'},path='/rooms')[1].get('error') == 'maintenance')
                check('maintenance can reopen', call({'v':1,'enabled':False},path='/maintenance')[1].get('maintenance') is False)
                check('private room control rejects missing token', call({'v': 1, 'op': 'status', 'room': 'room-one'}, auth=False)[0] == 401)
                # Produce a genuine starter Profile using Godot, not a Python schema copy.
                factory = root / 'fixture.gd'
                factory.write_text('extends SceneTree\nfunc _initialize():\n\tvar rules=load("res://logic/item_rules_loader.gd").load_default()\n\tvar camp=load("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())\n\tvar rng=RandomNumberGenerator.new()\n\trng.seed=77\n\tvar p=load("res://logic/profile.gd").new_player(rules,camp,rng)\n\tFileAccess.open("res://profile.json",FileAccess.WRITE).store_string(JSON.stringify(p.to_dict()))\n\tquit()\n')
                # Host factory uses the same pinned Godot version for both native/Linux probes.
                result = subprocess.run([args.godot, '--headless', '--path', str(root), '--script', 'res://fixture.gd'], capture_output=True, timeout=30)
                if result.returncode or result.stderr: raise RuntimeError('profile fixture generation failed')
                profile = json.loads((root / 'profile.json').read_text())
                def create(room): return call({'v': 1, 'op': 'create', 'room': room, 'seed': '0123456789abcde', 'players': [{'id': 1, 'profile': profile}, {'id': 2, 'profile': profile}]})[1]
                check('real worker allocates two-player room', create('room-one').get('ok'))
                check('real worker allocates independent second room', create('room-two').get('ok'))
                check('duplicate control cannot replace room', create('room-one').get('error') == 'room_exists')
                time.sleep(.2)
                first = call({'v': 1, 'op': 'status', 'room': 'room-one'})[1]
                second = call({'v': 1, 'op': 'status', 'room': 'room-two'})[1]
                check('real server clock advances both room simulations', first.get('ok') and second.get('ok') and first['state']['tick'] >= 6 and second['state']['tick'] >= 6)
                check('control cannot inject client ticks', call({'v': 1, 'op': 'tick', 'room': 'room-one'})[1].get('error') == 'invalid_payload')
                check('closing room releases it', call({'v': 1, 'op': 'close', 'room': 'room-one'})[1].get('ok'))
                check('closing room leaves other room alive', call({'v': 1, 'op': 'status', 'room': 'room-two'})[1].get('ok'))
                check('closed room is unavailable', call({'v': 1, 'op': 'status', 'room': 'room-one'})[1].get('error') == 'room_not_found')
                print('PASS room process checks; no gameplay transport, image push or remote apply', flush=True)
            finally:
                if container:
                    subprocess.run(['docker', 'stop', container], capture_output=True, timeout=20)
                else: process.terminate()
                process.wait(timeout=30)
                if (root / 'stderr').stat().st_size:
                    # Preserve private logs without printing token-bearing process diagnostics.
                    logs = ROOT / 'build/room-smoke-private'; logs.mkdir(mode=0o700, exist_ok=True)
                    shutil.copy2(root / 'stderr', logs / 'stderr.log'); (logs / 'stderr.log').chmod(0o600)
                    raise RuntimeError('worker emitted stderr; private log retained')

if __name__ == '__main__': main()
