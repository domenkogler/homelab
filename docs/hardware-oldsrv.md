---
title: oldsrv — i7-7700K Docker Host
role: detail
domain: hardware
status: active
tags: [hardware, oldsrv, docker]
---
# oldsrv — i7-7700K Docker Host

> **Role:** Detail — Phase 1 primary server. Bare-metal Debian, simultaneously family desktop PC and 24/7 Docker host.
> **Current state (2026-08-23):** ✅ **Debian 13 (Trixie, XFCE) INSTALLED 2026-08-23** (Phase 1a reinstall done — interactively, not via preseed; execution record: [deployment-tasks.md §Phase 1a](../deployment-tasks.md) — the as-built evidence is the commit + this doc's status). Boot mode **BIOS/CSM** (msdos table on the 960 EVO; UEFI-force question answered No). Ansible hold rule active — first playbook contact only after the Phase 1.5 cutover. Everything below describes the target state; storage pools (ZFS `nvme`, NFS mounts) are NOT live yet.
> **NIC map (verified live at install):** `enp0s31f6` = onboard Intel (cabled during install, DHCP) · `enp5s0f0` / `enp5s0f1` = Intel i350-T2 (port 2 = `enp5s0f1` is the planned VLAN trunk to CRS328) · `wlp9s0` = WLAN card present — blacklisted at install (`module_blacklist=iwlwifi` on all media boot entries); consider disabling in BIOS.
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
| NVMe 1 | Samsung SSD 970 EVO 1TB — **data**: ZFS pool `nvme` (DBs, service data, TSDB, models, dumps) — heavy writes live here (600 TBW, fastest) · by-id `nvme-eui.0025385b0143f12e` |
| NVMe 2 | Samsung SSD 960 EVO 500GB — **system**: ext4 OS/root + `/opt` configs — light writes only (200 TBW) · by-id `nvme-eui.0025385c61b048c2` |

> by-ids derived from the Windows-reported EUI64 (2026-08-21; note: the pre-reinstall Windows C:\
> lived on the **970 EVO**, not the 960 — data was backed up, both disks are wiped/re-purposed at
> deploy). ✅ **Verified on Linux 2026-08-22** (Debian 13.6 live USB, [disk-facts report](../reports/disk-facts-oldsrv-20260822-191419.txt)):
> `nvme-eui.0025385c61b048c2` = 960 EVO 500 GB, S/N `S3EUNX0HC06971Z` (system) · `nvme-eui.0025385b0143f12e`
> = 970 EVO 1 TB, S/N `S5H9NS1NB12680T` (data — HD-128 closed). Both NVMes carried NTFS signatures at capture.
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

## Docker Services (HD-135 split — oldsrv = GPU/LAN core)

> **Single source of truth:** the canonical service catalog is [`services.md`](services.md).
> Per the HD-135 split, `oldsrv` runs the **GPU/LAN/storage-bound core** (ollama, immich-ml, jellyfin/*arr, sunshine, DNS, HA standby, homepage, signal-cli); the public edge + live-data apps + observability backend + GitOps moved to the VPS. **HD-135b (2026-08-28): Dozzle also moved to the VPS** (logs viewer independent of home hosts) — see [`observability.md`](observability.md) §Placement.
> GPU-enabled containers (Ollama, Immich-ML, Sunshine) are noted in `hardware-gpu.md`.

---

## Observability Storage & Notes

- **TSDB storage:** the observability **backend moved to the VPS (HD-135)** — Prometheus/Loki live on **VPS NVMe** (`/srv/tsdb` on the VPS, or equivalent `prometheus`/`loki` service volumes), not on oldsrv. Oldsrv runs only the thin **Alloy collector** (host metrics + logs) forwarding over the `wg-s2s` tunnel (`alloy_backend_host`). Metrics/logs remain **regenerable**, ~10–20 GB at 30d/14d retention, not backed up. See `observability.md` §Placement. **HD-135b: the VPS runs its OWN Alloy** (loopback → local Prometheus/Loki) + own Dozzle — it does not depend on oldsrv for its own observability.
- **Disk headroom:** monitor the `nvme` pool (oldsrv) + OS disk **and** the VPS NVMe in Grafana — pool ≥70% Warning / ≥80% Critical (see `observability.md`), OS disk ≥90% Critical.
- **SPOF (accepted, HD-135, narrowed HD-135b):** the observability **backend** now lives on the **VPS** — if the VPS (or the home↔VPS `wg-s2s` tunnel) is down, *home* metrics/logs are unavailable in Grafana (aggregation is buffered/replayed on reconnect; the VPS's own stack stays observable locally via its loopback Alloy + Dozzle). NUT-side `notifycmd`/`upssched-cmd` on nas remains the independent power-loss alert path. Documented in `observability.md` §Placement.
- Adds RAM weight vs original: n8n + Loki are the main additions; i7-7700K / 48 GB handles the collector side.

---

## Docker Networks

| Network | Purpose |
|---------|---------|
| traefik-public | Traefik ↔ exposed services |
| services-internal | App ↔ app communication |
| db-internal | Databases, fully isolated |

> CIDRs: [`network-addresses-generated.md`](network-addresses-generated.md) → *Infrastructure networks* (SSOT).

---

## Remote Management

**GL.iNet Comet KVM (GL-RM1):**
- Connects to motherboard iGPU HDMI
- PoE-powered from CRS328 switch
- BIOS-level control, remote power/reset, virtual ISO mounting
- OS-independent (works if Debian crashes)

---

## Design Consideration: Proxmox Hypervisor Layer — REJECTED for Phase 1

> **REJECTED (2026-08-16, HD-92):** oldsrv stays **bare-metal Debian + Docker** — no local Proxmox and no GPU
> passthrough on the single Phase-1 box (one shared dGPU serves both desktop and AI; a single host gains no HA
> from VMs). Proxmox defers to Phase 2 (HD-41/42) with a real second node. Full rationale + the rejected
> `infra`/`desktop` VM split (blueprint decided 2026-08-19; live install used a single full-metal install — the split is a re-install option, per `hardware-oldsrv/` VM layout note) + git history.
