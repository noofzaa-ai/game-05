#!/usr/bin/env bash
# Read-only: fetch one day's Lag reports (zorx_feedback_v1) and diagnostics
# (zorx_diagnostics_v1) from Nakama PostgreSQL into build/. Run on the Mac.
# Usage: bash tools/backend/fetch_reports.sh [YYYY-MM-DD]   (default: today, Bangkok)
# The client header changed with the Netfox migration: client/lag_report.gd now
# emits "[NETFOX ROOM REPORT v1]", older builds emitted "[LAG REPORT v1|v2]".
# Match every known header, otherwise current reports are silently dropped.
set -euo pipefail
cd "$(dirname "$0")/../.."
DAY="${1:-$(TZ=Asia/Bangkok date +%Y-%m-%d)}"
HOST="wiyazard@100.78.133.27"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=8)
[ -f /tmp/zorx-release-known-hosts ] && SSH_OPTS+=(-o UserKnownHostsFile=/tmp/zorx-release-known-hosts)
REMOTE="kubectl -n zorx-staging exec -i postgres-0 -c postgres -- sh -c 'exec psql -U \"\$POSTGRES_USER\" -d nakama -At -v ON_ERROR_STOP=1'"
SINCE="extract(epoch from timestamptz '${DAY} 00:00+07')*1000"
UNTIL="extract(epoch from timestamptz '${DAY} 00:00+07' + interval '1 day')*1000"
mkdir -p build

ssh "${SSH_OPTS[@]}" "$HOST" "$REMOTE" > "build/lag-reports-${DAY}.jsonl" <<SQL
BEGIN READ ONLY;
SELECT json_build_object(
  'at', to_char(to_timestamp((value->>'at')::bigint/1000) AT TIME ZONE 'Asia/Bangkok','YYYY-MM-DD HH24:MI:SS'),
  'name', value->>'name', 'platform', value->>'platform',
  'version', value->>'version', 'message', value->>'message')
FROM storage
WHERE collection='zorx_feedback_v1'
  AND (value->>'message' LIKE '[LAG REPORT%' OR value->>'message' LIKE '[NETFOX ROOM REPORT%')
  AND (value->>'at')::bigint >= ${SINCE} AND (value->>'at')::bigint < ${UNTIL}
ORDER BY (value->>'at')::bigint;
ROLLBACK;
SQL

ssh "${SSH_OPTS[@]}" "$HOST" "$REMOTE" > "build/diagnostics-${DAY}.jsonl" <<SQL
BEGIN READ ONLY;
SELECT value FROM storage
WHERE collection='zorx_diagnostics_v1'
  AND (value->>'at')::bigint >= ${SINCE} AND (value->>'at')::bigint < ${UNTIL}
ORDER BY (value->>'at')::bigint;
ROLLBACK;
SQL

echo "Lag reports : $(grep -c '^{' "build/lag-reports-${DAY}.jsonl" || true)  -> build/lag-reports-${DAY}.jsonl"
echo "Diagnostics : $(grep -c '^{' "build/diagnostics-${DAY}.jsonl" || true)  -> build/diagnostics-${DAY}.jsonl"
