---
title: Home Assistant Failover & High Availability
role: detail
domain: smart-home
status: active
tags: [smart-home, homeassistant, failover, ha, vip, standby]
---
# Home Assistant Failover & High Availability

> **Role:** Detail — active/standby HA failover to oldsrv, takeover + reverse (failback) runbooks, DNS redundancy tie-in.
> **Links to:** `smart-home.md`, `network-dns.md`, `network-vlans.md`,
> `deployment-ansible.md`, `services.md`, `backup.md`
> **Linked from:** `smart-home.md`, `index.md`

---

## Goals & Non-Goals

### Must hold (non-negotiables)
- **No WAN dependency on the critical path.** Lights/covers toggling must keep working when the internet is down.
- **WAN loss is NOT a failover trigger.** HA is fully local — internet loss does not move HA. Failover is triggered only by **Pi failure** (power, SD card, OS crash, network path) and the *mechanism* simply must work while WAN is down.
- **Exactly one active HA node at a time** (no split-brain). Two HAs driving the same Shelly/KNX/ESPHome devices conflict; HA has **no native active/active clustering or state replication**.

### Scope
- Primary: Raspberry Pi 4 (`ha.kogler.si`, `10.10.1.122`, Home VLAN 10).
- Fallback: **oldsrv** (`home-assistant-standby` Docker container, cold by default).
- Supervision: **manual** trigger + **manual** failback (accepted design — no false negatives from automation).
- Stale state on takeover is acceptable: HA re-polls devices on startup (target: controlling again in 1–3 min).

---

## Architecture Overview

```
   ┌─────────────────────────────┐
   │  MikroTik RB4011 (always on) │   also runs DHCP; router/switch
   │                             │   independent of both HA nodes
   └──────────────┬──────────────┘
                  │ route / DHCP / optional VIP contact
   ┌──────────────▼──────────────┐
   │     HA VIP 10.10.1.122      │   stable address everything points to
   └──────┬──────────────┬───────┘
          │              │
   ┌──────▼─────┐   ┌─────▼─────┐
   │   Pi 4     │   │  oldsrv   │
   │ HA PRIMARY │   │ HA STANDBY│   cold — started on takeover
   └──────┬─────┘   └─────┬─────┘
          │ keepalived VRRP — VIP follows the active node
   devices / Traefik / Technitium DNS all point at the VIP
```

### Addressing: shared Virtual IP (VIP)

- HA gets a **floating VIP `10.10.1.122`** on the Home VLAN that moves between the Pi and oldsrv via **keepalived (VRRP)**.
- **Devices, Companion apps, Traefik's `ha` route, and Technitium DNS all point at the VIP**, never a node-specific IP.
- On takeover the VIP follows the active node → **no per-device reconfiguration and no DNS flip on failover**. This is the key that makes failover practical.
- **Firewall:** Home→IoT trusted-IP rules for MQTT/HA must reference the **VIP / an IP-set**, not a per-node IP, so the standby can reach Shelly/KNX after takeover (see `network-vlans.md`).

> ⚠ **VRRP requires a controllable host on both sides.** This is only possible once the Pi runs **Debian + HA Container** (see Decision: HA OS vs Debian/Docker below). If the Pi ever runs HA OS again, VRRP on it is not feasible → fall back to manual DNS/NAT steering (slower, still workable).

---

## Nodes & Deployment

| Node | Role | Deployment | VIP |
|------|------|-----------|-----|
| Pi 4 (`ha.kogler.si`) | **Primary** (active) | **Debian + Home Assistant Container**, managed by the Ansible `home_assistant` role | owns `10.10.1.122` in normal mode |
| oldsrv | **Fallback** (standby, cold) | `home-assistant-standby` Docker compose (normally `disabled` systemd unit), same `home_assistant` role template | takes over `10.10.1.122` on takeover |

- **Identical config from one source:** both nodes render the **same `configuration.yaml`** from the repo (`use_x_forwarded_for: true`, `trusted_proxies: <Traefik>`), including the `owner` recovery account and Authentik OIDC settings.
- **Role/playbook:** `raspberry_pi.yml` (common → network → home_assistant → monitoring) configures the Pi as primary. The `home_assistant` role on `home_servers` renders the standby container on oldsrv.
- **Update policy:** pinned image + Renovate; watchtower optional (see `hardware-oldsrv.md`, `deployment-renovate.md`).

### Decision: HA OS vs Debian/Docker (Pi primary)

| | **HA OS** | **Debian + Docker (chosen)** |
|---|---|---|
| Failover enabler (VIP/VRRP) | **Not feasible** on Pi | **Native** — Pi runs keepalived |
| Config parity with standby | Separate envs | One Ansible role + one template for **both** nodes |
| Updates | Zero-touch | Your responsibility (Renovate + watchtower) |
| Add-ons | Official store | Run as separate containers (already the oldsrv pattern) |
| Migration risk | None | Small (Pi is in daily use) |

**Chosen:** Debian + HA Container on the Pi, managed by the same role as the standby. The reinstall happens opportunistically during the planned network redo (the network is currently flat / no VLANs; `network-vlans.md`).

---

## Remote & App Access (`ha.kogler.si`)

- **Route:** `ha.kogler.si` → Traefik → **VIP**. The `ha` route must **NOT** use Authentik Forward-Auth (breaks the Companion WebSocket/token flow) — see `smart-home.md`.
- **Normal (Pi active):** Android app works over WAN (Cloudflare → VPS Traefik, Phase 2) and over VPN (Headscale).
- **Fallback (oldsrv active):** same hostname routes to the standby. **WAN access is NOT required in fallback** (accepted) — app still works on LAN/WiFi, and over VPN if needed.
- **Security:** HA `http.use_x_forwarded_for: true` + `trusted_proxies: <Traefik>`; one local `owner` account as recovery if Authentik is unreachable.

---

## Forward Takeover (Pi → oldsrv) — MANUAL

**Trigger:** A single dashboard action / script on `home.kogler.si` (no automation, so no false negatives from a mis-updated HA OS). Steps:

1. **Confirm Pi is down** (human verifies — power, SD, OS, network).
2. **Move the VIP** to oldsrv (`keepalived` demote on Pi / promote on oldsrv). If no VIP (HA OS fallback): update Technitium `ha.kogler.si` → oldsrv IP **and** Traefik `ha` service endpoint.
3. **Start the standby:** `systemctl enable --now home-assistant-standby`.
4. HA boots from last config/DB snapshot → reconnects KNX / Shelly / ESPHome.
5. **Notify:** n8n → Signal/email (Homelab Alerts), and log the event (see `observability.md`).

---

## Reverse Failback (oldsrv → new/repaired Pi) — MANUAL

> ⚠ **Never auto-failback in a two-node VIP setup** — that is how split-brain happens. Prefer explicit manual transfer, especially because the standby has been running and holds **newer state** than a freshly-rebuilt Pi.

1. **Build the new Pi as a peer, not master:** run the `raspberry_pi` playbook → Pi comes up with the same config as **standby** (disabled VIP, no active role).
2. **Reverse the state sync (standby → Pi):** oldOVs (former standby) now has the freshest config/DB; push it to the new Pi so no family/lights config is lost. (Normal sync direction is Pi → standby; reverse it here.)
3. **Drain the standby:** put it in maintenance (disable its VIP/watchdog), confirm the new Pi is healthy and can control a live device.
4. **Flip the VIP back** to the Pi (manual button/script).
5. **Mark Pi = primary**, oldOVs returns to cold/disabled.
6. **Drill:** exercise forward + reverse right after the network redo, and re-test annually with the backup restore drill (see `backup.md`).

---

## Config & State Sync

- **Source of truth:** this repo (config already lives here). The standby is healthy when its rendered `/config` matches the repo + a recent Pi snapshot.
- **Normal direction (Pi → standby):** local push of `/config` (and optionally HA DB) to oldsrv on a timer (e.g. every 15 min), LAN-only, no WAN dependency.
- **Best-effort only:** on takeover the standby boots from the last snapshot and **re-polls all devices**; full live-state continuity is not a goal (accepted).

---

## DNS Redundancy Tie-In (see `network-dns.md`)

- Both **Technitium** instances (primary on oldsrv, **secondary on nas**) serve `ha.kogler.si` → **VIP** in normal mode, so DNS is never the thing that breaks HA lookup.
- The VIP handles *steering*; the second Technitium handles *lookup availability* when oldsrv is down.

---

## Shelly / MQTT Note

- No MQTT broker exists in the design — Shelly are connected via HA's **native Shelly integration** (direct LAN HTTP/WebSocket per device), so **no broker is a failover surface**. The standby talks to each Shelly directly on takeover.
- If MQTT is ever added (e.g. a rocker switch), run a **Mosquitto** container on oldsrv and give it a stable address reachable by whichever HA is active.

---

## Open Questions / Decisions

- [x] Takeover trigger = **manual**; failback = **manual** (accepted).
- [x] Stale state on takeover (15-min snapshot) = **acceptable**.
- [x] WAN access in fallback = **not required** (LAN/VPN only).
- [ ] Confirm the live Pi's current install method before the redo (docs assume Docker).
- [ ] Choose VIP range/notation for Home VLAN + firewall IP-set name.
- [ ] Whether to add `watchtower` for the Pi's HA container update automation.

## Related

- [Smart Home](smart-home.md)
- [Network DNS](network-dns.md)
- [Ansible Specification](deployment-ansible.md) (home_assistant role)
- [Service Catalog](services.md)
- [Backup & DR](backup.md)
