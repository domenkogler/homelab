#!/bin/bash
set -uo pipefail
echo "=== collaboration service running inside opencloud? ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker exec opencloud sh -c 'collaboration --version 2>&1 | head -1' 2>&1 || echo 'no collaboration binary'" 2>/dev/null
echo "=== opencloud services via health/version ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker logs --since 1h opencloud 2>&1 | grep -iE 'collaboration|onlyoffice|error|fatal' | grep -viE 'grpc|osinfo|csp' | tail -8" 2>/dev/null
echo "=== csp.yaml mount present + frame-src office ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker inspect opencloud --format '{{json .Mounts}}' 2>/dev/null | grep -o 'csp[^\"]*'" 2>/dev/null
echo "=== done ==="
