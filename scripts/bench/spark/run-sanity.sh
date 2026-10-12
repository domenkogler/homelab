#!/usr/bin/env bash
set -euo pipefail
cd /home/ansible-admin/bench
export PATH=/usr/bin:/bin:/usr/local/bin
echo "=== accuracy gate B1 ==="
bash accuracy-gate.sh B1
echo "=== C1 seed42 ==="
bash run-scenario.sh B1 C1 42
echo "=== C1 seed43 ==="
bash run-scenario.sh B1 C1 43
echo "=== C2 seed42 ==="
bash run-scenario.sh B1 C2 42
echo "=== C2 seed43 ==="
bash run-scenario.sh B1 C2 43
echo "=== C3 seed42 ==="
bash run-scenario.sh B1 C3 42
echo "=== C3 seed43 ==="
bash run-scenario.sh B1 C3 43
echo "=== C1 warm (seed42) ==="
bash run-scenario.sh B1 C1 42 --warm
echo "=== ALL DONE ==="