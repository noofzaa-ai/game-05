#!/usr/bin/env python3
"""Nakama transport/auth diagnostics. Reports never contain response bodies or tokens."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
UA = 'zorx-backend-smoke/1.0'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward credentials to another location.


def valid_url(value):
    p = urllib.parse.urlsplit(value)
    if p.scheme not in ('http', 'https') or not p.hostname or p.username or p.password or p.query or p.fragment or p.path not in ('', '/'):
        raise argparse.ArgumentTypeError('Use an HTTP(S) origin without credentials, path or query')
    return value.rstrip('/')


def cors_origin(headers, origin):
    return headers.get('Access-Control-Allow-Origin', '') in ('*', origin)


def cors_preflight(headers, origin):
    allowed = {v.strip().lower() for v in headers.get('Access-Control-Allow-Headers', '').split(',')}
    # POST is safelisted. Authorization is a non-wildcard request header.
    return cors_origin(headers, origin) and 'authorization' in allowed and ('content-type' in allowed or '*' in allowed)


def private_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(state, stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('route', choices=('internal', 'external', 'both'), nargs='?', default='both')
    parser.add_argument('--health-only', action='store_true', help='Health + CORS only; no credentials needed')
    parser.add_argument('--profiles', action='store_true', help='After deploying M3-4: load the isolated account profile and verify rejected mutations')
    parser.add_argument('--names', action='store_true', help='After deploying M3-3: verify name RPCs using the isolated smoke account')
    parser.add_argument('--init', action='store_true', help='Create ONE smoke account only when state does not exist')
    parser.add_argument('--internal-url', type=valid_url, default='http://100.78.133.27:30350')
    parser.add_argument('--external-url', type=valid_url, default='https://api-game-test.daiyooo.com')
    parser.add_argument('--origin', type=valid_url, default='https://game-test.daiyooo.com')
    parser.add_argument('--state', type=Path, default=ROOT / 'build/k3s-remote/smoke-state.json')
    parser.add_argument('--secrets', type=Path, help='Private complete deployment YAML (requires PyYAML)')
    parser.add_argument('--key-file', type=Path, help='File containing only Nakama server_key; or use NAKAMA_SERVER_KEY env')
    parser.add_argument('--report', type=Path, default=ROOT / 'build/backend-smoke/report.json')
    parser.add_argument('--timeout', type=float, default=10)
    args = parser.parse_args()
    if (args.names or args.profiles) and args.health_only:
        parser.error('--names/--profiles requires authenticated mode')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    try:
        import certifi
        tls = ssl.create_default_context(cafile=certifi.where())
        if not args.health_only:
            import websocket
        key = os.environ.get('NAKAMA_SERVER_KEY', '')
        if not args.health_only:
            if args.key_file:
                key = args.key_file.read_text().strip()
            if args.secrets:
                import yaml
                doc = next(d for d in yaml.safe_load_all(args.secrets.read_text()) if d and d.get('kind') == 'Secret' and d.get('metadata', {}).get('name') == 'nakama-config')
                key = json.loads(doc['stringData']['config.yml'])['socket']['server_key']
            if not key:
                parser.error('Provide --key-file, --secrets or NAKAMA_SERVER_KEY')
            state = json.loads(args.state.read_text()) if args.state.exists() else None
            if state is not None:
                if not state.get('device') or not state.get('uid'):
                    raise ValueError('invalid state')
                if args.state.stat().st_mode & 0o077:
                    raise ValueError('state permissions must be 600')
            elif not args.init:
                parser.error('State missing: run once with --init, then verify without --init')
    except Exception as error:
        print('SETUP FAIL:', type(error).__name__, '(details withheld; check dependencies, private input and chmod 600)')
        return 2
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=tls))
    results = []

    def record(route, name, status, detail=''):
        results.append(dict(route=route, check=name, status=status, detail=detail))
        print(f'{status:4} [{route}] {name}' + (f' ({detail})' if detail else ''), flush=True)

    def request(api, path, payload=None, token=None, app_key=None, method=None, extra=None):
        headers = {'User-Agent': UA, 'Origin': args.origin}
        if payload is not None:
            headers['Content-Type'] = 'application/json'
        if token:
            headers['Authorization'] = 'Bearer ' + token
        if app_key is not None:
            headers['Authorization'] = 'Basic ' + base64.b64encode((app_key + ':').encode()).decode()
        headers.update(extra or {})
        req = urllib.request.Request(api + path, data=json.dumps(payload).encode() if payload is not None else None, headers=headers, method=method)
        try:
            response = opener.open(req, timeout=args.timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            raw = response.read(1024 * 1024)
            try:
                data = json.loads(raw)
            except (ValueError, UnicodeDecodeError):
                data = None
            return response.code, data, response.headers

    routes = [('internal', args.internal_url), ('external', args.external_url)]
    for route, api in routes:
        if args.route not in (route, 'both'):
            continue
        print(f'\n{route}: {api}', flush=True)
        def check(name, fn):
            try:
                good = fn()
                record(route, name, 'PASS' if good else 'FAIL')
                return bool(good)
            except Exception as error:
                record(route, name, 'FAIL', type(error).__name__ + '; inspect DNS/Tailscale/TLS/Tunnel/pod logs')
                return False
        def health():
            code, data, _ = request(api, '/healthcheck')
            record(route, 'health HTTP status', 'PASS' if code == 200 else 'FAIL', str(code))
            return code == 200 and isinstance(data, dict)
        healthy = check('health JSON / TLS verification', health)
        def cors():
            code, _, headers = request(api, '/v2/account/authenticate/device?create=false', method='OPTIONS', extra={'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization,content-type'})
            return code in (200, 204) and cors_preflight(headers, args.origin)
        check('CORS login preflight', cors)
        if args.health_only:
            continue
        if not healthy:
            record(route, 'authenticated checks', 'SKIP', 'health failed; credentials not sent')
            continue
        def login(device, create=False, app_key=key):
            return request(api, '/v2/account/authenticate/device?create=' + str(create).lower(), {'id': device}, app_key=app_key)
        session = {}
        def authenticate():
            nonlocal state, session
            device = state['device'] if state else 'zorx-k3s-smoke-' + secrets.token_hex(12)
            code, data, headers = login(device, state is None)
            record(route, 'login HTTP status', 'PASS' if code == 200 else 'FAIL', str(code))
            if code != 200 or not isinstance(data, dict) or not data.get('token') or not cors_origin(headers, args.origin):
                return False
            code, account, headers = request(api, '/v2/account', token=data['token'])
            record(route, 'account HTTP status', 'PASS' if code == 200 else 'FAIL', str(code))
            uid = account.get('user', {}).get('id') if isinstance(account, dict) else None
            if code != 200 or not uid or not cors_origin(headers, args.origin):
                return False
            if state:
                if data.get('created', False) or uid != state['uid']:
                    return False
            else:
                state = {'device': device, 'uid': uid}
                private_state(args.state, state)
            session = data
            return True
        if not check('login / same persisted account / response CORS', authenticate):
            record(route, 'remaining auth + WS checks', 'SKIP', 'valid login failed')
            continue
        def relogin():
            code, data, _ = login(state['device'])
            if code != 200 or not isinstance(data, dict) or data.get('created', False):
                return False
            code, account, _ = request(api, '/v2/account', token=data['token'])
            return code == 200 and account.get('user', {}).get('id') == state['uid']
        check('repeat login without account recreation', relogin)
        def rejected(path, **kwargs):
            code, data, _ = request(api, path, **kwargs)
            return code in (401, 403) and isinstance(data, dict)
        check('invalid session rejected by API', lambda: rejected('/v2/account', token='invalid-smoke-token'))
        check('invalid application key rejected by API', lambda: rejected('/v2/account/authenticate/device?create=false', payload={'id': state['device']}, app_key='invalid-smoke-key'))
        if args.names:
            def name_rpc(kind, payload):
                code, data, _ = request(api, '/v2/rpc/zorx_name_' + kind + '_v1', json.dumps(payload), token=session['token'])
                if code != 200 or not isinstance(data, dict):
                    return {}
                try:
                    result = json.loads(data.get('payload', ''))
                except (ValueError, TypeError):
                    return {}
                return result if isinstance(result, dict) else {}
            named = name_rpc('get', {'v': 1})
            def claim_smoke_name():
                if named.get('v') != 1 or not named.get('ok'):
                    return False
                wanted = named.get('name') or ('QA_' + hashlib.sha256(state['device'].encode()).hexdigest()[:10])
                claimed = name_rpc('claim', {'v': 1, 'name': wanted})
                reread = name_rpc('get', {'v': 1})
                return claimed.get('ok') is True and claimed.get('name') == wanted and reread.get('name') == wanted
            check('name RPC claim/read with same isolated smoke account', claim_smoke_name)
            check('name RPC rejects invalid name', lambda: name_rpc('claim', {'v': 1, 'name': 'x'}).get('error') == 'too_short')
            check('name RPC rejects forged identity payload', lambda: name_rpc('claim', {'v': 1, 'name': 'QA_Test', 'user_id': 'forged'}).get('error') == 'invalid_payload')
        if args.profiles:
            def profile_rpc(payload, command=False):
                code, data, _ = request(api, '/v2/rpc/zorx_profile_' + ('command' if command else 'get') + '_v1', json.dumps(payload), token=session['token'])
                if code != 200 or not isinstance(data, dict): return {}
                try: value = json.loads(data.get('payload', ''))
                except (ValueError, TypeError): return {}
                return value if isinstance(value, dict) else {}
            snapshot = profile_rpc({'v': 1})
            check('profile RPC loads authoritative isolated account', lambda: snapshot.get('ok') is True and isinstance(snapshot.get('profile'), dict) and isinstance(snapshot.get('revision'), int) and snapshot['revision'] >= 1)
            bad = {'v': 1, 'revision': snapshot.get('revision', 1), 'request_id': secrets.token_hex(16), 'command': {'type': 'repair_all'}, 'profile': {'gold': '999999999'}}
            check('profile RPC rejects client snapshot injection', lambda: profile_rpc(bad, True).get('error') == 'invalid_payload')
            denied = {'v': 1, 'revision': snapshot.get('revision', 1), 'request_id': secrets.token_hex(16), 'command': {'type': 'journey_finish'}}
            check('profile RPC rejects client reward settlement', lambda: profile_rpc(denied, True).get('error') == 'not_available_here')
            check('rejected profile commands preserve saved state', lambda: profile_rpc({'v': 1}) == snapshot)
        ws_api = ('wss' if api.startswith('https:') else 'ws') + api[api.index(':'):]
        def connect(token):
            url = ws_api + '/ws?' + urllib.parse.urlencode({'token': token, 'status': 'false', 'lang': 'en'})
            return websocket.create_connection(url, timeout=args.timeout, origin=args.origin, header=['User-Agent: ' + UA], redirect_limit=0, sslopt={'cert_reqs': ssl.CERT_REQUIRED, 'ca_certs': certifi.where(), 'check_hostname': True})
        def ws_ping():
            connection = connect(session['token'])
            try:
                marker = b'zorx-k3s-smoke'
                connection.ping(marker)
                deadline = time.monotonic() + args.timeout
                while time.monotonic() < deadline:
                    connection.settimeout(max(.01, deadline - time.monotonic()))
                    opcode, data = connection.recv_data(control_frame=True)
                    if opcode == websocket.ABNF.OPCODE_PONG and data == marker:
                        return True
                return False
            finally:
                connection.close()
        if check('authenticated WS upgrade + ping/pong', ws_ping):
            def ws_negative():
                try:
                    connection = connect('invalid-smoke-token')
                    connection.close()
                    return False
                except websocket.WebSocketBadStatusException as error:
                    return error.status_code in (400, 401, 403)
            check('invalid WS token rejected', ws_negative)
        else:
            record(route, 'invalid WS token rejected', 'SKIP', 'positive WS failed')
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({'checks': results}, indent=2) + '\n')
    counts = {s: sum(r['status'] == s for r in results) for s in ('PASS', 'FAIL', 'SKIP')}
    print('\nSUMMARY:', counts, '\nReport:', args.report)
    return 1 if counts['FAIL'] or counts['SKIP'] else 0


if __name__ == '__main__':
    sys.exit(main())
