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

> 🟢 **NUT master LIVE 2026-09-03 (HD-06/314):** the PowerWalker VFI IoT 3000 is monitored from nas (NUT master) over USB — `upsc powerwalker@localhost` returns battery 100% / runtime / Innova Unity (Phoenixtec `06da:ffff`). `upsd` :3493 + `nut_exporter` :9199 (pinned v3.3.0, 2026-09-08) active on nas; udev perms fixed (nut group), `retrycount` removed from ups.conf (invalid for usbhid-ups in NUT 2.8.1). **Clients (oldsrv/pi) LIVE 2026-09-08** — oldsrvs + pi converged (HD-318/HD-307), both NUT clients active (slave to nas, deferred shutdown via `upssched`). ⏳ battery-pull test (owner, HD-06).

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
| **Ethernet (RJ45)** | LAN (IoT VLAN 20) — no consumer; web UI/Modbus not used (NUT USB), NIC kept isolated |

The USB link is a HID device, so it is *not* exposed as a serial (`/dev/ttyS*`) port.

---

## Management Interfaces (verified on the UPS NIC)

| Protocol | Port | Status |
|----------|------|--------|
| **Modbus TCP** | **502** | ✅ Open, working (unit ID 1). Responds to Read Holding Registers (fn `0x03`); register block 0 starts with the ASCII strings `PHOENIXTEC` then `RT 3K` (model). |
| Web UI (HTTP) | 80 | ✅ Open |
| Web UI (HTTPS) | 443 | ✅ Open |
| SNMP | 161 (UDP) | ⚠️ **Untestable from agent host** — TCP probe closed; UDP reachable only from the IoT VLAN (20). Monitoring is NUT/USB (no SNMP consumer), so this is informational only. |

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
       └─ nut_exporter ──▶ VictoriaMetrics (single source of metrics)
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
- [x] **NUT on nas — LIVE 2026-09-03** — master: `usbhid-ups` (USB path), `upsd`, `nut_exporter`, `upssched-cmd` notify (per [`deployment-ansible.md`](deployment-ansible.md) `nut` role); `upsc powerwalker@localhost` verified (battery 100%, Innova Unity). Battery-pull test ⏳ (owner/manual).
- [x] **NUT clients** on `oldsrv` + `pi` (*slave* mode) with per-host shutdown delay (60 s / 0 / 0) — ✅ **IaC done** (client upsmon, secret-free upssched-cmd, deferred-shutdown via upssched ONBATT timer — HD-07); ⏳ live deploy pending host provisioning.
- [ ] Wire UPS metrics + alerts into VictoriaMetrics/Grafana (see [`observability.md`](observability.md)) — Critical battery/runtime, Warning on-battery, Info transitions. ✅ **Metric shape RESOLVED 2026-09-04:** the exporter is DRuggeri/nut_exporter v3, emitted over `/ups_metrics?ups=powerwalker` as **`network_ups_tools_*`** with per-flag `network_ups_tools_ups_status{flag=...}` labels (OL/OB/RB…) — NOT `nut_*` bitmask. Alert rules + dashboard + Alloy scrape (`metrics_path: /ups_metrics`, `params.ups`) updated to match (topology B). ⏳ **Remaining:** live-verify after the next monitoring converge that `network_ups_tools_battery_charge` etc. land + alerts fire (exporter was running a `(devel)` build — pin a tagged release in the nut role). See monitoring role `vars/main.yml` + `alloy.river.j2`.
- [x] ~~Open firewall rule 80/443 Home→Mgmt for the UPS **web UI**~~ **SUPERSEDED HD-338 (2026-09-07):** UPS NIC moved to IoT VLAN 20 (no WAN); the trusted-admin→UPS web forward rule was REMOVED (no consumer — NUT/USB is the only monitoring path). |

---

## Open Items

- [x] **SNMP UDP — CLOSED 2026-09-08 (HD-26):** probed from a Mgmt-99 host (oldsrv `.99.30`) — **no reply on 161/UDP (filtered)**, while **Modbus TCP 502 is open** + ICMP reaches the `ups` host. So the UPS NIC simply does **not answer SNMP**; **no consumer uses it anyway** — monitoring is NUT/USB. The old "Informational only / untested" checkbox is swept; the SNMP row in the protocol table below stays as-is (informational).

> Modbus TCP register-map item **removed (retired):** HA Modbus UPS sensors were removed;
> UPS monitoring is NUT/USB via `nut_exporter` (`hardware-ups` topology above).

---

## Related

- [HP MicroServer Gen8 (nas)](hardware-nas.md) — the protected host
- [Rack Layout](network-rack.md) — physical placement + manual PDF
- [VLAN Plan](network-vlans.md) — UPS NIC on IoT VLAN 20 (no WAN); monitoring NUT/USB on Home VLAN 10
- [Home Assistant — current instance](home-assistant-current.md) — HA (UPS via NUT now, not Modbus)
- [Observability](observability.md) — where UPS metrics would land
