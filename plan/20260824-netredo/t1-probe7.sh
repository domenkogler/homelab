#!/bin/bash
set -uo pipefail
echo "=== opencloud opencloud.yaml (collab service cfg, keys redacted) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker exec opencloud sh -c 'cat /etc/opencloud/opencloud.yaml 2>/dev/null | grep -iE \"collaboration|wopi|onlyoffice|add.service|exclude\" | head -20 || echo no-config'" 2>/dev/null
echo "=== done ==="
