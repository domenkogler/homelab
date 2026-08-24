#!/bin/bash
set -uo pipefail
echo "=== onlyoffice internal health endpoints ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker exec onlyoffice-docs sh -c 'wget -q -T 6 -O- http://localhost/healthcheck 2>&1 | head -c 300; echo; wget -q -T 6 -O- http://localhost/ 2>&1 | head -c 100'" 2>/dev/null
echo
echo "=== onlyoffice-docs env (names only, no values) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker inspect onlyoffice-docs --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -iE 'JWT|SECRET' | sed 's/=.*/=<redacted>/' | head" 2>/dev/null
echo "=== opencloud traefik route status (public) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "curl -s -o /dev/null -w 'office.kogler.si -> %{http_code}\n' --max-time 8 https://office.kogler.si/healthcheck; curl -s -o /dev/null -w 'file.kogler.si -> %{http_code}\n' --max-time 8 https://file.kogler.si/" 2>/dev/null
echo "=== done ==="
