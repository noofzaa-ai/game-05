#!/usr/bin/env python3
"""Real isolated Nakama/Postgres/Godot name RPC smoke. Never touches k3s."""
import base64
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'server/k3s' / (name + '.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


def docker(*args, data=None):
    return subprocess.run(['docker', *args], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=120).stdout


def wait(check, timeout=120):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = check()
            if result: return result
        except (OSError, ValueError, subprocess.CalledProcessError): pass
        time.sleep(.25)
    raise TimeoutError('local service readiness timeout')


def check(label, good):
    print(('PASS ' if good else 'FAIL ') + label, flush=True)
    if not good: raise AssertionError(label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--admin', action='store_true', help='Isolated admin RPC authorization, SQL, ban/unban and audit')
    parser.add_argument('--party', action='store_true', help='Four-client camp/Friends/ready/depart integration')
    parser.add_argument('--rooms', action='store_true', help='Also start the local room worker and run actual two-client SDK flow')
    parser.add_argument('--native-rooms', action='store_true', help='Use pinned host Godot for room authority, avoiding amd64 emulation stalls')
    parser.add_argument('--long-run', action='store_true', help='Full impaired Journey probe, up to20 minutes')
    args = parser.parse_args()
    if args.party and args.long_run: parser.error("--party and --long-run select different probes; run separately")
    if args.native_rooms or args.party: args.rooms = True
    renderer = module('render'); prepare = module('prepare_secrets')
    prefix = 'zorx-names-' + secrets.token_hex(4)
    created = []
    native_room = None
    network = prefix + '-net'
    with tempfile.TemporaryDirectory(prefix=prefix) as folder:
        root = Path(folder)
        password = secrets.token_urlsafe(32); admin = secrets.token_urlsafe(32); validator_token = secrets.token_urlsafe(32)
        base = prepare.config(password)
        (root / 'base.json').write_text(json.dumps(base))
        runtime = {'runtime': {'path': '/opt/zorx/modules', 'js_entrypoint': 'index.js', 'env': ['ZORX_NAMES_URL=http://name-validator:8051', 'ZORX_NAMES_TOKEN=' + validator_token, 'ZORX_RPC_BURST=1000', 'ZORX_RPC_REFILL=1000', 'ZORX_RPC_AUDIT_THRESHOLD=3']}}
        admin_token = secrets.token_urlsafe(32)
        if args.admin: runtime['runtime']['env'].extend(['ZORX_ADMIN_TOKEN='+admin_token, 'ZORX_ADMIN_EMAILS=["wanwit.phbn@gmail.com"]'])
        (root / 'runtime.json').write_text(json.dumps(runtime))
        (root / 'postgres.env').write_text('POSTGRES_PASSWORD=' + admin + '\n')
        (root / 'worker.env').write_text('ZORX_NAMES_TOKEN=' + validator_token + '\n')
        for file in ('postgres.env', 'worker.env'): (root / file).chmod(0o600)
        docker('network', 'create', network)
        try:
            def start(name, *args):
                created.append(name)
                docker('run', '-d', '--name', name, '--network', network, *args)
            pg = prefix + '-pg'; worker = prefix + '-worker'; nk = prefix + '-nk'
            start(pg, '--network-alias', 'postgres', '--env-file', str(root / 'postgres.env'), renderer.POSTGRES_IMAGE)
            wait(lambda: docker('exec', pg, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres'))
            docker('exec', '-i', pg, 'psql', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', data=("CREATE ROLE nakama LOGIN PASSWORD '%s';\nCREATE DATABASE nakama OWNER nakama;\n" % password).encode())
            common = ['--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--tmpfs', '/tmp:uid=10001,gid=10001']
            start(worker, '--platform', 'linux/amd64', '--network-alias', 'name-validator', '--env-file', str(root / 'worker.env'), *common, 'zorx-name-validator:m3-4-local')
            if args.rooms:
                room_env = root / 'room.env'
                room_env.write_text('ZORX_WORKER_TOKEN=' + validator_token + '\nZORX_ROOM_NAKAMA_URL=http://nakama:7350\nZORX_ROOM_HTTP_KEY=' + base['runtime']['http_key'] + '\n')
                room_env.chmod(0o600)
                room_worker = prefix + '-rooms'
                if args.native_rooms:
                    import socket
                    with socket.socket() as reserved:
                        reserved.bind(('127.0.0.1', 0)); room_port = reserved.getsockname()[1]
                else:
                    start(room_worker, '--platform', 'linux/amd64', '-p', '127.0.0.1::8060', '--env-file', str(room_env), *common, 'zorx-room-worker:m4-1-local')
                    room_port = int(json.loads(docker('inspect', room_worker))[0]['NetworkSettings']['Ports']['8060/tcp'][0]['HostPort'])
                runtime['runtime']['env'].append('ZORX_ROOM_WS_URL=ws://127.0.0.1:' + str(room_port))
                (root / 'runtime.json').write_text(json.dumps(runtime))
            mounts = ['-v', str(root / 'base.json') + ':/run/nakama/config.yml:ro', '-v', str(root / 'runtime.json') + ':/run/zorx-names/runtime.yml:ro']
            docker('run', '--rm', '--platform', 'linux/amd64', '--network', network, *common, *mounts, '--entrypoint', '/nakama/nakama', 'zorx-nakama:m3-4-local', 'migrate', 'up', '--config', '/run/nakama/config.yml')
            start(nk, '--network-alias', 'nakama', '--platform', 'linux/amd64', '-p', '127.0.0.1::7350', *common, *mounts, 'zorx-nakama:m3-4-local')
            port = int(json.loads(docker('inspect', nk))[0]['NetworkSettings']['Ports']['7350/tcp'][0]['HostPort'])
            api = 'http://127.0.0.1:' + str(port)
            if args.native_rooms:
                spec = importlib.util.spec_from_file_location('native_room_prepare', ROOT / 'server/rooms/smoke.py')
                packager = importlib.util.module_from_spec(spec); spec.loader.exec_module(packager)
                project = root / 'room-project'; project.mkdir(); packager.prepare(project)
                with socket.socket() as reserved:
                    reserved.bind(('127.0.0.1', 0)); control_port = reserved.getsockname()[1]
                native_env = dict(os.environ, ZORX_WORKER_TOKEN=validator_token, ZORX_WORKER_BIND='127.0.0.1',
                                  ZORX_WORKER_PORT=str(control_port), ZORX_ROOM_WS_PORT=str(room_port),
                                  ZORX_ROOM_NAKAMA_URL=api, ZORX_ROOM_HTTP_KEY=base['runtime']['http_key'])
                godot_native = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')
                with (root / 'room.stdout').open('w') as out, (root / 'room.stderr').open('w') as err:
                    native_room = subprocess.Popen([godot_native, '--headless', '--path', str(project), '--script', 'res://server/rooms/worker.gd'], env=native_env, stdout=out, stderr=err)
            def request(path, body=None, token=None, key=None, method=None):
                headers = {'Content-Type': 'application/json', 'User-Agent': 'zorx-name-smoke/1.0'}
                if token: headers['Authorization'] = 'Bearer ' + token
                if key: headers['Authorization'] = 'Basic ' + base64.b64encode((key + ':').encode()).decode()
                req = urllib.request.Request(api + path, headers=headers, data=json.dumps(body).encode() if body is not None else None, method=method)
                try: response = urllib.request.urlopen(req, timeout=15)
                except urllib.error.HTTPError as error: response = error
                with response: return response.code, json.loads(response.read())
            def runtime_ready():
                state = json.loads(docker('inspect', nk))[0]['State']
                if not state['Running']: raise RuntimeError('isolated Nakama exited before readiness; private logs retained')
                return request('/healthcheck')[0] == 200
            wait(runtime_ready)
            check('new Nakama image starts with second runtime config', True)
            def authenticate():
                code, value = request('/v2/account/authenticate/device?create=true', {'id': 'zorx-name-test-' + secrets.token_hex(16)}, key=base['socket']['server_key'])
                if code != 200: raise RuntimeError('local device auth failed')
                return value['token']
            a, b, c = authenticate(), authenticate(), authenticate()
            if args.admin:
                admin_target = authenticate()
                def uid(token): return json.loads(base64.urlsafe_b64decode(token.split('.')[1]+'=='))['uid']
                def admin_rpc(op, **extra):
                    payload=dict(secret=admin_token,actor=dict(email='wanwit.phbn@gmail.com',id=uid(a)),op=op,**extra)
                    code,value=request('/v2/rpc/zorx_admin_v1?http_key='+urllib.parse.quote(base['runtime']['http_key'],safe=''),json.dumps(payload))
                    if code!=200: raise RuntimeError('Admin isolated RPC HTTP '+str(code))
                    return json.loads(value['payload'])
                admin_status=admin_rpc('status'); print('Admin aggregate QA status',json.dumps(admin_status),flush=True)
                check('admin real SQL status count',int(admin_status.get('total',0))>=3)
                check('admin real users paginated query',len(admin_rpc('users').get('users',[]))>=3)
                code,_=request('/v2/rpc/zorx_admin_v1',json.dumps(dict(secret=admin_token,actor=dict(email='wanwit.phbn@gmail.com',id=uid(a)),op='status')),token=a)
                check('user bearer cannot call private admin',code in (401,403))
                check('admin bans isolated test account',admin_rpc('ban',target=uid(admin_target),reason='isolated QA suspend').get('ok'))
                check('real user list reports ban',any(x['id']==uid(admin_target) and x['banned'] for x in admin_rpc('users')['users']))
                check('admin unbans isolated test account',admin_rpc('unban',target=uid(admin_target),reason='isolated QA restore').get('ok'))
                check('admin audit persisted',len(admin_rpc('audit').get('events',[]))==2)

            ops_spec = importlib.util.spec_from_file_location('room_operations', ROOT / 'tools/backend/room_ops.py')
            ops = importlib.util.module_from_spec(ops_spec); ops_spec.loader.exec_module(ops)
            admin_url = api + '/v2/rpc/zorx_maintenance_admin_v1'
            switched = ops.call(admin_url, {'v':1,'secret':validator_token,'enabled':True}, runtime_key=base['runtime']['http_key'])
            code, status = request('/v2/rpc/zorx_online_status_v1', json.dumps({'v':1}), token=a)
            check('private admission switch and public maintenance status work on real Nakama', switched.get('maintenance') is True and code == 200 and json.loads(status['payload']).get('maintenance') is True)
            if args.rooms:
                code, closed = request('/v2/rpc/zorx_room_create_v1', json.dumps({'v':1,'capacity':1}), token=a)
                check('maintenance rejects new real room admission', code == 200 and json.loads(closed['payload']).get('error') == 'maintenance')
            check('private switch reopens admissions without restarting pods', ops.call(admin_url, {'v':1,'secret':validator_token,'enabled':False}, runtime_key=base['runtime']['http_key']).get('maintenance') is False)

            def rpc(token, name=None, get=False, extra=None):
                payload = {'v': 1} if get else {'v': 1, 'name': name}
                payload.update(extra or {})
                code, value = request('/v2/rpc/' + ('zorx_name_get_v1' if get else 'zorx_name_claim_v1'), json.dumps(payload, ensure_ascii=False), token=token)
                if code != 200: return {'ok': False, 'http_status': code}
                return json.loads(value['payload'])
            # Retry readiness while the separate validator process starts under emulation.
            wait(lambda: rpc(a, get=True).get('ok'))
            check('new account has no claimed character name', rpc(a, get=True).get('name') is None)
            wait(lambda: rpc(a, ' Hero ').get('ok'))
            check('shared Godot validation trims name', rpc(a, get=True).get('name') == 'Hero')
            check('case-only duplicate rejected for another account', rpc(b, 'hero').get('error') == 'name_taken')
            check('duplicate retry does not give loser a profile', rpc(b, get=True).get('name') is None)
            check('idempotent retry returns same name', rpc(a, 'Hero').get('ok'))
            check('Thai name accepted through Godot worker', rpc(b, 'หมาป่าแดง').get('ok'))
            check('invalid name rejected by original Profile rules', rpc(c, 'x').get('error') == 'too_short')
            check('spoofed user ID rejected', rpc(c, 'Spoof', extra={'user_id': 'forged'}).get('error') == 'invalid_payload')
            with ThreadPoolExecutor(max_workers=2) as executor:
                values = list(executor.map(lambda token: rpc(token, 'RaceName'), [a, c]))
            check('simultaneous duplicate claim has one winner', sum(bool(value.get('ok')) for value in values) == 1 and sum(value.get('error') == 'name_taken' for value in values) == 1)
            check('rename succeeds atomically', rpc(a, 'New Name').get('ok'))
            check('old name becomes available after rename', rpc(c, 'Hero').get('ok'))
            if args.admin:
                feedback_payload={'v':1,'request_id':secrets.token_hex(16),'message':'isolated feedback QA <script>plain text</script>','platform':'web','version':'qa-feedback'}
                def feedback_rpc(value):
                    code,result=request('/v2/rpc/zorx_feedback_v1',json.dumps(value),token=a)
                    if code!=200: raise RuntimeError('Feedback isolated HTTP '+str(code))
                    return json.loads(result['payload'])
                submitted=feedback_rpc(feedback_payload)
                check('feedback real authenticated write',submitted.get('ok'))
                check('feedback uncertain-response retry is idempotent',feedback_rpc(feedback_payload).get('id')==submitted.get('id'))
                check('feedback per-account quota enforced',feedback_rpc(dict(feedback_payload,request_id=secrets.token_hex(16))).get('error')=='rate_limited')
                feed=admin_rpc('feedback')
                check('admin real SQL feedback feed preserves text and identity',len(feed.get('feedback',[]))==1 and feed['feedback'][0]['message']==feedback_payload['message'] and feed['feedback'][0]['player_id']==uid(a))
                spoof=dict(feedback_payload,player_id=uid(b))
                check('feedback client identity injection rejected',feedback_rpc(spoof).get('error')=='invalid_payload')
                objects={'objects':[{'collection':'zorx_feedback_v1','key':'spoof','value':json.dumps({'message':'spoof'})}]}
                denied,_=request('/v2/storage',objects,token=a,method='PUT')
                check('feedback direct client storage write denied',denied in (400,401,403))

            code, _ = request('/v2/rpc/zorx_name_claim_v1?http_key=' + urllib.parse.quote(base['runtime']['http_key'], safe=''), json.dumps({'v': 1, 'name': 'Forged'}))
            check('server HTTP-key RPC without a user cannot impersonate a player', code in (401, 403))
            # API hooks protect new rows as well as existing authoritative records.
            body = {'objects': [{'collection': 'zorx_character_v1', 'key': 'display_name', 'value': json.dumps({'v': 1, 'name': 'Forged'})}]}
            new_token = authenticate()
            code, _ = request('/v2/storage', body, token=new_token, method='PUT')
            check('direct client cannot pre-create authoritative name record', code in (400, 401, 403))
            # Existing authoritative records are protected too.
            body = {'objects': [{'collection': 'zorx_character_v1', 'key': 'display_name', 'value': json.dumps({'v': 1, 'name': 'Forged'}), 'permission_read': 1, 'permission_write': 1}]}
            code, _ = request('/v2/storage', body, token=a, method='PUT')
            check('direct client storage write cannot bypass name validation', code in (400, 401, 403))
            check('direct write attempt preserves authoritative name', rpc(a, get=True).get('name') == 'New Name')
            code, _ = request('/v2/storage/delete', {'object_ids': [{'collection': 'zorx_character_v1', 'key': 'display_name'}]}, token=a, method='PUT')
            check('direct client cannot delete authoritative name', code in (400, 401, 403))
            sdk = ROOT / 'build' / (prefix + '-sdk'); sdk.mkdir(mode=0o700)
            config = sdk / 'config.json'
            config.write_text(json.dumps({'version': 1, 'enabled': True, 'host': '127.0.0.1', 'port': port, 'scheme': 'http', 'client_key': base['socket']['server_key']}))
            config.chmod(0o600)
            godot = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')
            with (sdk / 'stdout').open('w') as out, (sdk / 'stderr').open('w') as err:
                probe = subprocess.run([godot, '--headless', '--path', str(ROOT), '--script', 'res://tests/online_names_live_probe.gd', '--', '--config', str(config)], stdout=out, stderr=err, timeout=90)
            check('real Godot SDK completes name claim/read/duplicate flow', probe.returncode == 0 and 'NAME_SDK_FAILED=0' in (sdk / 'stdout').read_text() and (sdk / 'stderr').stat().st_size == 0)
            keyfile = root / 'client-key'; keyfile.write_text(base['socket']['server_key']); keyfile.chmod(0o600)
            remote_probe = subprocess.run([os.environ.get('PYTHON_BIN', 'python3'), str(ROOT / 'tools/backend/smoke.py'), 'internal', '--internal-url', api, '--key-file', str(keyfile), '--state', str(root / 'remote-state.json'), '--report', str(sdk / 'backend-report.json'), '--init', '--names', '--profiles'], capture_output=True, text=True, timeout=90)
            check('portable backend --names/--profiles diagnostics pass against real stack', remote_probe.returncode == 0)
            if args.rooms:
                room_config = sdk / 'rooms-config.json'
                room_config.write_text(json.dumps({'version': 1, 'enabled': True, 'host': '127.0.0.1', 'port': port, 'scheme': 'http', 'client_key': base['socket']['server_key'], 'fixture_seed': args.long_run}))
                room_config.chmod(0o600)
                with (sdk / 'rooms.stdout').open('w') as out, (sdk / 'rooms.stderr').open('w') as err:
                    command_args = [godot, '--headless', '--path', str(ROOT), '--script', 'res://tests/online_party_live_probe.gd' if args.party else 'res://tests/online_rooms_live_probe.gd', '--', '--config', str(room_config)]
                    if args.long_run: command_args.append('--long-run')
                    room_probe = subprocess.Popen(command_args, stdout=out, stderr=err)
                    try:
                        if args.long_run:
                            wait(lambda: Path(str(room_config) + '.room.json').exists() or room_probe.poll() is not None, timeout=90)
                            fixture = Path(str(room_config) + '.room.json')
                            if fixture.exists():
                                fixture.chmod(0o600)
                                info = json.loads(fixture.read_text())
                                if not __import__('re').fullmatch('[a-f0-9]{32}', info['room']): raise ValueError('unsafe fixture room id')
                                sql = "UPDATE storage SET value=jsonb_set(value,'{seed}','\"00000000000004d\"'::jsonb) WHERE collection='zorx_rooms_v1' AND key='%s';" % info['room']
                                docker('exec', '-i', pg, 'psql', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'nakama', data=sql.encode())
                                Path(str(room_config) + '.seeded').touch()
                        room_probe.wait(timeout=1260 if args.long_run else 180)
                    except Exception:
                        room_probe.kill(); room_probe.wait(); raise
                check('two real RemoteSessions complete admission, binary state, fencing, impairment and reconnect', room_probe.returncode == 0 and 'ROOM_SDK_FAILED=0' in (sdk / 'rooms.stdout').read_text() and (sdk / 'rooms.stderr').stat().st_size == 0)
            # Profile authority: actual Godot Commands.apply + Nakama private storage.
            def profile_rpc(token, payload=None):
                code, value = request('/v2/rpc/' + ('zorx_profile_get_v1' if payload is None else 'zorx_profile_command_v1'), json.dumps(payload or {'v': 1}), token=token)
                if code != 200: return {'ok': False, 'http_status': code}
                return json.loads(value['payload'])
            def command(revision, value, request_id=None):
                return {'v': 1, 'revision': revision, 'request_id': request_id or secrets.token_hex(16), 'command': value}
            before = profile_rpc(a)
            check('server creates real starter profile without local upload/test kit', before.get('ok') and before['revision'] == 1 and before['profile']['stash']['items'] == [] and before['profile']['name'] == 'New Name')
            check('private RNG/storage receipts absent from client snapshot', 'rng_state' not in before and 'receipts' not in before)
            other = profile_rpc(b)
            check('separate account starts with separate profile', other.get('ok') and other['profile']['name'] == 'หมาป่าแดง')
            cmd = command(1, {'type': 'unequip', 'slot': 'weapon', 'destination': 'stash'})
            after = profile_rpc(a, cmd)
            check('actual shared Commands moves starter weapon to stash', after.get('ok') and after['revision'] == 2 and len(after['profile']['stash']['items']) == 1)
            replay = profile_rpc(a, cmd)
            check('identical network retry is idempotent', replay.get('ok') and replay.get('replayed') and replay['revision'] == 2 and replay['profile'] == after['profile'])
            reused = dict(cmd, command={'type': 'repair_all'})
            check('same request ID cannot carry different command', profile_rpc(a, reused).get('error') == 'request_id_reused')
            check('stale revision cannot mutate profile', profile_rpc(a, command(1, {'type': 'repair_all'})).get('error') == 'revision_conflict')
            forged = dict(command(2, {'type': 'repair_all'}), profile={'gold': 999999}, user_id='forged')
            check('caller cannot inject state or identity', profile_rpc(a, forged).get('error') == 'invalid_payload')
            check('unowned item rejected by actual Godot rules', profile_rpc(a, command(2, {'type': 'discard', 'item': 'forged', 'source': 'stash'})).get('error') == 'item_not_owned')
            check('client cannot request journey rewards', profile_rpc(a, command(2, {'type': 'journey_finish'})).get('error') == 'not_available_here')
            check('profile command cannot bypass name reservation', profile_rpc(a, command(2, {'type': 'set_name', 'name': 'Forged'})).get('error') == 'name_rpc_required')
            check('rejected commands leave authoritative snapshot unchanged', profile_rpc(a)['profile'] == after['profile'] and profile_rpc(a)['revision'] == 2)
            # Two valid mutations at one revision must have only one committed winner.
            race_commands = [command(2, {'type': 'randomize_appearance'}), command(2, {'type': 'randomize_appearance'})]
            with ThreadPoolExecutor(max_workers=2) as executor:
                values = list(executor.map(lambda p: profile_rpc(a, p), race_commands))
            check('same-account command race has one CAS winner', sum(bool(v.get('ok')) for v in values) == 1 and sum(v.get('error') == 'revision_conflict' for v in values) == 1)
            saved = profile_rpc(a)
            check('second account inventory remains untouched', profile_rpc(b)['profile'] == other['profile'])
            for verb, route, body in [('PUT', '/v2/storage', {'objects': [{'collection': 'zorx_profile_v1', 'key': 'camp', 'value': json.dumps({'gold': 999999})}]}), ('PUT', '/v2/storage/delete', {'object_ids': [{'collection': 'zorx_profile_v1', 'key': 'camp'}]})]:
                code, _ = request(route, body, token=a, method=verb)
                check('direct profile storage write/delete blocked', code in (400, 401, 403))
            # Disposable database fixture: emulate a persisted v1 grant, never a public upload.
            cleanup_token = authenticate()
            cleanup_before = profile_rpc(cleanup_token)
            fixture = json.loads(json.dumps(cleanup_before['profile']))
            grant = json.loads(json.dumps(next(iter(fixture['loadout']['equipped'].values()))))
            grant['id'] = 'beta-v1-' + grant['item_id']
            earned = dict(grant, id='earned-cleanup-fixture')
            fixture['stash']['items'] = [grant, earned]
            fixture['beta_kit_version'] = 1; fixture['bonus_stash_slots'] = 1
            fixture['stash']['capacity'] += 1
            cleanup_uid = json.loads(base64.urlsafe_b64decode(cleanup_token.split('.')[1]+'=='))['uid']
            __import__('uuid').UUID(cleanup_uid)
            encoded = json.dumps(fixture).replace("'", "''")
            sql = "UPDATE storage SET value=jsonb_set(jsonb_set(value,'{profile}','%s'::jsonb),'{revision}','2'::jsonb),version=md5(value::text||clock_timestamp()::text) WHERE collection='zorx_profile_v1' AND key='camp' AND user_id='%s'::uuid;" % (encoded, cleanup_uid)
            docker('exec','-i',pg,'psql','-v','ON_ERROR_STOP=1','-U','postgres','-d','nakama',data=sql.encode())
            retired = profile_rpc(cleanup_token)
            check('real v1 cleanup persists v2 and removes only grant spares', retired.get('ok') and retired['revision']==3 and retired['profile']['beta_kit_version']==2 and [i['id'] for i in retired['profile']['stash']['items']]==['earned-cleanup-fixture'])
            check('real cleanup preserves equipped gear and balances', retired['profile']['loadout']==cleanup_before['profile']['loadout'] and retired['profile']['stash']['gold']==cleanup_before['profile']['stash']['gold'] and retired['profile']['stash']['materials']==cleanup_before['profile']['stash']['materials'])
            check('real cleanup is idempotent after fetch', profile_rpc(cleanup_token)['revision']==3)
            # Same linked identity/session from a new connection sees the same data.
            check('fresh client reads same authoritative state', profile_rpc(a)['profile'] == saved['profile'])
            docker('restart', nk)
            port = int(json.loads(docker('inspect', nk))[0]['NetworkSettings']['Ports']['7350/tcp'][0]['HostPort'])
            api = 'http://127.0.0.1:' + str(port)
            wait(lambda: request('/healthcheck')[0] == 200)
            check('name persists across Nakama restart', rpc(a, get=True).get('name') == 'New Name')
            check('profile persists across Nakama restart', profile_rpc(a)['profile'] == saved['profile'])
            docker('restart', pg)
            wait(lambda: docker('exec', pg, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres'))
            wait(lambda: rpc(a, get=True).get('name') == 'New Name')
            check('name persists across Postgres restart', True)
            check('profile persists across Postgres restart', profile_rpc(a)['profile'] == saved['profile'])
            docker('stop', worker)
            check('worker outage cannot commit profile command', profile_rpc(a, command(saved['revision'], {'type': 'randomize_appearance'})).get('error') == 'unavailable')
            check('worker outage preserves saved inventory', profile_rpc(a)['profile'] == saved['profile'])
            check('validator outage returns safe unavailable result', rpc(a, 'Another').get('error') == 'unavailable')
            check('validator outage does not mutate saved name', rpc(a, get=True).get('name') == 'New Name')
            # Reconfigure only the disposable runtime to a tiny, slow-refilling budget.
            runtime['runtime']['env'] = [entry for entry in runtime['runtime']['env'] if not entry.startswith(('ZORX_RPC_BURST=', 'ZORX_RPC_REFILL='))] + ['ZORX_RPC_BURST=3', 'ZORX_RPC_REFILL=0.01']
            (root / 'runtime.json').write_text(json.dumps(runtime))
            docker('restart', nk)
            port = int(json.loads(docker('inspect', nk))[0]['NetworkSettings']['Ports']['7350/tcp'][0]['HostPort'])
            api = 'http://127.0.0.1:' + str(port)
            wait(lambda: request('/healthcheck')[0] == 200)
            rate_user = authenticate()
            limited = [rpc(rate_user, get=True) for _ in range(9)]
            check('real gateway allows burst then rejects excess before handler', sum(bool(v.get('ok')) for v in limited) == 3 and sum(v.get('error') == 'rate_limited' for v in limited) == 6)
            check('rate budget is isolated per authenticated account', rpc(authenticate(), get=True).get('ok'))
            body = {'objects': [{'collection': 'zorx_rpc_budget_v1', 'key': 'shared', 'value': json.dumps({'tokens': 999999})}]}
            code, _ = request('/v2/storage', body, token=rate_user, method='PUT')
            check('client cannot refill its own quota storage', code in (400, 401, 403))
            lines = [line for line in docker('logs', nk).decode(errors='replace').splitlines() if 'zorx rpc rejected actor=' in line]
            check('repeated rejected requests produce redacted audit logs', bool(lines) and all(__import__('re').fullmatch(r'zorx rpc rejected actor=[a-f0-9]{12} rpc=zorx_[a-z0-9_]+ reason=[a-z_]{1,40} count=[0-9]+', json.loads(line).get('msg', '')) for line in lines))
            docker('restart', nk)
            port = int(json.loads(docker('inspect', nk))[0]['NetworkSettings']['Ports']['7350/tcp'][0]['HostPort'])
            api = 'http://127.0.0.1:' + str(port)
            wait(lambda: request('/healthcheck')[0] == 200)
            check('Nakama restart does not reset exhausted account budget', rpc(rate_user, get=True).get('error') == 'rate_limited')
            print('PASS real local stack; no live k3s changes; credentials withheld', flush=True)
        except Exception:
            logs = ROOT / 'build/names-smoke-private'; logs.mkdir(mode=0o700, parents=True, exist_ok=True)
            logs.chmod(0o700)
            for name in created:
                try:
                    path = logs / (name + '.log'); path.write_bytes(docker('logs', name)); path.chmod(0o600)
                except Exception: pass
            print('Private container logs retained under ignored build/names-smoke-private; values not printed', flush=True)
            raise
        finally:
            if native_room is not None:
                native_room.terminate()
                try: native_room.wait(timeout=5)
                except subprocess.TimeoutExpired: native_room.kill(); native_room.wait()
                target = ROOT / 'build/names-smoke-private'; target.mkdir(mode=0o700, parents=True, exist_ok=True)
                for suffix in ('stdout', 'stderr'):
                    source = root / ('room.' + suffix)
                    if source.exists():
                        destination = target / (prefix + '-native-room.' + suffix)
                        destination.write_bytes(source.read_bytes()); destination.chmod(0o600)
            for name in reversed(created):
                try: docker('rm', '-fv', name)
                except subprocess.CalledProcessError: pass
            docker('network', 'rm', network)


if __name__ == '__main__':
    main()
