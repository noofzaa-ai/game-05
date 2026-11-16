"""Local ZORX online stack (Postgres + Nakama w/ current runtime + profile worker running natively).
Throwaway local-only keys. Never touches k3s. Writes build/localstack/state.json and data-free config for the game."""
import json, secrets, subprocess, sys, time, os, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parents[2] / 'build' / 'localstack'  # throwaway local keys + generated config (git-ignored)
HERE.mkdir(parents=True, exist_ok=True)
NET = 'zorx-local-net'
PG = 'zorx-local-pg'
NK = 'zorx-local-nk'
PG_IMAGE = 'postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24'
NK_IMAGE = '192.168.1.99:30500/zorx-nakama:chest-id-fix-20261101-2'
WORKER_PORT = 8051


def d(*a, data=None, check=True):
    return subprocess.run(['docker', *a], input=data, capture_output=True, check=check, timeout=180)


def main():
    state_path = HERE / 'state.json'
    if state_path.exists():
        st = json.loads(state_path.read_text())
    else:
        st = {'pg_admin': secrets.token_urlsafe(24), 'pg_app': secrets.token_urlsafe(24),
              'server_key': secrets.token_urlsafe(24), 'http_key': secrets.token_urlsafe(24),
              'worker_token': secrets.token_urlsafe(32), 'guest_secret': secrets.token_hex(32),
              'enc': secrets.token_urlsafe(32), 'renc': secrets.token_urlsafe(32), 'console': secrets.token_urlsafe(24), 'sign': secrets.token_urlsafe(24)}
        state_path.write_text(json.dumps(st))
    for c in (NK, PG):
        d('rm', '-f', c, check=False)
    d('network', 'create', NET, check=False)
    d('run', '-d', '--name', PG, '--network', NET, '--network-alias', 'postgres', '-e', 'POSTGRES_PASSWORD=' + st['pg_admin'], PG_IMAGE)
    for _ in range(120):
        if d('exec', PG, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', check=False).returncode == 0:
            break
        time.sleep(.5)
    time.sleep(1)
    d('exec', '-i', PG, 'psql', '-U', 'postgres', '-d', 'postgres',
      data=("CREATE ROLE nakama LOGIN PASSWORD '%s';\nCREATE DATABASE nakama OWNER nakama;\n" % st['pg_app']).encode(), check=False)
    cfg = {'name': 'nakama1', 'data_dir': '/nakama/data', 'logger': {'level': 'INFO'},
           'database': {'address': ['nakama:%s@postgres:5432/nakama' % st['pg_app']]},
           'socket': {'server_key': st['server_key']},
           'session': {'encryption_key': st['enc'], 'refresh_encryption_key': st['renc'], 'token_expiry_sec': 7200, 'refresh_token_expiry_sec': 604800},
           'runtime': {'http_key': st['http_key']},
           'console': {'address': '127.0.0.1', 'username': 'zorx-admin', 'password': st['console'], 'signing_key': st['sign']}}
    runtime = {'runtime': {'path': '/opt/zorx/modules', 'js_entrypoint': 'index.js', 'env': [
        'ZORX_NAMES_URL=http://name-validator:8051', 'ZORX_NAMES_TOKEN=' + st['worker_token'],
        'ZORX_RPC_BURST=1000', 'ZORX_RPC_REFILL=1000', 'ZORX_RPC_AUDIT_THRESHOLD=3', 'ZORX_ROOM_WS_URL=ws://127.0.0.1:8061']}}
    (HERE / 'nakama.yml').write_text(json.dumps(cfg))
    (HERE / 'runtime.yml').write_text(json.dumps(runtime))
    index = ROOT / 'build/names-runtime/index.js'
    mounts = ['-v', str(HERE / 'nakama.yml') + ':/run/nakama/config.yml:ro', '-v', str(HERE / 'runtime.yml') + ':/run/zorx-names/runtime.yml:ro',
              '-v', str(index) + ':/opt/zorx/modules/index.js:ro']
    host = ['--add-host', 'name-validator:host-gateway']
    d('run', '--rm', '--network', NET, *mounts, '--entrypoint', '/nakama/nakama', NK_IMAGE, 'migrate', 'up', '--config', '/run/nakama/config.yml')
    d('run', '-d', '--name', NK, '--network', NET, *host, '-p', '127.0.0.1:7350:7350', *mounts, NK_IMAGE)
    for _ in range(120):
        try:
            if urllib.request.urlopen('http://127.0.0.1:7350/healthcheck', timeout=2).status == 200:
                break
        except Exception:
            time.sleep(.5)
    else:
        print(d('logs', NK, check=False).stderr.decode()[-3000:]); sys.exit(1)
    print('nakama up on 127.0.0.1:7350')


if __name__ == '__main__':
    main()
