# `prompt-spark-external.md` — the spark residue that a spark-backed session may NOT run (HD-395 live proof + the bench-gated ladder)

> **Role:** single-lane brief, **rewritten 2026-09-23** after the spark cadence/edge work landed. Read THIS
> file and nothing else to start.
> **Linked from:** [prompt.md](prompt.md) §4 · [todo.md](todo.md) HD-395 / HD-359 / HD-367 / HD-376 / HD-400 ·
> predecessor lanes: `session/420-cadence-20260922-1607` (merged), `session/spark-edge-20260923-0904` (HD-451).
> **Deliver to:** `spark-external-delivery.md` (see §Delivery — the closing session parses it).

## 0. Why this brief still exists — and why it is four times smaller than it was

Two standing rules used to gate this file. One of them is now narrower, so read the current wording
([todo-table.md](todo-table.md) §C2):

* **Still binding:** *never **benchmark** spark from a session whose own model is spark*, and never run
  **the engine-restart leg** from such a session. The contamination argument is real: the nine panels
  being certified at 5 s include token throughput and KV-pool memory that your own session produces, and
  the HD-395 recycle proof needs **in-flight = 0**, which is unattainable while a spark-backed agent
  generates through the engine.
* **Narrowed 2026-09-23 (owner decision):** a spark-backed session **may** run spark converges that
  provably cannot touch the inference engine — `--tags monitoring`, the `spark-dcgm` sidecar, the
  `spark-dashboard` / `traefik-tailnet` **file-provider** route edits, and `--tags watchdog`
  (which restarts only `spark-oom-watchdog.service`). It ran exactly those on 2026-09-23 and proved it:
  engine id + `StartedAt` identical before and after every converge, `RestartCount=0`, `llm.kogler.si`
  200 throughout.

**So: if your `PI_PROVIDER`/`PI_MODEL` (`env | grep '^PI_'`) is spark, you may NOT take this brief.**
Everything left here either restarts the engine or is a benchmark. Stop and tell the owner instead.

## 1. Already done — do not redo (measured, 2026-09-23)

* **HD-420 spark half is LIVE.** Hot/cold Alloy jobs (`changed=2` + `restart alloy`), `spark-dcgm`
  recreated at `DCGM_EXPORTER_INTERVAL=5000`, and the acceptance already measured through VM:
  `count_over_time(node_load1{instance=~"spark.*"}[1m])` = **12**, `vllm:generation_tokens_total` =
  **12**, `DCGM_FI_DEV_GPU_UTIL` = **12**, while oldsrv and nas stayed **1**; rows/s 227.65 → **242.8**
  (+15, not the +125 an un-matched cold `drop` produces) and **one** series per hot name (so the
  hot/cold sets are disjoint and no `-dedup.minScrapeInterval` change is owed). Do not re-measure it.
* **The DCGM sidecar is at 5 s and inside its cap at idle:** 170 MiB used, cgroup **anon 164 MiB** of the
  256 MiB `spark_dcgm_exporter_memory_limit`, CPU idle at idle. The J1 pre-flight gate is therefore
  answered **at idle**; only the under-load sample is missing (§J2 below).
* **HD-451 (short name / legacy alias) is LIVE** — `https://spark.kogler.si` (LAN) and
  `https://spark.ts.kogler.si` (tailnet-only, `tailnet_ts_only_subdomains`) both serve the dashboard;
  `db-spark*` is legacy and stays routed. **Never add a new consumer on `db-spark*`, and never publish
  the plain host name into `tailnet_subdomains`** — the reason is written into
  `group_vars/vps.yml` and [hardware-spark.md](docs/hardware-spark.md) §Remote management.
* **HD-440 is fixed at the source** (`roles/docker_services/tasks/deploy-service.yml`): the HD-268c stub
  removal is a `stat` + remove-only-if-**directory** pair, the HD-162 compose-validation task is
  `changed_when: false`, and `spark-dashboard` joins the restart-guard exclusion list next to
  `traefik`/`traefik-ha`/`traefik-tailnet` (it is a file-provider edge AND the `llm.kogler.si` edge, so a
  bounce = a 502 on inference). Proven on spark: same commit twice → `changed=3` then **`changed=0`**.
* Still done from the previous lane, unchanged: the Alloy hot/cold authoring, the Grafana datasource
  `timeInterval` floor, the `rate()` fix on *Cached Token Stats*, the six-signal GPU row, HD-345's
  relabel (authored; it waits on an **oldsrv** converge, not you).

## 2. Your jobs, in this order

### J1 — HD-395: converge the watchdog, then prove it live (the only engine-restart leg)

Read `IaC/ansible/roles/spark/files/spark-oom-watchdog.sh` **and its unit template** first; the script's
own comments carry the in-flight-`ERR` asymmetry and the sampler row layout, and it carries a four-case
`self-test` that is **mutant-tested — keep it honest**.

The defect, with today's evidence (read-only, `sudo /usr/local/bin/spark-oom-watchdog.sh status` +
`state/enforce.log`): the baseline is the **first** post-boot top-pid sample, and it is a coin-flip —
`enforce.log` shows **three** recycles on 2026-09-23 alone (`03:41:15Z`, `04:15:44Z`, `04:50:14Z`), each
reading `engine 92343 MiB > baseline 71911 + 8 GiB and idle > 1800s`, i.e. the guard was **permanently
armed** against a healthy engine, and every 30-minute idle gap cost a cold start.

1. Converge it — this part is engine-safe (the handler restarts the watchdog unit, never the engine):
   `bash scripts/ansible-run.sh playbooks/spark.yml --tags watchdog --limit spark.kogler.si` (detached,
   ⛔ never `--diff`). ⚠ **Use `--tags watchdog`, NOT `--tags spark,watchdog`:** Ansible reads a
   comma-separated `--tags` as a **union**, so the second form also drags the `spark` role's XFS /
   sysctl / headless tasks onto a live inference box for no reason. The watchdog tasks carry
   `tags: [spark, watchdog]`, so one tag already covers them.
2. Prove a **unit restart does not recycle**: after the converge, the engine id/`StartedAt` must be
   unchanged and `status` must show the baseline field the fix adds.
3. Then the intentional restart: with **in-flight = 0** and **no agent session attached**, drive the
   recycle path once and watch it recover. ⚠ `docker stop` is intentional in that unit, so
   `unless-stopped` will NOT bring the engine back — say so in the pre-announcement and expect the
   cold-start window (`llm.*` 502s for the duration; hardware-spark.md's cold-start note).
4. Re-check the +8 GiB margin against the certified peak arithmetic: `usable = MemAvailable − CmaFree`
   (the inverted `MemFree − CmaFree` form is a documented mistake), idle `usable` **18.5 GiB**, CRIT 8 /
   WARN 12, KV **16 GiB** reserved (14.9 GiB / 515,786 tok / 1.97× @262k), engine cage 105 GiB,
   `--enforce-eager` (C3) stays OFF on measurement.
5. ⚠ **The margin is two-sided, and the fix makes it visible rather than deciding it.** With a *correct*
   baseline (~92,343 MiB) the trigger lands at ~100,535 MiB, which is **above** the certified peak
   (96,235 MiB) — so recycle will likely go **silent**, which is the opposite failure direction and is
   what the guard exists to prevent. `status` now prints the floor spread and the `margin:` verdict:
   read it, and if the margin is inert, take the decision to `RECYCLE_GROW_GIB` (or to the peak the
   baseline should be measured against) **to the owner** — it is a tuning decision, not a bug fix.

### J2 — HD-420 tails that need traffic you generate off-box

* Load the engine **from the laptop** (a couple of long completions through `llm.kogler.si`) and sample
  the sidecar again: `docker stats --no-stream dcgm-exporter-spark` + the cgroup `memory.stat` **anon**.
  If anon passes ~200 MiB, raise `spark_dcgm_exporter_memory_limit` in `group_vars/spark.yml` — a
  compose spec change ⇒ sidecar recreate only. ⛔ Do not touch any other `group_vars/spark.yml` value:
  the 16 GiB KV pool is the certified live config.
* The nine panels at 5 s granularity on `$__interval`, 15-min range, **on external traffic** — the
  contamination rule is the whole reason this line is still here.

### J3 — the bench-gated engine legs (only inside an owner-opened bench window)

HD-376 (262k needle test + `spark-lane` 64k profile), HD-367/359 (the S1 ladder, S2/S3 NVFP4 × SGLang),
HD-400 (text-only engine mode). Each is an **engine recreate** (~20 min cold start) and a benchmark;
batch them into ONE window so the box pays one cold start, not three. Outside an open window: do not
start. Never with a large agent session attached (incident #6: ~162k tok ≈ 56 % of the old pool).

## 3. Files

**Yours:** `IaC/ansible/roles/spark/files/spark-oom-watchdog.sh` + its unit template + `roles/spark/defaults/main.yml`,
`group_vars/spark.yml` **only** for `spark_dcgm_exporter_memory_limit`, `docs/observability.md`
(§Scrape cadence, §LLM Dashboard), `docs/hardware-spark.md` (§Unified-memory budget), **your own
`todo.md` rows** (HD-395, HD-420 tails — row-local hunks, never re-sort the table) and **your own
`deployment-tasks.md` lines**.
**Never:** `prompt.md`, `todo-table.md`, `prompt-*.md` (closing session's job), the KV/cache values in
`group_vars/spark.yml`, `roles/router/**`, `roles/tailscale-node/**`, `IaC/ansible/playbooks/**`,
`scripts/**`, `reports/**`, any `*-generated.md`, `roles/docker_services/tasks/**` (HD-440 landed — if
it is still open when you run, say so instead of fixing it in this lane).
**Host slots you hold:** spark only. Do not converge oldsrv (HD-345's relabel and HD-440's oldsrv
re-proof both wait for whoever holds that slot) and do not re-converge the VPS unless J2 needs it.

## 4. Converge discipline (what the last lane learned, so you do not re-learn it)

* **A deploy-scoped run needs BOTH tag classes.** `--tags docker_services` alone silently deploys
  nothing — the per-service tasks carry `tags: <svc.name>` (the old version of this brief had that bug).
  Correct form: `--tags docker_services,spark-dcgm -e docker_services_scope=spark-dcgm`.
* **`--check` cannot prove a deploy.** The deploy loop skips in check mode, so `--check` shows scoping
  only (`ok=19 changed=0` while nothing was applied).
* **Detached or die.** `nohup … > log 2>&1 &` + poll; a foreground converge behind an outer timeout gets
  killed mid-restart (HD-370).
* ⛔ **never `--diff`** on `monitoring` or `docker_services` — `alloy.river.j2` renders the Victoria*
  `basic_auth` credentials out of the vault.
* **Anything that can restart a control plane goes through `scripts/guarded-converge.sh`** (arm the
  watchdog on the target → prove it alive → only then touch the service → verify → disarm). It was used
  again on 2026-09-23 for the headscale `extra_records` publish (`RESULT: GREEN`, self-tests A–D PASS).
* **Engine-untouchability is a measured claim, not an assertion.** Take
  `docker inspect -f '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' vllm-qwen-spark` **before** every
  converge and after the last one, plus `curl -s -o /dev/null -w '%{http_code}' https://llm.kogler.si/health`.
  An unchanged pair + 200 is the proof; anything else is an outage you caused — say so immediately.

## 5. Delivery — write `spark-external-delivery.md` (in YOUR worktree, commit it on YOUR branch)

The closing session reads it from your branch (`git show <branch>:spark-external-delivery.md`), so
**commit it**. Never write it into `/home/domen/source/homelab` — a dirty primary on `main` breaks the
clean-main exemption in `validate-all.sh`. Fallback path: `/home/domen/source/spark-external-delivery.md`,
and you say so in your final message. Use exactly these headings:

```
## METADATA          # branch, worktree path, model/provider you ran as, date+tz
## ENGINE UNTOUCHED  # the id/StartedAt/RestartCount pair before and after EVERY converge + the /health code
## J1 HD-395         # converge recap (PLAY RECAP verbatim, handlers that fired), self-test output,
                     # the unit-restart proof, the intentional recycle (timestamped pre-announcement +
                     # recovery time), the baseline field as read back from `status`
## J2 CADENCE TAILS  # sidecar anon/CPU under load, any spark_dcgm_exporter_memory_limit change,
                     # the nine-panel verdict per panel
## J3 BENCH          # which legs ran, in which window, or the reason none did
## ROWS              # per todo.md row: DELETE (fully done) or EDIT with the new ⏳ tail text, verbatim
## LEDGER            # deployment-tasks.md lines to tick (- [x] with the date) or reword
## DOCS              # the after-numbers to write into observability.md / hardware-spark.md, per section
## PARKED            # exact blocked action + who owns it (owner / another lane / a host slot)
## RED LINES         # anything you did NOT do and why
```

Rules: **measure, never assert**; never print a secret (lengths/prefixes/item ids only); a test that
cannot fail is not evidence; sign your commits (`Couldn't find key in agent` → `ssh-add
~/.ssh/github_signing ~/.ssh/github_auth`); finish with `bash scripts/validate-all.sh` green in your
worktree and **stop** — do not merge, do not delete the brief, do not touch the two views.
