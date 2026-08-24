#!/bin/bash
set -uo pipefail
echo "=== opencloud service registry (collaboration?) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker exec opencloud sh -c 'opencloud --version 2>/dev/null | head -1; (wget -q -T 6 -O- http://localhost:9242/healthcheck 2>&1 | head -c 120) ; echo; (wget -q -T 6 -O- http://localhost:9120/healthcheck 2>&1 | head -c 120) 2>/dev/null || true'" 2>/dev/null
echo "=== try grpc registry port ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker port opencloud 2>/dev/null | head; echo '---'; sudo docker exec opencloud sh -c 'cat /etc/opencloud/gateway 2>/dev/null | head -1; ls /etc/opencloud/ 2>/dev/null | head'" 2>/dev/null
echo "=== done ==="
