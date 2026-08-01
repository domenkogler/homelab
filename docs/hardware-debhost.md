# debhost — i7-7700K Docker Host

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
| NVMe 1 | Samsung SSD 970 EVO 1TB — OS, Docker volumes, DBs, LLM models |
| NVMe 2 | Samsung SSD 960 EVO 500GB — bulk data, media, second-stage storage |
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

> Full CPU-Z data dump: [`assets/references/DOMENPC-cpuz.txt`](../assets/references/DOMENPC-cpuz.txt)

---

## Network

- Single UTP to CRS328 switch (port 7 on patch panel)
- VLAN trunk: 10 (Home), 20 (IoT), 50 (Media) tagged + 99 (Management) native
- Intel i350-T2 dual-port NIC — only one port used

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

## Docker Services (Phase 1 — all on debhost)

| Category | Service | GPU | Network | Description |
|----------|---------|-----|---------|-------------|
| **Edge** | Traefik | No | traefik-public | Reverse proxy, auto-SSL, Forward Auth |
| **Edge** | CrowdSec | No | traefik-public | WAF, brute-force protection |
| **Identity** | Authentik | No | services-internal | OIDC SSO, MFA (WebAuthn) |
| **Platform** | OpenCloud | No | services-internal | File sync, WebDAV, OIDC |
| **Platform** | Immich | No | services-internal | Photo management |
| **Platform** | Forgejo | No | services-internal | Git hosting, Issues, PRs |
| **AI** | Ollama | **Yes** | services-internal | LLM inference |
| **AI** | Immich-ML | **Yes** | services-internal | Face recognition, object detection |
| **DNS** | Technitium | No | services-internal | Central DNS router |
| **DNS** | Pi-hole | No | services-internal | Ad-blocking |
| **VPN** | Headscale | No | traefik-public | Tailscale coordination server |
| **Backup** | Kopia | No | services-internal | Encrypted off-site backup → iDrive e2 |
| **Backup** | DB Backup | No | db-internal | Database dumps (tiredofit/db-backup) |
| **Dashboard** | Homepage | No | traefik-public | Family launchpad at `kogler.si` |
| **Observe** | Grafana | No | traefik-public | Analytics dashboards |
| **Observe** | InfluxDB | No | db-internal | Time-series metrics |
| **Observe** | Prometheus | No | db-internal | Metrics collection |
| **Observe** | Loki | No | db-internal | Log aggregation |
| **CD** | Doco-CD | No | host docker.sock | GitOps continuous delivery |
| **Update** | Renovate Bot | No | services-internal | Docker image version tracking |
| **Stream** | Sunshine | **Yes** | services-internal | Game streaming (manual start) |
| **System** | sanoid/syncoid | No | host (cron) | ZFS snapshots → gen8 |

**Total: 22+ Docker services.**

---

## Docker Networks

| Network | CIDR | Purpose |
|---------|------|---------|
| traefik-public | 172.20.0.0/16 | Traefik ↔ exposed services |
| services-internal | 172.21.0.0/16 | App ↔ app communication |
| db-internal | 172.22.0.0/16 | Databases, fully isolated |

---

## Remote Management

**GL.iNet Comet KVM (GL-RM1):**
- Connects to motherboard iGPU HDMI
- PoE-powered from CRS328 switch
- BIOS-level control, remote power/reset, virtual ISO mounting
- OS-independent (works if Debian crashes)