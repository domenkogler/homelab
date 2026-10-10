---
title: Observability — Rejected / Dropped Decision Log
role: log
domain: observability
status: active
tags: [observability, alerting, rejected, decision-log]
---
# Observability — Rejected / Dropped

> **Role:** Decision log — the `observability` domain's rejected mechanisms (what a signal will be taken
> from, what will not be instrumented, which exporter path is out). Sorted by subject, one row per subject.
> This log is the per-domain **decision-log SSOT** ([CONVENTIONS.md](../CONVENTIONS.md) §8.3).
> **Links to:** `observability.md`, `services-ai.md` (decision #26, the reason one row below reads the way it does)
> **Linked from:** `index.md`, `observability.md`

> Each row is `| <subject> | <rejected|dropped|superseded> | <why> |` — no dates, no links, no prose.
> **Append-only:** add rows, never rewrite or delete an existing one; rows are keyed by subject
> (`CONVENTIONS.md` §8.3). Evidence = the current-state text in the owning doc.

## Decisions

| Subject                                         | Status     | Why                                              |
|-------------------------------------------------|------------|--------------------------------------------------|
| A durable log store on the Raspberry Pi         | rejected   | bounded buffer only; VictoriaLogs stores logs    |
| Age-tiering / downsampling of stored metrics    | rejected   | absent from the VictoriaMetrics community binary |
| Alerting on intentionally-empty state           | rejected   | unprovisioned links are not incident-worthy      |
| Alerting on `probe_ssl_earliest_cert_expiry`    | dropped    | blackbox emits no SSL expiry series              |
| A second `nut_exporter` per host                | rejected   | one exporter on the NUT master avoids redundancy |
| Blanket 5 s scrape cadence for every series     | rejected   | 365 d cost; 50 panel series cover the need       |
| Client list derived from router logs via Loki   | rejected   | brittle parsing; logs miss lease/ARP events      |
| DCGM profiling (DCP) metrics on GB10            | rejected   | NVIDIA will not support DCGM on Spark            |
| DGX Dashboard as a telemetry source             | rejected   | no /metrics, no history; RAM labelled GPU        |
| `dgx-spark-exporter`                            | rejected   | duplicates the Alloy unix collector, no VRAM     |
| Disabling the HA recorder to spare the microSD  | rejected   | Logbook, Energy LTS and history() need it        |
| Dozzle as a second stored-log backend           | rejected   | VictoriaLogs is the single stored-log source     |
| Dozzle UI auth on the LAN hub                   | dropped    | LAN-only edge, matches the no-Forward-Auth rule  |
| Global `-dedup.minScrapeInterval` change        | rejected   | silently re-tunes dedup for every host           |
| Grafana-triggered host shutdown                 | rejected   | shutdown belongs to the host NUT agents          |
| InfluxDB as a metrics store                     | superseded | VictoriaMetrics is the sole metrics store        |
| Infomaniak kSuite as the alert SMTP relay       | rejected   | fail-safe must not couple to personal email      |
| LiteLLM as a metering proxy for the harness leg | rejected   | decision #26 removes that hop on purpose         |
| Loki + Prometheus as the TSDB                   | superseded | VictoriaMetrics and VictoriaLogs replaced them   |
| MCP AI-debugging servers on the VPS or Pi       | rejected   | ~700 MB each; oldsrv has the RAM                 |
| minio_exporter                                  | superseded | Immich originals live on the Hetzner Box (CIFS)  |
| Moving the HA recorder to Postgres              | rejected   | worse microSD wear and failover coupling         |
| Observability backend on oldsrv                 | superseded | reliable tier runs on the VPS                    |
| Promtail as the log shipper                     | superseded | Alloy ships logs to VictoriaLogs                 |
| Renaming the `prometheus` datasource uid        | rejected   | churns every provisioned panel                   |
| RouterOS API access directly from the VPS       | rejected   | router INPUT accepts Mgmt VLAN only              |
| Signal as the only alert delivery channel       | superseded | the operator reads Element, not Signal           |
| SNMP walk as the client-list source             | dropped    | no lease hostnames, no wifi-qcom-ac data         |
| `spark_hwmon` (antheas SPBM DKMS driver)        | rejected   | experimental module on an OOM-prone host         |
| Standalone Alertmanager beside Grafana          | rejected   | Unified Alerting keeps rules with the data       |
| Telegraf as the collector                       | superseded | Alloy is the single scrape tier                  |
| Textfile collector for hygiene metrics          | rejected   | Alloy rejects every textfile path attribute      |
| tmpfs for the Docker data-root                  | rejected   | images and containers would not survive reboot   |
| Trimming `dcgm-exporter` counters to save RAM   | rejected   | ~4 MiB; the hard cap is the real lever           |
| Uptime Kuma as the uptime checker               | superseded | blackbox probes cover external reachability      |
