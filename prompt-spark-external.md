# `prompt-spark-external.md` — spark-side half of HD-420 + HD-395, for a session whose model is NOT spark

> **Role:** single-lane brief. **Read THIS file and nothing else to start.** You exist because the
> previous lane session ran on `PI_PROVIDER=spark` / `PI_MODEL=spark/qwen3.8-flash-next`, and two
> standing rules forbid that model doing this work:
> * `todo-table.md` §C2 — *"Never benchmark or converge spark from a session whose own model is
>   spark (incidents #3 + #6)."*
> * The contamination is not theoretical: the nine panels being certified at 5 s include
>   **token throughput and KV-pool memory that your own session produces**, and HD-395 needs
>   **in-flight = 0**, which is unattainable while a spark-backed agent generates through the engine.
> If your `PI_PROVIDER`/`PI_MODEL` (see `env | grep '^PI_'`) is spark — **STOP and tell the owner.**
> **Linked from:** [prompt.md](prompt.md) §4 · [todo.md](todo.md) HD-420/HD-395 ·
> predecessor lane `session/420-cadence-20260922-1607` (merged; its work is already in `main`).
> **Deliver to:** `spark-420-delivery.md` (see §Delivery — the closing session parses it).

## 0. Start here (exact)

```bash
cd /home/domen/source/homelab && git fetch && git status --short && git checkout main
bash scripts/validate-all.sh | tail -3                     # clean main is the exempt form (O5)
TS=$(date +%Y%m%d-%H%M)
git worktree add -b session/420-spark-$TS ../homelab-wt-$TS main
cd ../homelab-wt-$TS && bash scripts/guard-session.sh      # must print: edit context safe
```
Then read, in this order: `docs/observability.md` §Scrape cadence and metric resolution (**its
"State" block is your brief-in-brief**), §LLM Dashboard, §Host sensors; `todo.md` rows **HD-420**
and **HD-395**; `roles/spark/files/spark-oom-watchdog.sh`; `scripts/README.md` §Notes (detached
converges). Do **not** re-read `prompt-420.md` for direction — rows 1–4, 8, 10 of it are done;
this brief is the residue.

**Already done, do not redo:** the Alloy hot/cold split (row 1), `DCGM_EXPORTER_INTERVAL: "5000"`
(row 2 edit), the Grafana `timeInterval` floor (row 3, **live on the VPS**), the `rate()` panel fix
and the six-signal GPU row (rows 4/8, **live on the VPS**), and the HD-345 SNMP relabel (authored,
needs an **oldsrv** converge — not yours).

## 1. Your four jobs, in this order

### J1 — DCGM sidecar pre-flight (the gate that row 2 owed)
The compose already says `"5000"`; it is **not converged**, so the live sidecar is still at 30 s.
Gate = the sidecar's CPU and cgroup **anon** RSS at 5 s against `spark_dcgm_exporter_memory_limit`
= **256M** (the cap exists because it outgrew its cap during HD-378; measured floor ≈ 139–143 MiB,
and GOMEMLIMIT/GOGC changed nothing — the floor is DCGM/NVML's device context).

```bash
# baseline at 30 s (read-only)
ssh spark 'docker stats --no-stream --format "{{.Name}} {{.MemUsage}} {{.CPUPerc}}" dcgm-exporter-spark'
ssh spark 'ID=$(docker inspect -f "{{.Id}}" dcgm-exporter-spark); sudo -n cat /sys/fs/cgroup/system.slice/docker-$ID.scope/memory.stat | grep -E "^(anon|slab) "'
```
Then run J2 (which moves it to 5 s), let it settle ~10 min under a real load you generate
**from the laptop** (a couple of long completions through `llm.kogler.si`), and sample the same
two commands again. **PASS = anon stays ≤ ~200 MiB and CPU ≤ ~0.5 core sustained.**
FAIL ⇒ revert **both** `DCGM_EXPORTER_INTERVAL` and the `scrape_interval = "5s"` on
`prometheus.scrape "dcgm"` in `alloy.river.j2` — they are one coupled pair, never one without the other.

### J2 — converge spark (⛔ never bare `docker_services` on this box)
Two deploys: the Alloy config (hot/cold jobs) and the `spark-dcgm` sidecar. **The vLLM engine must
never restart.** `spark.yml` runs `monitoring`; the sidecar is a `docker_services` service, so
scope it and prove the task list before you touch anything:

```bash
bash scripts/ansible-run.sh playbooks/spark.yml --tags monitoring --limit spark.kogler.si --check
bash scripts/ansible-run.sh playbooks/spark.yml --tags docker_services --limit spark.kogler.si \
     -e docker_services_scope=spark-dcgm --check          # task list = spark-dcgm + the vault pre-pass ONLY
```
If the scoped `--check` lists any other service, **stop** and report it. Then run both **detached**
(a full converge behind an outer timeout gets killed mid-restart — HD-370):
```bash
nohup bash scripts/ansible-run.sh playbooks/spark.yml --tags monitoring --limit spark.kogler.si \
  > /tmp/hd420-spark-monitoring.log 2>&1 && echo done &
nohup bash scripts/ansible-run.sh playbooks/spark.yml --tags docker_services --limit spark.kogler.si \
  -e docker_services_scope=spark-dcgm > /tmp/hd420-spark-dcgm.log 2>&1 && echo done &
```
⛔ **never `--diff`** — not on `docker_services` and not on `monitoring`: `alloy.river.j2` renders
the Victoria* `basic_auth` credentials out of the vault, so a diff prints them.
⛔ never converge `group_vars/spark.yml` values: the 16 GiB KV pool is the certified live config.

### J3 — acceptance (measure, do not eyeball)
Load the engine while you sample. Run the queries through the VPS (creds from the `basic_auth`
block of `/etc/alloy/config.alloy`; **never print a value, lengths only**):
```bash
ssh vps 'bash -s'   # parse U/P with sed -n "/basic_auth/,/}/p", then POST to :8428/api/v1/query
```
| Probe | Pass |
|---|---|
| `count_over_time(node_load1{instance=~"spark.*"}[1m])` | **12** (1 ⇒ still 60 s) |
| `count_over_time(vllm:generation_tokens_total{instance=~"spark.*"}[1m])` | **12** |
| `sum(rate(vm_rows_inserted_total[5m]))` | baseline was **227.65** ⇒ ≈ **+9** rows/s, **not +125**. ~10× the expected delta ⇒ the cold `drop` matchers are not matching — fix the matcher, do not "accept the extra" |
| `vm_active_time_series` | essentially unchanged (cadence adds samples, not series) |
| Alloy containers on spark + VPS | RSS ≈ prior |
| `spark-oom-watchdog` | keeps sampling |
| the nine panels | 5 s granularity at `$__interval` on a 15-min range |

⛔ No engine restart anywhere in this lane. ⛔ Do not touch the alert-group `interval: 1m`.

### J4 — HD-395, the watchdog idle-recycle baseline
Read `roles/spark/files/spark-oom-watchdog.sh` **and its unit template** first; its own comments
carry the in-flight-`ERR` asymmetry and the sampler row layout, and it carries a four-case
`self-test` that is **mutant-tested — keep it honest**: removing the recovery call, the
running-check or either marker branch must turn it RED.
* Defect: the recycle fires at *first-post-boot top-pid + 8 GiB*, and that first sample has read
  **71,911 / 86,243 / 92,343 MiB on one config** ⇒ it either restarts a healthy engine (two fired
  35 min apart) or goes silent.
* Fix: take the baseline only **after `/health` 200 AND a settle window** (or the max of N
  samples), then re-check the +8 GiB margin against the **certified** peak — `usable =
  node_memory_MemAvailable_bytes − node_memory_CmaFree_bytes`, idle usable **18.5 GiB**,
  CRIT 8 / WARN 12, KV 16 GiB reserved (14.9 GiB / 515,786 tok / 1.97× @262k).
* Run the self-test locally (it stubs `docker`), then prove the behaviour live. A restart of the
  engine during this test is **intentional and must be pre-announced in the delivery** — and note
  `docker stop` is intentional in that unit, so `unless-stopped` will not bring it back on its own.
* ⛔ Never with an agent session attached to the engine. Never drive it from a spark-backed session.

## 2. Files

**Yours:** `IaC/ansible/roles/monitoring/templates/alloy.river.j2` (hot/cold cadence only),
`IaC/ansible/templates/docker_services/spark-dcgm/docker-compose.yml.j2`,
`IaC/ansible/roles/spark/files/spark-oom-watchdog.sh` + its unit template,
`docs/observability.md`, **your own `todo.md` rows** (HD-420, HD-395 — row-local hunks, never
re-sort the table) and **your own `deployment-tasks.md` lines**.
**Never:** `prompt.md`, `todo-table.md`, `prompt-*.md` (closing session's job), `group_vars/spark.yml`,
`roles/spark/**` beyond the watchdog + unit, `roles/router/**`, `roles/tailscale-node/**`,
`IaC/ansible/playbooks/**`, `scripts/**`, `reports/**`, any `*-generated.md`.
**Host slots you hold:** spark only. Do not converge oldsrv (HD-345's relabel waits for whoever
holds that slot) and do not re-converge the VPS unless J3 needs a monitoring re-run.

## 3. Delivery — write `spark-420-delivery.md` (in YOUR worktree, commit it on YOUR branch)

The closing session reads it from your branch (`git show <branch>:spark-420-delivery.md`), so
**commit it**. Never write it into `/home/domen/source/homelab` — a dirty primary on `main` breaks
the clean-main exemption in `validate-all.sh`. If your branch cannot carry it, the fallback path is
`/home/domen/source/spark-420-delivery.md` and you say so in your final message.

Use exactly these headings (the closing session parses them):

```
## METADATA          # branch, worktree path, model/provider you ran as, date+tz
## J1 DCGM PREFLIGHT # PASS|FAIL, the anon/CPU numbers before and after, the exact commands
## J2 CONVERGES      # one block per run: command, PLAY RECAP verbatim, handlers that fired
## J3 ACCEPTANCE     # every probe: query, value, verdict; the rows/s baseline→after pair
## J4 HD-395         # what changed, self-test output, live proof, whether the engine was restarted
## ROWS              # per todo.md row: DELETE (fully done) or EDIT with the new ⏳ tail text, verbatim
## LEDGER            # deployment-tasks.md lines to tick (- [x] with the date) or reword
## DOCS              # the after-numbers to write into docs/observability.md, per section
## PARKED            # exact blocked action + who owns it (owner / another lane / a host slot)
## VIEWS DELTA       # what prompt.md and todo-table.md must say once this all merges
## RED LINES         # anything you did NOT do and why
```
Rules: **measure, never assert**; never print a secret (lengths/prefixes/item ids only); a test
that cannot fail is not evidence; sign your commits (`Couldn't find key in agent` → `ssh-add
~/.ssh/github_signing ~/.ssh/github_auth`); finish with `bash scripts/validate-all.sh` green in
your worktree and **stop** — do not merge, do not delete the briefs, do not touch the two views.
