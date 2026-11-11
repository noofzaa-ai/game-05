#!/usr/bin/env python3
"""Postgres custom archive to private S3-compatible storage; restore only into restore_* DBs."""
import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile


def digest(path):
    result = hashlib.sha256()
    with open(path, 'rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def client():
    import boto3  # installed in the dedicated backup image, not required by manifest rendering
    endpoint = os.environ.get('S3_ENDPOINT_URL') or None
    if endpoint and not endpoint.startswith('https://') and os.environ.get('ALLOW_INSECURE_S3') != '1':
        raise ValueError('S3 endpoint requires HTTPS')
    return boto3.client('s3', endpoint_url=endpoint, region_name=os.environ.get('AWS_DEFAULT_REGION', 'us-east-1'))


def backup(s3, bucket, prefix, directory):
    if not re.fullmatch(r'zorx-(staging|prod)/', prefix):
        raise ValueError('BACKUP_PREFIX must isolate zorx-staging/ or zorx-prod/')
    archive = Path(directory) / 'database.dump'
    subprocess.run(['pg_dump', '--format=custom', '--no-owner', '--file', str(archive)], check=True)
    subprocess.run(['pg_restore', '--list', str(archive)], check=True, stdout=subprocess.DEVNULL)
    checksum = digest(archive)
    key = prefix + datetime.now(timezone.utc).strftime('%Y/%m/%d/%H%M%S-%f.dump')
    extra = {'Metadata': {'sha256': checksum}}
    if os.environ.get('S3_ENCRYPTION', 'AES256'):
        extra['ServerSideEncryption'] = os.environ.get('S3_ENCRYPTION', 'AES256')
    s3.upload_file(str(archive), bucket, key, ExtraArgs=extra)
    head = s3.head_object(Bucket=bucket, Key=key)
    if head['ContentLength'] != archive.stat().st_size or head.get('Metadata', {}).get('sha256') != checksum:
        raise RuntimeError('uploaded backup size/checksum metadata mismatch')
    print('Backup uploaded and metadata verified:', key, archive.stat().st_size, 'bytes')
    return key


def restore(s3, bucket, key, target, directory):
    if not re.fullmatch(r'restore_[a-z0-9_]+', target):
        raise ValueError('restore target must be an existing scratch database named restore_*')
    archive = Path(directory) / 'restore.dump'
    head = s3.head_object(Bucket=bucket, Key=key)
    expected = head.get('Metadata', {}).get('sha256', '')
    if not re.fullmatch(r'[a-f0-9]{64}', expected):
        raise ValueError('backup is missing SHA256 metadata')
    s3.download_file(bucket, key, str(archive))
    if archive.stat().st_size != head['ContentLength'] or digest(archive) != expected:
        raise ValueError('downloaded backup checksum mismatch')
    subprocess.run(['pg_restore', '--list', str(archive)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['pg_restore', '--dbname', target, '--single-transaction', '--exit-on-error',
                    '--no-owner', '--clean', '--if-exists', str(archive)], check=True)
    print('Restored verified backup into scratch database:', target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('backup')
    restoration = commands.add_parser('restore')
    restoration.add_argument('--key', required=True)
    restoration.add_argument('--target-db', required=True)
    args = parser.parse_args()
    bucket = os.environ['S3_BUCKET']
    with tempfile.TemporaryDirectory(prefix='zorx-backup-') as directory:
        if args.command == 'backup':
            backup(client(), bucket, os.environ['BACKUP_PREFIX'], directory)
        else:
            restore(client(), bucket, args.key, args.target_db, directory)


if __name__ == '__main__':
    main()
