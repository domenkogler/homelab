---
title: oldsrv — i7-7700K Docker Host
role: detail
domain: hardware
status: active
tags: [hardware, oldsrv, docker]
---
# oldsrv — i7-7700K Docker Host

> **Role:** Detail — the primary home server. Bare-metal Debian 13 (Trixie, XFCE), simultaneously family
> desktop PC and 24/7 Docker host.
> **Status: ✅ LIVE** — full `home_servers.yml` stack converged: network (SSOT static IPs + the tagged-99
> Mgmt leg), storage (ZFS `nvme` pool + NFS client mounts to nas: `/mnt/nas/{data,media,thumbs}`), NUT
> client, Cockpit, `amd_rocm` host userland + `/dev/dri` GPU plumbing, desktop (Xorg/XFCE,
> iGPU-primary), ONLYOFFICE office stack, the enabled `docker_services` set (media/*arr, downloads, DNS
> secondary, smart-home, backup agent, LAN AI tier), the Home Assistant **standby** render (cold standby +
> keepalived BACKUP + failover variant), and the thin monitoring collector.
> ⏳ **Remaining:** the kopia-agent connect gate (needs the VPS kopia-server leg), signal-cli phone
> registration (owner), the battery-pull test (HD-06), and nas's Mgmt-99 `eno1.99` leg (convenience only).
>
> Execution history for this host = [deployment-tasks.md](../deployment-tasks.md) + git log.
> **NIC map:** `enp0s31f6` = onboard Intel (boot/main, Home VLAN) · `enp5s0f0` / `enp5s0f1` = Intel i350-T2
> (port 2 = `enp5s0f1`) · `wlp9s0` = WLAN card, blacklisted (`module_blacklist=iwlwifi`); consider
> disabling in BIOS.
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
| NIC | **Onboard Intel I219-V** (`enp0s31f6`, MAC `70:85:C2:2D:6F:04`) = boot/main link on Home VLAN (IP see `network_static_hosts` SSOT), **WoL-capable** (BIOS: ACPI Config → PCIE Devices Power On + I219 LAN Power On = Enabled, Deep Sleep = Disabled; OS `wake-on g` via if-up hook) · Intel i350-T2 (`enp5s0f0/1`) — one port used, planned VLAN trunk to CRS328 |
| RAM | 48 GB DDR4 (2×8 GB + 2×16 GB Corsair Vengeance LPX, DDR4-2400) |
| NVMe 1 | Samsung SSD 970 EVO 1TB — **data**: ZFS pool `nvme` (DBs, service data, models, dumps) — heavy writes live here (600 TBW, fastest) · by-id `nvme-eui.0025385b0143f12e` |
| NVMe 2 | Samsung SSD 960 EVO 500GB — **system**: ext4 OS/root + `/opt` configs — light writes only (200 TBW) · by-id `nvme-eui.0025385c61b048c2` |

> by-ids **verified on Linux** (Debian live USB, [disk-facts report](../reports/disk-facts-oldsrv-20260822-191419.txt)):
> `nvme-eui.0025385c61b048c2` = 960 EVO 500 GB, S/N `S3EUNX0HC06971Z` (**system**) ·
> `nvme-eui.0025385b0143f12e` = 970 EVO 1 TB, S/N `S5H9NS1NB12680T` (**data**). Do not infer the mapping
> from an old Windows report — the pre-reinstall Windows `C:\` lived on the 970, and both disks were
> wiped and re-purposed at deploy.
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
- **Radeon RX 7600 (dGPU):** No monitor. Containers reach it through `/dev/dri/renderD128` + the
  `video`/`render` groups; only the images that actually ship ROCm (immich-ML) also need `/dev/kfd`.
  The pinned AI tier is Vulkan and deliberately gets **no** `/dev/kfd`.
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
> `oldsrv` runs the **GPU/LAN/storage-bound core** — media/*arr, downloads, DNS secondary, HA standby,
> immich-ML, Sunshine, signal-cli and the pinned-AI legs; the public edge, live-data apps, the
> observability **backend**, GitOps and the log viewer (Dozzle) live on the VPS (HD-135/HD-135b —
> independent of the home hosts). GPU-enabled containers are listed in `hardware-gpu.md`.
> **There is no family-LLM serving tier here:** big-model generation runs on spark, vision on the
> workstation ([`services-ai.md`](services-ai.md) §9).

---

## Observability Storage & Notes

- **GPU (RX 7600, decision #24):** three users of one 8 GB card, in priority order —
  **gaming (Sunshine encode) > the pinned AI tier (whisper STT + bge-m3 embed + bge-reranker,
  2475 MiB measured all-three warm) > immich-ML batch inference (lowest)**. Sunshine's prep-commands
  pause/resume the AI containers so a session always wins.
  **The pinned tier is Vulkan/RADV, not ROCm:** it mounts only `/dev/dri/renderD128` + the `video`/`render`
  groups — **no `/dev/kfd`, no `HSA_*`** — because there is no published ROCm artifact for that engine
  family (immich-ML is the exception: it bundles its own ROCm userspace).
  **There is no general LLM runtime here** — generation is on spark. The one exception is the retained
  `ollama` service, kept **only** as the embed fallback rung (see
  [services-ai.md](services-ai.md) §Pinned tier) and not a chat/generation host. `amd_rocm` host userland is
  Debian-trixie-native tooling only.
- **Metrics/logs storage:** the observability **backend is on the VPS** —
  VictoriaMetrics/VictoriaLogs data on **VPS NVMe** (`/srv/docker/victoria-*/data`), not on oldsrv. Oldsrv
  runs only the thin **Alloy collector** (host metrics + logs) forwarding over the `wg-s2s` tunnel
  (`alloy_backend_host`). Metrics/logs are **Kopia-backed** (HD-341/342). The VPS runs its **own** Alloy
  (loopback → local VictoriaMetrics/VictoriaLogs) + its own Dozzle, so it never depends on oldsrv for its
  own observability. See `observability.md` §Placement.
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

### Reachability & wake (measured 2026-09-24)

**Off the network since 2026-09-23 21:39:55 local.** Four independent observations agree, and the
point of listing them is that the first one people reach for does NOT prove it:

- headscale (authoritative, ACL-blind): node id 11 `oldsrv`, `Connected: offline`,
  last seen `2026-09-23 19:39:55` **UTC** = 21:39:55 local — the same second as the nas `rpc.mountd`
  `v4.2 client detached` lease release for that NFS client (the address is the SSOT's, not this doc's).
  Two control planes, one timestamp.
- `ip neigh show <oldsrv Home IP>` on the nas: `INCOMPLETE`; the MAC above is absent from the
  neighbour table entirely, and a sweep of the usual alternate addresses finds nothing → it is not a
  DHCP re-assign, it is L2-dead.
- `tailscale ping <oldsrv tailnet IP>` from the VPS sidecar answers `no matching peer`, which proves
  **nothing** about this box: the sidecar is ACL-scoped away from `tag:dev` by design. Do not record
  that output as evidence of a dead host again.

**To bring it back, in increasing order of cost:**
1. `wakeonlan` from the nas (same L2, binary present, `ansible-admin` has NOPASSWD sudo):
   `sudo wakeonlan 70:85:C2:2D:6F:04`. Needs standby power, and it is a power action → §5.9 human gate.
2. The Comet KVM above: BIOS-level power/reset, so a *hung* box is reachable from anywhere without a
   hand on the button. This is the path when (1) is refused by silence.
   **Attempted 2026-09-24, and it was:** three magic-packet shapes (default broadcast, subnet broadcast,
   port 9) sent twice from the nas on the same L2 as the target, with no ARP entry for the MAC afterwards
   and no answer on the Home IP. Silence after that pattern means "no standby power or the wake path is
   not armed", not "wrong packet" — so do not re-litigate the packet shape; go to the KVM.
   ⚠ **The KVM is documented as a capability and not as an access path**: this file names the model and
   what it can do, but records no address, no network (VLAN 10 / VLAN 99 / tailnet?), no account, and no
   reachability check from off-site. Until that is written down, "use the KVM" cannot be executed by a
   session or by the owner from a phone — tracked as **HD-454**, which also asks whether a device that can
   hard-power a production host belongs on a user VLAN un-gated. ⚠ **The conditional that decides whether
   "from anywhere" is even true:** if the Comet sits on VLAN 99, then **HD-398 decision A seals it to
   same-site** and there is no off-site path to the reset button at all, so a hung oldsrv waits for a human
   at home; if it is on VLAN 10 or a tailnet node, the seal does not apply and the gap is only that nobody
   wrote the path down. HD-454 must measure which, not assume either — the answer is a one-line `ip neigh`
   / ARP lookup against the KVM's address.
3. HD-06's `nut-wake.timer` is NOT a rescue path: it arms only after a NUT-initiated powerdown and
   recharge, so it cannot wake an unscheduled drop.

**Registered as HD-455** (P1) — a measured fault with an owning doc but no backlog row is invisible to every
lane, and the tail behind this box is long: the home edge, `cockpit-oldsrv`, the nas cockpit's tailnet name
(rendered onto oldsrv by the cockpit role), the control node, the pinned-AI tier, HD-442, HD-443's oldsrv
placements and the HD-419-class 502s all wait here. **The wake path is spent** (2026-09-24, above), so what
recovery needs is not another packet but the answer HD-454 owes: an executable off-site power path, or an
explicit decision that a hung oldsrv waits for a human at home.

**Consequence for the fleet:** a down oldsrv takes the home edge with it — including the nas's own
Cockpit route, because `/opt/traefik/dynamic/cockpit.yml` is rendered onto oldsrv by the cockpit role.
A healthy nas with a dead console is normal behaviour here, not a nas fault.


---

## Host platform: bare-metal, no hypervisor

oldsrv is **bare-metal Debian + Docker** — no local hypervisor, no GPU passthrough. One shared dGPU serves
both the desktop and the AI containers, and a single host gains no HA from VMs. The `infra`/`desktop` VM
split was considered and never installed (a re-install option at most).
Decision log: [deployment-rejected.md](deployment-rejected.md) (Proxmox rows).
