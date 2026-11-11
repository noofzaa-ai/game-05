#!/usr/bin/env python3
"""Run ON the k3s host. Retire v1 catalog spares using private Godot rules + storage CAS.
Default is dry-run. --apply requires zero rooms and enabled worker maintenance.
Credentials and profile data stay on the host; stdout contains aggregate counts only.
"""
import argparse
import base64
import copy
import datetime
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import uuid

NS = 'zorx-staging'

def kubectl(*args, data=None):
    return subprocess.run(['kubectl', '-n', NS, *args], input=data, capture_output=True,
                          text=True, check=True, timeout=45).stdout

def get(kind, name):
    return json.loads(kubectl('get', kind, name, '-o', 'json'))

def token(container):
    for entry in container.get('env', []):
        if entry['name'] not in ('ZORX_WORKER_TOKEN', 'ZORX_NAMES_TOKEN'): continue
        if 'value' in entry: return entry['value']
        ref = entry['valueFrom']['secretKeyRef']
        return base64.b64decode(get('secret', ref['name'])['data'][ref['key']]).decode()
    raise ValueError('Missing private worker credential')

def private(service, path, payload, credential):
    spec = get('service', service)['spec']
    port = next(p['port'] for p in spec['ports'] if p['port'] != 8060)
    request = urllib.request.Request('http://%s:%d%s' % (spec['clusterIP'], port, path),
        data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json',
                                                  'Authorization': 'Bearer ' + credential})
    with urllib.request.urlopen(request, timeout=15) as response: result = json.load(response)
    if not result.get('ok'): raise ValueError('Private worker rejected operation')
    return result

def sql(query):
    return kubectl('exec', '-i', 'postgres-0', '--', 'psql', '-X', '-qAt', '-U', 'postgres',
                   '-d', 'nakama', '-v', 'ON_ERROR_STOP=1', data=query)

def records():
    return json.loads(sql("SELECT COALESCE(json_agg(row_to_json(s)), '[]'::json) FROM storage s WHERE collection='zorx_profile_v1' AND key='camp';"))

def validate(before, result):
    after = result['profile']; original = before['profile']
    if after.get('beta_kit_version') != 2 or result['rng_state'] != before['rng_state']:
        raise ValueError('Migration version/RNG contract failed')
    removable = lambda item: item['id'] == 'beta-v1-' + item['item_id']
    expected = [item for item in original['stash']['items'] if not removable(item)]
    if after['stash']['items'] != expected: raise ValueError('Earned ownership contract failed')
    a = copy.deepcopy(after); b = copy.deepcopy(original)
    for p in (a, b):
        p.pop('beta_kit_version', None); p.pop('bonus_stash_slots', None)
        p['stash'].pop('items'); p['stash'].pop('capacity')
    if a != b: raise ValueError('Equipment/balance/appearance preservation failed')
    return len(original['stash']['items']) - len(expected)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--backup-dir', type=Path,
        default=Path('/home/wiyazard/deployment/game-test/zorx-staging/.backups'))
    args = parser.parse_args()
    containers = get('deployment', 'headless')['spec']['template']['spec']['containers']
    rooms = next(c for c in containers if c['name'] == 'rooms')
    profiles = next(c for c in containers if c['name'] == 'profiles')
    metrics = private('room-worker', '/metrics', {'v': 1}, token(rooms))
    if metrics['rooms'] or metrics['peers']: raise ValueError('Drain rooms before migration')
    if args.apply and not metrics.get('maintenance'): raise ValueError('Enable maintenance before applying')
    rows = records(); backup = None
    if args.apply:
        args.backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        args.backup_dir.chmod(0o700)
        backup = args.backup_dir / ('catalog-retirement-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:8] + '.json')
        with os.fdopen(os.open(backup, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), 'w') as f:
            json.dump(rows, f)
    report = {'mode': 'apply' if args.apply else 'dry-run', 'profiles': len(rows),
              'eligible': 0, 'migrated': 0, 'removed': 0, 'deferred_active': 0, 'conflicts': 0,
              'kept_equipped_grants': 0, 'kept_other_stash': 0}
    for row in rows:
        state = row['value']
        if isinstance(state, str): state = json.loads(state)
        if state['profile'].get('beta_kit_version') != 1: continue
        if state.get('active_room'):
            report['deferred_active'] += 1; continue
        result = private('name-validator', '/profile', {'v': 1, 'state': {
            'profile': state['profile'], 'rng_state': state['rng_state']},
            'seed': '00000000000004d', 'name': state['profile']['name'], 'command': None}, token(profiles))
        removed = validate(state, result)
        report['eligible'] += 1
        if args.apply:
            updated = copy.deepcopy(state); updated['profile'] = result['profile']; updated['revision'] += 1
            if updated['revision'] > 2147483646: raise ValueError('Profile revision exhausted')
            uid = str(uuid.UUID(row['user_id']))
            literal = json.dumps(updated, separators=(',', ':')).replace("'", "''")
            previous = row['version'].replace("'", "''")
            query = "SET standard_conforming_strings=on; UPDATE storage SET value='%s'::jsonb,version='%s',update_time=now() WHERE collection='zorx_profile_v1' AND key='camp' AND user_id='%s'::uuid AND version='%s' AND (value->'active_room' IS NULL OR value->'active_room'='null'::jsonb) RETURNING 1;" % (literal, uuid.uuid4().hex, uid, previous)
            if sql(query).strip() != '1':
                report['conflicts'] += 1; continue
            report['migrated'] += 1
        report['removed'] += removed
        report['kept_other_stash'] += len(result['profile']['stash']['items'])
        report['kept_equipped_grants'] += sum(i['id'] == 'beta-v1-' + i['item_id'] for i in result['profile']['loadout']['equipped'].values())
    if backup: report['backup'] = str(backup)
    print(json.dumps(report))
    if report['conflicts']: raise SystemExit(2)

if __name__ == '__main__':
    main()
