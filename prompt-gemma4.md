# Overnight unattended: Gemma 4 (laptop) benches spark `fast`, then `reasoning`

> **Role:** the entire prompt for one unattended overnight run (laptop driver → spark benches).
> **Linked from:** [`prompt-remaining-bench.md`](prompt-remaining-bench.md) §Runner seat.

Driver = you: laptop LM Studio Gemma 4 26B (`127.0.0.1:1234`) — never a bench target. Engine under test
= spark `https://llm.kogler.si/v1`, model `spark/qwen3.8-flash-next` (same id on every profile).
`fast` = live winner: ctx 262,144, seqs 8, KV 25 GB = 805,749 slots = 3.07× window. `reasoning` = AWQ
lane, seqs 4, 16 GB. Read nothing else; every command here is complete.

**Rules.** (1) Never stop, never ask: a leg you can't finish gets one line `BLOCKED: <why> — <log>` in
`RESULTS.md`, then the NEXT leg. (2) Max 2 retries per leg. (3) One leg at a time, never overlapping.
(4) Edit nothing but your evidence dir; no IaC, no constants, no ceilings, no restart, no reboot. FAIL
and BLOCKED are results. (5) Never write the bearer anywhere — only its length (32). (6) Order: verify →
MMLU@8 → gate4 → depth → fp8 → flip to `reasoning` + same suite + McNemar → converge back to `fast` →
commit. Budgets: 5m/5h/20m/45m/15m/3h/45m. Hit a budget → `pkill -f evaluate_from_apiX`, log
`BLOCKED: budget`, next leg (the eval resumes per category). The converge-back and the commit are never
skipped.

## 1. Setup

```bash
cd ~/source/homelab && git log --oneline -1
WT=../homelab-wt-$(date +%Y%m%d-%H%M); git worktree add "$WT" -b session/hd489-$(date +%H%M) && cd "$WT"
export TS=$(date +%Y%m%d-%H%M) EV=spark/reports/hd489-overnight-$TS URL=https://llm.kogler.si/v1
mkdir -p "$EV/raw"
export OPENAI_API_KEY="$(op item get spark-llm_api --vault Homelab-ansible --fields label=credential --reveal)"
[ -n "$OPENAI_API_KEY" ] || export OPENAI_API_KEY="$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.pi/agent/models.json')))['providers']['spark']['apiKey'])")"
echo "bearer len=${#OPENAI_API_KEY}"; curl -s -o /dev/null -w 'endpoint http=%{http_code}\n' -H "Authorization: Bearer $OPENAI_API_KEY" "$URL/models"
echo "runner=$(hostname)/${PI_MODEL:-lmstudio-gemma} TS=$TS" | tee "$EV/raw/seat.txt"
```
Worktree path exists → new `$(date +%H%M)`, never delete another session's. Need `200`: `401` → retry
once, else `BLOCKED: endpoint` and jump to §8.

## 2. Verify what is live (≤5 min, read-only — do NOT converge first, the model is already loaded)

```bash
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' /opt/spark-ai/docker-compose.yml" | tee "$EV/raw/live.txt"
ssh spark "docker inspect vllm-qwen-spark --format 'started={{.State.StartedAt}} restarts={{.RestartCount}}'" | tee -a "$EV/raw/live.txt"
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast health 2>&1 | tail -8 | tee "$EV/raw/health.log"
```
Want `25000000000` / `8` / `restarts=0` / green → go to §3. Wrong pool or seqs or `restarts>0` → the
premise is broken: converge (`nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark
--no-pull >/tmp/cg-$TS.log 2>&1 &`, `tail -25 /tmp/cg-$TS.log` every 5 min, ≤40 min), then re-check once.
`ssh spark` dead → `BLOCKED: spark leg`, run §3–§6 anyway (endpoint only), skip §6, note it first.

## 3. MMLU-Pro mini on `fast`, concurrency 8 (the priority; ≤5 h)

1,400 items (14×100, CoT). Per-category loop = a crash costs one category; re-running a category
resumes it. `-n 8` matches seqs 8 — never higher.

```bash
sha256sum /tmp/mmlu-pro-harness/mini_test.json | tee "$EV/raw/sha.txt"    # expect e67bad86a84e25bc90f475cd7fc004fa23fca2c562c8b7acc9b38fb07e6c0c4d
export OUT=~/mmlu-eval-fast-$TS && mkdir -p "$OUT"
for s in business law psychology biology chemistry history other health economics math physics "computer science" philosophy engineering; do
  echo "=== $s $(date -u +%FT%TZ)" >> "$EV/raw/mmlu-fast.log"
  MMLU_PRO_MINI=/tmp/mmlu-pro-harness/mini_test.json NO_COLOR=1 TERM=dumb \
    /tmp/mmlu-venv/bin/python /tmp/mmlu-pro-harness/evaluate_from_apiX.py --url "$URL" \
    -m spark/qwen3.8-flash-next -n 8 -a "$s" -o "$OUT" --retry 2 --retry_wrong 2 </dev/null >> "$EV/raw/mmlu-fast.log" 2>&1
done
```
No mini file / wrong sha / no venv → `BLOCKED: harness`, download nothing, next leg. At 30 min check
`items done:` below — under 60 → `pkill -f evaluate_from_apiX`, `BLOCKED: throughput`, next leg.

```bash
OUT="$OUT" python3 - <<'PY' | tee "$EV/raw/acc-fast.txt"
import glob,json,os; d=os.environ["OUT"]; c=w=null=tot=0
for f in glob.glob(d+"/*_summary.json"):
    t=json.load(open(f)).get("total",{}); c+=t.get("corr",0); w+=t.get("wrong",0)
for f in glob.glob(d+"/*_result.json"):
    for e in json.load(open(f)): tot+=1; null+= e.get("pred") is None
print(f"arm=fast n={tot} acc={c/max(1,c+w)*100:.2f} % extraction_fail={null/max(1,tot)*100:.2f} %")
print("items done:",tot)
PY
```
Record accuracy + extraction_fail + n beside: harness `MMLU-Pro @ f418b116`, `-n 8`, `--retry 2
--retry_wrong 2`.

## 4. Gate 4 — concurrency on `fast` (≤20 min)

```bash
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast concurrent 1 2>&1 | tee "$EV/raw/g4-solo.log" | tail -5
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast concurrent 8 2>&1 | tee "$EV/raw/g4-c8.log" | tail -5
```
PASS = `200s=8/8` and slowest ≤ 3× solo median. A 429/timeout is FAIL (a finding), not BLOCKED.

## 5. Depth (≤45 min)

```bash
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast ctx 163840 2>&1 | tee "$EV/raw/d163k.log" | tail -6
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast ctx 236000 2>&1 | tee "$EV/raw/d236k.log" | tail -6
```
PASS = HTTP 200 and `prompt_tokens ≥ 80 %` of the ask, both. 236k may preempt: record it, don't retry.

## 6. fp8 image probe (≤15 min, no GPU)

```bash
python3 scripts/spark-fp8-image-probe.py 2>&1 | tee "$EV/raw/fp8.log" | tail -20
```
Want a verdict + digest. `BLOCKED-ON-IMAGE` = the known answer. Refuses during a converge: wait 5 min
once, then cross.

## 7. Second arm: `reasoning` (≤3 h — all `fast` legs must be in)

Both quantisations were timed; no public suite ever ran on both. Flip, run the same items at ITS seqs,
then the paired test (unpaired diffs prove nothing here). `reasoning` is certified — no override.

```bash
N=$(python3 -c "import yaml;print(yaml.safe_load(open('IaC/ansible/group_vars/spark.yml'))['spark_llm_profiles']['reasoning']['max_num_seqs'])")
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull -e spark_llm_profile=reasoning >/tmp/cg-reasoning-$TS.log 2>&1 &
sleep 300; tail -20 /tmp/cg-reasoning-$TS.log          # every 5 min, ≤40 min (~20 min boot)
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile reasoning health 2>&1 | tail -6 | tee "$EV/raw/health-reasoning.log"
export OUT2=~/mmlu-eval-reasoning-$TS && mkdir -p "$OUT2"
for s in business law psychology biology chemistry history other health economics math physics "computer science" philosophy engineering; do
  MMLU_PRO_MINI=/tmp/mmlu-pro-harness/mini_test.json NO_COLOR=1 TERM=dumb \
    /tmp/mmlu-venv/bin/python /tmp/mmlu-pro-harness/evaluate_from_apiX.py --url "$URL" \
    -m spark/qwen3.8-flash-next -n "$N" -a "$s" -o "$OUT2" --retry 2 --retry_wrong 2 </dev/null >> "$EV/raw/mmlu-reasoning.log" 2>&1
done
```
Not healthy in 40 min → `BLOCKED: reasoning boot`, no re-converge, go to §8 (it restores `fast`).
Partial is fine: the test scores only what both arms have.

```bash
OUTA="$OUT" OUTB="$OUT2" python3 - <<'PY' | tee "$EV/raw/mcnemar.txt"
import glob,json,os; from math import comb
def load(d):
    m={}
    for f in glob.glob(d+"/*_result.json"):
        for e in json.load(open(f)):
            if e.get("pred") is not None: m[e["question_id"]]=(e["pred"]==e["answer"])
    return m
A,B=load(os.environ["OUTA"]),load(os.environ["OUTB"]); k=A.keys()&B.keys()
b=sum(1 for q in k if A[q] and not B[q]); c=sum(1 for q in k if B[q] and not A[q]); n=b+c
p=0.0 if n==0 else min(1.0,2*sum(comb(n,i) for i in range(min(b,c)+1))*0.5**n)
print(f"n_paired={len(k)} acc_fast={sum(A[q] for q in k)/max(1,len(k))*100:.2f} % acc_reasoning={sum(B[q] for q in k)/max(1,len(k))*100:.2f} % discordants b={b} c={c} p={p:.4g}")
print("rule (pre-registered): <=2 pts keep | 3-5 pts decide on the pi-harness tasks | >5 pts speed win void")
PY
```
Report `n_paired` FIRST; under ~300 paired items resolves nothing below ~20 points.

## 8. Converge back to `fast` — LAST (≤45 min), then commit

The box must end as the repo renders it (`fast`; this also installs the `--never-evict-*` pair). It
recreates the container: ~15–20 min boot.

```bash
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/cg-back-$TS.log 2>&1 &
sleep 300; tail -20 /tmp/cg-back-$TS.log          # every 5 min, ≤40 min
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' -e 'never-evict' /opt/spark-ai/docker-compose.yml" > "$EV/raw/live-after.txt"
ssh spark "docker logs vllm-qwen-spark --since 60m 2>&1 | grep -m2 -e 'GPU KV cache size' -e 'Initial free memory'" >> "$EV/raw/live-after.txt"
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast health 2>&1 | tail -6 | tee "$EV/raw/health-final.log"
{ echo "# run $TS"; cat "$EV/raw/seat.txt"; grep -h -e 'arm=' -e 'n_paired=' "$EV"/raw/acc-fast.txt "$EV"/raw/mcnemar.txt 2>/dev/null; } >> RESULTS.md
git add -A "$EV" RESULTS.md && git commit -s -m "test(spark-llm): HD-489 overnight run $TS — fast suite + reasoning arm + McNemar, box left on fast"
```
PASS = `failed=0`, `restarts=0`, KV line, health green, `25000000000`/`8`. Never leave it on
`reasoning`. An assert in the log → `BLOCKED: gate — <first line>`, change NOTHING. Not healthy 40 min
after a reboot → `BLOCKED: engine down` on the FIRST line of `RESULTS.md`, do not restart it. Do not
merge to `main`, do not remove the worktree — the parent merges. Then stop.

## 9. Never

bench `127.0.0.1:1234` or the laptop's 32k window · raise `spark_llm_pool_ceiling_bytes`,
`…_device_hold_ceiling_bytes`, `fixed_cost_bytes`, or `-n` above an arm's own `max_num_seqs` · run two
legs at once · converge before §3–§6 are done · use `spark.kogler.si/v1` (302 to `/`; if §1's check
fails, `ssh -N -f -L 8000:127.0.0.1:8000 spark` then `http://127.0.0.1:8000/v1` + `--token-env
OPENAI_API_KEY`) · run SWE-bench containers on spark · touch `spark_llm_profile` outside §7 · delete or
`git clean` anything you did not create.
