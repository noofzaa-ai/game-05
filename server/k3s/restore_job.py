#!/usr/bin/env python3
"""Render a restore drill Job into an existing restore_* database. Never applies it."""
import argparse
import json
import re
from render import render


def restore_job(environment, backup_image, key, database, job_name):
    if not re.fullmatch(r'restore_[a-z0-9_]+', database):
        raise ValueError('only existing scratch restore_* databases are allowed')
    if not key.startswith('zorx-' + environment + '/') or not key.endswith('.dump'):
        raise ValueError('backup key must belong to the selected environment')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,61}[a-z0-9]', job_name):
        raise ValueError('job name must be a 2–63 character DNS label')
    cron = next(doc for doc in render(environment, backup_image=backup_image)['items'] if doc['kind']=='CronJob')
    spec = cron['spec']['jobTemplate']['spec']
    spec['backoffLimit'] = 0
    spec['template']['spec']['containers'][0]['args'] = ['restore', '--key', key, '--target-db', database]
    return {'apiVersion': 'batch/v1', 'kind': 'Job', 'metadata': {'name': job_name, 'namespace': 'zorx-' + environment}, 'spec': spec}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', choices=['staging','prod'], required=True)
    parser.add_argument('--backup-image', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--database', required=True)
    parser.add_argument('--job-name', required=True)
    args = parser.parse_args()
    try: print(json.dumps(restore_job(**vars(args)), indent=2))
    except ValueError as exc: parser.error(str(exc))


if __name__ == '__main__': main()
