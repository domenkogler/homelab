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

> **Status: 🟢 NUT monitoring + shutdown chain LIVE on all three protected hosts (nas master,
> oldsrv + Pi clients).** `usbhid-ups` over USB on nas, `upsd` :3493, `nut_exporter` :9199 (tagged
> release pinned), clients in `slave` mode with per-host shutdown, and a live-verified battery-pull drill.
> ⏳ Remaining: one more short battery-pull re-test (owner/manual), and live-verification that the
> `network_ups_tools_*` series + alert rules land after the next monitoring converge.
>
> **Shutdown policy (owner decision):** oldsrv is the biggest load → **halt at ≤ 75 % battery charge**, so
> the battery is preserved for nas/Pi; **nas + Pi are critical-only** (`LOWBATT` = battery < 20 % or
> runtime < 5 min). Implemented as an upssched 30 s charge-poll started on `ONBATT` (cancelled on `ONLINE`)
> → poweroff at `battery.charge ≤ nut_shutdown_charge_threshold` (oldsrv 75, nas/Pi 0 = never via this path).
> **Poweroff, never `shutdown -h`** — a halt leaves this board powered (LEDs on); every path uses
> `/sbin/poweroff` with a matching sudoers rule.
>
> **Defects the drill exposed — all fixed in the role, do not re-introduce:**
> ① a stray ACL on `upssched-cmd` (`group::r--` despite mode 0750) gave `nut` exec 126 → **no notify and no
> shutdown on any host**; ② the SMTP credentials rendered as shell vars (`${nut_smtp_*}`) instead of Jinja,
> so SMTP auth silently failed empty (masked by `|| true`) — they must render inline from the vault;
> ③ no sudoers rule → `nut` could not run the shutdown command; ④ `nut_signal_helper` aborted the on-battery
> notify under `set -u` (guard with `${nut_signal_helper:-}`); ⑤ an upssched restart handler that existed
> only on the master left **clients running stale configs** (oldsrv powered off 60 s after *any* mains loss
> on first deploy) — the restart handler must apply to **all modes**.

---

## Identity

| Property | Value |
|----------|-------|
| Model | PowerWalker VFI ICT/ICR **IoT** 3000 (3 kVA) |
| USB identity | `PHOENIXTEC Innova Unity` (HID name reported by the UPS itself) |
| MAC | `00:20:85:C0:92:FA` |
| IP | static — `ups` per [`network-addresses-generated.md`](network-addresses-generated.md) |
| VLAN | **20 (IoT, no WAN)** — access port; no consumer (NUT/USB is the only monitoring path) |
| Location | Rack floor / near the rack (18U cabinet) |
| Protects | **nas** (HP MicroServer Gen8), **oldsrv** (i7-7700K), **ha** (Raspberry Pi 4) + rack infra (router, switch, ONT) |

> The "IoT" in the model name means the RJ45 is the built-in **network (Ethernet)
> port**, not a serial/RS-485 Modbus port. It has an IoT network card with its own
> IP. Status is visible via the **winPower View** Android app.

---

## Physical Links

| Link | To | Detail |
|------|----|--------|
| **USB HID** | gen8 (`nas`) | `/dev/hidraw0`, `/dev/usb/hiddev0` — the **only live data link** to a host |
| **Ethernet (RJ45)** | LAN, **IoT VLAN 20 (no WAN)** | No consumer: the web UI and Modbus TCP are unused and the NIC stays isolated on a no-WAN VLAN |

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
- Unit ID **1**, function **0x03** (Read Holding Registers) works over the LAN (register block 0 identifies
  the model).
- **Not a consumer of record:** the HA Modbus sensors were removed and UPS monitoring is exclusively NUT over
  **USB HID**. No register map is needed. The endpoint stays available on the NIC (isolated VLAN, no WAN) but
  is not part of the design — see [network-rejected.md](network-rejected.md) / [network-vlans.md](network-vlans.md)
  for the NIC's VLAN move.

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
- **Shutdown policy + charge thresholds:** see the status block at the top (single place), implemented in the `nut` role via `nut_shutdown_charge_threshold`.

### Wake-after-recharge (WoL)

 when mains returns and `battery.charge ≥ nut_wake_charge` (80 on nas), the
master wakes a halted client (e.g. oldsrv, which halts at 75 %) with a magic packet. It must be a
**persistent systemd timer on nas** (`nut-wake.timer` → `nut-wake.service` → `/usr/local/sbin/nut-wake`,
every 60 s) — an upssched helper is NOT viable: it died with the SSH session in the first drill and sent no
packet. Conditions: UPS `OL`, charge ≥ threshold, client offline (ping fails) → `wakeonlan <mac>`
(MACs/IPs from `nut_wake_macs` + `network_static_hosts` SSOTs).
**BIOS requirements (ASRock Z270 Extreme4, oldsrv — verified):** `Advanced → ACPI Configuration →`
`PCIE Devices Power On = Enabled`, `I219 LAN Power On = Enabled`, `RTC Alarm Power On = By OS`, and
**`Deep Sleep = Disabled` — which lives under Advanced → Chipset Configuration, NOT under ACPI
Configuration** (the manual's ToC pagination is offset). OS side: `wake-on g` persists via
`/etc/network/if-up.d/ethtool`. Note: if the UPS itself cuts power (total outage), a board may need one
manual boot before WoL re-arms; with battery ride-down the master never cuts, so that is not the normal path.

## Monitoring & shutdown — implementation state

- **NUT master on nas — ✅ live:** `usbhid-ups` (USB), `upsd`, `nut_exporter`, `upssched-cmd` notify —
  the `nut` role in [`deployment-ansible.md`](deployment-ansible.md). `upsc powerwalker@localhost` answers.
- **NUT clients on oldsrv + Pi — ✅ live** (slave mode) with per-host shutdown (oldsrv 75 % charge +
  pre-flush, nas/Pi critical-only): client `upsmon`, a secret-free `upssched-cmd`, and charge-threshold
  shutdown via the upssched poll (HD-06).
- **Metrics + alerts (⏳ verify):** UPS metrics/alerts into VictoriaMetrics + Grafana
  ([`observability.md`](observability.md)) — Critical on battery charge/runtime, Warning on-battery, Info on
  transitions. **Metric shape is settled:** the exporter is DRuggeri `nut_exporter` v3, served on
  `/ups_metrics?ups=powerwalker` as **`network_ups_tools_*`** with per-flag
  `network_ups_tools_ups_status{flag=…}` labels (OL/OB/RB…) — **not** a `nut_*` bitmask. Alert rules,
  dashboard and the Alloy scrape (`metrics_path: /ups_metrics`, `params.ups`) match that shape; keep the
  **tagged** exporter release pinned in the nut role (a `(devel)` build was the original cause of the
  mismatch). ⏳ Live-verify the series + one alert firing after the next monitoring converge.
  See the monitoring role `vars/main.yml` + `alloy.river.j2`.
- **No web-UI firewall path:** the UPS NIC sits on IoT VLAN 20 with no WAN, and the old trusted-admin → UPS
  web forward rule is removed — NUT/USB is the only monitoring path (HD-338).
- **Guaranteed notify:** NUT-side `upssched-cmd` on nas emails + sends Signal directly on `ONBATT`/`LOWBATT`,
  independent of Grafana/n8n. The SMTP credentials must be rendered **inline from the vault** (see defect ②
  above); after a `smtp_login` rotation, re-converge nas and confirm the value in `/etc/nut/upssched-cmd`
  matches the vault.

## Hardware facts worth keeping

- **SNMP does not work on this NIC.** Probed from the Mgmt plane: no reply on 161/UDP (filtered) while
  Modbus TCP 502 is open and ICMP answers. Nothing would use SNMP anyway (monitoring is NUT/USB) — so the
  SNMP row in the protocol table is informational, and no SNMP consumer should ever be designed against it.
- The USB link is a HID device: it is **not** exposed as a serial (`/dev/ttyS*`) port.
- `usbhid-ups` on NUT 2.8.1 rejects `retrycount` in `ups.conf` — do not add it.

---

## Related

- [HP MicroServer Gen8 (nas)](hardware-nas.md) — the protected host
- [Rack Layout](network-rack.md) — physical placement + manual PDF
- [VLAN Plan](network-vlans.md) — UPS NIC on IoT VLAN 20 (no WAN); monitoring NUT/USB on Home VLAN 10
- [Home Assistant — current instance](home-assistant-current.md) — HA (UPS via NUT now, not Modbus)
- [Observability](observability.md) — where UPS metrics would land
