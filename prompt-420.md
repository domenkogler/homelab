# `prompt-420.md` — Re-dispatch card · the two observability rows that survived the HD-420 thread (HD-377(a) · HD-342)

> **Role:** **trimmed 2026-09-23 to its two living rows.** This brief opened 2026-09-21 as the spark
> metric-cadence lane (HD-420 + the merged HD-395 / HD-377(b) / HD-345). **All four of those are closed and
> live** — the cadence work, the watchdog baseline work and the SNMP label fix landed and were verified on the
> boxes. What is left here is only what the thread could not finish itself: one **owner eyeball** and one
> **backup tail whose client belongs to another row**. Kept deliberately, because deleting it would orphan
> them (the precedent is `prompt-414.md`, closed but kept as a re-dispatch card).
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, items O1–O8; where it is
> silent, README §4 + CONVENTIONS stand):** one session, one worktree, one branch. **Never edit `prompt.md` or
> `todo-table.md`** (O2). Edit **your own `todo.md` rows** and tick **your own** `deployment-tasks.md` lines.
> Owner gate → **park and continue** (O4). Finish with `bash scripts/validate-all.sh` green **in your
> worktree**, then **stop** — the parent merges and retires this brief.

## What is already true — do not re-do, do not re-measure, do not re-decide

Verified on the boxes 2026-09-23 (parent close-out; the numbers live in the owning docs):

* **HD-420 is LIVE end to end** — the hot/cold `prometheus.scrape` jobs in `alloy.river.j2` (spark-gated,
  **disjoint** `keep`/`drop`), `DCGM_EXPORTER_INTERVAL: "5000"` and the `prometheus` datasource's
  `jsonData.timeInterval = "5s"`. Acceptance re-read after the oldsrv converge:
  `count_over_time(node_load1{instance=~"spark.*"}[1m])` = **12** with cold-only names at **1**; the sidecar
  under load held **anon 56–59 MiB of its 256 MiB cap**, so no limit change is owed. Arithmetic, the rejected
  options and the measurement method: [docs/observability.md](docs/observability.md) §Scrape cadence.
* **HD-395 is closed and its idle-recycle term is OFF by owner decision** — see
  [docs/hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget for the decision, the re-arm
  condition and the `sudo … status` ≠ unit-env trap. ⛔ Do not "restore" the recycle margin.
* **HD-345 is closed** — it was a **label** fault, not a walk fault; `up{job="alloy-snmp",instance="router"}=1`
  after the oldsrv `--tags monitoring` converge.
* **HD-377(b) is done** — the three `DCGM_FI_PROF_*` panels are deleted, the six real DCGM signals + XID
  readiness are wired, **53 panels**, re-derived by `scripts/build-llm-dashboard.py`.
* ⛔ **No-re-decide list stays in force:** no second VictoriaMetrics, no OpenObserve, no age-tiering (community
  VM has no `-downsampling.period` / `-retentionFilter`), no touch of the alert-group `interval: 1m`, and
  **never restart the vLLM engine** for observability work.

## The two rows

| # | Row | The action | Gate / limit |
|---|-----|-----------|--------------|
| 1 | **HD-377(a)** | **owner only:** open `https://stats.kogler.si` → **Homelab — LLM**, look at the 53 panels, sign off. The board is already **provisioned + imported** (VPS file byte-identical to the repo, `uid=homelab-llm`, datasource health OK), so this is an eyeball, not a deploy. On sign-off the AI deletes `llm-inference-sglang-vllm.json` + `vllm-master-v2.json` + `vllm-dashboard.json` from `roles/monitoring/files/dashboards/` and re-converges `vps.yml --tags monitoring` | Park until the owner speaks (O4). Deleting the retired boards also retires the hard-coded `[5m]` prefix-cache gauge — **rebuilding that panel on a board scheduled for deletion is not the fix** |
| 2 | **HD-342 (backup tail)** | The Victoria data dirs (`/srv/docker/victoria-{metrics,logs}/data`) have **no backup client to wire**: the VPS runs `kopia-server` (the repository endpoint) and no client of its own | **This is HD-191's change, not this lane's.** Read [docs/backup.md](docs/backup.md) §VPS-side coverage gap before touching an include list — adding paths to a list with no client is the fiction that file warns about. Keep the HD-342 tail naming HD-191 |

**Owed, in this file set, named but not dispatched:** the blackbox `tcp_connect` probe of RustDesk `21116/21117`
(HD-412's named debt) lives in `roles/monitoring/**`; it is a small add-on to any `--tags monitoring` change,
not a lane of its own.

## Files

**Owns:** `IaC/ansible/roles/monitoring/files/dashboards/**`, `IaC/ansible/roles/monitoring/templates/**` and
`tasks/main.yml` (read first; **⛔ never `--diff` on `monitoring` — `alloy.river.j2` renders the Victoria*
`basic_auth` credentials out of the vault**), `scripts/build-llm-dashboard.py` + its `--check` gate,
`docs/observability.md`, and **your own `todo.md` rows** + your own `deployment-tasks.md` lines.

**Never touches:** `prompt.md`, `todo-table.md` (O2), `roles/router/**` + `roles/tailscale-node/**`
([`prompt-414.md`](prompt-414.md)), `roles/spark/**` and the engine/bench lane
([`prompt-376.md`](prompt-376.md)), `group_vars/spark.yml`, `roles/**` of any other lane, the frozen archives
(`reports/**`, `docs/archived/`) and generated `docs/*-generated.md`.

**Converge slots you hold:** `vps.yml --tags monitoring` and `home_servers.yml --tags monitoring` (both ran
2026-09-23; keep them **serial**, detached, `nohup … > log 2>&1 &`, **no `--diff`**).

## First action

Open [docs/observability.md](docs/observability.md) §LLM Dashboard and §Scrape cadence — if a statement there
still reads as owed, the row tail in `todo.md` is the authority, not this brief. Then **park on HD-377(a)**: it
waits on a human looking at a screen. Take HD-342 only as far as naming HD-191 correctly, and stop.
