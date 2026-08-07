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

---

## Identity

| Property | Value |
|----------|-------|
| Model | PowerWalker VFI ICT/ICR **IoT** 3000 (3 kVA) |
| USB identity | `PHOENIXTEC Innova Unity` (HID name reported by the UPS itself) |
| MAC | `00:20:85:C0:92:FA` |
| IP | `10.10.99.9` |
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
| **Ethernet (RJ45)** | LAN (Mgmt VLAN 99) | Network card, IP `10.10.99.9` — hosts web UI + Modbus TCP |

The USB link is a HID device, so it is *not* exposed as a serial (`/dev/ttyS*`) port.

---

## Management Interfaces (verified on `10.10.99.9`)

| Protocol | Port | Status |
|----------|------|--------|
| **Modbus TCP** | **502** | ✅ Open, working (unit ID 1). Responds to Read Holding Registers (fn `0x03`); register block 0 starts with the ASCII strings `PHOENIXTEC` then `RT 3K` (model). |
| Web UI (HTTP) | 80 | ✅ Open |
| Web UI (HTTPS) | 443 | ✅ Open |
| SNMP | 161 (UDP) | ⚠️ TCP probe closed; **UDP untested** — confirm |

### Modbus TCP notes
- Unit ID **1**, function **0x03** (Read Holding Registers) confirmed working over the LAN.
- NUT's `modbus_ups` driver can connect directly to `10.10.99.9:502` — **no serial/RS-485 adapter needed** (the UPS already exposes Modbus over its network port).
- **Register map is PowerWalker/Phoenixtec-proprietary** — needs a tailored mapping/config (see Open Items).

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
- [ ] **NUT clients** on `oldsrv` + `ha` (*slave* mode) with per-host shutdown delay (60 s / 0 / 0).
- [ ] Wire UPS metrics + alerts into Prometheus/Grafana (see [`observability.md`](observability.md)) — Critical battery/runtime, Warning on-battery, Info transitions.
- [ ] Open firewall rule 502/80/443 Home→Mgmt for modbus/web (see [`network-vlans.md`](network-vlans.md)).

---

## Open Items

- [ ] **Register map** for the PowerWalker/Phoenixtec Modbus TCP device — which
      register addresses hold battery %, input voltage, output load, runtime. HA already
      reads some `ups_*` sensors (scaled values — see `home-assistant-current.md`); exact
      map still to-confirm.
- [ ] **SNMP UDP** — confirm whether the network card serves SNMP (161/udp).

---

## Related

- [HP MicroServer Gen8 (nas)](hardware-nas.md) — the protected host
- [Rack Layout](network-rack.md) — physical placement + manual PDF
- [VLAN Plan](network-vlans.md) — UPS mgmt on VLAN 99
- [Home Assistant — current instance](home-assistant-current.md) — Modbus UPS sensors
- [Observability](observability.md) — where UPS metrics would land
