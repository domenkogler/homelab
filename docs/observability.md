---
title: Observability
domain: observability
role: ssot
status: active
tags: [observability, grafana, prometheus, monitoring]
---
# Observability

> **Role:** Single source of truth — the complete observability stack as a domain (VictoriaMetrics/VictoriaLogs/Grafana + Alloy/exporters + alerting).
> **Links to:** `interfaces.md`, `deployment-ansible.md`, `smart-home.md`, `backup.md`, `services.md`
> **Linked from:** `index.md`, `interfaces.md`, `services.md`

> **Status: 🟢 live.** The backend is the **Victoria stack on the VPS** — **VictoriaMetrics** (metrics,
> 365 d) + **VictoriaLogs** (logs, 90 d) + **Grafana** + blackbox-exporter, all on the tailnet-only edge.
> Prometheus and Loki are gone. Collectors: **Alloy** per host (VPS loopback, oldsrv, and — pending — nas +
> Pi), oldsrv's SNMP + network-clients exporters, RouterOS syslog over RFC5424, `nut_exporter` on nas,
> `zfs_exporter`, blackbox probes. Alerting: **Grafana → n8n (`homelab-alerts` webhook) → Signal + email**,
> with Grafana-native SMTP in parallel as the fail-safe.
>
> ⏳ **Open:** the **nas + Pi Alloy collectors** (converge adds their `node_*` to the Host Overview),
> **Signal delivery** (no linked device yet — HD-318d; until then the Signal leg silently delivers nothing
> and email is the only working channel), contact-point/datasource passwords in the HD-211 rotation batch,
> device-side SNMP enablement (HD-03 cutover), and the Kopia wiring for
> `/srv/docker/victoria-*/data`. The spark host-memory alert rules (HD-375) are **closed 2026-09-22** — see
> §Alerting.

---

## Architecture

```
Alloy (host agent: metrics + logs + SNMP, has docker.sock)  ← the SINGLE scrape tier (topology B)
   ├─ remote_write ──▶ VictoriaMetrics (THE metrics store, 365d)
   └─ push ──────────▶ VictoriaLogs   (logs, 90d)
Dozzle viewers (read-only docker.sock) ──▶ live per-container log tail (ops, no storage)
   ├─ VPS viewer (logs.kogler.si, tailnet) — VPS containers
   └─ OLDSRV HUB (llogs.kogler.si, :8081, LAN/internal edge) ──agents──▶ pi + spark containers
Home Assistant (SWO-B + ComfoAir) ──HA exporter──▶ Alloy scrape ──▶ VictoriaMetrics
MikroTik (SNMP, 5–15s poll) ─────────────────────────────▶ Alloy scrape ──▶ VictoriaMetrics
blackbox_exporter (external reachability) ───────────────▶ Alloy scrape ──▶ VictoriaMetrics  (probe_success)
nut_exporter (UPS, on nas) ──────────────────────────────▶ Alloy scrape ──▶ VictoriaMetrics  (battery/runtime/voltage)

                        VictoriaMetrics ──▶ Grafana (stats.kogler.si, internal, Authentik admin-only)
                                                  │  webhook
                                                  ▼
                                                n8n (alert router: dedup / tier / format)
                                                  ├──▶ signal-cli → Signal "Homelab Alerts" group
                                                  └──▶ SMTP → email
                               Grafana-native SMTP = fail-safe, parallel
```

- **Single source of truth** for every type of data; no redundant backends.
- **Display:** Grafana (admin analytics) + Homepage (status widget — reachability eyeball view).
- **Removed from earlier drafts:** InfluxDB, Telegraf, Promtail, Uptime Kuma — none are used.

### The Victoria stack (HD-341/342) — the shape and why

**One** metrics store (**VictoriaMetrics**, `victoriametrics:8428`) + **one** log store
(**VictoriaLogs**, `victoriametrics-logs:9428`), both on the **VPS**, with **many writers** (Alloy
collectors on VPS/oldsrv/nas/Pi, blackbox/nut/zfs exporters, MikroTik syslog) remote-writing into them.
**Grafana stays** in front of both. **MCP AI-debugging servers run on oldsrv** (much more RAM there) and
point at the VPS endpoints over wg-s2s — **storage stays on the VPS, tooling stays at home.**
Research + rationale: [`brainstorming/recent/Prometheus-Vs-victoriastack.md`](../brainstorming/recent/Prometheus-Vs-victoriastack.md).

```
Alloy (host agent: metrics + logs + SNMP) ──remote_write──▶ VictoriaMetrics (VPS, metrics)
Alloy (logs) ───────────────────────────────push─────────▶ VictoriaLogs   (VPS, logs)
MikroTik (SNMP / syslog) ────────────────────────────────▶ VictoriaMetrics / VictoriaLogs
blackbox / nut / zfs exporters ─────────────scrape/remote─▶ VictoriaMetrics

VictoriaMetrics ──▶ Grafana (stats.kogler.si)  ──webhook──▶ n8n → Signal + email
VictoriaLogs    ──▶ Grafana (logs datasource)

mcp-victoriametrics / mcp-victorialogs (on OLDSRV, RAM) ──wg-s2s/tailnet──▶ VPS Victoria endpoints
```

- **Writers stay on home infra** (oldsrv/nas/Pi Alloy + exporters), buffering over wg-s2s; the **single backend is on the VPS** (reliability).
- **MCP AI servers on oldsrv** (≈600–700 MB RAM each) — not on the VPS, not on the Pi.
- **Dozzle is kept alongside VictoriaLogs.** They are different tools: Dozzle is a live per-container tail
  with no storage, VictoriaLogs is the searchable 90-day store. Replacing one with the other loses an
  operator reflex, so both stay — but Dozzle must never become a second log backend.

### MCP AI-debugging servers on oldsrv (HD-344) — implemented form

> **Status: ✅ live** — two `docker_services` on **oldsrv**, `mcp-victoriametrics` (`:8083`) and
> `mcp-victorialogs` (`:8084`), fronting the VPS Victoria backend for AI tools (pi, Open WebUI, OpenClaw).
> They require the VPS backend to be reachable, which is why they were deploy-gated until the Victoria
> stack landed.

- **Endpoint reachability — wg-s2s now, tailnet later.** The MCP servers point at the VPS
  backend via `victoria_backend_host` (group_vars/all/main.yml), which **defaults to
  `wg_s2s_vps.ip`** — the same guaranteed-reachable tunnel the Alloy collector uses. The
  owner plans a full s2s-wg→tailnet redo (future HD): that redo re-plumbs **this one var**
  to the VPS tailnet address and the compose needs no other change. **No VPS tailnet IP
  exists in the SSOT yet — do not invent one** (see network-vpn.md before the redo).
- **Exposure — LAN/tailnet-only, never public/WAN.** Ports publish on oldsrv's Home-VLAN
  address (`oldsrv_home_ip`, actual-budget :5006 / immich-ml :3003 precedent); the future
  tailnet redo adds a Pattern-A sidecar. **No traefik-public labels, no `public: true`.**
- **Auth — Basic to the backend, network gate to the client.** The MCP server (`http` mode)
  has **no native auth**; each container sends `Authorization: Basic <b64(user:pass)>` to
  the VPS backend from the `victoria-metrics_api` / `victoria-logs_api` 1P items
  (`VM_INSTANCE_HEADERS` / `VL_INSTANCE_HEADERS`). The client-facing gate is the
  Home-VLAN-only bind + (future) tailnet ACL — **do not expose on the WAN edge**.
- **Images (pinned, CONVENTIONS §7):** `mcp_victoriametrics:v1.18.0` + `mcp_victorialogs:v1.8.0`,
  Renovate-tracked.
- **Registry:** oldsrv `docker_services` rows with `enabled: true`.

#### Wiring AI tools (pi, Open WebUI, OpenClaw)

Each AI client registers the MCP server as a **Streamable HTTP** MCP endpoint pointing at
the oldsrv MCP listen address (`http://oldsrv:8083` metrics / `:8084` logs). The MCP
servers carry the backend auth themselves, so the client config carries **no secrets**.
All endpoints are **LAN/tailnet-only** (deploy-gated on the hosts above).

- **pi (pi.dev)** — add an MCP server entry in the pi agent config pointing at
  `http://oldsrv:8080` (metrics) / `http://oldsrv:8081` (logs), transport `http` (SSE
  alias for Streamable HTTP). Exact config lives in `pi-agent/` prompts/extension docs
  once the service is live; authoring placeholder here (HD-344 tail).
- **Open WebUI** — register both as **Tools** (Admin → Tools → MCP) with `url:
  http://oldsrv:8080` / `http://oldsrv:8081` (Streamable HTTP), tagged for the internal
  `ai.kogler.si` instance so agent-role users can query metrics/logs.
- **OpenClaw** — add both MCP servers to the OpenClaw MCP config (`http://oldsrv:8083` /
  `:8084`), gated to the same tailnet/LAN path.
- ⏳ **Concrete client config files are authored here once the backend (HD-342) + oldsrv
  (HD-318) are live** — the URLs above are the SSOT contract; the client-side config is
  environment-specific and lives with each tool (services-ai.md).

---

## Component Table

| Layer | Service | Role | Network | Retention |
|-------|---------|------|---------|-----------|
| Agent | **Alloy** (per-node: vps/oldsrv/nas/pi) | Host metrics + logs + SNMP (oldsrv only for SNMP/network-clients); replaces Promtail/Telegraf/scraper | host (`docker.sock`) → `services-internal` | — |
| Backend | **VictoriaMetrics** | Sole metrics store (pure storage/query — Alloy does ALL scraping, topology B) | `db-internal` | 365d (Kopia-backed) |
| Backend | **VictoriaLogs** | Log aggregation, single-node/SSD | `db-internal` | 90d (Kopia-backed) |
| Exporter | **blackbox** | External reachability (`probe_success`) | `services-internal` | in VictoriaMetrics |
| Exporter | **HA exporter** | HA entities → VictoriaMetrics (Alloy scrape, gated `prometheus_ha_exporter`) | `services-internal` | in VictoriaMetrics |
| Exporter | **nut_exporter** | UPS status (battery/runtime/voltage/load) → VictoriaMetrics · single instance on **nas** (NUT master) | `services-internal` | in VictoriaMetrics |
| ~~Exporter~~ | ~~**minio_exporter**~~ | ~~MinIO S3 store~~ — **retired (HD-135): Immich originals = live Hetzner Box (CIFS), not S3/MinIO** | — | — |
| UI | **Grafana** | Dashboards, `stats.kogler.si` (**internal**) | `traefik-public` **+** `db-internal` | — |
| Router | **n8n** | Alert routing/dedup → Signal/email | `services-internal` | — |
| Notify | **signal-cli** | Signal delivery (linked device) | `services-internal` (needs internet) | — |
| Viewer | **Dozzle** | Live per-container log streaming (read-only `docker.sock`); **two instances** — VPS (`logs.kogler.si`, tailnet via `traefik-tailnet`) + home LAN hub on oldsrv (`llogs.kogler.si`, :8081, via `traefik-internal`, pi/spark remote agents :7007); **viewer only — nothing stored** | `traefik-public` | — |

## Access & login path (stats.kogler.si)

**Tailnet-only:** the observability dashboards (`stats`/`traefik`/`logs`/`llogs`/`csui`/`auto`
and by extension the underlying victoria-metrics/victoria-logs/blackbox) have **no public DNS record** and are **not
WAN-reachable**. They are reached over the **headscale tailnet** from admin devices via the
**`traefik-tailnet` edge** (node `vps-obs`) — a consumer-mode Traefik (+ userspace tailscale sidecar
sharing its netns) that serves the dashboards with **clean subdomain URLs** and no port numbers
(see [`network-vpn.md`](network-vpn.md) §Tailnet-exposed services and the `docker_services/traefik-tailnet`
compose):

| App | URL (tailnet) |
|-----|---------------|
| Grafana (`stats`) | `https://stats.kogler.si` / `https://stats.ts.kogler.si` |
| Dozzle (`logs`) | `https://logs.kogler.si` / `https://logs.ts.kogler.si` |
| Dozzle home hub (`llogs`) | `https://llogs.kogler.si` (**LAN-only** — oldsrv `traefik-internal` edge, WAN-out survival; shows oldsrv + pi + spark containers) |
| CrowdSec Web UI (`csui`) | `https://csui.kogler.si` / `https://csui.ts.kogler.si` |
| Traefik dashboard (`traefik`) | `https://traefik.kogler.si` / `https://traefik.ts.kogler.si` |
| n8n (`auto`, **internal-only**) | `https://auto.kogler.si` / `https://auto.ts.kogler.si` |

The plain `*.kogler.si` names resolve via headscale MagicDNS (`dns.search_domains: [kogler.si]`, and **`dns.nameservers` must put the MagicDNS loop `100.100.100.100` FIRST** — HD-371) and carry
**Authentik Forward-Auth** (same chain as the public edge). The `*.ts.kogler.si` MagicDNS twins are
**ACL-gated** (no forward-auth — the headscale ACL `tag:sidecar:443` is the gate; tailnet-only by
construction). The public CNAMEs from the Phase-1 wave are removed from the IaC SSOT and deleted from
Cloudflare at deploy time (owner action).

> **Why the loop must come first (HD-371).** With only the Technitium VPS primary in `dns.nameservers`, a
> tailnet device on a foreign network (mobile hotspot) sent `stats.kogler.si` to the system resolver →
> NXDOMAIN → `ERR_NAME_NOT_RESOLVED`, while `stats.ts.kogler.si` still resolved and the phone on the same
> hotspot worked (its client-side MagicDNS `extra_records` answered). Ordering the MagicDNS loop first
> resolves **both** namespaces locally on any network. Symptom shape to remember: "one suffix works, the
> other does not, and it depends on the network you are on" is a **resolver order** bug, not a routing bug.

Forward-Auth (Traefik chain) still gates the route; Grafana then auto-logs-in via `[auth.proxy]`,
trusting the `X-authentik-email` header ONLY from the pinned Traefik edge IP (`traefik_edge_ip_pin`
via compose `ipv4_address`, whitelisted through `GF_AUTH_PROXY_WHITELIST` = `traefik_edge_ips`).
The native login form is disabled (`GF_AUTH_DISABLE_LOGIN_FORM`), so a **logo-only bare `/login`
page means Grafana rejected proxy auth** — either a whitelist/edge-IP mismatch or no matching user:
`AUTO_SIGN_UP` is off by design (HD-190), so every user must be mapped explicitly via the
break-glass admin API before SSO works for them. Two operational caveats learned live (HD-240):
Docker's dynamic bridge assignment can silently drift the edge IP off the whitelist (pin prevents
it), and Grafana provisioning does NOT overwrite `secureJsonData` of an EXISTING datasource — a
rotated datasource password must be re-applied via delete+recreate with the same uid or an API
update, or queries keep 401-ing despite correct rendered files.

---

## Single Source of Truth Matrix

| Data | Owner | Where it lives |
|------|-------|----------------|
| Host + SNMP metrics | per-node Alloy (vps/oldsrv/nas/pi host exporters) + oldsrv SNMP → VictoriaMetrics | VictoriaMetrics (365d, Kopia) |
| Service scrape (Traefik, CrowdSec) | Alloy (VPS loopback) → VictoriaMetrics | VictoriaMetrics (365d) |
| HA entity metrics (weather, ComfoAir) | HA exporter → Alloy → VictoriaMetrics | VictoriaMetrics (365d) |
| External reachability | blackbox → Alloy → VictoriaMetrics | VictoriaMetrics (365d) |
| UPS status (battery, runtime, voltage, load, online/on-batt) | nut_exporter (on nas) → Alloy → VictoriaMetrics | VictoriaMetrics (365d) |
| Logs | Alloy → VictoriaLogs | VictoriaLogs (90d, Kopia) |
| RouterOS logs (RB4011/switch/AP) | RFC5424 syslog → VPS rsyslog → CrowdSec/VictoriaLogs | VictoriaLogs (90d) (HD-313) |
| Live logs (ops day-to-day tail) | Dozzle viewers — VPS `logs.kogler.si` (tailnet) + home hub `llogs.kogler.si` (LAN, oldsrv, pi/spark agents) | ephemeral — nothing persisted |
| Alerts | Grafana Alerting → n8n → Signal/email | alert delivery |
| Display | Grafana + Homepage | — |

---

## Alerting

- **Engine:** Grafana Unified Alerting (rules live with the data; no separate Alertmanager).
- **Router:** alerts → n8n webhook → normalize / dedup / tier / format → Signal + email. n8n also serves office automation ([`services-office.md`](services-office.md)).
- **Webhook:** Grafana's contact point posts to `grafana_alert_webhook_url` (group_var, default `http://n8n:5678/webhook/homelab-alerts`, traefik-public). ⚠ The n8n workflow **`homelab-alerts`** on that route must exist before the first alert fires (created at n8n setup; payload = Grafana alert-notification webhook, see the monitoring role `grafana-contactpoints.yml.j2`).
- **Fail-safe:** Grafana-native SMTP contact point runs in parallel — alerts still go out if n8n/signal-cli is down.
- **SMTP relay (HD-54, Option B — decided):** SMTP2Go (`mail-eu.smtp2go.com:2525`, STARTTLS). Dedicated transactional relay, free-tier 1000/mo, chosen independently of the Infomaniak kSuite decision (HD-30) so the alert fail-safe isn't coupled to personal email. Grafana + NUT share it; creds = `smtp_login` / `smtp_login` (Login items in 1Password). Rotating `smtp_login` means re-converging **every** consumer and verifying the rendered value: VPS
  Grafana (compose env), Pi + oldsrv HA (`secrets.yaml`), and **NUT `upssched-cmd` on nas**, which embeds it
  **inline** (see [hardware-ups.md](hardware-ups.md)).
  - **Connecting (SMTP2Go, EU datacenter — as provided by the account):** server `mail-eu.smtp2go.com`; SMTP port `2525` (default), alternates `8025`, `587`, `80`, `25` — **TLS available on the same ports** (STARTTLS). SSL: `465`, `8465`, `443`. The repo uses `mail-eu.smtp2go.com:2525` + STARTTLS (**587 is blocked from the VPS egress** — verified live — so **2525 is the SSOT port**, not 587).
- **Signal:** `signal-cli-rest-api` container, **linked** to Domen's personal number (no second SIM), sends to a dedicated **"Homelab Alerts"** group. Persist the Signal identity volume so it doesn't need re-linking. **Recipient value (owner confirmed 2026-09-21, HD-347): alerts go to the WHOLE group, and `signal_alert_recipients` takes the group ID that signal-cli reports** (read it from the linked daemon on oldsrv, read-only) — **not** the group's invite link, which is an encrypted join blob and not a recipient the API accepts.

### Operational gotchas (learned live — the rules that keep them from coming back)

**Grafana**

- **`read_only: true` breaks Grafana 13's bundled-plugin installer.** Grafana 13 keeps bundled plugins —
  **including `prometheus`, the datasource that talks to VictoriaMetrics** — in the image layer at
  `/usr/share/grafana/data/plugins-bundled` and re-installs them on every start; the installer must
  `unlinkat` that directory, which fails under the hardening flag, leaving the plugin **unregistered**:
  empty panels, `/api/datasources/uid/prometheus/health` → 404 `Plugin not registered`, and every rule
  erroring `plugin.notRegistered` (~2.5 k failed evals). **Fix = one env line,
  `GF_PLUGINS_PREINSTALL_DISABLED: "true"`** (the setting the image ships), so plugins load in place and
  `read_only: true` stays. **Diagnosis shortcut:** a datasource plugin installed into the **writable**
  `/var/lib/grafana/plugins` (like `victoriametrics-logs-datasource`) stays healthy — that contrast is the
  whole diagnosis. On any `grafana_version` bump: re-check preinstall **before** widening `read_only`.
- **Provisioning does NOT overwrite `secureJsonData` of an existing datasource.** A rotated datasource
  password must be re-applied by delete+recreate **with the same uid** (or an API update) — otherwise
  queries keep 401-ing while the rendered files look perfect.
- **Pin the edge IP.** Docker's dynamic bridge assignment silently drifts the Traefik edge address off
  `GF_AUTH_PROXY_WHITELIST`, which reads as "SSO stopped working after an unrelated redeploy".
- **`noDataState` is the loudest footgun in the stack.** A rule whose PromQL matches **no series** fires a
  synthetic `DatasourceNoData` alert on every evaluation. That is a **collection gap, never a condition**:
  real-condition rules take `noDataState: OK` (or `NoData`) + `execErrState: Error`; only self-monitoring
  rules (`victoria-*-down`, `wg-s2s-down`) keep `Alerting`. Anything whose series may legitimately be
  absent (UPS metrics while healthy, `probe_ssl_earliest_cert_expiry` — blackbox does not emit SSL expiry,
  SNMP interfaces before SNMP ships) must be set explicitly, not left at the default.
- **Alert rules must match the live backend.** After a backend migration, orphan rules survive in the live
  Grafana DB (provenance = file, but absent from the rendered rules file). Delete orphans after any
  backend change — a stale `prometheus-down` rule alerts about a component that no longer exists.

**Rules + exporters**

- **The evaluator has to match the expression.** Rules templated with a hardcoded `gt 0` can never fire for
  `expr: X == 0` (`*-down`, `host-unreachable`, `wg-s2s-down`) — the rule is silently dead, which is worse
  than a missing rule. The template carries `eval_type` per rule; `== 0` rules use `lt` with `[1]`.
- **Self-scrape needs the backend's auth.** Without `victoria-metrics_api` / `victoria-logs_api` basic auth
  on the self-scrape jobs, `up{job="victoria-metrics"}=0` permanently — which reads as "monitoring is down"
  and trains everyone to ignore it. Same class: a blackbox self-target pointed at `/probe` instead of
  `/metrics` is dead, not degraded.
- **SNMP interface names need two things at once.** The `ifName` OID must be in the module's `walk` list
  **and** the lookup must declare `type: DisplayString`; otherwise labels are missing (`interface [no value]`)
  and values render as hex (`0x65746865…`). Give each device its own `instance` label or two devices
  collapse into one flat series.
- **Do not alert on intentionally-empty state.** A `mikrotik-link-down` rule fired on every unpatched switch
  port (ten simultaneous instances on ports with no cable). Unprovisioned is not incident-worthy: alert on
  the loss of a link that carries something.

**Alert delivery**

- **The n8n workflow must exist and be ACTIVE before the first alert** — otherwise the Grafana contact point
  hits `POST /webhook/homelab-alerts` → 404 and nothing is routed. It is versioned at
  `roles/monitoring/files/n8n/homelab-alerts.workflow.json` and created/activated through the n8n public API
  (`n8n_api`, `POST /api/v1/workflows` + `/activate`). Verify with a POST expecting
  `200 "Workflow was started"`.
- **A missing Signal device is silent by design.** The Signal HTTP step uses
  `onError: continueRegularOutput` so an unlinked `signal-cli` cannot break email delivery — which also
  means **no alert ever proves the Signal leg works**. Linking the "Homelab Alerts" device is an owner
  action (HD-318d); until then email is the only proven channel.
- **`signal-cli-rest-api` is published on `{{ oldsrv_home_ip }}:8082`** because the alert brain (n8n) runs on
  the VPS and cannot resolve an oldsrv-only overlay name — the cross-host API-leg pattern (precedents:
  actual-budget `:5006`, immich-ml `:3003`). **`:8080` belongs to something else**, which is exactly how the
  collision was found; auth stays mandatory (`X-Api-Key`, KOPS-002/HD-125).
- **Three converge-time traps that are repo rules:** every vault item a template reads must be declared in
  `_template_vault_items`, or the render dies with `dict has no attribute …`; Jinja `default()` fallbacks in
  YAML need single quotes, or the fallback renders nested quotes and `docker compose config` fails; and a
  pinned image tag must be **verified to exist** in the registry before it lands (`1.9.0` vs `v1.9.0` is a
  failed pull on docker.io).

### spark host-memory (OOM) alert rules

The container memory cage cannot protect a GB10 host (GPU pages are not cgroup-charged) and Docker reports
`OOMKilled: false` on a host-side kill, so **host memory is the only early warning** there. Rules
`spark-host-mem-oom-warning` / `spark-host-mem-oom-critical`; the on-box enforcer is
`spark-oom-watchdog` (`roles/spark`: CRIT < 8 GiB → planned engine restart, max 2 per 2 h, arm-off file,
idle recycle at baseline +8 GiB).

- **Gauge: `usable = MemAvailable − CmaFree`** (`node_memory_MemAvailable_bytes -
  node_memory_CmaFree_bytes`, `job="alloy"`, `instance=~"spark.*"`). On GB10 the GPU carve is CMA and CMA
  counts as available, so raw `MemAvailable` **inflates as pressure rises** (by up to ~9.5 GiB here) — a
  threshold on it can never warn before the cliff. `MemFree − CmaFree` is the inverted alternative.
  Rationale + the incident series: [hardware-spark.md](hardware-spark.md) §Unified-memory budget and
  [spark-incidents.md](spark-incidents.md) #7/#8.
- **Thresholds are measured, not designed:** `WARN < 12 GiB for 2m` (`noDataState: OK`) /
  `CRIT < 8 GiB for 1m` (`noDataState: Alerting`). Both observed kills were at **1.62 / 1.64 GiB**, but the
  lowest value a 60 s scrape ever recorded inside those windows was **5.01** — a rule set at the kill point
  could not have fired. The sampling gap behind that sentence is its own row: **§Scrape cadence and metric
  resolution (HD-420)**.
- **Preflight before touching these rules:** confirm `node_memory_CmaFree_bytes` exists in VictoriaMetrics.
  It is **not** in node_exporter's default meminfo whitelist, and on a CRIT rule with
  `noDataState: Alerting` a missing series is a false-positive machine.
- **Operating point:** at the certified 16 GiB KV pool, idle `usable` is **18.5 GiB** (6.5 GiB of WARN
  margin) and the certified worst case bottoms at **17.78 GiB**. The thresholds still clear — but there is
  **no room for another KV raise in bf16**, because that would put WARN inside routine-transient range.
- ✅ **CLOSED 2026-09-22 (owner):** the two host-memory rules were taken as confirmed on the owner's call —
  the row is deleted from the backlog per CONVENTIONS §4(a); the record stays here. Deployed state unchanged:
  both rules load in the ruler (`vps.yml --tags monitoring`, failed=0, 2026-09-17 22:33C), CRIT
  `noDataState: Alerting`, and the WARN summary/label mismatch is fixed.

### Tiers

| Severity | What alerts | Channel | Notes |
|----------|-------------|---------|-------|
| **Critical** | oldsrv disk ≥90%, **nas ZFS pool usage ≥80% (`tank` & `bulk`)**, host down, ZFS pool degraded, service down >2min, `probe_success==0` · **UPS battery <20% or runtime <5 min (impending shutdown)** | Signal + email | page-worthy |
| **Warning** | container restart loop, high CPU/load, HA unreachable, MikroTik link down, **nas pool ≥70%** · **UPS on-battery / mains lost (auto-clear on return)** | Signal (deduped) | sent once |
| **Info** | transient / everything else · **UPS online ↔ on-battery transitions / restored** | logged only | no push |

- **Poke/throttle:** re-send only if still firing after ~30 min (prevents overnight alert floods).
- **Self-monitoring:** the observability stack itself (VictoriaMetrics/VictoriaLogs/n8n down) must alert — otherwise the alert channel dies silently.

---

## UPS / Power-Loss Monitoring (NUT)

- **Metrics (single source):** one **nut_exporter** on **nas** (the NUT master) reads local `upsd` → VictoriaMetrics (via Alloy scrape). Other hosts do **not** re-export identical UPS data (avoids redundancy).
- **Shutdown:** **NUT owns local shutdown** on `nas`, `oldsrv`, and `ha` (Raspberry Pi). Grafana/n8n are **alert-only** — there is **no shutdown action from Grafana** (the observability **backend is on the VPS**, so it must never be the thing that halts the NAS during a power cut; only the host NUT agents power their own box).
- **Notification ordering & delay:** on mains loss the **Warning "on-battery" alerts at t=0** (WAN still up via router/ONT on UPS → Signal + email deliver). At **Critical**, `oldsrv` is **delayed ~60 s** before powerdown (via NUT `upssched`) so its own Grafana→n8n→Signal/email pipeline flushes the Critical alert, then it powers off. `nas` + `ha` power down immediately.
- **Guaranteed fallback:** a **NUT-side `notifycmd`/`upssched-cmd` script on nas** emails + sends Signal directly on `ONBATT` and `LOWBATT`, independent of Grafana/n8n — so a pre-shutdown notification is sent even if the observability stack is already degraded.
- Registered/configured via the `nut` Ansible role — see [`deployment-ansible.md`](deployment-ansible.md).

---

## Microservice Notes

- **MikroTik SNMP:** poll at **5–15 s**; the "1s" in dashboards is a *refresh* interval, not a poll.
- **Retention is deliberate:** 30d metrics / 14d logs. TSDB data is **regenerable and not backed up** (see [backup.md](backup.md)); long-term metric history is a deferred option (remote-write/downsampling).
- **Placement:** the observability **backend** (VictoriaMetrics/VictoriaLogs/Grafana/blackbox + the VPS
  Dozzle viewer) runs on the **VPS** — the reliable tier. **The VPS is self-sufficient for its own
  observability**: it runs its own Alloy with `alloy_backend_host` defaulting to `127.0.0.1`, so VPS
  metrics/logs land locally with no tunnel, and its own Dozzle viewer (`logs.kogler.si`).
  **oldsrv/nas/Pi run thin Alloy collectors** forwarding *home* telemetry over the `wg-s2s` tunnel
  (nas's Alloy is host-exporter only — it has no Docker — and nas is still scraped for its `nut`/`zfs`
  exporters by oldsrv). **Dashboards are tailnet-only**: no public exposure, reached over the headscale
  mesh via the `traefik-tailnet` edge with clean subdomain URLs. **n8n (`auto`) is internal-only** (no
  public route). The alert brain is on the VPS and delivers over the public net, independent of the tunnel.
  **SPOF, accepted and narrowed:** if the home↔VPS tunnel or the VPS is down, *home* metrics/logs are
  unavailable in Grafana — gracefully (writers buffer and replay on reconnect) — while the VPS's own
  telemetry stays visible locally. NUT-side `notifycmd`/`upssched-cmd` on nas is the power-loss alert path
  that never depends on this stack.

- **Dozzle is not a second log backend** — it streams live logs straight from the Docker API (read-only socket) and persists nothing. VictoriaLogs stays the single stored-log source (90d) and Grafana the search/alert surface.

### Dozzle multi-host — VPS viewer + LAN hub

The design: the VPS keeps the VPS-only viewer (`logs.kogler.si`), and **oldsrv runs a LAN log HUB**
(`llogs.kogler.si`, :8081) that shows oldsrv + pi + spark containers via **remote agents**
(`DOZZLE_REMOTE_AGENT` over the Home VLAN). LAN logs stay **LAN-only by design** — never reach
VPS / public / tailnet. `nas` has no Docker (Alloy host-exporter only), so no agent.

```
VPS Dozzle (logs.kogler.si, tailnet)  ─── VPS containers only
OLDSRV Dozzle HUB (llogs.kogler.si, :8081, traefik-internal edge — WAN-out survival)
   ├─ own docker.sock  → oldsrv containers
   ├─ agent pi    (pi_home_ip:7007) → pi containers (HA primary, Technitium)
   └─ agent spark (spark_home_ip:7007) → spark containers (vLLM, dashboard)
```

- **Templates:** `dozzle` (dual-mode: VPS viewer vs oldsrv hub, `svc.dozzle_agent_connect` /
  `svc.dozzle_listen_ip` per-service vars) + `dozzle-agent` (one per docker host: pi, spark,
  oldsrv). Registry rows in `group_vars/{home_servers,raspberry_pi,spark}.yml`.
- **Security posture (Dozzle docs):** agents publish **only on the Home-VLAN IP** (`:7007`, never
  WAN/0.0.0.0). Dozzle's universal built-in cert encrypts the agent channel; the LAN bind is the
  access gate. No UI auth on the hub by owner decision (LAN-only internal edge — matches the
  **no Forward-Auth** doctrine on traefik-internal for WAN-out survival). Upgrade path: generate a
  custom cert pair (`dozzle generate-certs`) + `DOZZLE_CERT`/`DOZZLE_KEY` on hub + agents if an
  agent port is ever exposed beyond the Home VLAN.
- **DNS:** `llogs.kogler.si` → `{{ oldsrv_home_ip }}` is seeded by the technitium-seed loop on the
  **home instances only** (oldsrv secondary + Pi tertiary) — never the VPS primary (same LAN-only
  rule as `modem`/`spark`). LAN clients resolve it directly; WAN clients must NOT resolve it.
- **Route:** `llogs` router + `llogs-backend` → `http://{{ oldsrv_home_ip }}:8081` in the
  traefik-internal `routes.yml.j2` (file provider, hot-reload).

- **State: ✅ live** — hub on `:8081` answering through `traefik-internal`, agents on all three home hosts
  (`:7007`, LAN-only, healthy), VPS viewer unaffected. `llogs.kogler.si` resolves to `oldsrv_home_ip` on the
  two home Technitium instances and **not at all on the VPS primary** (verified with `dig`), which is the
  LAN-only design working. The per-host `dns-seed.timer` self-heal is active on VPS + oldsrv + Pi; a
  one-command re-seed of all three instances is `playbooks/dns-seed.yml`
  ([`network-dns.md`](network-dns.md) §Convergence & Drift) — note that a **scoped** host converge (e.g.
  `--tags dozzle-agent`) skips the seed tail, so DNS can lag a deploy on purpose.
- ⚠️ **Open, owner-side (two, both misdiagnosed easily):**
  1. **`traefik-internal` serves `TRAEFIK DEFAULT CERT`** (self-signed fallback) → "Not Secure" on
     `media.kogler.si` / `llogs`. Cause chain: the wildcard pair is not in `traefik-internal/certs` because
     the **`traefik-cert-pull` 401s** — `/root/.ssh/traefik-cert-sync` is not yet authorized on the VPS
     (manual step, [services-traefik.md](services-traefik.md) §Edge model). Fix: authorize the pubkey on the
     VPS `ansible-admin` → `systemctl start traefik-cert-pull.service` → restart `traefik-internal` →
     verify `CN=*.kogler.si`. **A default-cert response means the cert-pull is broken, not the edge.**
  2. **A phone that 404s on `llogs` is resolving it to the VPS public edge** (LE cert + 404 = the tailnet /
     Pi edge, which has no `llogs` route — correct). The client is bypassing RouterOS DHCP DNS (Android
     Private DNS / VPN / DoH). Fix it client-side or with a router DNS force — **do not** add `llogs` to the
     VPS primary to make the symptom go away.

- **Log/metric store access control (HD-342):** VictoriaLogs and VictoriaMetrics authenticate with **real
  Basic Auth** (`-httpAuth.username/-httpAuth.password`) from the `victoria-logs_api` /
  `victoria-metrics_api` items — consumed by Alloy (push/remote_write) and the Grafana datasources, and by
  the oldsrv MCP servers via `*_INSTANCE_HEADERS`. **This is a credential gate, not tenant isolation** —
  which was the accepted weakness of the previous backend, where a compromised `db-internal` container could
  forge a tenant header. Exposure: **loopback + the `wg-s2s` address only**, never a WAN or LAN-facing
  bind. Fail-loud lookups (no `default()`); the `$` in rendered values must be escaped for compose.
- ⚠ **The Victoria images are tool-less** (`/victoria-*-prod` only — no `sh`, `wget`, `curl`, `nc`), so a
  `CMD` healthcheck **cannot work** and Docker would mark the container unhealthy forever. Cover them with an
  external probe (Alloy scrape / blackbox), not a container healthcheck.
- **Pi keeps only a tiny bounded local log buffer.** The Raspberry Pi primary holds **no durable log store** — Docker uses log driver `local` (`max-size: 10m, max-file: 2`) as RAM/disk resilience when oldsrv/VictoriaLogs is down; the durable, searchable copy lives in VictoriaLogs. Host OS logs run on tmpfs (`journald Storage=volatile` + `/var/log` tmpfs). See [Pi SD-card wear strategy](#pi-sd-card-wear-strategy).
- **HA exporter** on the HA instance (Raspberry Pi 4 primary; cold-standby container on oldsrv — see [`smart-home-failover.md`](smart-home-failover.md)). Only the live instance is scraped (via the VIP); on failover the same URL resumes with no replay.
- **Conventions that are settled:** the Alloy `instance` label is `{{ inventory_hostname }}` per host, so
  series do not collide across hosts (HD-116); the MikroTik SNMP community is a dedicated **read-only**
  `network-snmp_api` item (fail-loud lookup in `snmp.yml.j2`) behind a Mgmt-VLAN-only INPUT ACL (HD-53) —
  the **device-side** `/snmp enable` + community setting is still an HD-03 deploy step.

---

## Pi SD-card wear strategy

The Raspberry Pi 4 primary runs HA from a **microSD** (`storage.md`), so the dominant continuous SD-wear
source is **HA's recorder DB**, plus rolling Docker/OS logs. Strategy (HD-19, applies to the Pi; the standby on
oldsrv is on NVMe and mostly unaffected):

1. **HA recorder → trim, NOT disable.** Grafana (central VictoriaMetrics, 365d) replaces HA for *long-term analytics*,
   so raw state history can be short: `recorder: { purge_keep_days: 1–2, commit_interval: 2–5, … }` plus
   `exclude:` for noisy domains you only need in Grafana. Keeping the recorder **enabled** is deliberate — it still
   powers the **Logbook**, the **Energy Dashboard (long-term-statistics tables)** (e.g. KNX appliance-current
   sensors → kWh), **`history_stats` / `history()` templates**, and per-entity short-term UI sparklines, none of
   which Grafana covers. LTS writes are hourly min/max/mean per entity — negligible SD cost. **Do NOT disable** the
   recorder, and do NOT move HA to Postgres (worse microSD wear + failover coupling — see `smart-home.md`).
2. **Docker container logs → stream + bounded local buffer.** Docker log driver `local`, `max-size: 10m, max-file: 2`
   on the Pi (and standby): small RAM/disk buffer survives an oldsrv/VictoriaLogs outage, while **Alloy ships logs → VictoriaLogs
   (14d, VPS NVMe)** and Dozzle streams live — no durable on-Pi log store.
3. **OS logs off the SD.** `journald Storage=volatile` + `/var/log` mounted as tmpfs (fstab) — host OS logs live in
   RAM, lost on reboot (acceptable; VictoriaLogs retains the useful logs). Cheap, well-tested Pi-SD saver.
4. *(Optional)* **Docker *log* directory on tmpfs** to guarantee zero *transient* SD writes — must stay hard-capped
   (`max-size`/`max-file`); **never** tmpfs the Docker data-root (`/var/lib/docker`/overlay2, that holds images &
   containers), only the log portion. Only if the 4 GB RAM budget (shared with HA/RaspberryMatic/Technitium) allows.

> Not addressed via ramdisk: the HA recorder DB and Technitium / RaspberryMatic state stay on the microSD but are
> kept small (trimmed recorder, reduced log verbosity). tmpfs-ing the recorder would throw away state/history on
> every reboot — see the energy/logbook caveats above.

---

## Dashboards

> Provisioned via the monitoring role (`files/dashboards/*.json` →
> `/etc/grafana/provisioning/dashboards`, hot-reloaded by the file provider in ~30 s). The metrics datasource
> uid is **`prometheus`** (kept even though the backend is VictoriaMetrics — it is a Prometheus-compatible
> datasource, and renaming it would churn every provisioned panel).
>
> ✅ **The SNMP series were never missing — the LABELS were (HD-345, measured 2026-09-22).**
> `match[]={job="alloy-snmp"}` returns 0 series, which is what every consumer asks for, while
> `match[]=ifOperStatus` returns **54 router + 54 switch series plus their `up`** — carrying
> `job="integrations/snmp/<dev>"` and `instance="prometheus.exporter.snmp.<dev>"`. Alloy's
> `prometheus.exporter.snmp` stamps its own component path onto the emitted target and
> OVERWRITES the `job` the scrape target asks for, so no walk/community/device change can fix
> it: the fix is a post-scrape `prometheus.relabel` that re-asserts `job="alloy-snmp"` +
> `instance="<dev>"` (`up` included), in `templates/alloy.river.j2`. ⛔ It waits on an oldsrv
> converge; verify afterwards with `up{job="alloy-snmp", instance="router"}`.
> The SNMP wiring that had to be correct to get here: `exporter.snmp` needs a valid `forward_to`, every SNMP
> target needs a `name`, and the auth block's `timeout`/`retries` must be valid for the module — an invalid
> one fails the whole Alloy reload, not just that target.

> **The vLLM dashboards (HD-368) — how they are derived, so nobody hand-edits a JSON.**
>
> Three grafana.com exports (25502 / 24756 / 25043) were adapted into this folder. The adaptation is a
> **script, not a hand edit**: [`scripts/adapt-vllm-dashboards.py`](../scripts/adapt-vllm-dashboards.py)
> carries every rewrite in `EXPR_REWRITES` / `PANEL_OVERRIDES` / `VAR_OVERRIDES` / `TEXT_TRANSLATE` /
> `STALE_METRICS`; re-download the exports and re-run it to re-derive the same files. It is byte-idempotent,
> **fails loud** on an unapplied rewrite, a surviving stale metric or an unmapped non-English string, and
> English-ises operator-visible strings (the exports shipped Chinese and Korean titles) per the repo language
> rule. Scaffolding (`__inputs`/`__requires`/`id`/`gnetId`) is stripped, `${DS_PROMETHEUS}` becomes the
> literal `prometheus` uid, uids are reissued as `homelab-*`.
>
> **Data path:** the spark-ai compose publishes vLLM's `:8000` **loopback-only** (`spark_metrics_publish`, the
> `127.0.0.1:8082` traefik precedent) → **spark's own Alloy** scrapes `vllm:/metrics`
> (`prometheus.scrape "vllm"`, `instance=spark.kogler.si`) → remote_write to the VPS VictoriaMetrics. vLLM
> serves `/metrics` on the API-server port via `PrometheusStatLogger` (`vllm:*` family, native `model_name`
> label; `instance` comes from the scrape config).
>
> **What upstream dashboards assume that this deployment does not have** — the audit result, which is what
> makes an exported dashboard render "No data" here (each is fixed in the adapter, not in the JSON):
> - metrics **removed in vLLM V1** (`vllm:num_requests_swapped` → `vllm:num_requests_waiting_by_reason`);
> - metrics **renamed in V1** (`vllm:gpu_prefix_cache_{hits,queries}_total` → `vllm:prefix_cache_*`, and the
>   K8s `endpoint="service-port"` label disappears);
> - **Kubernetes production-stack-only** series (`vllm:healthy_pods_total`, `router_{cpu,memory,disk}_usage_percent`,
>   `current_qps`) — no router, no pods here: use `sum(up{job="vllm"})`, a rate over
>   `vllm:request_success_total`, and the **spark host** via Alloy's node exporter for host CPU/mem/disk;
> - metrics **this build does not emit** (e.g. `vllm:kv_block_idle_before_evict_seconds_bucket`) — substitute
>   the signal you wanted (`vllm:num_preemptions_total` rate for KV pressure);
> - **unscoped** process metrics (`process_resident_memory_bytes` exists for every job in the DB, so the panel
>   plots the whole homelab) — always scope `job="vllm"`;
> - **stale upstream template variables** — one export shipped `model_name = /models/DeepSeek-V4-Flash`,
>   which silently No-datas every panel behind it; reset so the live value auto-selects.

| Dashboard | uid | View | Panels back on |
|-----------|-----|------|----------------|
| **Overview** | `homelab-overview` | top-level entry point — down-counts (public/hosts/tunnel/stack), VPS CPU+mem, links to all dashboards | `probe_success{job=blackbox_*}` · `up{job=…}` · `node_*{job="alloy"}` |
| **Host Overview** | `homelab-host-overview` | per-instance node resources: CPU, mem, load, uptime, network + **disk capacity AND disk work** — throughput B/s, IOPS, device busy %, avg wait ms — and **hwmon/thermal-zone temperatures** (HD-378); multi-host (instance template var) | `node_cpu_seconds_total` · `node_memory_*` · `node_load*` · `node_filesystem_*` · `node_network_*` · `node_boot_time_seconds` · **`node_disk_read_bytes_total`/`written_bytes_total`/`reads_completed_total`/`writes_completed_total`/`io_time_seconds_total`/`read_time_seconds_total`/`write_time_seconds_total`** · ⚙ `node_hwmon_temp_celsius` (+ `_max_celsius`/`_crit_celsius`/`sensor_label`) · `node_thermal_zone_temp` — all `job="alloy"`; ⚙ the hwmon/thermal_zone series need the Alloy `set_collectors` converge (HD-378), the disk ones are live already |
| **Service Reachability** | `homelab-service-reachability` | blackbox probe tables (HTTP + ICMP) + latency + TLS cert expiry | `probe_success` · `probe_duration_seconds` · `probe_ssl_earliest_cert_expiry` (`job=blackbox_*`) |
| **WAN & Tunnel** | `homelab-wan-tunnel` | wg-s2s liveness, Traefik requests, CrowdSec decisions, stack up | `probe_success{job=wg_icmp}` · `traefik_entrypoint_requests_total` · **`cs_active_decisions`** (NOT `crowdsec_decisions` — real CrowdSec metric, labels `origin`/`action`/`reason`) · `up{job=…}` |
| **Stack Health** | `homelab-selfmonitoring` | observability self-monitoring: up() per component | `up{job=victoria-metrics\|victoria-logs\|n8n\|blackbox-exporter\|crowdsec\|traefik}` (Alloy self-scrapes VM/VL /metrics; topology B) — **no alloy**: Alloy remote-writes its own series, so `up{job="alloy"}` has no series by design |
| **UPS** | `homelab-ups` | (pre-existing) NUT battery/load/voltages + status flags panel + **over-time: Output voltage, Load, Runtime, Battery charge** | `network_ups_tools_*` (DRuggeri/nut_exporter v3) |
| **LLM Inference (vLLM/SGLang)** | `homelab-llm-inference` | unified vLLM+SGLang inference view (grafana.com gnet 25502): request volume, token throughput, latency quantiles, queue/KV-cache, engine/TP-rank | **vLLM half live** (`vllm:*` `{job="vllm"}`, spark). 36 of 74 queries stay empty **by design**: they are the `sglang:*` mirrors — they light up when the SGLang throughput lane lands (HD-367/S2-S3) |
| **vLLM Monitoring V2** | `homelab-vllm-monitoring-v2` | vLLM server monitoring (gnet 24756): scheduler state by reason, KV-cache %, token rates, latency p50/p95/p99, prefix-cache, preemption, engine RSS/GC | **all 29 queries live** — `vllm:num_requests_{running,waiting,waiting_by_reason}` · `vllm:kv_cache_usage_perc` · `vllm:generation_tokens_total` · `vllm:time_to_first_token_seconds_bucket` · `vllm:num_preemptions_total` … (`num_requests_swapped` was V0 → replaced 2026-09-16) |
| **vLLM Dashboard** | `homelab-vllm-dashboard` | vLLM overview (gnet 25043, the production-stack template): engine count, QPS, latency e2e/TTFT/ITL, prefix-cache hit rate + spark host CPU/mem/disk | **all 14 queries live** — `up{job="vllm"}` · `rate(vllm:request_success_total)` · `vllm:e2e_request_latency_seconds_{sum,count}` · `vllm:prefix_cache_*` · `node_*{job="alloy",instance="spark.kogler.si"}` (production-stack `current_qps`/`healthy_pods_total`/`router_*` replaced 2026-09-16) |
| **★ LLM** *(HD-377, ⏳ deploy-gated)* | `homelab-llm` | **the unified inference dashboard — the merge of the three rows above into one board** (owner: "instead of many dashboards, I want 1"): readiness → spark node (CPU/RAM/GPU + **disk capacity and disk I/O**) → scheduling → latency → throughput → cache → reliability → request shape → per-engine detail → forward-look. Generated by [`scripts/build-llm-dashboard.py`](../scripts/build-llm-dashboard.py); see **§LLM Dashboard** below. The three HD-368 dashboards stay provisioned until the owner signs off. | 53 panels / 10 rows (HD-377(b), 2026-09-22): every query sits on a series proven in VM. The three `DCGM_FI_PROF_*` panels are **deleted** — they can never load on GB10 — and the six real GB10 signals are wired in their place: utilisation, die temperature, power draw **with the energy-counter rate beside it**, SM clock, PCIe replays, and `DCGM_FI_DEV_XID_ERRORS` as a readiness stat. The 7 whitelisted `job="dcgm"` series were re-confirmed live (`match[]={job="dcgm"}` → exactly 7 names) and joined the build script's `LIVE_DCGM_METRICS` allowlist, so the empty-panel guard PROVES them instead of accepting prose about them (see §LLM Dashboard → GPU) · `vllm:*` + `node_*{job="alloy",instance="spark.kogler.si"}` + `process_*{job=~"vllm|sglang"}` · every query joined `by (job, instance)` + scoped to `$instance` |

---

### LLM Dashboard (HD-377)

> **Role:** design SSOT for the **single** LLM/inference Grafana board (`homelab-llm`,
> `stats.kogler.si`) — the merge of the three HD-368 vLLM dashboards plus the spark node
> + readiness panels the owner asked for. Registered as HD-377 in `todo.md` §2.12.
> **⏳ deploy-gated:** authored and verified against live VictoriaMetrics; not yet converged. The three HD-368 dashboards stay provisioned until this board is signed off.
> **✅ provisioned on the VPS 2026-09-22** (`vps.yml --tags monitoring`, `changed=3 failed=0`; the file
> provider hot-reloads the JSON in ~30 s). What is still gated is the owner's sign-off on the OLD three
> boards (HD-377 a), not this board.

**Generation chain (SSOT direction).**
`grafana.com exports (25502/24756/25043)` → [`adapt-vllm-dashboards.py`](../scripts/adapt-vllm-dashboards.py)
→ the three repo JSONs → [`build-llm-dashboard.py`](../scripts/build-llm-dashboard.py) →
`files/dashboards/homelab-llm.json`. The merged file is a **derived artefact — never
hand-edit it**; a query fix belongs in the adapter (vLLM-side) or in the merge script's
`EXPR_REWRITES` / `NEW_PANELS` (merge-side). `--check` is the CI form (fails on drift);
`--report` prints the full carry/cut map.

**Why the merge is not a concatenation.** The three exports overlap heavily — three TTFT
panels, three KV-cache panels, two E2E latency, two prefix-cache hit rate, three
running/queued. The script's `DROPPED` map carries every cut **with its reason**, and
`guard_layout_consistency()` fails the build if the map and the layout ever disagree
(it caught two of the author's own documentation errors on first run). gnet 25043 is
cut 100 % — every one of its 14 queries is covered by a better-scoped panel elsewhere.

**The join rule (the part that matters for the RX 7600 later).** Every carried query is
rewritten to group `by (job, instance)` and to honour `$instance`, because a `sum()`
across two engines is not a metric. Adding an engine must add a *series*, not a dashboard
— so the RX 7600 (oldsrv, ROCm) and SGLang both land in these same rows with only a
scrape job each. `guard_instance()` refuses any query that ignores the picker. Joins are
applied **only** where both engines expose the same metric name; where they do not
(vLLM `prompt_tokens_total` vs SGLang `realtime_tokens_total` — different quantities,
the latter carries a `mode` dimension) the two upstream panels are kept side by side
rather than summed into a number that means neither. The board states this in-panel.

**Readiness = three signals, not one.** `up{job="vllm"}` (scrape leg), `up{job="sglang"}`
(the SGLang lane) and a blackbox `http_2xx` on the engine's own `/health`. They fail
differently: `/metrics` can serve while `/health` is 503 (initialised, not ready), and
`/health` can be 200 while the scrape leg is dead — which is a config problem, not an
inference outage. A readiness panel derived from `up{}` would be a duplicate of the first
panel and would hide exactly that. ⏳ The `/health` probe is **authored empty**: the
target is spark loopback, and the VPS blackbox-exporter has no path to `127.0.0.1:8000`
on spark — wiring it needs a blackbox exporter reachable from spark's Alloy (a
sidecar on spark, or scrape the probe from spark's Alloy the way the `vllm` job is
scraped). Not built in this HD; specified here so the panel is not mistaken for a bug.

**GPU on a GB10 — what is and is NOT obtainable** (verified live on the box, twice).
```
spark# nvidia-smi -q -d MEMORY   → FB/BAR1 Total/Used/Free: N/A
spark# nvidia-smi dmon -s um     → fb / bar1 columns: '-'
spark# dpkg -l | grep dcgm       → (none)      dcgmi: not found
spark# docker images | grep dcgm → nvidia/dcgm-exporter:3.3.5-3.4.1-ubuntu22.04  (on disk)
```
**NVIDIA has confirmed the memory reading is by design, not a gap:** `nvidia-smi` reports
"Not Supported" for memory because "the DGX Spark has a unified memory architecture" and
reports memory utilisation only when there is dedicated VRAM — for memory usage they point
to `top`/`htop`/`free` or the DGX Dashboard. So the honest GPU picture is unified-pool RAM
(where the allocation actually is), engine RSS (the process's share of it, vs the HD-374
105 GiB cage) and the engine's own per-GPU work estimates
(`vllm:estimated_flops_per_gpu_total`, `estimated_read_bytes_per_gpu_total` — live today,
plotted in "GPU work — engine reported").

**What DCGM actually delivers here** (measured by running the on-disk image):
The exporter starts and initialises, then refuses the profiling module outright:
`Not collecting DCP metrics: This request is serviced by a module of DCGM that is not
currently loaded`; forcing `dcp-metrics-included.csv` yields
`Skipping line 21..25 ('DCGM_FI_PROF_GR_ENGINE_ACTIVE' / 'PIPE_TENSOR_ACTIVE' /
'DRAM_ACTIVE' / 'PCIE_TX_BYTES' / 'PCIE_RX_BYTES'): metric not enabled` — NVIDIA has
stated there are **no plans to support DCGM profiling on Spark** (not a datacenter device).
13 series emit, with live values (`modelName="NVIDIA GB10"`,
`DCGM_FI_DRIVER_VERSION="580.178.04"`):

| Emits (live value) | Worth wiring? |
|---|---|
| `DCGM_FI_DEV_GPU_UTIL` (88–90 % under load) | **yes** — the only true GPU-busy signal; nothing else carries it |
| `DCGM_FI_DEV_GPU_TEMP` (50–58 °C) | **yes** — no nvidia hwmon chip, so `node_hwmon_*` does NOT include the GPU die |
| `DCGM_FI_DEV_POWER_USAGE` (12.3–38.9 W) | **yes** — GPU-rail power, absent from every other source |
| `DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION` (458 MJ, counter) | yes — accurate averaging (instantaneous power oscillates) |
| `DCGM_FI_DEV_SM_CLOCK` (2509 MHz) | yes — throttle/idle visibility |
| `DCGM_FI_DEV_XID_ERRORS`, `PCIE_REPLAY_COUNTER` | yes as silent-zero tripwires |
| `MEM_COPY_UTIL` (0), `MEMORY_TEMP` (**0 = bogus**), `ENC_UTIL`/`DEC_UTIL` (0), `NVLINK_BANDWIDTH_TOTAL` (0), `VGPU_LICENSE_STATUS` (0) | **no** — constant or wrong on GB10; do not chart |
| `FB_USED`/`FB_FREE`/`FB_RESERVED`, `MEM_CLOCK`, all `DCGM_FI_PROF_*` | **impossible** — not emitted |

**Corollary — the three `DCGM_FI_PROF_*` panels HD-377 authored must be DELETED, not
wired.** They were written on the assumption that wiring DCGM would fill them; that
assumption is dead (NVIDIA statement + exporter log + live probe). The `DCGM_FI_DEV_*`
row above is what to wire instead: `nvidia/dcgm-exporter` loopback-published on `:9400` +
a `prometheus.scrape "dcgm"` block in `alloy.river.j2` under
`{% if inventory_hostname == 'spark.kogler.si' %}`, `job="dcgm"` +
`instance="spark.kogler.si"` set by relabel (the container's own `Hostname` label is the
container id, not the host — never legend on it).

**The DGX Dashboard (`db-spark.kogler.si`, `dgx-dashboard.service` on spark) is not a
data source.** `POST /api/login` → JWT, then `GET /api/v1/gpu_telemetry/stream` (SSE, one
record/s): `{percentage_utilization, memory_available_in_kib, memory_total_in_kib,
temperature_in_c, power_draw_in_w, gpu_memory_in_use_in_mb, cpu_memory_in_use_in_mb,
power_limit_in_w}`. `memory_total_in_kib` = 127532360 KiB = **the whole 121.6 GiB host
pool** — its "GPU Memory" tile is system RAM under a GPU label, and
`gpu_memory_in_use_in_mb` / `power_limit_in_w` are hard `0`. Its three real fields are the
same util/temp/power DCGM gives, it has no `/metrics` endpoint and no history, so it
informs nothing here beyond corroborating the unified-memory finding. (Its temps, 57–62 °C,
sit between DCGM's 50–58 °C and the acpitz zones' 65–73 °C — three different sensors; never
plot them as one series.)

**DCGM is wired (HD-379) — the signals that are real on GB10.**

| Layer | What ships |
|---|---|
| Compose service | **`spark-dcgm`** (`templates/docker_services/spark-dcgm/`) — `dcgm-exporter` on **loopback only** `127.0.0.1:9400`, the same publish discipline as `spark_metrics_publish` (HD-368): no Traefik route, no Home VLAN, no auth on `/metrics`. `cap_drop ALL` + `cap_add SYS_ADMIN`, `read_only`, `pid: host`, GPU device reservation, **no memory limits** (a ~30 MB read-only observer must not compete with the HD-374 cage). Registered in `group_vars/spark.yml` (`enabled: true`). |
| Image pin | `spark_dcgm_exporter_image` in `group_vars/all/versions.yml` — **digest**-pinned (`nvidia/dcgm-exporter:3.3.5-3.4.1-ubuntu22.04@sha256:ec962b…f8870`, arm64 manifest, digest taken from spark's own image store where it was run live). Port comes from `spark_dcgm_exporter_port` (9400) — declared in group_vars, **not** `\| default()`'d: §1 fail-loud, and `validate-docker-services.py`'s mock `default` would silently render an empty port. |
| Scrape | `prometheus.scrape "dcgm"` + `prometheus.relabel "dcgm"` in `alloy.river.j2`, spark-gated, `job="dcgm"` + `instance="spark.kogler.si"` (the exporter's own `Hostname` label is the **container id** → `labeldrop`, it churns on every recreate). |
| **Metric policy** | Lives in the Alloy relabel as a **whitelist**, not in a counter CSV inside the image: `keep DCGM_FI_DEV_(GPU_UTIL\|GPU_TEMP\|POWER_USAGE\|TOTAL_ENERGY_CONSUMPTION\|SM_CLOCK\|XID_ERRORS\|PCIE_REPLAY_COUNTER)`. Dropped on evidence: `MEMORY_TEMP` (bogus **0** while the NVMe beside it reads 46 °C), `MEM_COPY_UTIL`/`ENC_UTIL`/`DEC_UTIL` (always 0), `NVLINK_BANDWIDTH_TOTAL` (no NVLink), `VGPU_LICENSE_STATUS` (no vGPU). |

⚠ **Do not add to that whitelist:** the DCP/profiling family (`GR_ENGINE_ACTIVE`, `SM_ACTIVE`,
`PIPE_TENSOR_ACTIVE`, `DRAM_ACTIVE`, `PCIE_TX/RX_BYTES`) and `FB_*`. They are not a scrape gap —
the exporter refuses them (`metric not enabled`) and NVIDIA states profiling will not be supported
on Spark. A new driver making them appear should be an explicit, reviewed IaC edit, not a silent
cardinality change.

**Deployed and live-verified:** `VM {job="dcgm"}` returns **exactly the 7 whitelisted
series** (`GPU_UTIL`, `GPU_TEMP` 46 °C, `POWER_USAGE` 10.25 W, `TOTAL_ENERGY_CONSUMPTION`,
`SM_CLOCK` 2411 MHz, `XID_ERRORS`, `PCIE_REPLAY_COUNTER`) and the host temperatures arrived too
(`node_hwmon_temp_celsius` per instance: spark 12, oldsrv 17, nas 9, pi 2 sensors — HD-378's
⏳ panels are now live). The vLLM engine was **not** restarted by any of it.

**⚠ Operational gotcha found the hard way (worth 30 seconds of anyone's time):** a service's own
deploy tasks carry `tags: "{{ svc.name }}"` (`docker_services/tasks/deploy-service.yml`), so
`--tags monitoring,docker_services` on a **NEW** service renders the loop but **skips every inner
task** — the first converge reported rc=0 while deploying nothing (the `dgx-dashboard` tombstone
teardown *did* run, because teardown is tagged `docker_services`). **A first deploy needs the
service's own tag**: `--tags monitoring,docker_services,spark-dcgm`. rc=0 is not proof of deploy;
the proof was `docker ps` + `VM {job="dcgm"}`.

**Memory (answering "can we trim the exporter's RAM via the counters CSV?") — measured, A/B on
the box.** Image default `default-counters.csv` (18 fields) = **143.2 MiB anon**; a 7-field CSV
via `DCGM_EXPORTER_COLLECTORS` = **138.8 MiB anon** (≈ **−3 %**); the same trimmed run with
`GOMEMLIMIT=64MiB GOGC=20` = 145 MiB (no effect). Conclusions:
  * The **profiling fields are not the cost here** — on GB10 the DCP module never loads
    (`Not collecting DCP metrics…`, so `dcp-metrics-included.csv` is not even read: the exporter
    logs `Falling back to metric file '/etc/dcgm-exporter/default-counters.csv'`), so there is no
    profiling buffer to reclaim. On a datacenter GPU with DCP enabled the CSV *is* a real lever;
    on Spark it is worth ~4 MiB.
  * The floor is **DCGM/NVML's device context**, not the Go heap — which is why the Go env knobs
    do nothing. `docker stats` readings drift 130–155 MiB with page cache; `memory.stat` `anon`
    is the number to trust.
  * So the lever that actually matters on this box is a **hard cap**, not trimming: the compose
    now sets `mem_limit: 256m` (~1.8× the measured peak, so the cap can never OOM it in normal
    operation) — an unbounded leak in a sidecar must not be able to eat into the 105 GiB engine
    cage (HD-374) on a host that has already OOM-killed (HD-375). Revisit the CSV only if a future
    driver starts emitting profiling fields.

**spark RAM reading — read the floor, not the ceiling.** On this box the useful signal is
`node_memory_MemAvailable_bytes` (live: 9.5 GiB of 121.6 GiB with the engine loaded),
not utilisation %: every global OOM in `spark-incidents.md` came from replace-by-percent
GPU-reserve arithmetic against this pool. The RAM panel and the HD-375 alert rules read the **same**
gauge — `usable = MemAvailable − CmaFree`, warn **< 12 GiB**, crit **< 8 GiB** — never raw
`MemAvailable` and never utilisation %, both of which hide the reserve on this box.

**Known limits, recorded rather than hidden.**
- Every `sglang:*` sibling comes from SGLang's documented metric names + the gnet 25502
  author's pairing — **never from a live scrape** (no SGLang engine has run here). Expect
  HD-368-style corrections; the fix goes in this script, not in the JSON.
- SGLang has no prefix-cache *queries* counter, so the SGLang hit-rate leg divides by
  total prompt tokens → an **upper bound**, flagged in the panel tooltip.
- SGLang has no `finished_reason` label, so "Success rate" and "Preemptions" are vLLM-only
  by necessity (SGLang's equivalent event is its eviction counters, already plotted by the
  carried gnet 25502 panel — deliberately not summed in).

**Retiring the three old boards (owner step, after sign-off).** Delete
`llm-inference-sglang-vllm.json`, `vllm-master-v2.json`, `vllm-dashboard.json` from
`files/dashboards/` and re-converge `--tags monitoring` — the file provider follows the
directory. Until then all four are provisioned; the `homelab-llm` board is the one to
open.

---

## Scrape cadence and metric resolution (HD-420)

Every job on every host scrapes at Alloy's default **60 s** — `scrape_interval` is set nowhere in the deployed
`/etc/alloy/config.alloy`. Fine history therefore exists nowhere downstream, and no Grafana setting invents it.
This is the other half of the OOM blind spot above, and the reason the spark GPU/engine panels read as a step
chart next to the DGX System Monitor, which samples **1 Hz**.

### Where the cadence is actually capped

| Source | New data exists at | Measured |
|---|---|---|
| `node_*` (Alloy host job) | kernel counters, 100 Hz jiffies | sub-second |
| `vllm:*` on `:8000/metrics` | **≈ 1 Hz under load** | `vllm:generation_tokens_total` advanced on **every one** of 17 consecutive 1 s scrapes taken during a live request (178,079 → 178,249). `VLLM_LOG_STATS_INTERVAL: "10"` is the engine's **log** heartbeat, not a publication cap — log-only lines (`running/waiting/… req/s`, `p: … reqs`) are capped at 10 s, cumulative counters are not ⇒ **no engine restart is needed** for one-second engine data |
| `DCGM_FI_DEV_*` on `:9400/metrics` | **once per 30 s** | `DCGM_EXPORTER_INTERVAL: "30000"` in `templates/docker_services/spark-dcgm/docker-compose.yml.j2`; `DCGM_FI_DEV_GPU_UTIL` returned `86` on twelve consecutive 1 Hz reads. Scraping faster than this stores copies of one sample |
| DGX System Monitor (the 1 s picture) | 1 Hz | authenticated `POST /api/login` (the JSON field is `token`) then `GET /api/v1/gpu_telemetry/stream` yields `percentage_utilization`, `memory_available_in_kib` / `memory_total_in_kib` (25,676,736 / 127,533,336 KiB = 19.7 % of the **host** pool — not a VRAM counter, see §LLM Dashboard → GPU), `temperature_in_c`, `power_draw_in_w`. It polls the **same** `spark-dcgm` exporter: the difference is cadence, plus a host-memory stat Alloy already scrapes directly |

### What resolution costs (measured on the VPS, VictoriaMetrics v1.151.0)

| Quantity | Value |
|---|---|
| Live write rate · active series · data dir | 227.8 rows/s · 2,756 series · **92 MB** — disk is not the constraint (`/` has 418 GB free) |
| Storage per sample | ≈ **0.33 B** (92 MB ÷ ≈ 286 M samples over 30 d) |
| spark → VPS wire | ≈ 590 B/s ≈ **51 MB/day**; 1,774 samples per scrape — host 669 (**160 of them `node_cpu_seconds_total`**), engine 476 (**309 request-completion-driven `_bucket{}`**), dcgm 18 → **7 kept** after relabel |
| Engine render | 4.8–6.1 ms per scrape (64 kB, 471 lines) → at 5 s = **0.10 % of one of 20 cores** |
| **50 hot series @ 5 s** | **+9.2 rows/s · ≈ +95 MB/yr · ≈ +2 MB/day wire** |
| every spark series (1,745) @ 5 s | +125 rows/s · ≈ +3.4 GB, and it **plateaus** at the 365 d retention |
| 50 hot series @ 1 s | +49 rows/s · ≈ +0.5 GB/yr |

**Age-tiering is not available in this stack.** `-downsampling.period` and `-retentionFilter` are both **absent
from the VictoriaMetrics community binary** (checked against `--help` of the deployed v1.151.0; the docs state
community supports a single retention and one storage tier), and OpenObserve's downsampling is an enterprise rule
set as well. Resolution is therefore bought **at write time** — scrape only what needs it faster — not by
collapsing old buckets afterwards. Memory, not disk, is the VPS ceiling (4.3 GiB available, no swap) and it tracks
*active series*, which cadence does not change.

### The hot set — 50 series, which is the whole fine-resolution ask

Owner scope 2026-09-21: fine data for these panels only, **everything else (latency, histograms) stays at 60 s**.
50 of spark's ~1,893 series — the 9 panels do not need 1,745 series, and the 365-day cost of blanket 5 s is what
the exclusions avoid:

| Panel | Series kept at fine cadence |
|---|---|
| spark memory (the OOM gauge + the Monitor's memory bar) | `node_memory_MemAvailable_bytes`, `node_memory_CmaFree_bytes`, `MemTotal`, `MemFree`, `Buffers`, `Cached`, `SwapCached`, `Shmem` |
| GPU utilization · temperature · power · SM clock · energy · XID · PCIe replays | all 7 whitelisted `DCGM_FI_DEV_*` — a scrape without them is empty, so they must ride the hot job |
| CPU utilization | `node_cpu_seconds_total{mode="idle"}` **only** — 20 series, not the 160 the panel's formula never reads |
| Token throughput · decode throughput | `vllm:generation_tokens_total`, `vllm:kv_cache_usage_perc`, `vllm:num_requests_running` |
| Prompt / generation token stats | `vllm:prompt_tokens_total`, `vllm:prompt_tokens_by_source_total{source=…}` ×3 |
| Prefix Cache Hit Rate | `vllm:prefix_cache_hits_total`, `vllm:prefix_cache_queries_total` |
| Cached Token Stats | `vllm:prompt_tokens_cached_total` (plotted as a raw counter today — see 4 below) |
| Scheduler / preemption | `vllm:num_requests_waiting`, `vllm:num_requests_waiting_by_reason{reason=…}` ×2, `vllm:num_preemptions_total` |
| load (the Monitor's other two numbers) | `node_load1`, `node_load5` |

⏳ **The work, in order (HD-420):**

1. **Split spark's scrapes into hot + cold jobs** in `roles/monitoring/templates/alloy.river.j2`, gated on the
   inventory host so only spark pays: `scrape_interval = "5s"` + `scrape_timeout = "3s"` on the hot jobs, and
   **disjoint metric sets** — `prometheus.relabel` `keep` in the hot job, the same `match_re` with
   `action = "drop"` in the cold job. Overlapping sets yield duplicate series at two cadences, which forces
   `-dedup.minScrapeInterval=5s` on the VPS: a shared-flag change that silently re-tunes dedup for every other
   host. Disjoint jobs also mean **no dashboard query changes** — the series names are identical.
2. **`DCGM_EXPORTER_INTERVAL: "30000"` → `"5000"`** in
   `templates/docker_services/spark-dcgm/docker-compose.yml.j2`, otherwise 5 s scraping records six copies of one
   GPU sample. Sidecar restart only — never the engine. ⛔ Pre-flight first: that sidecar carries
   `mem_limit: 256M` + `workers: 1` *because it grew past its cap during HD-378* — A/B its CPU and `memory.stat`
   anon against that cap at 5 s before converging.
3. **Fix the Grafana interval floor.** The Prometheus datasource carries **no `jsonData.timeInterval`**, so
   `$__interval` / `$__rate_interval` are floored at Grafana's default **15 s**, not 5 s. Set
   `jsonData: {timeInterval: "5s"}` on the `prometheus` datasource uid. ⚠ the provisioning seed in
   `roles/monitoring/tasks/main.yml` only fires `when: … status == 404`, so it needs an API PUT on the existing
   datasource (or delete-and-re-seed) — editing the seed alone does nothing.
4. **Panel representation** — "the same as the picture" is half cadence, half representation. "Prefix Cache Hit
   Rate" is a **gauge with a hard-coded `[5m]`** window: no 5 s data shows a spike through a 5-minute window, so
   it becomes a time series over `[1m]`/`$__rate_interval`. "Cached Token Stats" plots the raw counter with no
   `rate()`.
5. **Alert rules are not a driver here.** Every alert group evaluates at `interval: 1m` with `for: 1m`/`2m`, so
   5 s data changes what a rule *sees*, not how often it runs; raising the alert interval is a separate,
   deliberate decision (it multiplies ruler load and shortens `for:` windows into noise).

**State (HD-420): the whole thing is LIVE 2026-09-23** — VPS half (datasource `timeInterval` floor + the `rate()` fix, 2026-09-22) **and** the spark half (hot/cold Alloy jobs + `DCGM_EXPORTER_INTERVAL: "5000"` + the 5 s acceptance on external traffic).

- **LIVE on the VPS (item 3 + item 4's `rate()` fix):** proved by converging
  `vps.yml --tags monitoring` twice — `failed=0 changed=3`, then **`changed=0`** with the new
  datasource task reporting `skipping`, so the floor is not a changed-on-every-run task.
  Live read-back of the datasource: `jsonData {"timeInterval": "5s"}`, `basicAuthPassword`
  still set (the PUT re-sends the vault secret because PUT replaces the record), health OK.
- **The spark half is LIVE 2026-09-23 (this lane, external traffic):** the hot/cold Alloy jobs,
  `DCGM_EXPORTER_INTERVAL: "5000"` and the datasource floor are all converged; the acceptance was
  measured on **external** traffic (three 2k-token completions from the laptop through
  `llm.kogler.si`): `count_over_time(node_load1{instance=~"spark.*"}[1m])` = **12**,
  `count_over_time(vllm:generation_tokens_total[…][1m])` = **12**,
  `count_over_time(DCGM_FI_DEV_GPU_UTIL[…][1m])` = **12**, while cold-only names
  (`node_cpu_seconds_total{mode="user"}`, `vllm:e2e_request_latency_seconds_bucket`) read **1/1m**
  — the hot `keep` / cold `drop` are disjoint and matching, no `-dedup` change owed. Sidecar under
  load: **72 MiB / 256 MiB, cgroup anon 61.5 MiB** (idle 36.9) — well under the ~200 MiB raise
  threshold, so no `spark_dcgm_exporter_memory_limit` change was made. GPU util 84 %, die 64 °C,
  power 34 W, SM 2489, XID 0 on the loaded samples.
  both spark halves converge together (`alloy.river.j2` + the `spark-dcgm` interval are one
  coupled pair), and `count_over_time(node_load1{instance=~"spark.*"}[1m])` reads **12**.
- **Item 4's other half is not a panel bug.** The hard-coded `[5m]` gauge lives only on
  `vllm-master-v2.json` (id 402), one of the three retired HD-368 boards whose deletion waits on
  the owner's HD-377(a) sign-off; the board of record already carries that ratio as a
  `rate(…[$__rate_interval])` time series. Deleting the retired board is the fix — rebuilding a
  panel on a board scheduled for deletion is not.
- ⚠ **`--diff` on the `monitoring` role is the same secret-dump class as on `docker_services`:**
  `alloy.river.j2` renders the Victoria* `basic_auth` credentials straight out of the vault, so a
  diff prints them. `--check` is fine; `--diff` is not.
- The first converge rewrote `/etc/alloy/config.alloy` and the alert-rules file on the VPS: both
  had **drifted from a fresh render of `main`** (the new render is byte-identical to HEAD's —
  proved offline, `alloy.river.j2` for vps/nas/pi). Pre-existing drift, not a change from this
  lane, recorded because the `restart alloy` handler rides it.

**Re-measure instead of trusting this section** (everything below is read-only; the VM query credentials come
from the `basic_auth` block of `/etc/alloy/config.alloy` on the VPS — parse them into shell variables, never
print them):

```bash
ssh spark 'grep -c scrape_interval /etc/alloy/config.alloy'        # 0 → Alloy default 60 s everywhere
ssh spark 'curl -s -o /dev/null -w "%{size_download} %{time_total}\n" localhost:8000/metrics'
ssh spark 'curl -s localhost:9400/metrics | grep GPU_UTIL'          # repeat at 1 Hz: the value holds for 30 s
# per-minute samples per job: Alloy's own prometheus_forwarded_samples_total over a 60 s window
# VM write rate + active series: vm_rows_inserted_total, vm_active_time_series
```

---

## Host sensors and disk I/O (HD-378)

The board must cover **CPU, GPU, RAM and DISK io/throughput**
from spark — and temperatures belong on **Host Overview**, not on the LLM board. Two gaps
were found and closed; one turned out not to be a gap at all.

**Disk I/O needed no new telemetry.** `prometheus.exporter.unix "host"` has enabled the
`diskstats` collector from the start, so the I/O families were already in VM — verified per
family for `instance="spark.kogler.si", device="nvme0n1"`:
`node_disk_read_bytes_total`, `node_disk_written_bytes_total`,
`node_disk_reads_completed_total`, `node_disk_writes_completed_total`,
`node_disk_io_time_seconds_total`, `node_disk_io_time_weighted_seconds_total`,
`node_disk_read_time_seconds_total`, `node_disk_write_time_seconds_total`,
`node_disk_io_now`, `node_disk_info` (+ merged/flush families). The gap was purely in the
panels: every dashboard had capacity (`node_filesystem_*`, "how full") and none had work
("how hard"). **Host Overview** gains a 4-panel row — throughput (B/s), IOPS (ops/s),
busy % (saturation) and avg wait per op (latency: io-time / completions, `clamp_min`'d so
idle windows stay finite) — plus two top-row stats (**Busiest disk** = peak device busy %,
**Hottest sensor**), and the **LLM board** gains throughput / IOPS / saturation panels for
spark (HD-377). USE-method set: saturation and latency are the two that actually flag a
contended data device; capacity alone never does.

**spark's block layout limits the granularity:** one device (`nvme0n1`) serves BOTH the EXT4
root and the 503 GiB XFS weights/KV mount (`/mnt/spark_nvme`), so block-layer I/O cannot be
attributed per mount. Capacity stays per-mount, work stays per-device — said in-panel so
nobody reads a device series as "the XFS mount".

**Temperatures: the collectors were pinned off, nothing was missing on the box.**
`set_collectors` enumerated a minimal collector list that omitted `hwmon` and
`thermal_zone`, so `node_hwmon_*`/`node_thermal_zone_temp` were absent **for every host**
(VM check across 30 d: 0 series) even though the sensors are live in `/sys`. Added both
collectors (valid Alloy `prometheus.exporter.unix` collectors; spark runs Alloy v1.19.2).
Verified the exact series + label shape with a throwaway `node_exporter` v1.9.1 binary on
spark — names and labels below are measured, not guessed:

| Chip / sensor (measured on spark) | Reading | Note |
|---|---|---|
| `chip="nvme_nvme0", sensor="temp1"` | 45.9 °C | the **Composite** NVMe sensor (`node_hwmon_sensor_label` gives the name); `_max_celsius` 85.85, `_crit_celsius` 86.85 |
| `chip="nvme_nvme0", sensor="temp2"/"temp3"` | 56.9 / 45.9 °C | raw sensors (`_max_celsius` on temp2 reads 65261 °C — a firmware joke; use temp1) |
| `chip="thermal_thermal_zone0", sensor="temp0"…"temp7"` | 55.6–58.4 °C | the `acpitz` SoC/CPU zones |
| `chip="ieee80211_phy0", sensor="temp1"` | 54 °C | mt7925 WiFi PHY |
| `node_thermal_zone_temp{type="acpitz",zone="N"}` | same values | **duplicate** of the thermal_zone0 hwmon chip — read one or the other, not both in a sum |

⚠ **The acpitz zones are NOT the GPU.** They run 5–15 °C above `nvidia-smi`/DCGM GPU temp;
there is **no nvidia hwmon chip on this box**, so GPU die temp comes from DCGM only
(`DCGM_FI_DEV_GPU_TEMP`). That is why the two dashboards carry different temperature
sources: Host Overview = host silicon from hwmon, LLM board = GPU from DCGM.

**⚠ BIOS question, answered: the `hwmon` collector needs NO BIOS update, no kernel module,
no new daemon and no reboot.** It reads `/sys/class/hwmon`, which exists on the stock DGX
OS image today. The BIOS/firmware prerequisite belongs to a *different* thing — the
out-of-tree `antheas/spark_hwmon` SPBM driver, which is what would expose the per-rail
power split (CPU-P/CPU-E/SoC/DRAM/system). That is **not** wired here: it is a DKMS kernel
module (self-described as experimental, upstream states "vibe coded", and older firmware
genuinely misreports its CPU channels until `fwupdmgr update`), and loading it on the box
with the HD-375 OOM history is an owner risk decision, not a monitoring decision. Its
reward is also thin — the SPBM `gpu` channel "matches nvidia-smi", which DCGM already
delivers; the unique part is the CPU-rail split, which NVIDIA says has no supported
interface at all. If it is ever wanted, the wiring is already prepared: it lands in
`/sys/class/hwmon`, and the `hwmon` collector enabled here picks it up with **no further
change**. Same for the community `dgx-spark-exporter` (Go, `:9876/metrics`) — its ~50
`dgx_spark_*` metrics are a 1:1 duplicate of the Alloy unix collector already running
(CPU/mem/disk-IO/filesystem/network/load/fd), its GPU trio is nvidia-smi again, and it
carries no VRAM and no profiling either; not adopted.

**Verified from the backend, not from the playbook recap:** `node_hwmon_temp_celsius` exists per
instance (spark 12, oldsrv 17, nas 9, pi 2 sensors). The disk panels needed no converge at all — the
families were already in VM; they shipped with the dashboard copy. **If a temperature panel renders
empty for one host, that host's Alloy has not picked up `set_collectors` yet** (check the
`alloy.service` restart) — it is not a dashboard bug.

⚠ **Converge trap (HD-379):** a new/changed Alloy config converges under `--tags monitoring`, but the
**first deploy of a compose service needs that service's own tag**
(`--tags monitoring,docker_services,<name>`) or the deploy tasks are silently skipped while the run
still reports `failed=0`. Proof = a backend query or `docker ps`, never the recap.


> **Metric names that are not what you would guess** — every one of these was guessed once and cost a
> dead panel:
> - Traefik: **`traefik_entrypoint_requests_total`** (v3). `traefik_requests_total` is the v2 name and is
>   a phantom here. The metrics endpoint is enabled on the main edge (`--metrics.prometheus=true`,
>   `--entryPoints.metrics.address=:8082`) with a `db-internal` join so the collector can resolve
>   `traefik:8082` at all.
> - UPS: **`network_ups_tools_*`** (DRuggeri/nut_exporter v3, path `/ups_metrics?ups=<name>`), **not**
>   `nut_*`. The exporter is **version-pinned** (`nut_exporter_release`) — `@latest` tracks `(devel)` and
>   its metric names move.
> - CrowdSec: **`cs_active_decisions`** (labels `reason`/`origin`/`action`), not `crowdsec_decisions`.
> - Host metrics: the Alloy `unix` exporter is node_exporter-compatible (`node_cpu_seconds_total`,
>   `node_uname_info`, …) in the `job="alloy"` namespace — **and an Alloy component that is declared but
>   not consumed is silently dead** (`prometheus.exporter.unix` produced zero `node_*` series until a
>   `discovery.relabel` + `prometheus.scrape` pair consumed it). Lazy evaluation is the usual cause of
>   "the exporter is running but the metric does not exist".

---

## Network Clients Dashboard (HD-343)

> **Role:** design SSOT for the "all network clients, grouped per VLAN" Grafana dashboard
> (`homelab-network-clients`) at `stats.kogler.si`; HD-343 in `todo.md`.
> **Status: ✅ exporter live on oldsrv, ⏳ owner render-verification owed.**
> Deployment shape (all of it load-bearing): host binary + venv under `/opt/network-clients-exporter`
> (`routeros-api==0.21.0` pinned — Debian has no `python3-routeros-api` package and the exporter imports
> the PyPI module name `routeros_api`), running as `networkclients` with the install dir `0750
> root:networkclients` so a low-privilege service user holds the RouterOS credentials, and `/metrics`
> serving the `mikrotik_client` union (DHCP + ARP + FDB + wifi) from the RB4011 `logpipe` read-only user.
> ⏳ Open: verify the wifi path against `/interface/wifi/registration-table` (vs the legacy API) and the
> owner render-check of the dashboard.

**Goal.** One dashboard showing *every* client on the homelab, grouped by VLAN
(10 Home / 20 IoT / 30 Guest / 40 Kids / 50 Media / 99 Management).

**Why 5 data sources — no single one covers “all clients”.** DHCP leases alone miss the
~static-IP hosts (router/switch/APs, nas/oldsrv/pi, shelly/KNX/printers — all static per
`network_static_hosts`, SSOT `group_vars/all/main.yml`). The dashboard is a **join**:

| RouterOS source (live API) | Path | Covers | VLAN classifier |
|---------------------------|------|--------|-----------------|
| DHCP leases | `/ip/dhcp-server/lease` | DHCP-issued clients (hostname, mac, address, status) | lease `server` → pool → subnet → VLAN |
| ARP table | `/ip/arp` | any host that has talked (IP+MAC) | ARP row's interface name (`vlan10-home` → 10) |
| Bridge host table (FDB) | `/interface/bridge/host` | L2-attached MACs, wired + wireless | bridge/vlan attribute |
| WiFi registration | `/interface/wifi/registration-table` (modern wifi-qcom-ac, HD-232) | active wireless clients (mac, ssid, iface, signal) | SSID/interface → VLAN |
| SSOT static hosts (not scraped) | `network_static_hosts` | every static host + its true VLAN | `vlan` attr — naming/VLAN ground truth |

**Data path decision (HD-343).** A small **RouterOS-API collector on `oldsrv`** is the
primary pipe, not SNMP and not the VPS:

- **VPS → router API direct: rejected** — the router INPUT firewall accepts mgmt services
  (`22,8728,8729,8291,80,443`) and SNMP/161 **only from the Mgmt VLAN + `trusted-admin`**
  (`roles/router/tasks/main.yml`, HD-78/HD-53), then drops everything else (including the
  wg-s2s side). Opening wg-s2s to mgmt ports is a security regression.
- **SNMP extension (walk ARP `1.3.6.1.2.1.4.22` + FDB `1.3.6.1.2.1.17.4.3` + MikroTik DHCP
  MIB in `snmp.yml.j2`): kept as a **backstop only**.** Already-plumbed (the
  `prometheus.exporter.snmp` block already runs on oldsrv, `alloy.river.j2` L111),
  but gives no lease hostname/status richness and **no wifi-qcom-ac client data at all**
  (registration lives in the API path only). Device-side SNMP stays HD-03 deploy-gated.
- **Loki log-derivation: rejected** — brittle string-parsing; router logs don't emit every
  lease/ARP event with structured fields.
- **API collector on oldsrv (chosen).** oldsrv is on the Mgmt plane + tunnel legs, so the
  API is INPUT-legal — the same reachability that already justifies its SNMP exporter.
  Reuses the existing read-only API pattern: `skills/mikrotik/scripts/mikrotik-read.py` on
  RouterOS API `:8728` with a scoped `read`-group user (the `logpipe` precedent,
  `roles/router/tasks/main.yml` L1405). Exposes Prometheus-format metrics; the existing oldsrv
  Alloy `remote_write`s them over `wg-s2s` → VPS VictoriaMetrics (same channel as SNMP). **No
  new firewall open, no VPS reachability change.**

**Metric shape.** One gauge series, info-card style, enriched at authoring time from the
rendered SSOT (`network_static_hosts` is available to the Ansible-rendered exporter):

```
mikrotik_client{dhcp_status="bound", vlan="10", hostname="phone-domen", mac="AA:BB:…", ip="<ip from SSOT row>", source="dhcp|arp|fdb|wifi|static"} 1
```

- Union leases + ARP + FDB + wifi-reg, de-duped by MAC; `source` records which view found it.
- Static SSOT rows are emitted once as `mikrotik_static_host{vlan,hostname,ip}` (or matched
  at query time) — they never change and need no scrape; they are the naming/VLAN ground truth.
- Scrape interval ~30–60 s; exporter placed alongside the SNMP block, scoped
  `{% if inventory_hostname == 'oldsrv.kogler.si' %}`.

**Dashboard.** New `homelab-network-clients` in the monitoring role (folder `Homelab`, uid
convention `homelab-*`, datasource uid `prometheus` — same as HD-315 dashboards):

| Panel | View | Query basis |
|-------|------|-------------|
| All clients table | one row per MAC: VLAN badge, hostname (SSOT name else lease hostname), IP, MAC, source | `mikrotik_client` + `mikrotik_static_host` |
| Per-VLAN breakdown | grouped by `vlan` — template variable `vlan` (`label_values`) + sort | `count by (vlan)` |
| VLAN distribution stat | 6 stacked counts (10/20/30/40/50/99) | `count by (vlan)` |
| WiFi vs wired | optional breakdown | `source=wifi` vs others |

**Open before this is called done.**
- Exporter + dashboard are authored and deployed (`roles/monitoring/`: `network-clients-exporter.py.j2` host binary +
  systemd unit + Alloy `prometheus.scrape "network_clients"` + `homelab-network-clients.json`).
- ⏳ Confirm live wifi path: modern `wifi-qcom-ac` registers under `/interface/wifi/registration-table`
  (legacy `/interface/wireless/registration-table` in `skills/mikrotik` is the old path).
- ⏳ Router API reachable from oldsrv (Mgmt) — already the case for the SNMP exporter; re-verify with
  a read-only `mikrotik-read.py` call at deploy time.
- ⏳ Device-side SNMP enable (“if used as backstop”) stays HD-03 deploy-gated; the API collector
  needs only the API service (`/ip/service set api disabled=no`), already INPUT-scoped to Mgmt.

---

## Deferred / TODOs

| Item | When | Notes |
|------|------|-------|
| Pi recorder trim + log strategy | after observability live (HD-19) | recorder trimmed, **not disabled** (keep Logbook/Energy-Dashboard LTS/history_stats); Pi logs → VictoriaLogs + `local` driver buffer + `/var/log` tmpfs — see [Pi SD-card wear strategy](#pi-sd-card-wear-strategy)
| Homematic full-local (HmIP-RFUSB + RaspberryMatic on Pi) | **parked (HD-13)** — HmIP-HAP stays in cloud mode until an HmIP-RFUSB is bought | see `smart-home.md` — affects HAP/HA integration, not metrics flow |
| Container memory working-set metrics (Docker API → VictoriaMetrics) | with the *arr stack | validates the `services.md` RAM budget with real numbers, not estimates |
| **Homelable** (interactive topology/rack visualizer) | **Authored, deploy-gated (HD-45)** — oldsrv, internal-only dashboard. Live health-check map + rack canvas w/ port patching + nmap scan + MCP server. **Not** a metrics/logs/alert backend — it complements Grafana/HD-343 (see §Network Clients Dashboard). Owns the "who's on my network + where" visual that Grafana's per-VLAN tables don't. Deployment spec + onboarding: [`services-admin.md`](services-admin.md) §Homelable. |
| Route alerts to a **Matrix room** (`#homelab`) | with the Matrix stack (HD-46) | optional consolidation — alongside the Signal + SMTP fail-safe; homeserver/exporter only. · [`services-matrix.md`](services-matrix.md) |
| **Home-side tunnel check** (S14) | after Phase 1.5 cutover | blackbox `wg_icmp` probes run FROM the VPS (HD-159); add a router-side netwatch → SNMP trap (or equivalent) so a home↔VPS outage is also observable from home when the VPS path is the broken side |
| **Monitoring role split** (W6) | only when dashboard/rule iteration gets slow | Alloy+VictoriaMetrics+VictoriaLogs+Grafana live in one `monitoring` role — any rule tweak redeploys the chain; split into `tasks/{alloy,victoria-metrics,victoria-logs,grafana}.yml` includes + tags (no structural move needed until it hurts) |
| **Grafana alert-rule provisioning schema** (monitoring role `grafana-rules.yml.j2`) | first deploy of the monitoring role | ⚠ **needs live check:** query+threshold data-model + folder auto-creation unverified against a running Grafana — confirm rules load (Grafana logs) and fire once before trusting alerting |
