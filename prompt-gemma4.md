# Overnight, unattended: laptop Gemma 4 drives the spark `fast` benches

> **Role:** the whole prompt for ONE unattended overnight run. The driver is the laptop's local
> **Gemma 4 26B A4B (LM Studio, `http://127.0.0.1:1234/v1`)**; the engine under test is **spark**
> (`https://llm.kogler.si/v1`, profile `fast`). Nothing here needs any other file read first.
> **Linked from:** [`prompt-remaining-bench.md`](prompt-remaining-bench.md) §Runner seat.

---

## 0. The six rules (read once, obey all night)

1. **Never stop, never ask.** You are unattended. If a leg cannot be completed, append one line to
   `RESULTS.md` — `BLOCKED: <why> — <log path>` — and **start the next leg**. No question, no wait.
2. **Retry a leg at most twice.** Third failure = `BLOCKED`, move on.
3. **One leg at a time.** Never overlap legs (a leg's numbers are only valid on an idle engine).
4. **Change nothing except your evidence dir.** No IaC edits, no profile flip, no constant, no
   ceiling, no `docker restart`, no reboot. A `FAIL`/`BLOCKED` **is** a result — record and cross.
5. **Never paste a secret into a file, a log or a commit.** The bearer is read at runtime (§1.3) and
   only its length may be printed.
6. **Order is fixed:** Leg 0 converge → **Leg 1 MMLU @ conc 8** → Leg 2 → Leg 3 → Leg 4 → Leg 5 finish.
   Never start Leg 1 before Leg 0 says the engine is healthy (a converge mid-eval kills the requests).

Time budget: 0 ≤ 40 min · 1 ≤ 6 h · 2 ≤ 20 min · 3 ≤ 45 min · 4 ≤ 15 min. If Leg 1 is still running at
the end of its budget, stop it (`pkill -f evaluate_from_apiX`) — it **resumes** next time — and cross
to Leg 2.

---

## 1. Config of record + setup (do it in this order)

| thing | value |
|---|---|
| profile under test | `fast` (certified winner, ex-`ar-blk`) |
| container / model id | `vllm-qwen-spark` · `spark/qwen3.8-flash-next` |
| engine window / seqs | 262,144 tok · `max_num_seqs: 8` |
| KV pool | 25,000,000,000 B = **805,749 slots = 3.07 ×** window |
| endpoint | `https://llm.kogler.si/v1` (401 without key, 200 with) |
| driver model | laptop LM Studio Gemma 4 26B, ctx 32,768 — **never a bench target** (Rule 0 clean: the driver's model is not the engine under test) |

### 1.1 Worktree (CONVENTIONS §6 — never edit in the main checkout)

```bash
cd ~/source/homelab && git fetch -q origin 2>/dev/null; git log --oneline -1
WT=../homelab-wt-$(date +%Y%m%d-%H%M)
git worktree add "$WT" -b session/hd489-overnight-$(date +%H%M) && cd "$WT"
git status --short          # must be empty
```
If `git worktree add` says the path exists: **do not delete anything** — use a new `$(date +%H%M)`.

### 1.2 Legs run from the repo, so make sure the winner's config is what you think it is

```bash
grep -n "spark_llm_profile:" IaC/ansible/host_vars/spark.kogler.si.yml   # expect: spark_llm_profile: fast
python3 scripts/spark-llm-probe.py profile fast 2>&1 | tail -25          # local leg: repo only, no key, no network
```

### 1.3 The bearer (runtime only, never written down)

```bash
export TS=$(date +%Y%m%d-%H%M)
export EV=spark/reports/hd489-overnight-$TS URL=https://llm.kogler.si/v1
mkdir -p "$EV/raw"
export OPENAI_API_KEY="$(op item get spark-llm_api --vault Homelab-ansible --fields label=credential --reveal)"
# fallback if op is unavailable (same 32-char value, already on this laptop):
[ -n "$OPENAI_API_KEY" ] || export OPENAI_API_KEY="$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.pi/agent/models.json')))['providers']['spark']['apiKey'])")"
echo "bearer len=${#OPENAI_API_KEY} (value not printed)"          # expect 32
curl -s -o /dev/null -w 'endpoint http=%{http_code}\n' -H "Authorization: Bearer $OPENAI_API_KEY" "$URL/models"
echo "runner=$(hostname)/${PI_MODEL:-lmstudio-gemma-26b}  engine=spark/fast  TS=$TS" | tee "$EV/raw/seat.txt"
```
`endpoint http=200` required before any leg. `401` → one retry of §1.3, then `BLOCKED: endpoint` and
**skip to Leg 5** (nothing can be measured).

---

## 2. Leg 0 — the spark converge (FIRST; ≤ 40 min)

Purpose: land whatever the repo says onto the box, so tonight's numbers belong to the config we ship.
If nothing changed, Ansible re-renders and does **not** reboot the engine — that is the expected green.
**Tonight it will reboot**: `fast` gained the `--never-evict-kv-cache-*` arguments, so the compose
changes and the container is recreated (~15–20 min boot: 549 s weights, the KV line at ~+10 min). Wait
for it; Leg 1 must not start against a half-booted engine.

```bash
# 0.1 read-only: what the box serves now vs what the repo renders
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' /opt/spark-ai/docker-compose.yml" | tee "$EV/raw/leg0-live-before.txt"
# 0.2 converge DETACHED — never in a foreground shell (HD-370: a killed converge leaves siblings Exited)
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull > "/tmp/hd489-converge-$TS.log" 2>&1 &
sleep 300; tail -25 "/tmp/hd489-converge-$TS.log"          # repeat the tail every 5 min, cap 40 min
```

When the log ends (`failed=0` expected), verify what is actually serving:

```bash
ssh spark "docker inspect vllm-qwen-spark --format '{{.State.StartedAt}} restarts={{.RestartCount}}'"
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' /opt/spark-ai/docker-compose.yml" | tee "$EV/raw/leg0-live-after.txt"
ssh spark "docker logs vllm-qwen-spark --since 60m 2>&1 | grep -m3 -e 'GPU KV cache size' -e 'Initial free memory'"
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast health 2>&1 | tail -12 | tee "$EV/raw/leg0-health.log"
```

**Acceptance:** log `failed=0`, `restarts=0`, KV line present, health green, and the rendered pool =
`25000000000` / seqs `8`. → `PASS` (+ the `GPU KV cache size` number).

**Cross rules:**
* the playbook fails on an **assert** (pool ceiling, host floor, uncertified, artifact staging) →
  `BLOCKED: gate — <the assert's fail_msg first line>` from the log, change NOTHING, Leg 1 on the live engine;
* the playbook fails because the **tree is dirty / no upstream** → `BLOCKED: tree`, re-check §1.1 once, else continue;
* a reboot did happen and the engine is not healthy after 40 min → `BLOCKED: engine down`, **do not
  restart it**, still run Leg 1 (it will `BLOCKED` fast) then Leg 2–4, then finish — the log is the finding.

---

## 3. Leg 1 — MMLU-Pro mini, **concurrency 8** (the priority; ≤ 6 h)

1,400 items = 14 categories × 100, CoT mandatory, machine-scored. Per-category loop = a crash costs one
category, and **re-running a category resumes it** (already-scored `question_id`s are skipped).

```bash
test -f /tmp/mmlu-pro-harness/mini_test.json && sha256sum /tmp/mmlu-pro-harness/mini_test.json | tee "$EV/raw/leg1-mini-sha.txt"
# expected e67bad86a84e25bc90f475cd7fc004fa23fca2c562c8b7acc9b38fb07e6c0c4d
# missing / wrong sha / no venv  -> BLOCKED: harness — do NOT download anything overnight -> Leg 2

export OUT=~/mmlu-eval-fast-$TS && mkdir -p "$OUT"
# Side-witness, free while 1,400 real items run: the engine's OWN prefix-cache counters. The KV pin
# only helps if it ENGAGES, and the two earlier pin arms proved only that a SYNTHETIC prompt never
# engages it (spark/reports/hd489-u4-pin, hd489-v16b-pin). This is the delta of real traffic.
ssh spark "curl -sf localhost:8000/metrics" | grep -E '^vllm:prefix_cache_(hits|queries)_total' > "$EV/raw/leg1-metrics-before.txt"
for s in business law psychology biology chemistry history other health economics math physics "computer science" philosophy engineering; do
  echo "=== $s $(date -u +%FT%TZ)" >> "$EV/raw/leg1.log"
  MMLU_PRO_MINI=/tmp/mmlu-pro-harness/mini_test.json NO_COLOR=1 TERM=dumb \
    /tmp/mmlu-venv/bin/python /tmp/mmlu-pro-harness/evaluate_from_apiX.py \
      --url "$URL" -m spark/qwen3.8-flash-next -n 8 -a "$s" -o "$OUT" \
      --retry 2 --retry_wrong 2 </dev/null >> "$EV/raw/leg1.log" 2>&1
  python3 -c "import json,sys;print('$s items='+str(len(json.load(open(sys.argv[1])))))" "$OUT/${s}_result.json" >> "$EV/raw/leg1.log" 2>&1 || echo "BLOCKED: $s" >> RESULTS.md
done
ssh spark "curl -sf localhost:8000/metrics" | grep -E '^vllm:prefix_cache_(hits|queries)_total' > "$EV/raw/leg1-metrics-after.txt"
python3 - "$EV/raw/leg1-metrics-before.txt" "$EV/raw/leg1-metrics-after.txt" <<'PY' | tee -a "$EV/raw/leg1-accuracy.txt"
import sys
rd = lambda p: {l.split()[0].split('{')[0].split('}')[0]: float(l.split()[-1]) for l in open(p) if l.startswith('vllm:')}
b, a = rd(sys.argv[1]), rd(sys.argv[2])
dq = a.get('vllm:prefix_cache_queries_total', 0) - b.get('vllm:prefix_cache_queries_total', 0)
dh = a.get('vllm:prefix_cache_hits_total', 0) - b.get('vllm:prefix_cache_hits_total', 0)
print(f"prefix_cache delta over Leg 1: queries={dq:.0f} hits={dh:.0f} "
      f"hit_rate={(dh/dq*100 if dq else 0):.2f} % — the never-evict/prefix witness: 0 hits across "
      f"1,400 real requests IS the finding (the pin does not engage), not a failure")
PY
```

Throughput check at the 30-min mark (one item ≈ 800 output tokens at ~40 tok/s ⇒ **expect ≥ 2 items/min**):

```bash
python3 - <<'PY'
import glob,json,os
n=sum(len(json.load(open(f))) for f in glob.glob(os.path.expanduser(os.environ["OUT"]+"/*_result.json")))
print("items done:",n)
PY
```
Under 60 items after 30 min ⇒ `BLOCKED: throughput (<n> items/30min)`, `pkill -f evaluate_from_apiX`, Leg 2.
`-n 8` is the whole point (it matches `max_num_seqs=8`); **never** raise it — 8 streams already fit the
pool 100k tokens each.

**Score it** (the harness' own `compute_accuracy.py` wants a dir of `*_result.json` only and
random-guesses unparsed answers — use the summaries, and report the extraction-failure rate):

```bash
OUT="$OUT" python3 - <<'PY' | tee "$EV/raw/leg1-accuracy.txt"
import glob,json,os
d=os.environ["OUT"]; c=w=null=tot=0
for f in sorted(glob.glob(d+"/*_summary.json")):
    t=json.load(open(f)).get("total",{}); c+=t.get("corr",0); w+=t.get("wrong",0)
for f in sorted(glob.glob(d+"/*_result.json")):
    for e in json.load(open(f)):
        tot+=1; null+= 1 if e.get("pred") is None else 0
print(f"items={tot} correct={c} wrong={w} acc={c/max(1,c+w)*100:.2f} %  extraction_fail={null}/{tot} ({null/max(1,tot)*100:.2f} %)")
PY
```
**Acceptance:** `acc=%` + `extraction_fail` + `n`, and the mini sha. Record the pins beside it: harness
`TIGER-AI-Lab/MMLU-Pro @ f418b116`, engine `fast`, `-n 8`, `--retry 2 --retry_wrong 2`, `--client` seat
from `raw/seat.txt`.

---

## 4. Leg 2 — gate 4: concurrency 8 on `fast` (≤ 20 min)

The old B2 evidence is a `seqs=4` box; the winner now batches 8, so gate 4 must be re-proven at 8.

```bash
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast concurrent 1 2>&1 | tee "$EV/raw/leg2-solo.log" | tail -6
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast concurrent 8 2>&1 | tee "$EV/raw/leg2-c8.log" | tail -6
```
**Acceptance:** `200s=8/8` and the `max` latency ≤ 3 × the solo median (`PASS / FAIL` with the three
numbers). Any `429`/timeout ⇒ `FAIL`, not `BLOCKED` — that is a finding about the config, keep it.

---

## 5. Leg 3 — depth at the real workload (≤ 45 min)

```bash
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast ctx 163840 2>&1 | tee "$EV/raw/leg3-p50.log" | tail -8
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast ctx 236000 2>&1 | tee "$EV/raw/leg3-p95.log" | tail -8
```
**Acceptance:** HTTP 200 and `prompt_tokens ≥ 80 %` of the ask, on both. 236k may legitimately preempt —
record `preempt` if the probe prints it; do not retry a preemption.

---

## 6. Leg 4 — fp8 KV re-probe on the pinned image (≤ 15 min, no GPU)

```bash
python3 scripts/spark-fp8-image-probe.py 2>&1 | tee "$EV/raw/leg4-fp8.log" | tail -25
```
**Acceptance:** it prints a verdict (`REACHABLE` / `BLOCKED-ON-IMAGE` / `UNDECIDED`) with the digest.
`BLOCKED-ON-IMAGE` is the known answer (B6, 2026-10-03) — a `REACHABLE` here is news worth a line.
It refuses to run while a converge is in progress: if that is why it failed, wait 5 min, once, then cross.

---

## 7. Leg 5 — finish (≤ 10 min)

`RESULTS.md`, one line per leg, `PASS|FAIL|BLOCKED` + the number + the path. No prose, no diagnosis —
then the machine-readable tail, so the morning reader never has to open a log to see the shape:

```bash
{ echo "# Overnight run $TS"; echo "seat: $(cat "$EV/raw/seat.txt")";
  ssh spark "docker inspect vllm-qwen-spark --format 'engine started={{.State.StartedAt}} restarts={{.RestartCount}}'";
  grep -h -e 'items=' -e 'acc=' -e 'prefix_cache delta' "$EV"/raw/leg1-accuracy.txt "$EV"/raw/leg1.log 2>/dev/null | tail -6; } >> RESULTS.md
git add -A "$EV" RESULTS.md && git commit -s -m "test(spark-llm): HD-489 overnight unattended run $TS — Leg 0 converge + MMLU-Pro mini @ conc 8 + gate 4 + depth + fp8 re-probe" && git log --oneline -1
```
Do **not** merge to `main`, do not remove the worktree — the parent session merges. Then stop.

---

## 8. Do NOT (each of these has already cost this lab a number or a box)

* Do not run anything against `127.0.0.1:1234` (that is the driver's own model — Rule 0) or against the
  laptop's 32k window at all.
* Do not raise `spark_llm_pool_ceiling_bytes`, `…_device_hold_ceiling_bytes` or `fixed_cost_bytes` to
  make a leg pass — those constants **are** the certification.
* Do not add `--max-tokens` / `--n` variations, seeds, or a second `-n 8` run in parallel to "speed it up".
* Do not use `spark.kogler.si/v1` (that path 302-redirects to `/`; `llm.kogler.si` is the API router) and
  do not open an SSH tunnel unless §1.3's check fails — if you must: `ssh -N -f -L 8000:127.0.0.1:8000 spark`
  and use `http://127.0.0.1:8000/v1` with `--token-env OPENAI_API_KEY`.
* Do not run SWE-bench task containers on spark, do not touch `spark_llm_profile`, do not reboot.
* Do not delete or `git clean` anything you did not create in this run.
