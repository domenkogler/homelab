#!/bin/bash
set -uo pipefail
echo "=== opencloud processes (collab service?) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker exec opencloud sh -c 'ps aux 2>/dev/null | grep -iE \"collab|onlyoffice|wopi\" | grep -v grep | head'" 2>/dev/null
echo "=== opencloud env for collaboration (full names+non-secret values) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker inspect opencloud --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^COLLABORATION_APP_(NAME|PRODUCT|ADDR|INSECURE|PROOF_DISABLE)|^COLLABORATION_WOPI_SRC|^COLLABORATION_STORE|^OC_ADD_RUN_SERVICES|^OC_EXCLUDE_RUN_SERVICES'" 2>/dev/null
echo "=== done ==="
