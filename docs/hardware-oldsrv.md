---
title: oldsrv — i7-7700K Docker Host
role: detail
domain: hardware
status: active
tags: [hardware, oldsrv, docker]
---
# oldsrv — i7-7700K Docker Host

> **Role:** Detail — Phase 1 primary server. Bare-metal Debian, simultaneously family desktop PC and 24/7 Docker host.
> **Current state (2026-09-08):** ✅ **Debian 13 (Trixie, XFCE) INSTALLED 2026-08-23** (Phase 1a; execution record: [deployment-tasks.md §Phase 1a](../deployment-tasks.md)). ✅ **oldsrv = bare-metal Debian desktop + Docker host, FULL STACK LIVE (Phase-3, HD-318):** full `home_servers.yml` converge **failed=0 (2026-09-08)** — network (SSOT static IPs + tagged-99 Mgmt leg via NetworkManager), storage (ZFS `nvme` + NFS client mounts to nas live: `/mnt/nas/{data,media,thumbs}`), nut (UPS client), cockpit, **amd_rocm** (Debian-trixie-native ROCm host userland `rocm-opencl-icd`/`rocminfo` + GPU plumbing `/dev/dri`+`/dev/kfd` + udev — immich-ml container (bundled ROCm) healthy and ready for the whole-collection import, a separate later task), desktop (Xorg/XFCE/LightDM, iGPU-primary), office (ONLYOFFICE via official repo fixed key + MS core fonts), docker_services (17 enabled services — the full media/*arr/downloads/DNS/smart-home/backup-agent set all Up + healthy), home_assistant (standby cold-render COMPLETE: `/opt/home-assistant-standby` compose + BACKUP keepalived + failover variant + secrets; ha-failover-api active), monitoring (Alloy + rsyslog + CrowdSec-acquisition (VPS-side) + **network-clients exporter HD-343 LIVE**). 1P items all present (`check-vault-items.sh --strict` green). ⏳ **Remaining:** kopia-agent connect gate = VPS kopia-server leg (post-Victoria); signal-cli phone registration; battery-pull test (HD-06); nas Mgmt-99 `eno1.99` leg (pre-existing ifupdown-vs-netd mismatch — convenience only, not functional).
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

- **GPU (RX 7600, 2026-09-06, owner-corrected 2026-09-09):** **Sunshine gaming-encode + immich-ML batch
  inference (AI)** — the immich-ml container bundles its own ROCm runtime and uses `/dev/dri`+`/dev/kfd`;
  Sunshine prep-commands pause/unpause it (gaming-first). No **host LLM/Ollama** on oldsrv (inference
  consolidated on spark/Triton, HD-335); `amd_rocm` host userland stays Debian-trixie-native tooling only.
- **TSDB storage:** the observability **backend moved to the VPS (HD-135)** — VictoriaMetrics/VictoriaLogs live on **VPS NVMe** (`/srv/docker/victoria-metrics/data` + `/srv/docker/victoria-logs/data`), not on oldsrv. Oldsrv runs only the thin **Alloy collector** (host metrics + logs) forwarding over the `wg-s2s` tunnel (`alloy_backend_host`). Metrics/logs are **Kopia-backed** (owner decision HD-341/342; host binds under `/srv/docker/victoria-*/data`). See `observability.md` §Placement. **HD-135b: the VPS runs its OWN Alloy** (loopback → local VictoriaMetrics/VictoriaLogs) + own Dozzle — it does not depend on oldsrv for its own observability.
- **Disk headroom:** monitor the `nvme` pool (oldsrv) + OS disk **and** the VPS NVMe in Grafana — pool ≥70% Warning / ≥80% Critical (see `observability.md`), OS disk ≥90% Critical.
- **SPOF (accepted, HD-135, narrowed HD-135b):** the observability **backend** now lives on the **VPS** — if the VPS (or the home↔VPS `wg-s2s` tunnel) is down, *home* metrics/logs are unavailable in Grafana (aggregation is buffered/replayed on reconnect; the VPS's own stack stays observable locally via its loopback Alloy + Dozzle). NUT-side `notifycmd`/`upssched-cmd` on nas remains the independent power-loss alert path. Documented in `observability.md` §Placement.
- Adds RAM weight vs original: n8n + VictoriaLogs are the main additions; i7-7700K / 48 GB handles the collector side.

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
