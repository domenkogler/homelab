#!/bin/bash
set -uo pipefail
echo "=== running processes in opencloud (non-grep, top) ==="
ssh -o BatchMode=yes ansible-admin@vps.kogler.si "sudo docker exec opencloud sh -c 'ps -e -o comm 2>/dev/null | sort | head -40'" 2>/dev/null
echo "=== done ==="
