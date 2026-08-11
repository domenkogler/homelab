---
title: oldsrv — i7-7700K Docker Host
role: detail
domain: hardware
status: active
tags: [hardware, oldsrv, docker]
---
# oldsrv — i7-7700K Docker Host

> **Role:** Detail — Phase 1 primary server. Bare-metal Debian, simultaneously family desktop PC and 24/7 Docker host.
> **Links to:** `hardware-gpu.md`, `services.md`, `network-vlans.md`
> **Linked from:** `hardware.md`, `deployment-preseed.md`, `deployment-ansible.md`

---

## Hardware

| Component | Detail |
|-----------|--------|
| CPU | Intel i7-7700K (4C/8T, 4.2 GHz base, 4.5 GHz boost, Kaby Lake, 14 nm) |
| Motherboard | ASRock Z270 Extreme4 (AMI UEFI, Z270 chipset) |
| iGPU | Intel HD 630 → dedicated to Linux desktop (family PC) |
| dGPU | AMD Radeon RX 7600 8 GB → dedicated to Docker AI containers |
| NIC | Intel i350-T2 (one port used — VLAN trunk to CRS328) |
| RAM | 48 GB DDR4 (2×8 GB + 2×16 GB Corsair Vengeance LPX, DDR4-2400) |
| NVMe 1 | Samsung SSD 970 EVO 1TB — **data**: ZFS pool `nvme` (DBs, service data, TSDB, models, dumps) — heavy writes live here (600 TBW, fastest) |
| NVMe 2 | Samsung SSD 960 EVO 500GB — **system**: ext4 OS/root + `/opt` configs — light writes only (200 TBW) |
| OS | Debian with XFCE or GNOME desktop |
| Location | Workstation desk (not rack-mounted) |

### RAM DIMM Detail

| DIMM | Size | Part Number | Manufacturer |
|------|------|-------------|--------------|
| 1 | 8 GB | CMK16GX4M2A2400C14 | SK Hynix |
| 2 | 16 GB | CMK32GX4M2A2400C14 | Samsung |
| 3 | 8 GB | CMK16GX4M2A2400C14 | SK Hynix |
| 4 | 16 GB | CMK32GX4M2A2400C14 | Samsung |

### NVMe SMART Summary

| Drive | Hours | Written | Spare | Health |
|-------|-------|---------|-------|--------|
| Samsung SSD 970 EVO 1TB | 12,943 h | 48.8 TB | 98% | ✅ (⚠️ 87°C temp sensor 2) |
| Samsung SSD 960 EVO 500GB | 11,360 h | 30.5 TB | 100% | ✅ (⚠️ 226 unsafe shutdowns) |

> Full CPU-Z data dump: [`assets/references/DOMENPC-cpuz.txt`](assets/references/DOMENPC-cpuz.txt)

---

## Network

- Single UTP to CRS328 switch (port 7 on patch panel)
- VLAN trunk: 10 (Home), 20 (IoT), 50 (Media) tagged + 99 (Management) native
- Intel i350-T2 dual-port NIC — only one port used
- **UPS:** backed by the PowerWalker VFI ICT/ICR IoT 3000 (see [`hardware-ups.md`](hardware-ups.md)). Runs as a **NUT client** (slave to `nas`) with a **60 s shutdown delay** so its Grafana→n8n→Signal/email alerts flush before powerdown on a mains outage.

---

## Dual GPU Topology

See [`hardware-gpu.md`](hardware-gpu.md) for detailed VRAM management.

- **Intel HD 630 (iGPU):** Xorg runs exclusively here. Monitor on motherboard HDMI/DP.
- **Radeon RX 7600 (dGPU):** No monitor. Docker containers access via `/dev/dri` and `/dev/kfd`.
- Xorg config forces iGPU primary, excludes dGPU from desktop compositing.

---

## Headless Boot

Containers start at boot via systemd units **before any user logs in**:
- `restart: always` on all AI containers
- Scheduled reboot at 04:00 (systemd timer)
- Family logout or desktop session close does **NOT** affect containers

---

## Docker Services (Phase 1 — all on oldsrv)

> **Single source of truth:** the canonical service catalog is [`services.md`](services.md).
> In Phase 1 **all** services run here on `oldsrv.kogler.si`; in Phase 2 the public-facing ones move to `vps` (Traefik).
> GPU-enabled containers (Ollama, Immich-ML, Sunshine) are noted in `hardware-gpu.md`.

---

## Observability Storage & Notes

- **TSDB storage:** Prometheus/Loki on the oldsrv **`nvme` ZFS pool** (`nvme/tsdb`, 16K/lz4, no snapshots, no backup), not nas ZFS — metrics/logs are **regenerable**, expected ~10–20 GB at 30d/14d retention. Retention deliberate (see `observability.md`).
- **Disk headroom:** monitor the `nvme` pool **and** OS disk in Grafana — pool ≥70% Warning / ≥80% Critical (see `observability.md`), OS disk ≥90% Critical.
- **SPOF (accepted):** all observability lives here — if oldsrv dies, you cannot see nas/others. Documented; HA standby (see [`smart-home-failover.md`](smart-home-failover.md)) + backups cover recovery, not observability continuity.
- Adds RAM weight vs original: n8n + Loki are the main additions; i7-7700K / 48 GB handles it.

---

## Docker Networks

| Network | Purpose |
|---------|---------|
| traefik-public | Traefik ↔ exposed services |
| services-internal | App ↔ app communication |
| db-internal | Databases, fully isolated |

> CIDRs: [`network-addresses.md`](network-addresses.md) → *Infrastructure networks* (SSOT).

---

## Remote Management

**GL.iNet Comet KVM (GL-RM1):**
- Connects to motherboard iGPU HDMI
- PoE-powered from CRS328 switch
- BIOS-level control, remote power/reset, virtual ISO mounting
- OS-independent (works if Debian crashes)