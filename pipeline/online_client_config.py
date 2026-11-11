#!/usr/bin/env python3
"""Generate PUBLIC game settings from the private bundle; never copies backend secrets."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def public_config(documents, host, port=443, scheme='https'):
    secret = next(d for d in documents if d and d.get('kind') == 'Secret' and d.get('metadata', {}).get('name') == 'nakama-config')
    settings = json.loads(secret['stringData']['config.yml'])
    key = settings['socket']['server_key']
    if not isinstance(key, str) or not key or not re.fullmatch(r'[A-Za-z0-9.-]+', host) or not 1 <= port <= 65535 or scheme not in ('https', 'http'):
        raise ValueError('invalid public configuration')
    return dict(version=1, enabled=True, host=host, port=port, scheme=scheme, client_key=key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--secrets', type=Path, required=True)
    parser.add_argument('--host', default='zorxapi.daiyooo.com')
    parser.add_argument('--port', type=int, default=443)
    parser.add_argument('--scheme', choices=('https', 'http'), default='https')
    parser.add_argument('--output', type=Path, default=ROOT / 'data/online.local.json')
    args = parser.parse_args()
    try:
        import yaml
        config = public_config(list(yaml.safe_load_all(args.secrets.read_text())), args.host, args.port, args.scheme)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(config, indent=2) + '\n')
    except Exception as error:
        parser.exit(1, 'Configuration failed: ' + type(error).__name__ + ' (private details withheld)\n')
    print('Public connection settings generated; only socket application key is included. No credentials printed.')


if __name__ == '__main__':
    main()
