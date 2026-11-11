#!/usr/bin/env bash
# Run on the k3s host. Read-only; never reads Secrets or player profiles.
set -euo pipefail
since="${1:-5m}"
if [[ ! "$since" =~ ^[0-9]+[smh]$ ]]; then
  echo 'Usage: bash diagnose_lag.sh [5m]' >&2; exit 2
fi
kubectl top node
kubectl top pods -n zorx-staging --containers
kubectl logs -n zorx-staging deployment/headless -c rooms --since="$since" --timestamps=true | python3 -c '
import json,sys
count=0
for line in sys.stdin:
    stamp,sep,payload=line.strip().partition(" ROOM_PERF=")
    if not sep: continue
    try: row=json.loads(payload)
    except ValueError: continue
    print(stamp+" "+json.dumps(row,ensure_ascii=True));count+=1
if not count: print("No ROOM_PERF samples in this interval (no active rooms, old worker image, or window too short).")
'
