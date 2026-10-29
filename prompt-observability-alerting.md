# `prompt-observability-alerting.md` — Lane brief · silent-failure rules, Matrix alerting, boards

> **Role:** dispatch note for **one** lane session on the observability + alerting domain. **The rows are the authority**
> for what is missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-450 · HD-1108 · HD-342 · HD-344 · HD-315 · HD-343 · HD-377 · HD-1120 ·
> HD-1121 · HD-1122 · HD-1166 · HD-1182 · HD-14** (row ids as of `c13e30f6` — re-derive with
> `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge hosts + slots (O3):** the **VPS** is the primary slot (`--tags monitoring` restarts Grafana / VictoriaMetrics /
VictoriaLogs / Alloy there); **oldsrv** carries the MCP servers + the network-clients exporter; **nas / pi / spark** are
collector-only legs of the same role. One converge in flight per host, detached, **never `--diff`**. Router work here is
**read-only** (the RouterOS API for leases/FDB/wifi-reg) — that is not the router slot; a router **delta** would be, and the
router slot is global, so never bundle one with a monitoring converge.
⛔ **Do not share a wave with another VPS lane**: `monitoring` and `docker_services` on the VPS restart the scrape tier under
a sibling's feet, and an Alloy restart drops a scrape cycle on every host's data.
**The LLM-telemetry rows widen this lane's host set** (HD-1120 · HD-1121 · HD-1122, spec in
[docs/observability.md](docs/observability.md) §LLM token accounting): enabling the spark edge's access log converges
**spark** (`templates/docker_services/spark-dashboard`), and the `--metrics` flag converges **oldsrv** `docker_services`
(`templates/docker_services/{embed,reranker}`) — so neither runs inside a spark bench window and neither shares a wave with
another oldsrv lane. **Land each hunk in a clean window, never inside a spark bench window**: the oldsrv half is an ordinary
`docker_services` leg, but the **spark half holds the spark slot**, whose docker-family apply is still owed by the pin window's
spark phase ([prompt-update.md](prompt-update.md) Phase 6) — so the `traefik-spark` hunk rides that phase or a window after
it, from a seat spark does not serve. The scrape jobs themselves are monitoring-only and always safe.

**Read first:** [docs/observability.md](docs/observability.md) → §Alerting → §Silent-failure hygiene → §Component Table →
§Network Clients Dashboard → §LLM Dashboard → §MCP · [docs/services-matrix.md](docs/services-matrix.md) §Alert room ·
[docs/backup.md](docs/backup.md) §VPS-side coverage gap · [docs/deployment-ansible.md](docs/deployment-ansible.md).

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-1108** | Deliver the existing Grafana → n8n chain into a dedicated `#homelab-alerts` room on the live Tuwunel (room + dedicated alert user, token from the vault per the doc's §6 rule, never a literal), keep Grafana-native **SMTP fail-safe running in parallel**, then demote `signal-cli-rest-api` — last step, not the first | Acceptance is a **delivery proof, never a webhook `200`**: read the room's event for the canary, not the workflow's status. Both `onError: continueRegularOutput` mutes must stay removed on the new leg |
| 2 | **HD-450** | Re-point this row's alert leg at the Matrix channel `#homelab-alerts` — the one half left here, and it rides HD-1108's remaining leg: the one end-to-end canary on the real webhook path | Until that canary is read back **from the room**, Signal is the path this row's alerts are read on — **do not extend the Signal surface**, and the canary itself needs the owner to accept the Signal page it will send. ⛔ Never mute the class by tolerating a non-zero rc in the pull script: rc 90 is the self-pull guard and must stay loud. Thresholds are WARN `< 14` / CRIT `< 7` days (the `cert-age-warning` / `cert-age-critical` uids in `IaC/ansible/roles/monitoring/vars/main.yml`), re-derived from the measured 90-day pair — 30/14 fires before every scheduled renewal |
| 3 | **HD-344** | Register the two MCP endpoints in the consumers that should see them (the pi harness, Open WebUI, OpenClaw); the tailnet redo is an owner leg | Use the vars — `mcp_metrics_port: 8083` / `mcp_logs_port: 8084` (`IaC/ansible/group_vars/all/main.yml`), bound to `oldsrv_home_ip`. ⛔ Never a literal `:8080`/`:8081` — 8080 is pi-dev's |
| 4 | **HD-342** | The only open tail is off-site protection for `/srv/docker/victoria-{metrics,logs}/data`, and it belongs to the VPS backup client (HD-191): name the dependency in the row, do not add paths to an include list | ⛔ The VPS runs `kopia-server` — the repository endpoint — and has **no client of its own** (no binary, no client config, no `kopia-agent` entry). The shape is ruled (a `kopia-agent` container on the VPS, [docs/backup.md](docs/backup.md) §VPS-side backup client) but the client is **not landed** — so wiring two paths to a nonexistent client is the fiction that section warns about. The IaC-side precondition is already true (both paths are host binds under `/srv/docker`) |
| 5 | **HD-343** | Verify the live wifi source (`/interface/wifi/registration-table` vs the legacy path) against what the RB4011 actually answers, then render-verify the board on `stats.kogler.si` | The exporter runs in a dedicated venv with its own pinned `routeros-api` because trixie ships no `python3-routeros-api`; the unit runs `networkclients` with `0750 root:networkclients` (`0700 root` breaks the unprivileged unit). Read the union `/metrics` before touching the join |
| 6 | **HD-315** | Render-verify the technical boards **with data** (host overview, probe tables) — the metric-name work is done, the eyeball is not | Owner leg → park with the exact URL + board list (O4). An empty panel is a question, not a verdict: check the series exists in VM before calling a panel broken |
| 7 | **HD-1120** | Attribute LLM traffic **at the edge** (the metering-proxy shape is rejected by owner ruling): read which peer the spark edge logs on each path, enable `--accesslog=true` on `traefik-spark`, deliver a per-client VictoriaLogs read | ⛔ Measure the peer address **before** building: the tailnet path arrives through `traefik-tailnet` over WG S2S, so without XFF preserved **and** trusted every tailnet client logs as the tunnel hop and the table collapses to one healthy-looking row. ⚠ Tokens are NOT in the access log — per-client tokens stay a labelled estimate, never a counter. ⚠ No HD-280-style host bind (that exists for fail2ban); stdout already reaches VictoriaLogs |
| 8 | **HD-1121** | Scrape the two LiteLLM gateways (`litellm` VPS + `lan-litellm` oldsrv) so gateway-side token/spend usage is in VM at all: add the `prometheus` callback to both config templates, name the auth half in the same change, and give the **VPS** instance a loopback publish of its metrics port (it publishes no host port, so `discovery.docker` finds 0 targets) — then add one `prometheus.scrape` per instance | The surface question is **settled, not open**: on this pin `/metrics` answers `401` unauthenticated and `404` with a valid admin bearer because the endpoint is mounted only when the `prometheus` callback is configured — so the deliverable is the callback plus the jobs, not a probe. Quote names from the live render; explicit `job`/`instance` so the two instances never merge; 60 s cold. ⛔ `lan-litellm` binds `oldsrv_home_ip:4000`, so the unauthenticated form publishes the spend ledger to the whole LAN. ⚠ Counts only traffic that passes a gateway — never the direct harness leg (decision #26) |
| 9 | **HD-1122** | One authored panel, nothing else: the `llamacpp:*` names have no panel of their own on `homelab-llm` — add it in `scripts/ansible/build-llm-dashboard.py`, never by hand-editing the JSON, keeping the `by (job, instance)` join shape that makes a new target add a series rather than a dashboard. The `--metrics` flag behind `ai_tier_metrics_publish` (`group_vars/home_servers.yml`) and the RX 7600 `amdgpu` sysfs counters are **in the tree and on the box — no flip is owed here**, and nothing on this row waits on a `docker_services` recreate | ⛔ The family is `llamacpp:` (colon), read off the live `/metrics`: `{__name__=~"llama_.*"}` answers ZERO, so a query or rule written with the `llama_` prefix matches nothing, in silence. The engine-count readiness panel's own expression is `count(up{job=~"vllm\|sglang\|llama-cpp"})` — embed and reranker are two targets with one `up` each, so that panel moves **1 → 3**; never quote 1 → 2. The whisper.cpp leg and the `ollama` rung appear in no scrape target: they stay rungs, not rows. ⛔ no `textfile` dir (unusable on this Alloy build) — the host ships no `rocm-smi` and the GPU counters publish through the collector's direct-publish leg |
| 10 | **HD-377** | Re-render `homelab-llm` for the owner's sign-off; on sign-off, delete the three superseded vLLM board JSONs and re-converge `--tags monitoring` | ⛔ The merged board is **generated** — chain is upstream → `scripts/ansible/adapt-vllm-dashboards.py` → `scripts/ansible/build-llm-dashboard.py` (`--check` is the CI form); never hand-edit `homelab-llm.json`. Guards that keep it honest: the picker must join with `=~` (All → `.*`, and `=` is equality → zero series), a joined `{__name__=~"a\|b"}` selector must not carry one engine's label, and a `sum()` across two engines is not a metric |
| 11 | **HD-1182** (P1) | Give HA a liveness rule that can fire again — while the `ha_exporter` job is gated **no rule can fire for HA on any axis**: flip the gated job and land its bearer-token-file mount in the same change (`roles/monitoring/tasks/main.yml` gates both on one flag), then prove `up{job="ha_exporter"}` and author the rule; HD-439(b)'s KNX-forwarding detection waits on this same job and can ride it. Converge is the **VPS** `--tags monitoring` half | ⛔ Never by re-adding the never-resolvable probe target (`ha.kogler.si` has no public record, so the prober's `probe_ip_protocol` is 0 forever and a permanently-red CRITICAL is how a class gets muted). ⚠ `alloy_ha_exporter` is declared **only** in `group_vars/vps.yml` while the scrape block sits in the **oldsrv** half of `alloy.river.j2` — set it where oldsrv reads it, or the flip renders nothing. The `ha_api` **vault** half is done; the owner half is **PARKED** with its exact action (O4): prune HA's **Long-lived access tokens** list to exactly one entry in the HA UI — a vault write never revokes its predecessor, so until that click happens the rotation is not closed |
| 12 | **HD-14** | Enable the HA Prometheus exporter — filed under smart-home by the docs, but the **work is this lane's**: it is the same `ha_exporter` job HD-1182 needs, so land the exporter, the scrape job and the rule as one change and cross-name the dependency in both rows | The credential is in the vault; what this row still waits on is the machine half (the gated `ha_exporter` job, item 11) and HD-1182's owner prune of HA's long-lived-token list. An exporter nothing scrapes closes nothing. Do not let it be reported as a smart-home act — the smart-home lane owns the HA instance, this lane owns its observability |
| 13 | **HD-1166** | The target-naming half is taken — `instance` in the **target map** (shape (a)): `__param_target` is a query parameter and never becomes a label, and a `prometheus.relabel` runs after the scrape, so there is nothing there left to move. What is left is the acceptance half the row set and never met: see the **ICMP** page naming a HOST fire once — close it on the next real host-down, or in an owner-present window where one probe path is deliberately blocked | Print `count by (job, instance) (probe_success)` beside the close — that read is the proof, a rule that exists is not. The retired HA target and the deleted rule are **applied on the VPS** (one `--tags monitoring`, no UI mute and no ledger-style suppression), so `public-service-down` has no HA series left to match and that CRITICAL cannot re-fire. The HA liveness that removal exposed is **HD-1182**, not a loose end here |

## ⛔ Traps that cost a round

* **Positive instruments only.** A webhook that returned 200, a rule that exists, a timer that is enabled and a container that
  is `Up` all coexist with an alerting path that does not deliver. The proof is the event in the room, read back.
* **The canary form that cannot fire:** `systemd-run --unit=hd450-canary.service` is invisible to the hygiene exporter (an
  unlisted unit), so it proves nothing. The working trigger is the collector-silence recipe in
  [docs/observability.md](docs/observability.md) §Silent-failure hygiene — and `hygiene-collector-stale`
  (`IaC/ansible/roles/monitoring/vars/main.yml:46`) is the rule that catches the silence.
* **Some reads answer and some lie** for the rule plane: the ruler API, the datasource proxy and the collector's local
  `:9098` answer; `/api/v1/rules` 404s and a direct VictoriaMetrics `:8428` query 400s. The recipe is in the doc — do not
  re-derive it, and do not conclude "no rules loaded" from the wrong endpoint.
* **Rule uid changes need a redeploy of the rule file**, and Grafana counts what the file provider holds: quote the five
  `homelab_*` rules from the live instance, not from the repo.
* **The `textfile` collector is unusable on this Alloy build** — the hygiene collector publishes directly, which is why the
  heartbeat is a metric and not a file. Do not "simplify" it back to textfile.
* **NUT**: the exporter reporting unit results is not the claim "this client can reach the master" — a loopback-only window
  passes between converges. Assert the client→master path explicitly.
* **Dashboards are generated, not hand-edited** (`build-llm-dashboard.py`, `adapt-vllm-dashboards.py`, and the render map for
  generated docs). A hand-edit is lost on the next rebuild and hides the guard bug that produced the gap.
* VictoriaLogs' image is tool-less: its `wget` healthcheck could never exec (false `unhealthy`) — it was removed on purpose.
  Cover it with datasource health + `up{job="victoria-logs"}`, never by re-adding a healthcheck.
* GB10 exposes no VRAM counter and its DCGM profiling module refuses to load, so `SM active` / `tensor pipe` / `DRAM active`
  can never fill: those panels are deleted, not wired. Keep the six `DCGM_FI_DEV_*` signals that do work.

## Owns / never touches

**Owns:** `IaC/ansible/roles/monitoring/**` (rules in `vars/main.yml`, the hygiene collector, `files/dashboards/`, the Alloy
river template) and `IaC/ansible/templates/docker_services/{victoria-metrics,victoria-logs,grafana,n8n,mcp-victoriametrics,mcp-victorialogs,blackbox-exporter}/**`
as your rows name them, `scripts/ansible/build-llm-dashboard.py`, `scripts/ansible/adapt-vllm-dashboards.py`, the `alloy_version` /
`victoria_*` / `mcp_*` regions of `group_vars`, and your own `todo.md` rows.
**Owns additionally for the telemetry rows:** the `--accesslog` hunk in
`templates/docker_services/spark-dashboard/**`, the one `--metrics` line in each of
`templates/docker_services/{embed,reranker}/**`, and `templates/docker_services/{litellm,lan-litellm}/**` **only** for a
metrics flag HD-1121's probe proves necessary — the gateway internals, keys and model rows stay the litellm lane's.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; the Matrix **room/homeserver** provisioning beyond the
alert user this row names (the edge-identity lane owns Tuwunel and its OIDC); the VPS backup client and every Kopia/backup row
(HD-191 is the dependency, not your work); `roles/access`, `roles/cockpit` and the seat plane; LiteLLM gateway internals and
the spark LLM profile matrix (the spark lane owns the engine-side bench); traefik edges and the DNS answer plane;
`IaC/router/**` and the global router slot; the LLM engines themselves; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: an alert event read back from `#homelab-alerts` for a named canary — triggered by the collector-silence
recipe so the rule that catches a deliberate silence fires with it — with the SMTP fail-safe still configured and the Signal
demotion stated as the remaining step or done · every monitoring
host's running Alloy == the `alloy_version` pin (quote the var, never the number it carried) with `up{job="alloy"}` after
the restart, or the host that refused and the failing task quoted · the MCP endpoints registered in each named consumer, ports taken from the vars · HD-342's tail phrased as the HD-191
dependency, with no include-list edit · the wifi-reg source named from a live router answer · the two board render-verifications
either owner-signed or `PARKED` with the URL and board list, and the vLLM trio deleted only in the same change as the sign-off ·
HD-1120's per-client read named by path (Home vs tailnet) with the XFF decision stated, and no per-client **token** counter
shipped · HD-1121 with `up{job="litellm"}` on both instances and one named series quoted, or the no-surface finding written ·
HD-1122 with the authored `llamacpp:*` panel boarded and the engine-count panel read at its own expression (3, once both
GGUF legs are scraped) · HD-1166 closed on a real host-down with `count by (job, instance) (probe_success)` beside it ·
rows trimmed to their tails or deleted, no history in the row · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
