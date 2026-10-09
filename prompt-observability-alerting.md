# `prompt-observability-alerting.md` — Lane brief · silent-failure rules, Matrix alerting, boards

> **Role:** dispatch note for **one** lane session on the observability + alerting domain. **The rows are the authority**
> for what is missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-450 · HD-1108 · HD-342 · HD-344 · HD-315 · HD-343 · HD-377 · HD-1094 · HD-1120 ·
> HD-1121 · HD-1122** (row ids as of `939ad5e7` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
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
another oldsrv lane. Land those two hunks in a clean window; the scrape jobs themselves are monitoring-only and always safe.

**Read first:** [docs/observability.md](docs/observability.md) → §Alerting → §Silent-failure hygiene → §Component Table →
§Network Clients Dashboard → §LLM Dashboard → §MCP · [docs/services-matrix.md](docs/services-matrix.md) §Alert room ·
[docs/backup.md](docs/backup.md) §VPS-side coverage gap · [docs/deployment-ansible.md](docs/deployment-ansible.md).

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-1108** | Deliver the existing Grafana → n8n chain into a dedicated `#homelab-alerts` room on the live Tuwunel (room + dedicated alert user, token from the vault per the doc's §6 rule, never a literal), keep Grafana-native **SMTP fail-safe running in parallel**, then demote `signal-cli-rest-api` — last step, not the first | Acceptance is a **delivery proof, never a webhook `200`**: read the room's event for the canary, not the workflow's status. Both `onError: continueRegularOutput` mutes must stay removed on the new leg |
| 2 | **HD-450** | Three items: (a) make leg (c) a METRIC — "this client can reach the NUT master", not the units' last result; (b) export the VPS **box** cert (acme.sh) as a series so a rule becomes possible at all; (c) re-point this row's alert leg at the Matrix channel when HD-1108 lands | Until HD-1108 lands, Signal is the path this leg reads — **do not extend the Signal surface**. ⛔ Never mute the class by tolerating a non-zero rc in the pull script: rc 90 is the self-pull guard and must stay loud. Thresholds are WARN `< 14` / CRIT `< 7` days (`IaC/ansible/roles/monitoring/vars/main.yml:215`, `:34`), re-derived from the measured 90-day pair — 30/14 fires before every scheduled renewal |
| 3 | **HD-1094** | Fleet-wide pin is **`alloy_version: "1.20.1-1"`** (`IaC/ansible/group_vars/all/versions.yml:347`) with no per-host override left in `host_vars/`, so the decision is taken — what remains is proof: each monitoring host's **running** Alloy version equals the pin, and `up{job="alloy"}` still flows after its restart | ⛔ Never add `--allow-downgrades` — it silently downgrades any package whose pin lags the box. A version read from `dpkg` is not a health read: the restart drops one scrape cycle, so quote the series too |
| 4 | **HD-344** | Register the two MCP endpoints in the consumers that should see them (the pi harness, Open WebUI, OpenClaw); the tailnet redo is an owner leg | Use the vars — `mcp_metrics_port: 8083` / `mcp_logs_port: 8084` (`IaC/ansible/group_vars/all/main.yml:747`, `:748`), bound to `oldsrv_home_ip`. ⛔ Never a literal `:8080`/`:8081` — 8080 is pi-dev's |
| 5 | **HD-342** | The only open tail is off-site protection for `/srv/docker/victoria-{metrics,logs}/data`, and it belongs to the VPS backup client (HD-191): name the dependency in the row, do not add paths to an include list | ⛔ The VPS runs `kopia-server` — the repository endpoint — and has **no client of its own** (no binary, no client config, no `kopia-agent` entry). Wiring two paths to a nonexistent client is the fiction [docs/backup.md](docs/backup.md) warns about |
| 6 | **HD-343** | Verify the live wifi source (`/interface/wifi/registration-table` vs the legacy path) against what the RB4011 actually answers, then render-verify the board on `stats.kogler.si` | The exporter runs in a dedicated venv with its own pinned `routeros-api` because trixie ships no `python3-routeros-api`; the unit runs `networkclients` with `0750 root:networkclients` (`0700 root` breaks the unprivileged unit). Read the union `/metrics` before touching the join |
| 7 | **HD-315** | Render-verify the technical boards **with data** (host overview, probe tables) — the metric-name work is done, the eyeball is not | Owner leg → park with the exact URL + board list (O4). An empty panel is a question, not a verdict: check the series exists in VM before calling a panel broken |
| 8 | **HD-1120** | Attribute LLM traffic **at the edge** (the metering-proxy shape is rejected, owner 2026-10-09): read which peer the spark edge logs on each path, enable `--accesslog=true` on `traefik-spark`, deliver a per-client VictoriaLogs read | ⛔ Measure the peer address **before** building: the tailnet path arrives through `traefik-tailnet` over WG S2S, so without XFF preserved **and** trusted every tailnet client logs as the tunnel hop and the table collapses to one healthy-looking row. ⚠ Tokens are NOT in the access log — per-client tokens stay a labelled estimate, never a counter. ⚠ No HD-280-style host bind (that exists for fail2ban); stdout already reaches VictoriaLogs |
| 9 | **HD-1121** | Scrape the two LiteLLM gateways (`litellm` VPS + `lan-litellm` oldsrv) so gateway-side token/spend usage is in VM at all | **Probe the pin first** — if the pinned image publishes no Prometheus surface, the finding is the deliverable, not a config guess. Quote names from the live render; explicit `job`/`instance` so the two instances never merge; 60 s cold. ⚠ Counts only traffic that passes a gateway — never the direct harness leg (decision #26) |
| 10 | **HD-1122** | Make the oldsrv serving tier report: llama.cpp `--metrics` on `embed`/`reranker` (verify the flag on the pin, read-only, first), then the RX 7600 counters from `amdgpu` sysfs | The host ships no `rocm-smi`; publish through the collector's direct-publish pattern — ⛔ no `textfile` dir (unusable on this Alloy build). Acceptance moves the board's engine-count readiness panel from **1 → 2**; if it cannot move, correct the panel text instead of leaving the claim |
| 11 | **HD-377** | Re-render `homelab-llm` for the owner's sign-off; on sign-off, delete the three superseded vLLM board JSONs and re-converge `--tags monitoring` | ⛔ The merged board is **generated** — chain is upstream → `scripts/adapt-vllm-dashboards.py` → `scripts/build-llm-dashboard.py` (`--check` is the CI form); never hand-edit `homelab-llm.json`. Guards that keep it honest: the picker must join with `=~` (All → `.*`, and `=` is equality → zero series), a joined `{__name__=~"a\|b"}` selector must not carry one engine's label, and a `sum()` across two engines is not a metric |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

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
as your rows name them, `scripts/build-llm-dashboard.py`, `scripts/adapt-vllm-dashboards.py`, the `alloy_version` /
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
not run. Concretely: an alert event read back from `#homelab-alerts` for a named canary, with the SMTP fail-safe still
configured and the Signal demotion stated as the remaining step or done · the NUT reachability series present and the VPS box
cert exported as a series (or the exact blocker for it) with a rule that fires on a deliberate silence · every monitoring
host's running Alloy == `1.20.1-1` with `up{job="alloy"}` after the restart, or the host that refused and the failing task
quoted · the MCP endpoints registered in each named consumer, ports taken from the vars · HD-342's tail phrased as the HD-191
dependency, with no include-list edit · the wifi-reg source named from a live router answer · the two board render-verifications
either owner-signed or `PARKED` with the URL and board list, and the vLLM trio deleted only in the same change as the sign-off ·
HD-1120's per-client read named by path (Home vs tailnet) with the XFF decision stated, and no per-client **token** counter
shipped · HD-1121 with `up{job="litellm"}` on both instances and one named series quoted, or the no-surface finding written ·
HD-1122 with each new `up` quoted and the engine-count panel moved to 2 (or its text corrected) ·
rows trimmed to their tails or deleted, no history in the row · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
