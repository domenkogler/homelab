# `prompt-420.md` — Lane brief · make nine spark panels honest at 5 s (HD-420)

> **Role:** lane brief for the sampling-rate / hot-cadence work on the spark → Grafana path. Opened
> **2026-09-21** out of a **read-only** measurement session: the owner asked whether the pipeline can serve
> "5 s for the last 10 min, 30 s for the last hour, 60 s beyond that" without overloading spark during
> inference, and whether a second store (OpenObserve, or a second VictoriaMetrics on oldsrv) is needed.
> Both questions are **answered and closed** — the durable answer is
> [docs/observability.md](docs/observability.md) §Scrape cadence and metric resolution; read that section
> first, then this brief. Do **not** re-measure the baseline.
> **Linked from:** [prompt.md](prompt.md) §2 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
> **Sibling lanes:** transport = [prompt-414.md](prompt-414.md) · runner/cockpit =
> [prompt-407.md](prompt-407.md) · remote desktop = [prompt-412.md](prompt-412.md). This lane owns
> `roles/monitoring/**` + `templates/docker_services/spark-dcgm/**` — it collides with no live lane.

## Goal

Spark is scraped at **60 s everywhere** (`scrape_interval` is set nowhere in the deployed Alloy config, so the
Alloy default applies to all four hosts and every job). Nine panels are supposed to show what the DGX System
Monitor shows, and the Monitor is at **1 Hz**: spark memory (`MemAvailable − CmaFree`), GPU util, CPU util,
Prefix Cache Hit Rate, GPU KV Cache Usage, Token Throughput, Cached Token Stats, Decode Throughput.

**Done means:** those nine panels render 5-second data end to end (5 s scrape → VM → Grafana), nothing else
changes cadence, spark's inference path measurably unaffected, and the VPS still has headroom. Not "5 s
everywhere": the owner scoped fine resolution to these panels, and the exclusions are the whole reason the
change is cheap.

## Why the shape is this (settled — read before proposing anything)

- **Age-tiering does not exist in this stack.** `-downsampling.period` and `-retentionFilter` are absent from
  the deployed VictoriaMetrics **community** binary; OpenObserve's downsampling is enterprise too. Resolution
  is bought **at write time**, not by collapsing old buckets later.
- **Blanket 5 s is the expensive, pointless version.** spark emits **1,774 samples per scrape**, and 469 of
  them are `_bucket{}` histogram lines that only move when a request completes — faster scraping them stores
  the same number sooner. The nine panels need **50 series**. 50 @ 5 s = **+9.2 rows/s, ≈ +95 MB/yr**;
  1,745 @ 5 s = +125 rows/s and ≈ 3.4 GB (plateauing at the 365 d retention).
- **The engine needs nothing.** `vllm:generation_tokens_total` advanced on every one of 17 consecutive 1 s
  scrapes under load: `VLLM_LOG_STATS_INTERVAL: "10"` is the log heartbeat, not a publication cap. Render cost
  is 4.8–6.1 ms → **0.10 % of one of 20 cores** at 5 s. No engine restart, ever.
- **The real cap is the DCGM sidecar**, at `DCGM_EXPORTER_INTERVAL: "30000"` — twelve 1 Hz reads of
  `GPU_UTIL` all returned `86`. Fixing the picture without fixing collection writes six copies of one sample.
- **RAM, not disk, is the VPS limit** (4.3 GiB available, no swap) and it tracks *active series*, which cadence
  does not change. That is also why a second VM was rejected: the owner accepted the ~95 MB/yr instead of
  splitting the store in two.

## Rows (do them in this order)

| # | Action | Gate |
|---|--------|------|
| 1 | Hot/cold job split in `IaC/ansible/roles/monitoring/templates/alloy.river.j2`, **gated on the spark inventory host** — spec below | the disjointness rule below is not optional |
| 2 | `DCGM_EXPORTER_INTERVAL: "30000"` → `"5000"` in `IaC/ansible/templates/docker_services/spark-dcgm/docker-compose.yml.j2` | ⛔ pre-flight the sidecar's CPU + anon RSS against its `mem_limit: 256M` at 5 s **first** — that cap exists because the exporter outgrew it during HD-378 |
| 3 | Grafana datasource `jsonData.timeInterval = "5s"` on the `prometheus` uid | the seed only fires `when: … status == 404` → an API PUT on the live datasource, not a seed edit |
| 4 | Panel fixes: "Prefix Cache Hit Rate" gauge → time series with `[1m]`/`$__rate_interval` (it is hard-coded `[5m]` today); `rate()` for "Cached Token Stats" | re-derive the dashboards with `scripts/build-llm-dashboard.py` / `scripts/adapt-vllm-dashboards.py` — **never hand-edit `files/dashboards/*.json`** |
| 5 | Converge + verify (acceptance below), then update `docs/observability.md` §Scrape cadence (⏳ → ✅) and §LLM Dashboard in the **same** change | `vps.yml --tags monitoring` (datasource + dashboards) **and** the spark-side Alloy/DCGM converge — detached, `--tags` + scope, **no `--diff`** (HD-382 secret dump) |
| 6 | Report the measured after-numbers back into the doc section; close the HD row (delete it, record lands in the doc) | CONVENTIONS §3 lifecycle |

## Row 1 spec — the hot/cold split

Three hot jobs, `scrape_interval = "5s"`, `scrape_timeout = "3s"` (do not leave it at Alloy's 10 s default — a
hung scrape at a 10 s timeout blocks the 5 s cycle), each followed by a `prometheus.relabel` that **keeps only**
the hot set, and the **same** matcher with `action = "drop"` added to the existing cold jobs:

- hot host job: the eight `node_memory_*` from HD-378's `default_modern_config.text` **plus**
  `node_memory_CmaFree_bytes`, `node_load1`, `node_load5`, and `node_cpu_seconds_total{mode="idle"}`
  (`{__name__="node_cpu_seconds_total",mode!="idle"}` → `drop`)
- hot dcgm job: scrape `:9400` with the same `DCGM_FI_DEV_*` whitelist as today
- hot vllm job: the 14 `vllm:` names in the table in
  [docs/observability.md](docs/observability.md) §Scrape cadence → the hot set list

⚠ **Disjointness is load-bearing.** If a series is emitted by both jobs you get duplicates at two cadences, and
the only cure is `-dedup.minScrapeInterval=5s` on the VPS — a shared flag that silently re-tunes dedup for
**every host**, which is exactly the kind of unowned global change this repo refuses. With disjoint sets the
series names are unchanged, so **no dashboard query has to change** and no dedup flag is needed.
⚠ `prometheus.relabel` mutates `job`/`instance` labels on the target; the cold `drop` and the hot `keep` must
both run **after** the label shaping they reference.
⚠ Keep the hot jobs' `job` label distinct from the cold one **only if** a panel filters `by (job)` — several
existing queries select `job="vllm"` / `job="dcgm"`, so prefer reusing those labels and prove it in the verify
step rather than assuming it.

## Acceptance (measure, don't eyeball)

```promql
count_over_time(node_load1{instance=~"spark.*"}[1m])          -- 12 ⇒ 5 s landed, 1 ⇒ still 60 s
count_over_time(vllm:generation_tokens_total{instance=~"spark.*"}[1m])
```

Plus: `vm_rows_inserted_total` on the VPS rises by **≈ +9 rows/s** (not +125); `vm_active_time_series` is
essentially unchanged; the Alloy containers on spark and the VPS stay at their prior RSS; `spark-oom-watchdog`
keeps sampling; the nine panels show 5 s granularity with `$__interval` at 5 s on a 15-minute range.
⛔ If the row-rate delta is ~10× the expected +9/s, the cold `drop` rules are not matching — fix the matcher,
do not "accept the extra".

## ⛔ No-re-decide list

- **No second VictoriaMetrics, no OpenObserve** (owner 2026-09-21): the storage cost on the VPS is accepted.
  A second VM is *technically* fine and cheap, but it splits Grafana into two datasources and puts the metrics
  DB outside the off-site backup perimeter. Do not re-open unless the owner does.
- **Don't chase age-tiering** — community VM has no downsampling and no retention filters.
- **Never restart the vLLM engine** for this. No engine change is required; the 10 s `VLLM_LOG_STATS_INTERVAL`
  is not the limiter.
- **Don't touch the alert-group `interval: 1m`** as part of this row (see the doc §Scrape cadence item 5).
- **VLAN-99 seal, tailnet boundary, `wg_s2s` sets untouched** — none of this needs a network change; the VPS
  write target already works over `wg-s2s` with 0 failures.
- **`dcgm-exporter` is a 30 s-caching collector** until row 2 lands; any "GPU data looks steppy" report is that,
  not Alloy.

## Files

**Owns:** `IaC/ansible/roles/monitoring/templates/alloy.river.j2`,
`IaC/ansible/roles/monitoring/files/config.alloy`, `IaC/ansible/roles/monitoring/tasks/main.yml`
(datasource seed), `IaC/ansible/roles/monitoring/vars/main.yml`,
`IaC/ansible/templates/docker_services/spark-dcgm/docker-compose.yml.j2`,
`scripts/adapt-vllm-dashboards.py` + `scripts/build-llm-dashboard.py` and their `--check` gate,
`docs/observability.md`, `todo.md`, `todo-table.md`, `deployment-tasks.md`, `prompt.md`.

**Doesn't touch:** `roles/spark/**` (the engine + watchdog belong to the spark lane — row 2 is the *dcgm
sidecar*, which lives under `templates/docker_services/`), `roles/router/**` +
`roles/tailscale-node/**` ([prompt-414.md](prompt-414.md)), `scripts/bootstrap-runner.sh` +
`docs/{services-ai,pi-harness,1password,deployment-ansible}.md` ([prompt-407.md](prompt-407.md)),
`docs/services-rustdesk.md` ([prompt-412.md](prompt-412.md)), the frozen archives
(`reports/changelog.md`, `reports/deployment-journal.md`, `docs/archived/`), generated
`docs/*-generated.md`.

**Collides with:** nothing live. Note that **HD-342** (Kopia wiring for the Victoria data dirs) reads the same
role — coordinate if both land in one session, and keep the `vps.yml --tags monitoring` converges serial.

## First action

Read the current renderer once, in full: `roles/monitoring/templates/alloy.river.j2` is a **dual-mode** template
(spark loopback vs the `wg_s2s_vps` pull) and it also renders the legacy `config.alloy` path — so put the new
blocks inside the **R2 (VictoriaMetrics) branch**, and confirm on the live box which branch spark's deployed
config came from before adding anything (`/etc/alloy/config.alloy` carries a "GENERATED BY ANSIBLE — DO NOT
EDIT" banner naming the source template). Then author rows 1–3, run `--check`, and pre-flight row 2 on the box
before converging it.
