---
title: Observability
domain: observability
role: ssot
status: active
tags: [observability, grafana, prometheus, monitoring]
---
# Observability

> **Role:** Single source of truth — the complete observability stack as a domain (Prometheus/Loki/Grafana + Alloy/exporters + alerting).
> **Links to:** `interfaces.md`, `deployment-ansible.md`, `smart-home.md`, `backup.md`, `services.md`
> **Linked from:** `index.md`, `interfaces.md`, `services.md`

> 🟢 **Backend live since 2026-08-22** (Phase 1, VPS): prometheus / loki / grafana / blackbox-exporter deployed and converged — grafana↔prometheus auth gap fixed and datasource verified HTTP 200 (HD-220b); SSO login path repaired 2026-08-24 (edge IP pinned + datasource secret re-applied, HD-240). ⏳ deploy-gated: oldsrv/Pi **Alloy collectors** (come online with their hosts, Phase 3/4), alerting/contact-point live-verify (HD-08; contactpoint/datasource passwords sit in the HD-211 rotation batch), device-side SNMP enable (HD-03 cutover). Alerting/retention sections below remain the authoring spec for those gated parts.

---

## Architecture

```
Alloy (host agent: metrics + logs + SNMP, has docker.sock)
   ├─ remote_write ──▶ Prometheus  (THE metrics store, 30d)
   └─ push ──────────▶ Loki        (logs, 14d)
Dozzle (read-only docker.sock) ─────▶ live per-container log tail (ops, no storage)
Home Assistant (SWO-B + ComfoAir) ──Prometheus exporter──▶ Prometheus
MikroTik (SNMP, 5–15s poll) ─────────────────────────────▶ Prometheus
blackbox_exporter (external reachability) ───────────────▶ Prometheus  (probe_success)
nut_exporter (UPS, on nas) ──────────────────────────────▶ Prometheus  (battery/runtime/voltage)

                        Prometheus ──▶ Grafana (stats.kogler.si, internal, Authentik admin-only)
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

---

## Component Table

| Layer | Service | Role | Network | Retention |
|-------|---------|------|---------|-----------|
| Agent | **Alloy** | Host metrics + logs + SNMP; replaces Promtail/Telegraf/scraper | host (`docker.sock`) → `services-internal` | — |
| Backend | **Prometheus** | Sole metrics store | `db-internal` | 30d |
| Backend | **Loki** | Log aggregation, single-node/SSD | `db-internal` | 14d |
| Exporter | **blackbox** | External reachability (`probe_success`) | `services-internal` | in Prometheus |
| Exporter | **HA Prometheus exporter** | HA entities → Prometheus | `services-internal` | in Prometheus |
| Exporter | **nut_exporter** | UPS status (battery/runtime/voltage/load) → Prometheus · single instance on **nas** (NUT master) | `services-internal` | in Prometheus |
| ~~Exporter~~ | ~~**minio_exporter**~~ | ~~MinIO S3 store~~ — **retired (HD-135): Immich originals = live Hetzner Box (CIFS), not S3/MinIO** | — | — |
| UI | **Grafana** | Dashboards, `stats.kogler.si` (**internal**) | `traefik-public` **+** `db-internal` | — |
| Router | **n8n** | Alert routing/dedup → Signal/email | `services-internal` | — |
| Notify | **signal-cli** | Signal delivery (linked device) | `services-internal` (needs internet) | — |
| Viewer | **Dozzle** | Live per-container log streaming for ALL containers (read-only `docker.sock`); tailnet-only `logs.kogler.si` / `logs.ts.kogler.si` via the `traefik-tailnet` edge; **viewer only — nothing stored** | `traefik-public` | — |

## Access & login path (stats.kogler.si)

**Tailnet-only (HD-135b follow-up, 2026-08-28):** the observability dashboards (`stats`/`sec`/`traefik`/`logs`/`csui`/`auto`
and by extension the underlying prometheus/loki/blackbox) have **no public DNS record** and are **not
WAN-reachable**. They are reached over the **headscale tailnet** from admin devices via the
**`traefik-tailnet` edge** (node `vps-obs`) — a consumer-mode Traefik (+ userspace tailscale sidecar
sharing its netns) that serves the dashboards with **clean subdomain URLs** and no port numbers
(see [`network-vpn.md`](network-vpn.md) §Tailnet-exposed services and the `docker_services/traefik-tailnet`
compose):

| App | URL (tailnet) |
|-----|---------------|
| Grafana (`stats`) | `https://stats.kogler.si` / `https://stats.ts.kogler.si` |
| Dozzle (`logs`) | `https://logs.kogler.si` / `https://logs.ts.kogler.si` |
| CrowdSec Web UI (`csui`) | `https://csui.kogler.si` / `https://csui.ts.kogler.si` |
| Metabase (`sec`) | `https://sec.kogler.si` / `https://sec.ts.kogler.si` |
| Traefik dashboard (`traefik`) | `https://traefik.kogler.si` / `https://traefik.ts.kogler.si` |
| n8n (`auto`, **internal-only**) | `https://auto.kogler.si` / `https://auto.ts.kogler.si` |

The plain `*.kogler.si` names resolve via headscale MagicDNS (`dns.search_domains: [kogler.si]`) and carry
**Authentik Forward-Auth** (same chain as the public edge). The `*.ts.kogler.si` MagicDNS twins are
**ACL-gated** (no forward-auth — the headscale ACL `tag:sidecar:443` is the gate; tailnet-only by
construction). The public CNAMEs from the Phase-1 wave are removed from the IaC SSOT and deleted from
Cloudflare at deploy time (owner action).

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
| Host + SNMP metrics | Alloy → Prometheus | Prometheus (30d) |
| Service scrape (Traefik, CrowdSec) | Alloy/Prometheus | Prometheus (30d) |
| HA entity metrics (weather, ComfoAir) | HA exporter → Prometheus | Prometheus (30d) |
| External reachability | blackbox → `probe_success` | Prometheus (30d) |
| UPS status (battery, runtime, voltage, load, online/on-batt) | nut_exporter (on nas) → Prometheus | Prometheus (30d) |
| ~~MinIO S3 store health/usage (Immich originals)~~ | ~~minio_exporter (on oldsrv) → Prometheus~~ — retired (HD-135, CIFS) | — |
| Logs | Alloy → Loki | Loki (14d) |
| RouterOS logs (RB4011/switch/AP) | RFC5424 syslog → VPS rsyslog → CrowdSec/Loki | Loki (14d) (HD-313) |
| Live logs (ops day-to-day tail) | Dozzle (read-only viewer, no storage) | ephemeral — nothing persisted |
| Alerts | Grafana Alerting → n8n → Signal/email | alert delivery |
| Display | Grafana + Homepage | — |

---

## Alerting

- **Engine:** Grafana Unified Alerting (rules live with the data; no separate Alertmanager).
- **Router:** alerts → n8n webhook → normalize / dedup / tier / format → Signal + email. n8n also serves office automation ([`services-office.md`](services-office.md)).
- **Webhook:** Grafana's contact point posts to `grafana_alert_webhook_url` (group_var, default `http://n8n:5678/webhook/homelab-alerts`, traefik-public). ⚠ The n8n workflow **`homelab-alerts`** on that route must exist before the first alert fires (created at n8n setup; payload = Grafana alert-notification webhook, see the monitoring role `grafana-contactpoints.yml.j2`).
- **Fail-safe:** Grafana-native SMTP contact point runs in parallel — alerts still go out if n8n/signal-cli is down.
- **SMTP relay (HD-54, Option B — decided):** SMTP2Go (`mail-eu.smtp2go.com:587`, STARTTLS). Dedicated transactional relay, free-tier 1000/mo, chosen independently of the Infomaniak kSuite decision (HD-30) so the alert fail-safe isn't coupled to personal email. Grafana + NUT share it; creds = `smtp_login` / `smtp_login` (Login items in 1Password).
  - **Connecting (SMTP2Go, EU datacenter — as provided by the account):** server `mail-eu.smtp2go.com`; SMTP port `2525` (default), alternates `8025`, `587`, `80`, `25` — **TLS available on the same ports** (STARTTLS). SSL: `465`, `8465`, `443`. The repo uses `mail-eu.smtp2go.com:587` + STARTTLS (matches the NUT template's hardcoded `smtp.SMTP(server, 587)` + `starttls()`).
- **Signal:** `signal-cli-rest-api` container, **linked** to Domen's personal number (no second SIM), sends to a dedicated **"Homelab Alerts"** group. Persist the Signal identity volume so it doesn't need re-linking.

### Tiers

| Severity | What alerts | Channel | Notes |
|----------|-------------|---------|-------|
| **Critical** | oldsrv disk ≥90%, **nas ZFS pool usage ≥80% (`tank` & `bulk`)**, host down, ZFS pool degraded, service down >2min, `probe_success==0` · **UPS battery <20% or runtime <5 min (impending shutdown)** | Signal + email | page-worthy |
| **Warning** | container restart loop, high CPU/load, HA unreachable, MikroTik link down, **nas pool ≥70%** · **UPS on-battery / mains lost (auto-clear on return)** | Signal (deduped) | sent once |
| **Info** | transient / everything else · **UPS online ↔ on-battery transitions / restored** | logged only | no push |

- **Poke/throttle:** re-send only if still firing after ~30 min (prevents overnight alert floods).
- **Self-monitoring:** the observability stack itself (Prometheus/Loki/n8n down) must alert — otherwise the alert channel dies silently.

---

## UPS / Power-Loss Monitoring (NUT)

- **Metrics (single source):** one **nut_exporter** on **nas** (the NUT master) reads local `upsd` → Prometheus. Other hosts do **not** re-export identical UPS data (avoids redundancy).
- **Shutdown:** **NUT owns local shutdown** on `nas`, `oldsrv`, and `ha` (Raspberry Pi). Grafana/n8n are **alert-only** — there is **no shutdown action from Grafana** (the observability **backend is on the VPS**, so it must never be the thing that halts the NAS during a power cut; only the host NUT agents power their own box).
- **Notification ordering & delay:** on mains loss the **Warning "on-battery" alerts at t=0** (WAN still up via router/ONT on UPS → Signal + email deliver). At **Critical**, `oldsrv` is **delayed ~60 s** before powerdown (via NUT `upssched`) so its own Grafana→n8n→Signal/email pipeline flushes the Critical alert, then it powers off. `nas` + `ha` power down immediately.
- **Guaranteed fallback:** a **NUT-side `notifycmd`/`upssched-cmd` script on nas** emails + sends Signal directly on `ONBATT` and `LOWBATT`, independent of Grafana/n8n — so a pre-shutdown notification is sent even if the observability stack is already degraded.
- Registered/configured via the `nut` Ansible role — see [`deployment-ansible.md`](deployment-ansible.md).

---

## Microservice Notes

- **MikroTik SNMP:** poll at **5–15 s**; the "1s" in dashboards is a *refresh* interval, not a poll.
- **Retention is deliberate:** 30d metrics / 14d logs. TSDB data is **regenerable and not backed up** (see [backup.md](backup.md)); long-term metric history is a deferred option (remote-write/downsampling).
- **Placement (HD-135 + HD-135b):** the observability **backend** (Prometheus/Loki/Grafana) runs on the **VPS** (reliable tier). **HD-135b (2026-08-28): the VPS is self-sufficient for its own observability** — the VPS host runs its own **Alloy** (`[monitoring]` group, `alloy_backend_host` defaults to `127.0.0.1` → loopback Prometheus/Loki on the same host, no tunnel) and its own **Dozzle** live-log viewer (`logs.kogler.si`, moved from oldsrv). oldsrv/Pi keep thin **Alloy collectors** forwarding *home* telemetry over the `wg-s2s` tunnel. **Dashboards are tailnet-only** (HD-135b follow-up) — no public exposure; access is over the headscale mesh via the **`traefik-tailnet` edge** (`stats`/`sec`/`traefik`/`logs`/`csui`/`auto`, clean subdomain URLs on 443 — see [Access & login path](#access--login-path-statskoglersi) below). **n8n (`auto`) is internal-only** (public route removed from the main edge; reached over the tailnet). The n8n alert brain is on the VPS and emails/Signals over the public net — independent of the tunnel. **SPOF (narrowed):** if the home↔VPS tunnel or the VPS itself is down, *home* metrics/logs are unavailable in Grafana (the nesting is graceful: buffered, replayed on reconnect; NUT-side `notifycmd`/`upssched-cmd` on nas is the grounds for power-loss alerts independent of the stack). The **VPS's own** metrics/logs remain available locally even with the tunnel down (loopback Alloy → local Prometheus/Loki → local grafana/dozzle).
- **Dozzle is not a second log backend** — it streams live logs straight from the Docker API (read-only socket) and persists nothing. Loki stays the single stored-log source (14d) and Grafana the search/alert surface.
- **Loki access control (HD-115 / KOPS-023/051):** Loki runs with `auth_enabled: true` (multi-tenant) — pushes and queries must carry the `logs` tenant ID, wired through Alloy (`tenant_id = "logs"`) and the Grafana datasource (`jsonData.tenantId`). The **write** path is loopback-only (Alloy → `127.0.0.1:3100`, no db-internal requirement) and **reads** come only from Grafana on `db-internal`; Loki is never exposed on traefik-public or any LAN bind. **Accepted caveat:** Loki-native `auth_enabled` is tenant *isolation*, not a password gate — a compromised db-internal container could forge a tenant header. Acceptable for the trusted-`db-internal` Phase-1 set; re-evaluate (real credential gateway / separate write+read tenants) if more members join `db-internal`.
- **Pi keeps only a tiny bounded local log buffer.** The Raspberry Pi primary holds **no durable log store** — Docker uses log driver `local` (`max-size: 10m, max-file: 2`) as RAM/disk resilience when oldsrv/Loki is down; the durable, searchable copy lives in Loki. Host OS logs run on tmpfs (`journald Storage=volatile` + `/var/log` tmpfs). See [Pi SD-card wear strategy](#pi-sd-card-wear-strategy).
- **HA exporter** on the HA instance (Raspberry Pi 4 primary; cold-standby container on oldsrv — see [`smart-home-failover.md`](smart-home-failover.md)). Only the live instance is scraped (via the VIP); on failover the same URL resumes with no replay.
- **Decided (no longer open):** per-host Alloy `instance` label = `{{ inventory_hostname }}` — implemented in `alloy.river.j2` (**HD-116** / KOPS-036, closes HD-55), so series no longer collide across hosts. MikroTik SNMP community = dedicated read-only **`network-snmp_api`** (1Password, fail-loud lookup in `snmp.yml.j2`) + Mgmt-VLAN-only INPUT ACL — decided **HD-53** / KOPS-034; the device-side `/snmp enable` + community set stays an HD-03 deploy step.

---

## Pi SD-card wear strategy

The Raspberry Pi 4 primary runs HA from a **microSD** (`storage.md`), so the dominant continuous SD-wear
source is **HA's recorder DB**, plus rolling Docker/OS logs. Strategy (HD-19, applies to the Pi; the standby on
oldsrv is on NVMe and mostly unaffected):

1. **HA recorder → trim, NOT disable.** Grafana (central Prometheus, 30d) replaces HA for *long-term analytics*,
   so raw state history can be short: `recorder: { purge_keep_days: 1–2, commit_interval: 2–5, … }` plus
   `exclude:` for noisy domains you only need in Grafana. Keeping the recorder **enabled** is deliberate — it still
   powers the **Logbook**, the **Energy Dashboard (long-term-statistics tables)** (e.g. KNX appliance-current
   sensors → kWh), **`history_stats` / `history()` templates**, and per-entity short-term UI sparklines, none of
   which Grafana covers. LTS writes are hourly min/max/mean per entity — negligible SD cost. **Do NOT disable** the
   recorder, and do NOT move HA to Postgres (worse microSD wear + failover coupling — see `smart-home.md`).
2. **Docker container logs → stream + bounded local buffer.** Docker log driver `local`, `max-size: 10m, max-file: 2`
   on the Pi (and standby): small RAM/disk buffer survives an oldsrv/Loki outage, while **Alloy ships logs → Loki
   (14d, VPS NVMe)** and Dozzle streams live — no durable on-Pi log store.
3. **OS logs off the SD.** `journald Storage=volatile` + `/var/log` mounted as tmpfs (fstab) — host OS logs live in
   RAM, lost on reboot (acceptable; Loki retains the useful logs). Cheap, well-tested Pi-SD saver.
4. *(Optional)* **Docker *log* directory on tmpfs** to guarantee zero *transient* SD writes — must stay hard-capped
   (`max-size`/`max-file`); **never** tmpfs the Docker data-root (`/var/lib/docker`/overlay2, that holds images &
   containers), only the log portion. Only if the 4 GB RAM budget (shared with HA/RaspberryMatic/Technitium) allows.

> Not addressed via ramdisk: the HA recorder DB and Technitium / RaspberryMatic state stay on the microSD but are
> kept small (trimmed recorder, reduced log verbosity). tmpfs-ing the recorder would throw away state/history on
> every reboot — see the energy/logbook caveats above.

---

## Dashboards

> _Provisioned via the monitoring role (`files/dashboards/*.json` → `/etc/grafana/provisioning/dashboards`, 30s hot-reload by the file provider). Datasource uid = `prometheus` (API-seeded by the monitoring role — see `tasks/main.yml`). Rendered live at the next VPS `monitoring` converge (deploy-gated; no new services)._

| Dashboard | uid | View | Panels back on |
|-----------|-----|------|----------------|
| **Overview** | `homelab-overview` | top-level entry point — down-counts (public/hosts/tunnel/stack), VPS CPU+mem, links to all dashboards | `probe_success{job=blackbox_*}` · `up{job=…}` · `node_*{job="alloy"}` |
| **Host Overview** | `homelab-host-overview` | per-instance node resources: CPU, mem, load, disk (/, /srv, /var/lib/docker), network, uptime — multi-host (instance template var) | `node_cpu_seconds_total` · `node_memory_*` · `node_load*` · `node_filesystem_*` · `node_network_*` · `node_boot_time_seconds` — all `job="alloy"` |
| **Service Reachability** | `homelab-service-reachability` | blackbox probe tables (HTTP + ICMP) + latency + TLS cert expiry | `probe_success` · `probe_duration_seconds` · `probe_ssl_earliest_cert_expiry` (`job=blackbox_*`) |
| **WAN & Tunnel** | `homelab-wan-tunnel` | wg-s2s liveness, Traefik requests, CrowdSec decisions, stack up | `probe_success{job=wg_icmp}` · `traefik_requests_total` · `crowdsec_decisions` · `up{job=…}` |
| **Stack Health** | `homelab-selfmonitoring` | observability self-monitoring: up() per component | `up{job=prometheus\|loki\|n8n\|blackbox-exporter\|crowdsec\|traefik}` — **no alloy**: Alloy remote-writes its own series; Prometheus never synthesizes `up` for remote-written data, so `up{job="alloy"}` has no series by design |
| **UPS** | `homelab-ups` | (pre-existing) NUT battery/load/voltages | `nut_*` |

> **Metric-name gaps (authoring-time, 2026-09-04):** the panel expression names above match the **alert-rule metric names** in the monitoring role (`vars/main.yml`) and the Prometheus scrape jobs — but several component metrics are **not yet verified live** (no running instance to scrape until the next converge):
> - `traefik_requests_total` — Traefik template exposes `:8082` but the compose does **not** enable a Prometheus metrics endpoint (`--metrics.prometheus=true` + `:8082` entrypoint are absent). The `traefik` scrape job target exists; the series will be empty until Traefik metrics are enabled. **Consequence in dashboards:** `homelab-wan-tunnel`'s Traefik panels render empty AND `homelab-selfmonitoring` shows a permanent red `up=0` traefik row (inflating "Components down" by 1) until the endpoint is enabled — display-only, no alert impact (alert rules do not key off traefik up).
> - `crowdsec_decisions` — CrowdSec exposes `:6060` metrics by default (job exists); metric name is the upstream one, exact series unverified.
> - `node_cpu_seconds_total` / `node_uname_info` — the Alloy `unix` exporter's exact series names are node_exporter-compatible (occupying the `job="alloy"` namespace); the dashboard reads them generically, so if the exporter labels differ the panels just render empty (no alert impact).
> These are **display-only** — alert rules are untouched and key off the same names via Grafana Alerting (independent of dashboard rendering).

---

## Deferred / TODOs

| Item | When | Notes |
|------|------|-------|
| Pi recorder trim + log strategy | after observability live (HD-19) | recorder trimmed, **not disabled** (keep Logbook/Energy-Dashboard LTS/history_stats); Pi logs → Loki + `local` driver buffer + `/var/log` tmpfs — see [Pi SD-card wear strategy](#pi-sd-card-wear-strategy)
| Long-term metric retention (remote-write, downsampling) | if ever needed | escape hatch = Thanos/VictoriaMetrics |
| Prometheus Alertmanager | only if Grafana-outage resilience demanded | Grafana Alerting covers Phase 1 |
| Homematic full-local (HmIP-RFUSB + RaspberryMatic on Pi) | **parked (HD-13)** — HmIP-HAP stays in cloud mode until an HmIP-RFUSB is bought | see `smart-home.md` — affects HAP/HA integration, not metrics flow |
| Container memory working-set metrics (Docker API → Prometheus) | with the *arr stack | validates the `services.md` RAM budget with real numbers, not estimates |
| **Homelable** (interactive topology/rack visualizer) | Phase 2 — once services are live | MIT · Pouzor/homelable · young project (re-evaluate maturity before adopting). Live health-check map + rack canvas w/ port patching + nmap scan + MCP server. Could replace the Obsidian `Rack.canvas` as the *live* visual and subsume the Homepage reachability widget. **Not** a metrics/logs/alert backend. · [`network-rack.md`](network-rack.md), [`todo.md`](../todo.md) |
| Route alerts to a **Matrix room** (`#homelab`) | with the Matrix stack (HD-46) | optional consolidation — alongside the Signal + SMTP fail-safe; homeserver/exporter only. · [`services-matrix.md`](services-matrix.md) |
| **Home-side tunnel check** (S14) | after Phase 1.5 cutover | blackbox `wg_icmp` probes run FROM the VPS (HD-159); add a router-side netwatch → SNMP trap (or equivalent) so a home↔VPS outage is also observable from home when the VPS path is the broken side |
| **Monitoring role split** (W6) | only when dashboard/rule iteration gets slow | Alloy+Prometheus+Loki+Grafana live in one `monitoring` role — any rule tweak redeploys the chain; split into `tasks/{alloy,prometheus,loki,grafana}.yml` includes + tags (no structural move needed until it hurts) |
| **Grafana alert-rule provisioning schema** (monitoring role `grafana-rules.yml.j2`) | first deploy of the monitoring role | ⚠ **needs live check:** query+threshold data-model + folder auto-creation unverified against a running Grafana — confirm rules load (Grafana logs) and fire once before trusting alerting |
