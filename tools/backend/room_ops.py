#!/usr/bin/env python3
"""Private room monitoring / admission switch. Never prints credentials or profile data."""
import argparse
import json
import os
from pathlib import Path
import time
import urllib.request

def call(url, payload, token=None, runtime_key=None):
    headers = {'Content-Type': 'application/json'}
    if token: headers['Authorization'] = 'Bearer ' + token
    if runtime_key:
        from urllib.parse import urlencode
        url += '?' + urlencode({'http_key': runtime_key})
    request = urllib.request.Request(url, data=json.dumps(json.dumps(payload) if runtime_key else payload).encode(), headers=headers)
    with urllib.request.urlopen(request, timeout=5) as response: value = json.load(response)
    if runtime_key and isinstance(value, dict) and isinstance(value.get('payload'), str): value = json.loads(value['payload'])
    if isinstance(value, str): value = json.loads(value)
    if not value.get('ok'): raise RuntimeError('private operation rejected: ' + str(value.get('error', 'unavailable')))
    return value

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['monitor', 'maintenance-on', 'maintenance-off'])
    parser.add_argument('--workers', nargs='+', required=True, help='Private control URLs, e.g. http://127.0.0.1:8051 after port-forward')
    parser.add_argument('--token-file', type=Path, required=True)
    parser.add_argument('--nakama-url', help='Required for maintenance: internal or external HTTPS API base')
    parser.add_argument('--http-key-file', type=Path)
    parser.add_argument('--samples', type=int, default=1)
    parser.add_argument('--interval', type=float, default=5)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 1 or args.interval < 1: parser.error('samples >=1, interval >=1 required')
    token = args.token_file.read_text().strip()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    failed = False
    with args.report.open('a') as report:
        if args.action != 'monitor':
            if not args.nakama_url or not args.http_key_file: parser.error('maintenance requires --nakama-url and --http-key-file')
            enabled = args.action == 'maintenance-on'
            # Close admissions first; let existing rooms settle without force-killing pods.
            call(args.nakama_url.rstrip('/') + '/v2/rpc/zorx_maintenance_admin_v1', {'v':1,'secret':token,'enabled':enabled}, runtime_key=args.http_key_file.read_text().strip())
            for worker in args.workers: call(worker.rstrip('/') + '/maintenance', {'v':1,'enabled':enabled}, token)
            print('Maintenance enabled' if enabled else 'Admissions reopened')
            return
        for index in range(args.samples):
            for number, worker in enumerate(args.workers):
                try:
                    metrics = call(worker.rstrip('/') + '/metrics', {'v':1}, token)
                    alert = metrics['tick_p95_ms'] > 16 or metrics['backlog_ms'] > 50 or any(item['reason'] in ['overload','lease_unavailable'] for item in metrics['closed'])
                    row = {'time':time.time(),'worker':number,'alert':alert,**metrics}
                except Exception:
                    row = {'time':time.time(),'worker':number,'alert':True,'error':'worker_unreachable'}
                failed |= row['alert']; report.write(json.dumps(row)+'\n'); report.flush()
                print(json.dumps(row))
            if index+1 < args.samples: time.sleep(args.interval)
    if failed: raise SystemExit(1)
if __name__ == '__main__': main()
