---
title: Observability
role: ssot
domain: services
status: active
tags: [services, observability, grafana, monitoring]
---
# Observability

> **Role:** Single source of truth — the complete observability architecture in one page.
> **Links to:** `interfaces.md`, `deployment-ansible.md`, `smart-home.md`, `backup.md`
> **Linked from:** `index.md`, `interfaces.md`

---

## Architecture

```
Alloy (host agent: metrics + logs + SNMP, has docker.sock)
   ├─ remote_write ──▶ Prometheus  (THE metrics store, 30d)
   └─ push ──────────▶ Loki        (logs, 14d)
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
| UI | **Grafana** | Dashboards, `stats.kogler.si` (**internal**) | `traefik-public` **+** `db-internal` | — |
| Router | **n8n** | Alert routing/dedup → Signal/email | `services-internal` | — |
| Notify | **signal-cli** | Signal delivery (linked device) | `services-internal` (needs internet) | — |

---

## Single Source of Truth Matrix

| Data | Owner | Where it lives |
|------|-------|----------------|
| Host + SNMP metrics | Alloy → Prometheus | Prometheus (30d) |
| Service scrape (Traefik, CrowdSec, Doco-CD) | Alloy/Prometheus | Prometheus (30d) |
| HA entity metrics (weather, ComfoAir) | HA exporter → Prometheus | Prometheus (30d) |
| External reachability | blackbox → `probe_success` | Prometheus (30d) |
| UPS status (battery, runtime, voltage, load, online/on-batt) | nut_exporter (on nas) → Prometheus | Prometheus (30d) |
| Logs | Alloy → Loki | Loki (14d) |
| Alerts | Grafana Alerting → n8n → Signal/email | alert delivery |
| Display | Grafana + Homepage | — |

---

## Alerting

- **Engine:** Grafana Unified Alerting (rules live with the data; no separate Alertmanager).
- **Router:** alerts → n8n webhook → normalize / dedup / tier / format → Signal + email. n8n also serves office automation ([`llm-office.md`](llm-office.md)).
- **Fail-safe:** Grafana-native SMTP contact point runs in parallel — alerts still go out if n8n/signal-cli is down.
- **Signal:** `signal-cli-rest-api` container, **linked** to Domen's personal number (no second SIM), sends to a dedicated **"Homelab Alerts"** group. Persist the Signal identity volume so it doesn't need re-linking.

### Tiers

| Severity | What alerts | Channel | Notes |
|----------|-------------|---------|-------|
| **Critical** | oldsrv disk ≥90%, host down, ZFS pool degraded, service down >2min, `probe_success==0` · **UPS battery <20% or runtime <5 min (impending shutdown)** | Signal + email | page-worthy |
| **Warning** | container restart loop, high CPU/load, HA unreachable, MikroTik link down · **UPS on-battery / mains lost (auto-clear on return)** | Signal (deduped) | sent once |
| **Info** | transient / everything else · **UPS online ↔ on-battery transitions / restored** | logged only | no push |

- **Poke/throttle:** re-send only if still firing after ~30 min (prevents overnight alert floods).
- **Self-monitoring:** the observability stack itself (Prometheus/Loki/n8n down) must alert — otherwise the alert channel dies silently.

---

## UPS / Power-Loss Monitoring (NUT)

- **Metrics (single source):** one **nut_exporter** on **nas** (the NUT master) reads local `upsd` → Prometheus. Other hosts do **not** re-export identical UPS data (avoids redundancy).
- **Shutdown:** **NUT owns local shutdown** on `nas`, `oldsrv`, and `ha` (Raspberry Pi). Grafana/n8n are **alert-only** — there is **no shutdown action from Grafana** (observability lives on oldsrv, which must not be the thing that halts the NAS during a power cut).
- **Notification ordering & delay:** on mains loss the **Warning "on-battery" alerts at t=0** (WAN still up via router/ONT on UPS → Signal + email deliver). At **Critical**, `oldsrv` is **delayed ~60 s** before powerdown (via NUT `upssched`) so its own Grafana→n8n→Signal/email pipeline flushes the Critical alert, then it powers off. `nas` + `ha` power down immediately.
- **Guaranteed fallback:** a **NUT-side `notifycmd`/`upssched-cmd` script on nas** emails + sends Signal directly on `ONBATT` and `LOWBATT`, independent of Grafana/n8n — so a pre-shutdown notification is sent even if the observability stack is already degraded.
- Registered/configured via the `nut` Ansible role — see [`deployment-ansible.md`](deployment-ansible.md).

---

## Microservice Notes

- **MikroTik SNMP:** poll at **5–15 s**; the "1s" in dashboards is a *refresh* interval, not a poll.
- **Retention is deliberate:** 30d metrics / 14d logs. TSDB data is **regenerable and not backed up** (see [backup.md](backup.md)); long-term metric history is a deferred option (remote-write/downsampling).
- **SPOF:** all observability lives on oldsrv — accepted for Phase 1; documented as a known property.
- **HA exporter** on the HA instance (Raspberry Pi 4 primary; cold-standby container on oldsrv — see [`smart-home-failover.md`](smart-home-failover.md)). Only the live instance is scraped (via the VIP); on failover the same URL resumes with no replay.

---

## Deferred / TODOs

| Item | When | Notes |
|------|------|-------|
| Trim/disable HA recorder history | after observability live | protects Pi SD card; Grafana reads central Prometheus, not HA history |
| Long-term metric retention (remote-write, downsampling) | if ever needed | escape hatch = Thanos/VictoriaMetrics |
| Prometheus Alertmanager | only if Grafana-outage resilience demanded | Grafana Alerting covers Phase 1 |
| Homematic full-local (HmIP-RFUSB + RaspberryMatic on Pi) | redo plan | see `smart-home.md` — affects HAP/HA integration, not metrics flow |
