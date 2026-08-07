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
| IP | `10.10.1.109` |
| VLAN | 99 (Mgmt) — access port |
| Location | Rack floor / near the rack (18U cabinet) |
| Protects | **nas** (HP MicroServer Gen8) + rack infra (router, switch, ONT, HA Pi) |

> The "IoT" in the model name means the RJ45 is the built-in **network (Ethernet)
> port**, not a serial/RS-485 Modbus port. It has an IoT network card with its own
> IP. Status is visible via the **winPower View** Android app.

---

## Physical Links

| Link | To | Detail |
|------|----|--------|
| **USB HID** | gen8 (`nas`) | `/dev/hidraw0`, `/dev/usb/hiddev0` — currently the **only live data link** to a host |
| **Ethernet (RJ45)** | LAN (Mgmt VLAN 99) | Network card, IP `10.10.1.109` — hosts web UI + Modbus TCP |

The USB link is a HID device, so it is *not* exposed as a serial (`/dev/ttyS*`) port.

---

## Management Interfaces (verified on `10.10.1.109`)

| Protocol | Port | Status |
|----------|------|--------|
| **Modbus TCP** | **502** | ✅ Open, working (unit ID 1). Responds to Read Holding Registers (fn `0x03`); register block 0 starts with the ASCII strings `PHOENIXTEC` then `RT 3K` (model). |
| Web UI (HTTP) | 80 | ✅ Open |
| Web UI (HTTPS) | 443 | ✅ Open |
| SNMP | 161 (UDP) | ⚠️ TCP probe closed; **UDP untested** — confirm |

### Modbus TCP notes
- Unit ID **1**, function **0x03** (Read Holding Registers) confirmed working over the LAN.
- NUT's `modbus_ups` driver can connect directly to `10.10.1.109:502` — **no serial/RS-485 adapter needed** (the UPS already exposes Modbus over its network port).
- **Register map is PowerWalker/Phoenixtec-proprietary** — needs a tailored mapping/config (see Open Items).

---

## Monitoring & Shutdown Status

⚠️ **NUT (Network UPS Tools) is NOT installed on gen8 (`nas`).**

- No `nut` / `apcupsd` on gen8 — nothing reads battery/runtime/voltage, and there is
  **no automatic graceful shutdown** of the NAS on power failure.
- The USB link and the Modbus TCP interface both exist and work, but no host driver consumes them.
- Read-only view of the UPS currently comes from the **winPower View** mobile app only.

### Roadmap
- [ ] Install **NUT** on gen8 with the `usbhid-ups` driver (USB HID path) *or* the
      `modbus_ups` driver (`10.10.1.109:502`, unit 1).
- [ ] Configure `upsd` + a shutdown action so gen8 shuts down cleanly on low battery.
- [ ] Decide whether metrics flow to Prometheus (see `observability.md`) and whether
      Home Assistant keeps its own Modbus reader (`home-assistant-current.md` §6.1).

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
