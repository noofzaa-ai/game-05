"""Put a local-stack account into a named game state (tools/localstack/fixtures/<name>.json) without playing to it.

  python tools/localstack/fixture.py apply USER_ID NAME     # deep-merge the fixture into that account's saved profile
  python tools/localstack/fixture.py show USER_ID           # print the account's tutorial / unlocks / squad / gold

LOCAL STACK ONLY (tools/localstack/up.py: container zorx-local-pg). It refuses any other database container, so it
can never touch staging or production. A fixture is a partial profile: dictionaries merge key by key, anything else
(lists, numbers, strings) replaces; "_remove": [keys] drops top-level profile keys; keys starting with "_" are notes.
"""
import json, subprocess, sys
from pathlib import Path

PG = 'zorx-local-pg'
FIXTURES = Path(__file__).resolve().parent / 'fixtures'
COLLECTION, KEY = 'zorx_profile_v1', 'camp'


def psql(sql):
    # The SQL goes in on stdin (a whole profile does not fit a Windows command line).
    out = subprocess.run(['docker', 'exec', '-i', PG, 'psql', '-U', 'postgres', '-d', 'nakama', '-At', '-v', 'ON_ERROR_STOP=1'],
                         input=sql.encode('utf-8'), capture_output=True, check=True, timeout=60)
    return out.stdout.decode('utf-8').strip()


def merge(base, patch):
    for k, v in patch.items():
        if k.startswith('_'):
            continue
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v)
        else:
            base[k] = v
    return base


def load_record(uid):
    raw = psql(f"select value from storage where collection='{COLLECTION}' and key='{KEY}' and user_id='{uid}'")
    if not raw:
        sys.exit('no saved profile for that user yet (sign in once first)')
    return json.loads(raw)


def main():
    names = subprocess.run(['docker', 'ps', '--format', '{{.Names}}'], capture_output=True, text=True).stdout.split()
    if PG not in names:
        sys.exit('local stack is not running (python tools/localstack/up.py)')
    cmd, uid = sys.argv[1], sys.argv[2]
    if len(uid) != 36 or any(c not in '0123456789abcdef-' for c in uid):
        sys.exit('bad user id')
    record = load_record(uid)
    if cmd == 'apply':
        fixture = json.loads((FIXTURES / (sys.argv[3] + '.json')).read_text(encoding='utf-8'))
        for key in fixture.get('_remove', []):
            record['profile'].pop(key, None)
        merge(record['profile'], fixture)
        record['revision'] = int(record.get('revision', 1)) + 1
        text = json.dumps(record, ensure_ascii=False)
        # version = md5 of the stored value, as Nakama writes it (optimistic writes compare it)
        psql(f"update storage set value = $json${text}$json$::jsonb, version = md5($json${text}$json$), update_time = now() "
             f"where collection='{COLLECTION}' and key='{KEY}' and user_id='{uid}'")
        print('applied', sys.argv[3])
    p = load_record(uid)['profile']
    print(json.dumps({'tutorial': p.get('tutorial'), 'unlocks': p.get('unlocks'), 'squad': p.get('card_deck', {}).get('squad'),
                      'gold': p.get('stash', {}).get('gold')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
