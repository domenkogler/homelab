# Prompt: HD-159 — blackbox liveness → cover the home↔VPS WG link (tunnel-down alert)

> Handoff written 2026-08-19. Goal: make a `wg-s2s` tunnel-down a **first-class alert**, not silent.

## Task

Extend the observability stack so the **home↔VPS WireGuard tunnel** (`wg-s2s`) is watched. If the
tunnel drops, the family/VPS should get a real alert (via the existing n8n alert router → Signal/email),
not just a missing metric.

## Context

- The observability backend (Prometheus/Loki/Grafana/n8n) is on the **VPS** (`docs/observability.md`).
- The `wg-s2s` tunnel is VPS `.2` ↔ home router `.1` (10.255.40.0/30). VPS Prometheus scrapes home
  targets (nut/zfs/ha_vip + ICMP blackbox probes) **over this tunnel** (HD-135/155).
- There's already a `blackbox-exporter` job (`docs/observability.md`, `prometheus.yml.j2`) with
  `blackbox_http_probes` + `blackbox_icmp` (probes router/switch/nas/oldsrv/pi over the tunnel).

## What to do

1. **Read `docs/observability.md`** + `IaC/ansible/templates/docker_services/prometheus/prometheus.yml.j2`
   + the alerting rules (`monitoring` role / Grafana provisioning / alert files).
2. **Add a tunnel-liveness check** — pick the cleanest:
   - a **blackbox ICMP probe** to the home router's WG-side IP (`10.255.40.1`) and/or the VPS peer
     from home; OR
   - a **WG-uptime metric** (e.g. `wg show wg-s2s latest-handshakes` via node_exporter textfile, or
     a small exporter) exposed to Prometheus.
   Prefer the blackbox ICMP route if the WG IPs are routable from the VPS — least new moving parts.
3. **Add an alert rule**: `probe_success == 0` for the tunnel target for > N minutes →
   critical (tunnel-down). Wire it to the **n8n alert router** (the existing alert path, per
   `docs/observability.md` — Signal via `signal-cli-rest-api`, email as fail-safe).
4. Consider a **second direction** (home→VPS) so a one-way break is caught, if the architecture
   supports it (the VPS blackbox probes the home side; a home-side check of VPS reachability would
   need a home blackbox — flag if that's out of scope).
5. Update **HD-159 row in `todo.md`** (✅ IaC done; ⏳ deploy-gated: live-verify at Phase 1 when
   the tunnel is up + the alert fires on `wg down` test).
6. `bash scripts/validate-all.sh` green.

## Guardrails
- Reuse the existing alert path — don't invent a second notification channel.
- The probe targets must come from the SSOT (`wg_s2s_vps.router_ip` / `10.255.40.1`) — no literals
  (CONVENTIONS §2). HD-155 scoped the tunnel; keep the probe within the allowed scope.
- Don't alert on transient flaps — require sustained down (N minutes).

## Definition of done
Tunnel liveness is scraped + a critical alert rule fires on sustained `wg-s2s` down, routed through
the existing n8n→Signal/email path; HD-159 updated; validators green.
