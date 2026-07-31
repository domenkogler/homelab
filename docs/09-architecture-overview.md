# Architecture Overview

> **Single-page summary.** For details see referenced docs.  
> Created: 2026-07-31 — supersedes fragmented architecture across multiple docs.

---

## Machine Roles

| Machine | Phase 1 (Now) | Phase 2+ (Scale-up) |
|---------|---------------|----------------------|
| **debhost** (i7-7700K, 48 GB, RX 7600) | **All** 22+ Docker services — public web stack, AI/LLM, DNS, Git, VPN, backup, observability, family PC | AI/LLM only, or retired |
| **gen8** (HP MicroServer, 12 GB ECC) | ZFS pools (tank + backup), NFS exports, Cockpit monitoring | Same — permanent storage server |
| **VPS** (Contabo) | *Not used* | Public web stack — see [03](03-vps-infrastructure.md) |
| **custom** (Ryzen 9 + R9700) | *Not built* | Proxmox hypervisor — see [02](02-home-server-hardware.md#phase-2-target-build-if-phase-1-is-insufficient) |

---

## 5-Layer Architecture

| Layer | Name | Phase 1 Tool | Phase 2+ Tool | Doc |
|-------|------|-------------|---------------|-----|
| **5** | Visibility | Homepage, Grafana, Renovate Dashboard | Same (portable) | [08](08-gitops-operations.md) |
| **4** | Version Tracking | Renovate Bot | Same | [08](08-gitops-operations.md) |
| **3** | Deployment (CD) | **Doco-CD** (debhost, local Docker) | Doco-CD (debhost) + Forgejo Actions (VPS, remote) | [08](08-gitops-operations.md) |
| **2** | Git Hosting | Forgejo (self-hosted on debhost) | Same | [08](08-gitops-operations.md) |
| **1** | OS Bootstrap | Debian Preseed + Ansible | Same + Proxmox VM provisioning | [02](02-home-server-hardware.md) |

---

## Key Design Decisions

1. **Doco-CD for local CD** — faster than Ansible, automatic drift correction, no SSH needed. Forgejo Actions + Ansible remains available as **fallback for remote (VPS) deployments** and **CI (tests, image scanning) on pull requests**.
2. **Compose files are portable** — the same `docker-compose.yml` deploys identically on debhost (bare metal Docker), a VPS (remote Docker), or a Proxmox Docker VM. Doco-CD and Forgejo Actions both consume the same compose files.
3. **Ansible is OS-only** — system provisioning (ZFS, Docker daemon, GPU drivers, Doco-CD bootstrap) is one-time. Application lifecycle is fully GitOps via Doco-CD.
4. **Three dashboards, three audiences:**
   - **Homepage** (`kogler.si`) — family launchpad, app icons with health dots
   - **Renovate Dependency Dashboard** (Forgejo Issue) — admin: pending upstream updates, check-box approval
   - **Grafana** (`stats.kogler.si`) — admin: deep metrics, logs, resource usage
5. **VPS is deferred, not eliminated** — see [03](03-vps-infrastructure.md). The public web stack is designed to run on any Docker host. Phase 1 runs it on debhost; Phase 2+ can selectively migrate services to VPS, Proxmox, or both without architecture changes.

---

## Deployment Flows

### Third-Party Images (Immich, Authentik, OpenCloud, ...)

```
Upstream release → Renovate (3-day hold) → Dependency Dashboard
    → Domen checks box → Renovate PR → Domen merges
    → Doco-CD detects merge → docker compose up -d → deployed
```

### Custom C# Applications

```
git push → Doco-CD webhook → docker compose build + up → deployed in <5 min
```

---

## Service Catalog (Phase 1 — all on debhost)

| Category | Services | Network |
|----------|----------|---------|
| **Edge** | Traefik, CrowdSec | traefik-public |
| **Identity** | Authentik | services-internal |
| **Platform** | OpenCloud, Immich, Forgejo | services-internal |
| **AI/LLM** | Ollama, Immich-ML | services-internal (GPU: `/dev/dri`, `/dev/kfd`) |
| **DNS** | Technitium, Pi-hole | services-internal |
| **VPN** | Headscale | traefik-public |
| **Backup** | Kopia, DB Backup (tiredofit) | services-internal, db-internal |
| **Dashboard** | Homepage | traefik-public |
| **Observe** | Grafana, InfluxDB, Prometheus, Loki | traefik-public, db-internal |
| **CD** | Doco-CD | host Docker socket |
| **Update** | Renovate Bot | services-internal |
| **Stream** | Sunshine (manual) | services-internal (GPU) |

### Docker Networks

| Network | CIDR | Purpose |
|---------|------|---------|
| traefik-public | 172.20.0.0/16 | Traefik ↔ exposed services |
| services-internal | 172.21.0.0/16 | App ↔ app communication |
| db-internal | 172.22.0.0/16 | Databases, fully isolated |