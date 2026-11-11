#!/bin/bash
# Temporary local-only API DNS override. Game assets remain on Cloudflare.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CERT="$TASK_ROOT/build/lan-api-test/zorxapi-lan-ca.crt"
LEGACY_CERT="$TASK_ROOT/build/lan-api-test/zorxapi-lan-legacy.crt"
MODE="${1:-enable}"
if [[ "$MODE" != enable && "$MODE" != disable ]]; then
  echo 'Usage: bash tools/net/lan_api_bypass.sh enable|disable'; exit 2
fi
if [[ ! -f "$CERT" ]]; then echo "Missing test certificate: $CERT"; exit 1; fi
if [[ "$MODE" == enable ]]; then
  openssl x509 -checkend 0 -noout -in "$CERT" >/dev/null
  echo 'Enable direct API/WSS to 192.168.1.99; trust this temporary DNS-constrained test CA for SSL zorxapi.daiyooo.com.'
  sudo -v
  if [[ -f "$LEGACY_CERT" ]]; then
    sudo /usr/bin/security remove-trusted-cert -d "$LEGACY_CERT" || true
  fi
  sudo /usr/bin/security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain "$CERT"
  sudo /usr/bin/python3 - <<'PY'
from pathlib import Path
import shutil,time
p=Path('/etc/hosts');s=p.read_text();host='zorxapi.daiyooo.com'
for line in s.splitlines():
    active=line.split('#',1)[0].split()
    if host in active[1:] and '# zorx-lan-api-test' not in line:
        raise SystemExit('An existing API hosts mapping exists; leave it unchanged and review it first.')
backup=Path('/etc/hosts.zorx-lan-api-backup-'+time.strftime('%Y%m%d-%H%M%S'))
shutil.copy2(p,backup)
s='\n'.join(line for line in s.splitlines() if '# zorx-lan-api-test' not in line)
p.write_text(s.rstrip()+'\n192.168.1.99 zorxapi.daiyooo.com # zorx-lan-api-test\n')
print('Hosts backup:',backup)
PY
else
  echo 'Restore Cloudflare API DNS and remove the temporary certificate trust.'
  sudo -v
  sudo /usr/bin/python3 - <<'PY'
from pathlib import Path
p=Path('/etc/hosts');s=p.read_text()
p.write_text('\n'.join(line for line in s.splitlines() if '# zorx-lan-api-test' not in line).rstrip()+'\n')
PY
  sudo /usr/bin/security remove-trusted-cert -d "$CERT" || true
  CERT_SHA1="$(openssl x509 -in "$CERT" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
  sudo /usr/bin/security delete-certificate -Z "$CERT_SHA1" /Library/Keychains/System.keychain || true
fi
sudo /usr/bin/dscacheutil -flushcache
sudo /usr/bin/killall -HUP mDNSResponder
if [[ "$MODE" == enable ]]; then
  curl --fail --silent --show-error --connect-timeout 5 --max-time 10 --cacert "$CERT" https://zorxapi.daiyooo.com/healthcheck
  echo
  echo 'Enabled. Fully quit and reopen the browser to close cached WSS/DNS connections.'
  echo 'In DevTools Network, the new API/WSS Remote Address must be 192.168.1.99:443.'
else
  echo 'Disabled. Fully quit and reopen the browser before the Cloudflare comparison.'
fi
