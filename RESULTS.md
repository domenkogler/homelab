BLOCKED: reasoning boot — profile reasoning crash-loops (restarts=105): vLLM api_server.py rejects --never-evict-kv-cache-prompt-includes --never-evict-kv-cache-max-fraction 0.25 in the reasoning cmd; those flags are fast-pool-only per §8; no re-converge per §7; going to §8 to restore fast.
# run 20261004-0804
runner=DomenP14s/external-model TS=20261004-0804
arm=fast n=1398 acc=89.63 % extraction_fail=0.86 %
