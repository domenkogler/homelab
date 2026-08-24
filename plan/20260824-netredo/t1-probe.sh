#!/bin/bash
# READ-ONLY probe: ONLYOFFICE/OpenCloud collaboration (task 1)
set -uo pipefail
echo "=== containers ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker ps -a --filter name=opencloud --filter name=onlyoffice --format '{{.Names}} | {{.Status}}'" 2>/dev/null
echo "=== collab env (names only) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker inspect opencloud --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E 'COLLABORATION|OC_ADD_RUN_SERVICES|OC_EXCLUDE_RUN_SERVICES|PROXY_CSP' | sed 's/=.*/=<redacted>/'" 2>/dev/null
echo "=== onlyoffice healthcheck (internal) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker exec opencloud sh -c 'wget -q -T 8 -O- http://office.kogler.si/healthcheck 2>&1 | head -c 200' 2>&1 || echo '(no office.kogler.si from opencloud net)'" 2>/dev/null
echo "=== done ==="
