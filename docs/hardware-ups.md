---
title: PowerWalker VFI ICT/ICR IoT 3000 (UPS)
role: detail
domain: hardware
status: active
tags: [hardware, ups, power, modbus, nut]
---
# PowerWalker VFI ICT/ICR IoT 3000 (UPS)

> **Role:** Detail — single source of truth for the rack UPS: identity, physical
> links, management interfaces, and monitoring/shutdown status.
> **Links to:** `hardware-nas.md`, `network-rack.md`, `network-vlans.md`, `home-assistant-current.md`, `observability.md`
> **Linked from:** `hardware.md`, `index.md`

> 🟢 **IaC done, not yet live — ⏳ deploy-gated.** UPS hardware exists (PowerWalker on the rack); NUT monitoring does not. The PowerWalker is on the rack (VLAN 99, `ups` host per SSOT) but the NUT master (nas) + clients (oldsrv/pi) are **not live yet** — deploy-gated ⏳ (HD-06/07/08/09, hosts unprovisioned).

---

## Identity

| Property | Value |
|----------|-------|
| Model | PowerWalker VFI ICT/ICR **IoT** 3000 (3 kVA) |
| USB identity | `PHOENIXTEC Innova Unity` (HID name reported by the UPS itself) |
| MAC | `00:20:85:C0:92:FA` |
| IP | static — `ups` per [`network-addresses-generated.md`](network-addresses-generated.md) |
| VLAN | 99 (Mgmt) — access port |
| Location | Rack floor / near the rack (18U cabinet) |
| Protects | **nas** (HP MicroServer Gen8), **oldsrv** (i7-7700K), **ha** (Raspberry Pi 4) + rack infra (router, switch, ONT) |

> The "IoT" in the model name means the RJ45 is the built-in **network (Ethernet)
> port**, not a serial/RS-485 Modbus port. It has an IoT network card with its own
> IP. Status is visible via the **winPower View** Android app.

---

## Physical Links

| Link | To | Detail |
|------|----|--------|
| **USB HID** | gen8 (`nas`) | `/dev/hidraw0`, `/dev/usb/hiddev0` — currently the **only live data link** to a host |
| **Ethernet (RJ45)** | LAN (Mgmt VLAN 99) | Network card, static IP (per SSOT) — hosts web UI + Modbus TCP |

The USB link is a HID device, so it is *not* exposed as a serial (`/dev/ttyS*`) port.

---

## Management Interfaces (verified on the UPS NIC)

| Protocol | Port | Status |
|----------|------|--------|
| **Modbus TCP** | **502** | ✅ Open, working (unit ID 1). Responds to Read Holding Registers (fn `0x03`); register block 0 starts with the ASCII strings `PHOENIXTEC` then `RT 3K` (model). |
| Web UI (HTTP) | 80 | ✅ Open |
| Web UI (HTTPS) | 443 | ✅ Open |
| SNMP | 161 (UDP) | ⚠️ **Untestable from agent host** — TCP probe closed; UDP reachable only from the Mgmt VLAN (99). Monitoring is NUT/USB (no SNMP consumer), so this is informational only. |

### Modbus TCP notes
- Unit ID **1**, function **0x03** (Read Holding Registers) confirmed working over the LAN.
- **Retired as a consumer:** the UPS NIC exposes Modbus TCP on the `ups` NIC (port 502, verified — IP per SSOT), but **no service uses it** — the HA **Modbus sensors were removed** and UPS monitoring is exclusively NUT over **USB HID** (below). No register map needed; the Modbus endpoint is left open/available on the NIC but is not part of the design.

---

## Monitoring & Shutdown Topology (decided)

**Uses the USB HID link + NUT network protocol — not Modbus for monitoring.**

```
UPS (USB physical link → nas only)
  └─ nas = NUT MASTER
       ├─ usbhid-ups driver        (USB)
       ├─ upsd on :3493 (homelab-only)
       └─ nut_exporter ──▶ Prometheus   (single source of metrics)
      ▲ NUT network (upsmon SLAVE, :3493)
   ┌──┴───────────────────┐
oldsrv (client, 60 s delay)   ha/Pi (client) — each shuts down locally
```

- **Master = nas** (only host physically USB-wired). **Clients = oldsrv + ha/Pi**, each triggers its own local `shutdown` — no cross-host dependency.
- **Single sensor of truth:** one `nut_exporter` on the master; other hosts are NUT clients only (not exporters).
- **Shutdown policy:** Critical = battery < **20%** or runtime < **5 min**. `oldsrv` delayed **60 s** (flushes Grafana→n8n→Signal/email before powerdown); `nas`/`ha` power down immediately.
- **Guaranteed notify:** NUT-side `upssched-cmd` on nas emails + sends Signal directly on `ONBATT`/`LOWBATT`, independent of Grafana/n8n.

## Monitoring & Shutdown Status

### Roadmap (implementation pending)
- [ ] **NUT on nas** — master: `usbhid-ups` (USB path), `upsd`, `nut_exporter`, `upssched-cmd` notify (per [`deployment-ansible.md`](deployment-ansible.md) `nut` role).
- [x] **NUT clients** on `oldsrv` + `pi` (*slave* mode) with per-host shutdown delay (60 s / 0 / 0) — ✅ **IaC done** (client upsmon, secret-free upssched-cmd, deferred-shutdown via upssched ONBATT timer — HD-07); ⏳ live deploy pending host provisioning.
- [ ] Wire UPS metrics + alerts into Prometheus/Grafana (see [`observability.md`](observability.md)) — Critical battery/runtime, Warning on-battery, Info transitions. ⚠ **needs research + decision:** alert rules in the monitoring role assume the DRuggeri/nut_exporter `nut_ups_status` bitmask (`1=OL, 2=OB, 16=RB`); verify the installed exporter version's status flags + metric names at deploy before relying on on-battery / replace-battery alerts. See monitoring role `vars/main.yml`.
- [ ] Open firewall rule 80/443 Home→Mgmt for the UPS **web UI** only (Modbus **502 retired** — no consumer, see [`network-vlans.md`](network-vlans.md)).

---

## Open Items

- [ ] **SNMP UDP** — Mgmt-VLAN-only: the `ups` host is unreachable from the agent/LAN network segment (the Management VLAN is intentionally isolated — its gateway reports destination unreachable), so the probe must run from a Management-VLAN host (or via the management-side route) at deploy. Even if the NIC serves SNMP (161/udp), **no consumer uses it** — UPS monitoring is exclusively NUT over USB (`hardware-ups` topology above), so this is confirmational only. (HD-26 attempted 2026-08-18: blocked by Mgmt-VLAN isolation.)

> Modbus TCP register-map item **removed (retired):** HA Modbus UPS sensors were removed;
> UPS monitoring is NUT/USB via `nut_exporter` (`hardware-ups` topology above).

---

## Related

- [HP MicroServer Gen8 (nas)](hardware-nas.md) — the protected host
- [Rack Layout](network-rack.md) — physical placement + manual PDF
- [VLAN Plan](network-vlans.md) — UPS mgmt on VLAN 99
- [Home Assistant — current instance](home-assistant-current.md) — HA (UPS via NUT now, not Modbus)
- [Observability](observability.md) — where UPS metrics would land
