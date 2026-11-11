#!/usr/bin/env python3
"""Create NEW local 0600 Secret files. No kubectl, no printing values, no overwrites."""
import argparse
import json
import os
from pathlib import Path
import secrets


def config(password, host='postgres'):
    return {'name': 'nakama1', 'data_dir': '/nakama/data',
            'logger': {'level': 'INFO'},
            'database': {'address': ['nakama:%s@%s:5432/nakama' % (password, host)]},
            'socket': {'server_key': secrets.token_urlsafe(32)},
            'session': {'encryption_key': secrets.token_urlsafe(32), 'refresh_encryption_key': secrets.token_urlsafe(32),
                        'token_expiry_sec': 7200, 'refresh_token_expiry_sec': 604800},
            'runtime': {'http_key': secrets.token_urlsafe(32)},
            'console': {'address': '127.0.0.1', 'username': 'zorx-admin', 'password': secrets.token_urlsafe(32), 'signing_key': secrets.token_urlsafe(32)}}


def generate(environment):
    if environment not in ('staging', 'prod'):
        raise ValueError('environment must be staging or prod')
    namespace = 'zorx-' + environment
    password = secrets.token_urlsafe(32)
    def secret(name, data):
        return {'apiVersion': 'v1', 'kind': 'Secret', 'type': 'Opaque', 'metadata': {'name': name, 'namespace': namespace}, 'stringData': data}
    return [secret('postgres-auth', {'admin-password': secrets.token_urlsafe(32), 'app-password': password,
             'init.sql': "CREATE ROLE nakama LOGIN PASSWORD '%s';\nCREATE DATABASE nakama OWNER nakama;\n" % password}),
            secret('nakama-config', {'config.yml': json.dumps(config(password))})]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', choices=['staging', 'prod'], required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    # Refuse existing directory so a credential rotation cannot accidentally break a live PVC.
    args.output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
    for item in generate(args.environment):
        path = args.output_dir / (item['metadata']['name'] + '.json')
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as out:
            json.dump(item, out, indent=2)
    print('Created private Secret files in', args.output_dir)


if __name__ == '__main__':
    main()
