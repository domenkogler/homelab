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

> 🟢 **Backend live since 2026-08-22** (Phase 1, VPS): prometheus / loki / grafana / blackbox-exporter deployed and converged — grafana↔prometheus auth gap fixed and datasource verified HTTP 200 (HD-220b); SSO login path repaired 2026-08-24 (edge IP pinned + datasource secret re-applied, HD-240). ✅ **oldsrv Alloy collector LIVE 2026-09-08 (Phase-3/HD-318 converge):** rsyslog (RouterOS 514 receiver, HD-313), CrowdSec-acquisition (VPS-side), SNMP (MikroTik) + the **network-clients exporter (HD-343)** collect on oldsrv and remote_write over wg-s2s — see §Network Clients Dashboard. ✅ **VICTORIA MIGRATION LIVE 2026-09-08 (HD-341/342 cutover, this session):** VictoriaMetrics (:8428) + VictoriaLogs (:9428) replace Prometheus/Loki on the VPS — seeded `victoria-metrics_api`/`victoria-logs_api`, converged VPS, **Grafana datasources API-seeded to VM/VL** (uid `prometheus`→VM, `loki`→VL; stale read-only Loki datasource removed via DB), **Alloy restarted** to load Victoria remote_write (had been running the Sep-3 config — root cause of the empty Host Overview), old prometheus/loki containers stopped, datasource healths + 13 `up` series verified, alert rules evaluate with 0 errors. ✅ **ALERT-ROUTER + SNMP CLEANUP LIVE 2026-09-09 (HD-347):** `homelab-alerts` n8n webhook workflow created + ACTIVATED via the n8n API (200 "Workflow was started", was 404); `signal-cli-rest-api` published on oldsrv Home IP for the VPS n8n over WG; `mikrotik-link-down` alert **removed** (owner decision — empty switch ports aren't real incidents); stale `prometheus-down`/`loki-down` orphans deleted; **`ifName` SNMP labels fixed** (walk + `type: DisplayString`; router/switch per-instance labels); **self-monitoring rules fixed** (per-rule `lt` evaluator for `== 0` exprs + VM/VL self-scrape basic_auth — `victoria-metrics-down`/`victoria-logs-down` now genuinely armed). ⏳ deploy-gated/remaining: nas + Pi **Alloy collectors** (per-node, Phase-4/HD-318c — both hosts already run the same `unix` host-exporter path as oldsrv; converge adds their `node_*` to the Host Overview), contact-point/datasource passwords in the HD-211 rotation batch, device-side SNMP enable (HD-03 cutover), kopia client wiring for `/srv/docker/victoria-*/data`, oldsrv MCP (HD-344), **Signal device link** (owner — no linked device yet, HD-318d; once linked the n8n Signal leg delivers). Alerting/retention sections below remain the authoring spec for those remaining parts.

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
> ⏳ **Deploy-gated:** the Victoria stack replaces Prometheus/Loki on the VPS at the HD-342 converge; until then the live stack is still Prometheus/Loki. This diagram is the target.

- **Single source of truth** for every type of data; no redundant backends.
- **Display:** Grafana (admin analytics) + Homepage (status widget — reachability eyeball view).
- **Removed from earlier drafts:** InfluxDB, Telegraf, Promtail, Uptime Kuma — none are used.

### Victoria* migration decision (HD-341, 2026-09-08) — target state

> **Decision (owner, 2026-09-08):** replace the Prometheus + Loki backends with a **single Victoria stack on the VPS** — one **VictoriaMetrics** (metrics, `victoriametrics:8428`) + one **VictoriaLogs** (logs, `victoriametrics-logs:9428`) — with **multiple writers** (Alloy collectors on oldsrv/nas/Pi/VPS, blackbox/nut/zfs exporters, MikroTik syslog) remote-writing into the single VPS instance. **Grafana stays** (add VM + VictoriaLogs datasources; drop Prometheus/Loki/Dozzle). **MCP AI-debugging servers live on oldsrv** (much more RAM there) pointed at the VPS endpoints over wg-s2s/tailnet — **logs + metrics stay on the VPS** (reliability). Prior research + rationale: [`brainstorming/recent/Prometheus-Vs-victoriastack.md`](../brainstorming/recent/Prometheus-Vs-victoriastack.md). Target state below; implementation = HD-342 (IaC), MCP = HD-344.

```
Alloy (host agent: metrics + logs + SNMP) ──remote_write──▶ VictoriaMetrics (VPS, metrics)
Alloy (logs) ───────────────────────────────push─────────▶ VictoriaLogs   (VPS, logs)
MikroTik (SNMP / syslog) ────────────────────────────────▶ VictoriaMetrics / VictoriaLogs
blackbox / nut / zfs exporters ─────────────scrape/remote─▶ VictoriaMetrics

VictoriaMetrics ──▶ Grafana (stats.kogler.si)  ──webhook──▶ n8n → Signal + email
VictoriaLogs    ──▶ Grafana (logs datasource)

mcp-victoriametrics / mcp-victorialogs (on OLDSRV, RAM) ──wg-s2s/tailnet──▶ VPS Victoria endpoints
```

- **Writers stay on home infra** (oldsrv/nas/Pi Alloy + exporters), buffering over wg-s2s; the **single backend is on the VPS** (reliability, same as today).
- **MCP AI servers on oldsrv** (≈600–700 MB RAM each) — NOT on the VPS/Pi.
- Drop: Prometheus + Loki (replaced by VictoriaMetrics/VictoriaLogs). **Dozzle is KEPT** (live per-container tail convenience — the earlier "drop Dozzle" wording was reverted by the owner; VictoriaLogs adds stored-log search).

### MCP AI-debugging servers on oldsrv (HD-344) — implemented form

> **2026-09-08 (HD-344 IaC authored); 2026-09-14 flipped `enabled: true` + DEPLOYED (oldsrv converge)** — two Docker compose
> services on **oldsrv** — `mcp-victoriametrics` (:8083) + `mcp-victorialogs` (:8084) — fronting the VPS
> Victoria backend for AI tools (**pi, Open WebUI, OpenClaw** for now). ⏳ **Deploy-gated:** oldsrv is
> Phase-3/HD-318 **and** needs the VPS Victoria backend live (HD-342) — both now true; the `enabled:
> true` flip (with the oldsrv converge) deploys them. Rows + `_template_vault_items` already updated in IaC.

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
- **Images (pinned, CONVENTIONS §7):** `mcp_victoriametrics:v1.18.0` +
  `mcp_victorialogs:v1.8.0` (GHCR-tag verified 2026-09-08; Renovate-tracked).
- **Registry:** oldsrv `docker_services` rows — **`enabled: true` since 2026-09-14** (was `enabled: false` until HD-318 + HD-342 both live; the oldsrv converge deploys them).

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

**Tailnet-only (HD-135b follow-up, 2026-08-28):** the observability dashboards (`stats`/`sec`/`traefik`/`logs`/`csui`/`auto`
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
| ~~Metabase (`sec`)~~ | ~~`https://sec.kogler.si` / `https://sec.ts.kogler.si`~~ — **retired 2026-09-14** (VPS); future home = oldsrv |
| Traefik dashboard (`traefik`) | `https://traefik.kogler.si` / `https://traefik.ts.kogler.si` |
| n8n (`auto`, **internal-only**) | `https://auto.kogler.si` / `https://auto.ts.kogler.si` |

The plain `*.kogler.si` names resolve via headscale MagicDNS (`dns.search_domains: [kogler.si]` + **HD-371 (2026-09-15):** the `dns.nameservers` list now puts the **MagicDNS loop `100.100.100.100` first**, so a tailnet device resolves BOTH namespaces locally on any network) and carry
**Authentik Forward-Auth** (same chain as the public edge). The `*.ts.kogler.si` MagicDNS twins are
**ACL-gated** (no forward-auth — the headscale ACL `tag:sidecar:443` is the gate; tailnet-only by
construction). The public CNAMEs from the Phase-1 wave are removed from the IaC SSOT and deleted from
Cloudflare at deploy time (owner action).

> **HD-371 live case (2026-09-15, ✅ RESOLVED + LIVE):** laptop on a mobile hotspot + Tailscale connected, `stats.kogler.si` /
> `llm.kogler.si` → `ERR_NAME_NOT_RESOLVED` while `stats.ts.kogler.si` worked and the phone (same hotspot)
> resolved everything. Root cause: with the old nameservers (Technitium VPS primary only), a remote
> mobile-network source hit the system resolver → NXDOMAIN, while the phone's client-side MagicDNS
> extra_records still answered. The `100.100.100.100`-first fix resolves every tailnet name locally on
> any network; live-verified after the Windows client DNS re-pull (laptop + phone). (The phone `llm.kogler.si/v1` 401 vs `litellm.kogler.si` 502 was a separate litellm
> docker-DNS gap — HD-372, ✅ fixed + LIVE.)

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
| ~~MinIO S3 store health/usage (Immich originals)~~ | ~~minio_exporter (on oldsrv) → Prometheus~~ — retired (HD-135, CIFS) | — |
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
- **SMTP relay (HD-54, Option B — decided):** SMTP2Go (`mail-eu.smtp2go.com:2525`, STARTTLS). Dedicated transactional relay, free-tier 1000/mo, chosen independently of the Infomaniak kSuite decision (HD-30) so the alert fail-safe isn't coupled to personal email. Grafana + NUT share it; creds = `smtp_login` / `smtp_login` (Login items in 1Password). ✅ **Rotation 2026-09-09:** `smtp_login.password` rotated → propagated to **VPS Grafana + Metabase** (compose re-render, verified live env hash), **Pi + oldsrv HA `secrets.yaml`** (role re-render), and **NUT `upssched-cmd` on nas** (inline render — see NUT fix in [hardware-ups.md](hardware-ups.md)).
  - **Connecting (SMTP2Go, EU datacenter — as provided by the account):** server `mail-eu.smtp2go.com`; SMTP port `2525` (default), alternates `8025`, `587`, `80`, `25` — **TLS available on the same ports** (STARTTLS). SSL: `465`, `8465`, `443`. The repo uses `mail-eu.smtp2go.com:2525` + STARTTLS (587 was blocked from the VPS egress — live-verified 2026-09-08 — so 2525 is the SSOT port).
- **Signal:** `signal-cli-rest-api` container, **linked** to Domen's personal number (no second SIM), sends to a dedicated **"Homelab Alerts"** group. Persist the Signal identity volume so it doesn't need re-linking.

### Known gaps / recent fixes (2026-09-08 → 09-09)

- ✅ **`homelab-alerts` webhook workflow LIVE (HD-347, 2026-09-09)** — created + ACTIVATED via the n8n public API (`n8n_api` key; `POST /api/v1/workflows` + `/activate`; workflow JSON versioned in `roles/monitoring/files/n8n/homelab-alerts.workflow.json`). Verified: `POST http://n8n:5678/webhook/homelab-alerts` → **HTTP 200 "Workflow was started"** (was 404). The workflow routes Grafana's alert webhook by `state` (alerting → ⚠️ / resolved → ✅), sends to Signal via `signal-cli-rest-api` (env-driven `SIGNAL_CLI_URL`/`SIGNAL_API_TOKEN`/`SIGNAL_NUMBER`/`SIGNAL_RECIPIENTS`; the Signal HTTP step `onError: continueRegularOutput` so a not-yet-linked signal-cli never breaks delivery). ⏳ **Signal delivery still owner-gated:** no Signal device is linked yet (HD-318d) — link the "Homelab Alerts" group in the signal-cli account, then the Signal leg starts delivering; email routing now happens through n8n.
- ✅ **`signal-cli-rest-api` cross-host leg wired (HD-347)** — the old "no host ports" + "n8n reaches this on services-internal" comment was aspirational: n8n runs on the VPS and couldn't resolve `signal-cli-rest-api` (oldsrv-only overlay). Now published on `{{ oldsrv_home_ip }}:8082` (the same cross-host API-leg pattern as actual-budget :5006 / immich-ml :3003); **port 8080 belongs to pi-dev (HD-355)** — the signal gateway was moved off it to :8082 when the two collided (2026-09-15 converge); auth stays mandatory (`X-Api-Key`, KOPS-002/HD-125).
- ✅ **`mikrotik-link-down` alert REMOVED (HD-347, owner decision)** — the rule fired on every empty switch port (10 simultaneous instances: ether3-8, ether17, ether22-24, sfp-sfpplus1 — no cable, admin up). Owner: "do not alert me this, remove this alert". The intentionally-disabled NAS port (switch ether9, admin down) was already correctly excluded. Rule + its dashboards' matching panels removed from `roles/monitoring/vars/main.yml`.
- ✅ **Stale `prometheus-down`/`loki-down` rules removed (HD-347)** — pre-Victoria leftovers that only existed as live-Grafana orphans (provenance=file but not in the current rules.yml). Deleted from the live instance; next converge renders 17 rules (9 critical + 8 warning).
- ✅ **Self-monitoring rules actually fire now (HD-347)** — two compounding bugs: (1) the rules template hardcoded `evaluator: gt 0`, so every `expr: X == 0` rule (up-down, host-unreachable, wg-s2s-down, victoria-*-down, n8n-down) returned 0 and `gt 0` never fired — now per-rule `eval_type: lt` + `eval_params: [1]` for `== 0` rules; (2) the VPS Alloy `vm_self`/`vl_self` scrapes lacked the `victoria-metrics_api`/`victoria-logs_api` basic auth → `up{job="victoria-metrics"}=0` permanently → now authenticated. `victoria-metrics-down`/`victoria-logs-down`/`wg-s2s-down`/`host-unreachable`/`public-service-down`/`ha-unreachable`/`n8n-down` are now live-capable.
- ✅ **MikroTik SNMP `ifName` labels fixed (HD-347)** — snmp_exporter looked up `1.3.6.1.2.1.31.1.1.1.1` (ifName) but it was **not in the `walk` list** and the lookup lacked `type: DisplayString` → series had no `ifName` (alerts said "interface [no value]") and values rendered as hex (`0x65746865...`). Fixed in `snmp.yml.j2` (add ifName to walk + `type: DisplayString` on both lookups). Live-verified against RB4011 + CRS328 (snmp_exporter 0.30.1 test scrapes). Per-target `instance` (router/switch) labels also added so the two devices no longer collapse into one flat series.
- ✅ **False `DatasourceNoData` alert flood fixed (IaC, 2026-09-08):** Grafana was paging `DatasourceNoData` for `Host disk nearly full` / `Host unreachable` / `ZFS pool nearly full` / `UPS battery low` because several alert rules had `noDataState: Alerting` — they fired on *no data* (missing series), not on real conditions. Fixed in `roles/monitoring/vars/main.yml`: real-condition rules (`host-unreachable`, `host-disk-full`, `zfs-pool-*`, `host-load-high`, `loki-down`, `n8n-down`, ups rules) now `noDataState: NoData` + `execErrState: Error`; only genuine self-monitoring rules (`prometheus-down`, `wg-s2s-down`) keep `Alerting`. Requires re-converge of the monitoring role to take effect.
- ✅ **Remaining `DatasourceNoData` false alerts fixed (IaC, 2026-09-08 follow-on):** after the 2026-09-08 batch above, Grafana still paged `DatasourceNoData` **every minute** for 6–8 rules whose queries matched no series — the exact `noDataState` footgun, but on the rules that batch left at the Grafana default. Live diagnosis (VPS, read-only): with `noDataState: NoData` (default) a rule **fires a synthetic `DatasourceNoData` alert** whenever its PromQL returns no matching series; the UPS rules (`network_ups_tools_*` — battery/charge/runtime series *present*, values healthy, so the threshold matches nothing), `mikrotik-link-down` (live `ifOperStatus{job="alloy-snmp"}` has **0 series** — SNMP not shipping), and `ssl-cert-expiring` (live `probe_ssl_earliest_cert_expiry` has **0 series** — blackbox doesn't emit SSL expiry) were all stuck firing NoData every eval → routed to email via the SMTP fail-safe (the n8n leg is 404 — see below). Fixed in `roles/monitoring/vars/main.yml`: **every remaining rule now carries `noDataState: OK` + `execErrState: Error`** (`ups-battery-low`, `ups-runtime-low`, `ups-on-battery`, `ups-battery-replace`, `public-service-down`, `ha-unreachable`, `mikrotik-link-down`, `ssl-cert-expiring`) — no-data is a **collection gap**, never a real condition; only self-monitoring rules (`victoria-metrics-down`, `victoria-logs-down`, `wg-s2s-down`) keep `execErrState: Alerting`. ⏳ Deploy-gated on the next VPS monitoring converge after the Victoria migration (the monitoring role's datasource tasks must be aligned with the live backend first).
- ✅ **Prometheus self-scrape + n8n self-scrape were missing basic_auth (IaC, 2026-09-08):** `up{job="prometheus"}=0` / `up{job="n8n"}=0` because the prometheus endpoint requires basic auth (`prometheus-internal_api`) but the self-scrape jobs had none. Fixed in `prometheus.yml.j2` — both jobs now carry the same `basic_auth` the Grafana datasource uses. Also `blackbox-exporter` self-target was scraping the wrong path (`/probe` instead of `/metrics`) → `up{job="blackbox-exporter"}=0`; corrected.
- ✅ **HD-347 converge-completion + follow-on fixes (2026-09-09):** VPS `docker_services` converge applied the n8n `SIGNAL_*` env (webhook verified 200 "Workflow was started" with a real alert payload). Three latent bugs caught + fixed during the converge: ① **`_template_vault_items["n8n"]` was missing the two Signal items** (`signal-internal_api`, `signal_api`) → the secret-export dict rendered `vault['signal-internal_api']` as None and the compose render failed with "dict has no attribute" — added both to `roles/docker_services/defaults/main.yml`. ② **`SIGNAL_RECIPIENTS` double-quote YAML bug** — the Jinja `default()` fallback string (the signal-group name) produced a double-quoted YAML value with embedded quotes (invalid YAML, `docker compose config` failed): switched the line to single-quoted YAML `'…'` + `default(…, true)` so an empty SSOT renders the quoted group-name fallback and a UUID SSOT renders `"group.xxx"` correctly. ③ **`tuwunel_version: "1.9.0"` points at a nonexistent docker.io tag** (registry-verified 2026-09-08 assertion was wrong — bare `1.9.0` returns 404; the real tag is `v1.9.0`, same digest sha256:62339669… as `latest`) → corrected to `"v1.9.0"` (matrix was blocking the converge with a failed pull).
- ✅ **spark host-memory OOM alert rules — LIVE (rules `spark-host-mem-oom-warning` / `spark-host-mem-oom-critical`; converged `vps.yml --tags monitoring` 2026-09-17 22:33C, failed=0); tracked as HD-375.** Three global-OOM incidents on spark in 24 h (2026-09-15 ×2, 2026-09-16 ×1) killed the host user session + the vLLM engine. The container memory cage can't protect the host (GPU pages are not cgroup-charged), and Docker's `OOMKilled` is a false negative — the only early warning is host memory.
  - **Gauge (this is the part that was wrong first):** the rules fire on **`usable = MemAvailable − CmaFree`**, `node_memory_MemAvailable_bytes` **minus** `node_memory_CmaFree_bytes`, `job="alloy"`, `instance=~"spark.*"`. On GB10 the GPU carve is CMA and CMA counts as available, so raw `MemAvailable` **inflates as pressure rises** (up to ~9.5 GiB here). The original 2026-09-16 spec (Warning <24 / Critical <18 on raw `MemAvailable`) is **superseded** — it could never have warned before the cliff. `MemFree − CmaFree` is the other rejected form (INVERTED on this box; would restart-storm a healthy engine) — see [spark-incidents.md](spark-incidents.md) #7/#8.
  - **Thresholds are MEASURED, not designed:** `WARN < 12 GiB for 2m` (`noDataState: OK`) / `CRIT < 8 GiB for 1m` (`noDataState: Alerting`). Both real kills landed at **1.62 / 1.64 GiB**, but the lowest value a 60 s scrape ever recorded in those windows was **5.01** — so a rule set at 1.6 could not fire. `node_memory_CmaFree_bytes` is **verified present in VM** (it is NOT in node_exporter's default meminfo whitelist — check that before authoring any future CMA-based rule).
  - **Live operating point (2026-09-18, KV pool 16 GiB):** idle `usable` **18.5 GiB** → WARN margin 6.5 GiB. The 8.2-GiB-pool era idled at 30.4. Under the certified worst case (2×240k ≈ 94.6 % pool) the floor was **17.78 GiB**. Interpretation: the thresholds still clear, but **there is no room for another KV raise in bf16** — one would put WARN into routine-transient range (see [hardware-spark.md](hardware-spark.md) §Unified-memory budget).
  - Deploy preflight (do this before any future change to these rules): confirm the CmaFree series exists, or `noDataState: Alerting` on CRIT becomes a false-positive machine. The paired on-box enforcer is `spark-oom-watchdog` (`roles/spark`, enforcing: CRIT < 8 → planned engine restart, max 2 / 2 h, arm-off file, idle recycle at baseline +8 GiB).
  - ⏳ tail: owner confirms the two rules render in the Grafana UI + that a firing alert reaches n8n. · [hardware-spark.md](hardware-spark.md) §Unified-memory budget · [spark-incidents.md](spark-incidents.md)

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
- **Placement (HD-135 + HD-135b):** the observability **backend** (Prometheus/Loki/Grafana) runs on the **VPS** (reliable tier). **HD-135b (2026-08-28): the VPS is self-sufficient for its own observability** — the VPS host runs its own **Alloy** (`[monitoring]` group, `alloy_backend_host` defaults to `127.0.0.1` → loopback Prometheus/Loki on the same host, no tunnel) and its own **Dozzle** live-log viewer (`logs.kogler.si`, moved from oldsrv). **2026-09-15: a second Dozzle hub runs on oldsrv (`llogs.kogler.si`, LAN-only) showing oldsrv + pi + spark containers via remote agents** (see §Dozzle multi-host below) — the VPS viewer and the home hub are independent (the hub survives WAN-out via the traefik-internal edge). oldsrv/nas/Pi keep thin **Alloy collectors** forwarding *home* telemetry over the `wg-s2s` tunnel (nas's Alloy is host-exporter only — no Docker; it ships nas `node_*` and is still scraped for its nut/zfs exporters by oldsrv). **Dashboards are tailnet-only** (HD-135b follow-up) — no public exposure; access is over the headscale mesh via the **`traefik-tailnet` edge** (`stats`/`sec`/`traefik`/`logs`/`csui`/`auto`, clean subdomain URLs on 443 — see [Access & login path](#access--login-path-statskoglersi) below). **n8n (`auto`) is internal-only** (public route removed from the main edge; reached over the tailnet). The n8n alert brain is on the VPS and emails/Signals over the public net — independent of the tunnel. **SPOF (narrowed):** if the home↔VPS tunnel or the VPS itself is down, *home* metrics/logs are unavailable in Grafana (the nesting is graceful: buffered, replayed on reconnect; NUT-side `notifycmd`/`upssched-cmd` on nas is the grounds for power-loss alerts independent of the stack). The **VPS's own** metrics/logs remain available locally even with the tunnel down (loopback Alloy → local Prometheus/Loki → local grafana/dozzle).
- **Dozzle is not a second log backend** — it streams live logs straight from the Docker API (read-only socket) and persists nothing. VictoriaLogs stays the single stored-log source (90d) and Grafana the search/alert surface.

### Dozzle multi-host (2026-09-15) — VPS viewer + LAN hub

Owner design: the VPS keeps the VPS-only viewer (`logs.kogler.si`), and **oldsrv runs a LAN log HUB**
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

- **LIVE 2026-09-15 (oldsrv + pi + spark converges, failed=0):** hub `:8081` HTTP 200 via
  `traefik-internal` + direct; agents on all 3 home hosts (`:7007`, LAN-only, healthy); VPS
  viewer (`logs.kogler.si`) untouched. **✔️ `llogs.kogler.si` RESOLVED + LIVE-VERIFIED 2026-09-15**
  (via `playbooks/dns-seed.yml` — the one-command re-seed of all three Technitium instances,
  see [`network-dns.md`](network-dns.md) §Convergence & Drift): the Pi converge was scoped to
  `dozzle-agent` so the `technitium-seed` tail had not run on the Pi; the re-seed ran the
  full split-horizon set on Pi + oldsrv + VPS (`failed=0`), and live `dig` confirms
  `llogs.kogler.si → {{ oldsrv_home_ip }}` on both home instances + **no answer on the VPS primary**
  (LAN-only, correct). The per-host `dns-seed.timer` self-heal is now **active on all three**
  hosts (VPS/oldsrv/Pi), so this class self-heals going forward.
  ⚠️ **Two findings that remain OPEN (owner/follow-up):** (1) **oldsrv `traefik-internal` serves `TRAEFIK DEFAULT CERT`** (self-signed fallback) → Chrome "Not Secure" on `media.kogler.si`/`llogs` — the wildcard pair isn't in `traefik-internal/certs`; the `traefik-cert-pull` timer is armed but `/root/.ssh/traefik-cert-sync` is **not authorized on the VPS** (manual LIVE step, [services-traefik.md](services-traefik.md) §Edge model) → pull 401s → fallback cert. **Owner:** authorize the pubkey on VPS `ansible-admin` → `systemctl start traefik-cert-pull.service` → restart `traefik-internal` → verify `CN=*.kogler.si`. (2) **a phone 404ing `llogs` is resolving it to the VPS public edge** (Let's Encrypt + 404 = `traefik-tailnet`/`traefik-ha`, NO `llogs` route — correct LAN-only design) → the phone **bypasses RouterOS DHCP DNS** (Android Private DNS/VPN/DoH). Fix client-side or router DNS force; **do not** add `llogs` to the VPS primary.

- **Loki access control (HD-115 / KOPS-023/051):** Loki runs with `auth_enabled: true` (multi-tenant) — pushes and queries must carry the `logs` tenant ID, wired through Alloy (`tenant_id = "logs"`) and the Grafana datasource (`jsonData.tenantId`). The **write** path is loopback-only (Alloy → `127.0.0.1:3100`, no db-internal requirement) and **reads** come only from Grafana on `db-internal`; Loki is never exposed on traefik-public or any LAN bind. **Accepted caveat:** Loki-native `auth_enabled` is tenant *isolation*, not a password gate — a compromised db-internal container could forge a tenant header. Acceptable for the trusted-`db-internal` Phase-1 set; re-evaluate (real credential gateway / separate write+read tenants) if more members join `db-internal`.
- **Pi keeps only a tiny bounded local log buffer.** The Raspberry Pi primary holds **no durable log store** — Docker uses log driver `local` (`max-size: 10m, max-file: 2`) as RAM/disk resilience when oldsrv/VictoriaLogs is down; the durable, searchable copy lives in VictoriaLogs. Host OS logs run on tmpfs (`journald Storage=volatile` + `/var/log` tmpfs). See [Pi SD-card wear strategy](#pi-sd-card-wear-strategy).
- **HA exporter** on the HA instance (Raspberry Pi 4 primary; cold-standby container on oldsrv — see [`smart-home-failover.md`](smart-home-failover.md)). Only the live instance is scraped (via the VIP); on failover the same URL resumes with no replay.
- **Decided (no longer open):** per-host Alloy `instance` label = `{{ inventory_hostname }}` — implemented in `alloy.river.j2` (**HD-116** / KOPS-036, closes HD-55), so series no longer collide across hosts. MikroTik SNMP community = dedicated read-only **`network-snmp_api`** (1Password, fail-loud lookup in `snmp.yml.j2`) + Mgmt-VLAN-only INPUT ACL — decided **HD-53** / KOPS-034; the device-side `/snmp enable` + community set stays an HD-03 deploy step.

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

> _Provisioned via the monitoring role (`files/dashboards/*.json` → `/etc/grafana/provisioning/dashboards`, 30s hot-reload by the file provider). Datasource uid = `prometheus` (API-seeded by the monitoring role — see `tasks/main.yml`). **LIVE 2026-09-03** — the 5 HD-315 dashboards + ups were copied to `/srv/docker/grafana/provisioning/dashboards/` by the VPS monitoring converge. **LIVE-FIXES 2026-09-08 (HD-346):** Host Overview + Overview host panels repopulated by wiring Alloy's `unix` host exporter (node_* now flowing — VPS 1,641 + oldsrv 1,096 series, both with `job=alloy`/`instance=<host>`); Service Reachability / WAN & Tunnel blackbox + wg panels repopulated by fixing the blackbox probe family (container egress + IPv4 forcing + correct Alloy target pattern); **oldsrv Alloy fixed** (was failed: invalid `forward_to` in `exporter.snmp` + missing `name` on SNMP targets + invalid `timeout/retries` in `snmp.yml` auth — now active, remote-writing to VM) → Network Clients (`mikrotik_client`, 40 series) + UPS (`network_ups_tools_*`) dashboards now populate. **Remaining empty: MikroTik SNMP** (`ifOperStatus` on router/switch) — device-side `/snmp enable` + RO community (HD-03/HD-53) still pending on the RB4011/CRS328 (SNMP port refused); the SNMP exporter + Alloy scrape are wired and ready. Owner step: panel render verification._

> **vLLM dashboards (HD-368, 2026-09-14):** three Grafana-com templates were adapted into this folder (`llm-inference-sglang-vllm` gnet 25502, `vllm-master-v2` gnet 24756, `vllm-dashboard` gnet 25043) — stripped of the grafana.com `__inputs`/`__requires`/`id`/`gnetId` scaffolding, `${DS_PROMETHEUS}` rewritten to the literal `prometheus` datasource uid, uids reissued as `homelab-*`, homelab tags/time/refresh applied. **Data path:** the spark-ai compose publishes vLLM's `:8000` **loopback-only** (`spark_metrics_publish`, traefik `127.0.0.1:8082` precedent) → the **spark Alloy** scrapes `vllm:/metrics` (`prometheus.scrape "vllm"`, `instance=spark.kogler.si`) → remote_write → VPS VM. vLLM serves `/metrics` on the API-server port (PrometheusStatLogger, `vllm:*` metric family, `model_name` label native; `instance` comes from the scrape target). The engine was flipped `spark-ai.enabled: true` 2026-09-14 by the HD-367 Track-1 session (`9445d35`).
>
> **✅ vLLM dashboards LIVE + CLOSED 2026-09-16 (HD-368; row deleted per §4(a), record lives here).** **Owner visual round-trip on `stats.kogler.si` confirmed all three dashboards render with data.** Deploy: `playbooks/vps.yml --limit vps.kogler.si --tags monitoring` converge (failed=0, changed=3: Alloy config + `Copy Grafana dashboards` + alert rules); the file provider hot-loaded them, and the Grafana API confirms all three uids at `version 2` in the `Homelab` folder with **zero stale metric refs and zero non-English titles**. Close-out evidence: spark engine `vllm-qwen-spark` serves `/health` 200 + **415 `vllm:` sample lines** on the loopback `:8000`; the spark Alloy config carries `prometheus.scrape "vllm"` and remote-writes it; VM holds **137 distinct `job="vllm"` series** for `instance="spark.kogler.si"` (`vllm:kv_cache_usage_perc`, `vllm:prefix_cache_*`, `vllm:time_to_first_token_seconds_bucket` — TTFT p99 ≈ 19 s at 250k-context fill, `up{job="vllm"}=1`). The three JSONs were already provisioned on the VPS (copied by the 2026-09-15 monitoring converge), so the gap was **not** the pipeline but **queries that can never resolve on our deployment**. Live audit (every panel `expr` diffed against the live `/metrics` set AND the VM `job="vllm"` series set) found and fixed:
> - **V0-era metric removed in V1** — `vllm:num_requests_swapped` (V2 dashboard, Scheduler State) → `vllm:num_requests_waiting_by_reason` (`reason=capacity|deferred`).
> - **K8s production-stack-only metrics** — `vllm:healthy_pods_total` → `sum(up{job="vllm"})`; `vllm:current_qps` → `sum(rate(vllm:request_success_total[…]))`; `router_{cpu,memory,disk}_usage_percent` (the stack's router hostmetrics we do not run) → the **spark host** via the Alloy unix exporter (`node_cpu_seconds_total`/`node_memory_*`/`node_filesystem_*`, `job="alloy"`, `instance="spark.kogler.si"`, HD-346) — live: CPU 11.7 %, mem 81.6 %, disk(/) 21.4 %.
> - **Renamed in V1** — `vllm:gpu_prefix_cache_{hits,queries}_total` → `vllm:prefix_cache_*` (and the K8s `endpoint="service-port"` label dropped) — live hit ratio 0.97.
> - **Not emitted by this engine build** — `vllm:kv_block_idle_before_evict_seconds_bucket` → the panel now shows KV pressure via `vllm:num_preemptions_total` (rate + window).
> - **Unscoped process metrics** — `process_resident_memory_bytes` / `python_gc_collections_total` existed for 12 jobs in VM (so the panel plotted every process in the homelab) → scoped `job="vllm"`.
> - **Stale upstream `current:`** — the gnet 25502 export shipped `model_name = /models/DeepSeek-V4-Flash` (the author's model); reset so Grafana auto-selects the live value (`spark/qwen3.8-flash-next`). Left as-shipped, every panel behind that variable renders No data.
>
> **Reproducible, not hand-edited:** all of the above lives in the drift layer of
> [`scripts/adapt-vllm-dashboards.py`](../scripts/adapt-vllm-dashboards.py) (`EXPR_REWRITES` /
> `PANEL_OVERRIDES` / `VAR_OVERRIDES` / `TEXT_TRANSLATE` / `STALE_METRICS`) — re-download the
> grafana.com exports and re-run the script to re-derive the same files; it fails loud on an
> unapplied rewrite, a surviving stale metric or an unmapped non-English string, and is
> byte-idempotent on re-runs. It also **English-ises the operator-visible strings** (the exports
> carried Chinese titles/tooltips in 25502, Korean in 24756) per the repo language rule.
>
> **Search result (2026-09-16, what else exists):** the three adopted exports are all still at
> **revision 1** upstream (`grafana.com/api/dashboards/<id>`), so nothing to pull. Candidates
> considered and **not** adopted: **gnet 25263** "vLLM Metrics" (8 panels, 7 live — thin
> overlap with what we already have) and **gnet 25620** "vLLM Serving Overview" (actively
> revised, but queries an `llm:*` **recording-rule** layer + a simulated-GPU panel → 7/13
> panels dead without Prometheus recording rules we do not run). The official vLLM repo also
> ships `examples/online_serving/dashboards/grafana/{performance,query}_statistics.json` —
> version-matched but per-request debugging, covered by the V2 dashboard here. Rejected for
> bloat/absence, not for quality.

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
| **★ LLM** *(HD-377, ⏳ deploy-gated)* | `homelab-llm` | **the unified inference dashboard — the merge of the three rows above into one board** (owner: "instead of many dashboards, I want 1"): readiness → spark node (CPU/RAM/GPU + **disk capacity and disk I/O**) → scheduling → latency → throughput → cache → reliability → request shape → per-engine detail → forward-look. Generated by [`scripts/build-llm-dashboard.py`](../scripts/build-llm-dashboard.py); see **§LLM Dashboard** below. The three HD-368 dashboards stay provisioned until the owner signs off. | 48 panels / 10 rows; **43 of 47 query metric names live in VM today** for the vLLM half (+ the `node_disk_*` I/O families, live) — the 3 absent are the DCGM profiling panels, which are **impossible on GB10 and must be deleted, not wired** (see §LLM Dashboard → GPU) · `vllm:*` + `node_*{job="alloy",instance="spark.kogler.si"}` + `process_*{job=~"vllm|sglang"}` · every query joined `by (job, instance)` + scoped to `$instance` |

---

### LLM Dashboard (HD-377)

> **Role:** design SSOT for the **single** LLM/inference Grafana board (`homelab-llm`,
> `stats.kogler.si`) — the merge of the three HD-368 vLLM dashboards plus the spark node
> + readiness panels the owner asked for. Registered as HD-377 in `todo.md` §2.12.
> **⏳ deploy-gated:** authored + live-verified against VM 2026-09-16; not yet converged.

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

**GPU on a GB10 — what is and is NOT obtainable (verified live 2026-09-16, twice).**
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

**What DCGM actually delivers here (measured by running the on-disk image, 2026-09-16).**
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

**✅ DCGM is WIRED (HD-379, 2026-09-16) — the six signals that are real on GB10.**

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

**✅ Deployed + live-verified 2026-09-16.** `VM {job="dcgm"}` returns **exactly the 7 whitelisted
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
GPU-reserve arithmetic against this pool. The RAM % panel's thresholds are the HD-375
alert reserve (warn < 24 GiB / crit < 16 GiB available ≈ 80 % / 87 % used).

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

## Host sensors and disk I/O (HD-378)

Owner ask (2026-09-16): the unified board must cover **CPU, GPU, RAM and DISK io/throughput**
from spark — and temperatures belong on **Host Overview**, not on the LLM board. Two gaps
were found and closed; one turned out not to be a gap at all.

**Disk I/O needed no new telemetry.** `prometheus.exporter.unix "host"` has enabled the
`diskstats` collector from the start, so the I/O families were already in VM — verified per
family for `instance="spark.kogler.si", device="nvme0n1"` on 2026-09-16:
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

✅ **Deploy state (2026-09-16, same session):** converged and **verified from the backend, not
from the playbook recap** — `node_hwmon_temp_celsius` now exists per instance: **spark 12,
oldsrv 17, nas 9, pi 2** sensors. The disk panels needed no converge at all (the families were
already in VM); they shipped with the dashboard copy. The in-panel ⏳ wording on the two
temperature panels is now historical — if a temp panel renders empty for some host, that host's
Alloy has not picked up `set_collectors` yet (check `alloy.service` restart), it is not a
dashboard bug.

⚠ **Converge note that cost an hour (HD-379):** a new/changed Alloy config converges under
`--tags monitoring`, but the **first deploy of a compose service needs the service's own tag**
(`--tags monitoring,docker_services,<name>`) or the deploy tasks are silently skipped while the
run still reports `failed=0`. Proof = a backend query / `docker ps`, never the recap.


> **Metric-name gaps (authoring-time, 2026-09-04):** the panel expression names above match the **alert-rule metric names** in the monitoring role (`vars/main.yml`) and the Prometheus scrape jobs — but several component metrics are **not yet verified live** (no running instance to scrape until the next converge):
> - `traefik_requests_total` — **✅ CLOSED 2026-09-04 (IaC + live):** the Traefik compose now enables a Prometheus metrics endpoint on the main edge (`--metrics.prometheus=true` + `--entryPoints.metrics.address=:8082` + `db-internal` net join so Prometheus can resolve `traefik:8082`). **Live-verified:** `up{job="traefik"}=1` + `traefik_entrypoint_requests_total` flowing (v3 name — the dashboards use `traefik_entrypoint_requests_total`, NOT the v2 `traefik_requests_total`).
> - `network_ups_tools_*` (UPS) — **✅ RESOLVED 2026-09-04:** DRuggeri/nut_exporter v3 emits `network_ups_tools_*` (battery_charge/runtime/voltage, output_voltage, ups_load, per-flag `ups_status`) via `/ups_metrics?ups=powerwalker` — NOT `nut_*`. Prometheus scrape (metrics_path+params), alert rules + UPS dashboard all updated to match. **✅ Exporter PINNED (2026-09-04, HD-315):** `roles/nut/defaults/main.yml` `nut_exporter_release: "v3.3.0"` (latest tagged release 2026-05-15, replacing the earlier `@latest`→`(devel)` drift); binary already deployed on nas (`3.3.0`, verified live). Renovate trails the tag.
> - `node_cpu_seconds_total` / `node_uname_info` — the Alloy `unix` exporter's exact series names are node_exporter-compatible (occupying the `job="alloy"` namespace); the dashboard reads them generically. **✅ FIXED + LIVE 2026-09-08 (HD-346):** the `prometheus.exporter.unix "host"` block was declared but never consumed (Alloy components are lazy) → zero `node_*` series. Wired it via `discovery.relabel "host_metrics"` + `prometheus.scrape "host_metrics"` (tag `job="alloy"`, `instance=vps.kogler.si`). VM now has 1,641 `node_*` series; Host Overview + Overview host panels populate.
> - `crowdsec_decisions` — **✅ FIXED (2026-09-08):** the WAN dashboard queried a phantom name; the real CrowdSec metric is **`cs_active_decisions`** (Gauge, labels `reason`/`origin`/`action` — live-verified 10 series, `origin=CAPI`). Dashboard query updated.


---

## Network Clients Dashboard (HD-343)

> **Role:** design SSOT (authoring spec) for the “all network clients, grouped per VLAN”
> Grafana dashboard at `stats.kogler.si`. Registered as HD-343 in `todo.md` §2.3.
> **2026-09-08 (HD-343): exporter role + dashboard JSON AUTHORED in
> `IaC/ansible/roles/monitoring/`** (host-binary `network-clients-exporter` on oldsrv +
> `homelab-network-clients` dashboard). **LIVE 2026-09-08 (oldsrv converge):** exporter
> deployed + verified — runs as `networkclients` (0750 root:networkclients), pinned
> `routeros-api==0.21.0` in `/opt/network-clients-exporter` venv (trixie has no
> `python3-routeros-api` apt pkg; the exporter imports PyPI `routeros_api`), `ROUTER_TLS`
> bool-render fixed; unit active, `/metrics` serves real `mikrotik_client` union
> (DHCP/ARP/FDB/wifi from the RB4011 `logpipe` read-only user). ⏳ **Owner/verify steps:**
> live wifi-path verify (`/interface/wifi/registration-table` vs legacy), owner
> render-verify, dashboard reachable on `stats.kogler.si` after the VPS Grafana
> provisioning converge (VPS-side, post-Victoria).

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

**Gates before implementation.**
- ✅ `todo.md` HD-343 row exists (this design).
- ✅ **2026-09-08: exporter role + dashboard JSON authored** in `IaC/ansible/roles/monitoring/`
  (`network-clients-exporter.py.j2` host binary + systemd unit + Alloy `prometheus.scrape`
  `network_clients` + `homelab-network-clients.json` dashboard).
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
| **Homelable** (interactive topology/rack visualizer) | **Implementation authored, deploy-gated (HD-45, 2026-09-09)** — oldsrv, internal-only dashboard. Live health-check map + rack canvas w/ port patching + nmap scan + MCP server. **Not** a metrics/logs/alert backend — it complements Grafana/HD-343 (see §Network Clients Dashboard). Owns the "who's on my network + where" visual that Grafana's per-VLAN tables don't. Deployment spec + onboarding: [`services-admin.md`](services-admin.md) §Homelable. |
| Route alerts to a **Matrix room** (`#homelab`) | with the Matrix stack (HD-46) | optional consolidation — alongside the Signal + SMTP fail-safe; homeserver/exporter only. · [`services-matrix.md`](services-matrix.md) |
| **Home-side tunnel check** (S14) | after Phase 1.5 cutover | blackbox `wg_icmp` probes run FROM the VPS (HD-159); add a router-side netwatch → SNMP trap (or equivalent) so a home↔VPS outage is also observable from home when the VPS path is the broken side |
| **Monitoring role split** (W6) | only when dashboard/rule iteration gets slow | Alloy+VictoriaMetrics+VictoriaLogs+Grafana live in one `monitoring` role — any rule tweak redeploys the chain; split into `tasks/{alloy,victoria-metrics,victoria-logs,grafana}.yml` includes + tags (no structural move needed until it hurts) |
| **Grafana alert-rule provisioning schema** (monitoring role `grafana-rules.yml.j2`) | first deploy of the monitoring role | ⚠ **needs live check:** query+threshold data-model + folder auto-creation unverified against a running Grafana — confirm rules load (Grafana logs) and fire once before trusting alerting |
