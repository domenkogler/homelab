# Architecture Audit — Kogler Homelab

> **Date:** 2025-07-XX
> **Auditor:** AI (cross-referenced against `Qwen-bugs.md`, `todo.md`, full IaC + docs scan)
> **Status:** Pre-production — nothing live yet; all findings are design-time.

---

## 1. Current Topology & Traffic Flow

### 1.1 Hardware Layer

```
                     ┌─────────────────────────────────────────────────┐
                     │         Telekom PPPoE (WAN)                    │
                     └──────────────────────┬──────────────────────────┘
                                            │  ether1 (WAN)
                          ┌─────────────────▼─────────────────┐
                          │   MikroTik RB4011 (router)        │
                          │   VLANs: 10/20/21/30/40/50/99     │
                          │   (currently flat — VLAN redo = HD-03)│
                          └───┬──────────────┬───────────┬─────┘
                              │              │           │
                   sfp+ trunk │      ether access       │ ether (AP PoE)
                     │        │          ports          │
    ┌────────────────▼───┐    │                         │
    │ MikroTik CRS328    │    │    ┌──────────┐  ┌─────▼──────┐
    │ L2 PoE switch      │    │    │ wAP ac   │  │ hAP ac²    │
    │ (VLAN-aware)       │    │    │ (garaža) │  │ (spalnica) │
    └───┬───────┬────┬───┘    │    └──────────┘  └────────────┘
        │       │    │        │         (CAPsMAN, local-fwd=no)
   eth? │   eth?│  eth?│      │
        │       │      │      │
   ┌────▼─┐ ┌───▼──┐ ┌─▼─────┐ ┌──────────┐
   │nas   │ │oldsrv│ │  Pi 4 │ │ UPS IoT  │
   │HP MS │ │i7-7K │ │Debian │ │10.10.99.9│
   │Gen8  │ │+AMD  │ │HA+DNS │ │          │
   │ZFS   │ │GPU   │ │sec'dry│ │          │
   └──────┘ └──────┘ └───────┘ └──────────┘
```

**Three compute hosts, one NAS, one router, one switch:**

| Host | Arch | Role | Network Position |
|------|------|------|-----------------|
| `oldsrv.kogler.si` | x86_64, i7-7700K + AMD RX 7600 | Docker host (full service stack) + family desktop + Technitium DNS primary + HA cold standby | Trunk: VLANs 10/20/50 tagged + 99 native |
| `pi.kogler.si` | ARM64, RPi4 | Home Assistant primary + RaspberryMatic + Technitium DNS secondary + traefik-ha VIP edge | Access: VLAN 10 (Home), mgmt on VLAN 99 |
| `nas.kogler.si` | x86_64, HP MicroServer Gen8 | ZFS storage (tank + bulk pools), NFS server, NUT master | Trunk: VLANs 10 + 99 |
| `router.kogler.si` | x86_64, MikroTik RB4011 | Gateway, DHCP, firewall, CAPsMAN controller, WireGuard endpoint | All VLANs (inter-VLAN routing) |
| `switch.kogler.si` | ARM, MikroTik CRS328 | L2 VLAN-aware PoE switch | SFP+ uplink to router, RJ45 downlinks |

### 1.2 Ingress Traffic Flow — Internet → Services

```
               Internet
                  │
                  │  DNS: *.kogler.si → real IP (Cloudflare DNS-only, no proxy)
                  ▼
           ┌──────────────┐
           │  Cloudflare   │  Registrar: domenca.com
           │  DNS only     │  Nameservers: george/may.ns.cloudflare.com
           └──────┬───────┘
                  │  A record → public WAN IP
                  ▼
           ┌─────────────────┐
           │ Telekom WAN     │  PPPoE on ppooe-telekom / ether1
           │ (NAT boundary)  │
           └──────┬──────────┘
                  │  Port 443 forwarded (if any forwarding set)
                  ▼
    ┌─────────────────────────────────────────────┐
    │          Traefik Edge (oldsrv)              │
    │                                             │
    │  Entrypoints:                               │
    │    :80  → HTTP → redirect :443              │
    │    :443 → HTTPS (wildcard *.kogler.si cert) │
    │                                             │
    │  Cert: Cloudflare DNS-01 ACME (LETSENCRYPT) │
    │  Token from 1Password `cloudflare_api`      │
    │                                             │
    │  Middleware chain (default):                 │
    │    1. crowdsec-bouncer (WAF + IP blocklist)  │
    │    2. authentik-forward-auth-inner (SSO)    │
    │                                             │
    │  Exception routes (no Forward-Auth):        │
    │    ha.kogler.si      → VIP:8123             │
    │    matrix.kogler.si  → Tuwunel homeserver   │
    │    chat.kogler.si    → Element Web static   │
    │    media.kogler.si   → Jellyfin             │
    │    seerr.kogler.si   → Seerr                │
    │                                             │
    │  Internal-only routes (no public DNS):      │
    │    stats.bck.dns.ad.auto.sec.logs.home      │
    │    cockpit-nas, cockpit-oldsrv, dns-pi      │
    │    sonarr, radarr, lidarr, prowlarr, …      │
    └──────┬──────────────┬──────────┬────────────┘
           │              │          │
    ┌──────▼──────┐ ┌─────▼────┐ ┌──▼──────────┐
    │ Authentik   │ │ Service  │ │ VIP route    │
    │ SSO (sso.)  │ │ backend  │ │ ha-vip:8123  │
    │ OIDC MFA    │ │ container│ │ (Pi or       │
    │ Passkeys    │ │ on       │ │  oldsrv)     │
    │ WebAuthn    │ │traefik-  │              │
    │ + TOTP      │ │public    │              │
    └─────────────┘ └──────────┘              │
                                              │
                               ┌──────────────▼───────┐
                               │  Pi (traefik-ha edge) │
                               │  VIP-bound :80/:443   │
                               │  serves ha.kogler.si  │
                               │  + dns-pi.kogler.si   │
                               │  (cert synced from    │
                               │   oldsrv, not ACME)   │
                               └───────────────────────┘
```

### 1.3 Ingress Traffic Flow — Headscale VPN (Road Warrior)

```
  Client device (phone/laptop)
        │
        │  Tailscale-compatible client
        │  OIDC auth → Authentik (headscale_api)
        │
        ▼
  ┌─────────────────┐
  │ Headscale       │
  │ (oldsrv Docker) │  CGNAT 100.64.0.0/10
  │ vpn.kogler.si   │  Auto-approve after OIDC (⚠ KOPS-022)
  └──────┬──────────┘
         │  WireGuard overlay
         ▼
  ┌─────────────────┐
  │ RB4011          │  Routes CGNAT traffic per policy
  │ WireGuard iface │
  └─────────────────┘
```

### 1.4 Internal Traffic Flows

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                      Docker Networks                            │
  │                                                                 │
  │  ┌─────────────────────────┐                                    │
  │  │  traefik-public         │  Traefik ↔ exposed services        │
  │  │  CIDR: 172.20.0.0/16    │  (CrowdSec bouncer, Homepage,     │
  │  │                          │   Metabase, Technitium web UI,    │
  │  │  Members:                │   Jellyfin, Seerr, *arr UIs,      │
  │  │  Traefik, CrowdSec,     │   Grafana, Dozzle, Element Web,   │
  │  │  Authentik server,      │   Headscale, Matrix/Tuwunel,      │
  │  │  Technitium, Pi-hole,   │   Renovate, gluetun network)       │
  │  │  Homepage, Metabase,    │                                    │
  │  │  Grafana, Dozzle,       │                                    │
  │  │  Headscale, Matrix,     │                                    │
  │  │  Element Web, Jellyfin, │                                    │
  │  │  Seerr, *arr stack,     │                                    │
  │  │  gluetun network        │                                    │
  │  └─────────────────────────┘                                    │
  │                                                                 │
  │  ┌─────────────────────────┐                                    │
  │  │  services-internal      │  App ↔ app communication           │
  │  │  CIDR: 172.21.0.0/16    │  No Traefik labels needed here     │
  │  │                          │                                    │
  │  │  Members:                │                                    │
  │  │  Authentik, OpenCloud,   │                                    │
  │  │  Immich, Forgejo, Ollama,│                                    │
  │  │  Immich-ML, Technitium,  │                                    │
  │  │  Pi-hole, Kopia, n8n,    │                                    │
  │  │  signal-cli, blackbox,   │                                    │
  │  │  Renovate, sunshine,     │                                    │
  │  │  Matrix, *arr apps,      │                                    │
  │  │  Recyclarr, Actual Budget│                                    │
  │  └─────────────────────────┘                                    │
  │                                                                 │
  │  ┌─────────────────────────┐                                    │
  │  │  db-internal            │  Database layer (fully isolated)    │
  │  │  CIDR: 172.22.0.0/16    │                                    │
  │  │                          │                                    │
  │  │  Members:                │                                    │
  │  │  Prometheus, Loki,       │                                    │
  │  │  Grafana DB access,      │                                    │
  │  │  db-backup,              │                                    │
  │  │  Authentic DB,           │                                    │
  │  │  Immich DB, Forgejo DB   │                                    │
  │  └─────────────────────────┘                                    │
  │                                                                 │
  │  Host-level:                                                    │
  │  Alloy (host binary, docker.sock ro) → Loki/Prometheus scrape   │
  │  Doco-CD (host network + docker.sock rw) ⚠ not yet activated    │
  └─────────────────────────────────────────────────────────────────┘
```

### 1.5 DNS Resolution Chain

```
  Client device (DHCP client on VLAN X)
        │
        │  Primary:  Technitium on oldsrv (10.10.1.30:53)
        │  Secondary: Technitium on Pi (10.10.1.20:53)
        │  Fallback:  Router /ip dns → 1.1.1.1 (unfiltered)
        ▼
  ┌──────────────────────────────────────────────┐
  │  Technitium DNS Router                       │
  │                                              │
  │  Internal *.kogler.si → authoritative (A)    │
  │  + mDNS reflector across VLANs               │
  │  + auto-create from DHCP leases              │
  │                                              │
  │  Per-subnet upstream (per VLAN group):        │
  │    Home (10)  → Pi-hole → Cloudflare         │
  │    Kids (40)  → Cloudflare Families (1.1.1.3)│
  │    IoT (20)   → Quad9 (9.9.9.9)              │
  │    Guest (30) → Cloudflare (1.1.1.1)         │
  │    Mgmt (99)  → Local system (infrastructure) │
  │                                              │
  │  ha.kogler.si → VIP (10.10.1.200) [static]   │
  │  dns-pi.kogler.si → VIP [static]             │
  └──────────────────────────────────────────────┘
```

### 1.6 HA Failover Edge (VIP Mechanism)

```
  Normal mode:
    ha.kogler.si → VIP 10.10.1.200 → Pi (keepalived MASTER)
    Pi traefik-ha edge binds VIP:80/VIP:443 → local HA:8123
    Cert synced from oldsrv ACME (NOT issued by Pi edge)

  After forward takeover (Pi → oldsrv):
    ha.kogler.si → VIP 10.10.1.200 → oldsrv (keepalived promoted)
    oldsrv traefik edge → VIP:8123 → home-assistant-standby
    RaspberryMatic-standby started on oldsrv (HmIP-RFUSB moved physically)
```

### 1.7 Backup Data Flows

```
  ┌─────────────────────────────┐     ┌─────────────────────────────┐
  │  ZFS Layer (Local)          │     │  Kopia Layer (Off-Site)     │
  │                             │     │                             │
  │  nas tank/data/*            │     │  oldsrv local scratch        │
  │    ├── immich (originals)   │     │    ├── DB dumps (postgres)   │
  │    ├── documents            │     │    ├── service state         │
  │    ├── services             │     │    ├── face thumbnails       │
  │    └── db-dumps             │     │    └── configs / router .rsc │
  │        sanoid hourly/daily/ │     │                             │
  │        weekly/monthly       │     │  kopia-server container      │
  │        syncoid → bulk pool  │     │    → encrypted dedup S3      │
  │        ≈ hourly incremental │     │    → iDrive e2 (e2.idy.io)   │
  │                             │     │                             │
  │  NOT backed: bulk/media     │     │  NAS-independent (works if   │
  │  (redownloadable via usenet)│     │   NAS is fully down)         │
  └─────────────────────────────┘     └─────────────────────────────┘
```


 ### REJECTED / OUTDATED — Final Architecture Proposal (superseded by bare-metal Debian + Docker)

> **REJECTED** (2025-08-16, per HD-92 / brainstorming): oldsrv runs bare-metal Debian + Docker, **not**
> Proxmox. No local Proxmox and no GPU passthrough on the single Phase-1 box — one shared dGPU serves
> desktop **and** AI, and a single host gains no HA from VMs. The Proxmox role/VMs are deferred to
> Phase 2 (HD-41/42) with a real second node. The `oldsrv (Proxmox)` / `infra VM` / `desktop VM`
> / `GPU PCI passthrough` diagram below is therefore **not the target architecture** and must not be
> used as a spec. See README + `todo.md` (HD-92).

 ```
   oldsrv (Proxmox)                Pi 4 (bare Debian)           nas (bare Debian)
   ┌──────────────────────┐        ┌──────────────────┐         ┌──────────────────┐
   │ infra VM (Docker)    │        │ HA primary       │         │ ZFS tank/bulk    │
   │ ~32 GB, 8 vCPU       │        │ RMat + HmIP stick│         │ NFS server       │
   │                      │        │ traefik-ha edge  │         │ NUT master       │
   │ Traefik, Authentik,  │        │ Technitium sec'dry│        │ nut_exporter     │
   │ Immich, OpenCloud,   │        │                  │         │ zfs_exporter     │
   │ Grafana, Matrix…     │        └──────────────────┘         └──────────────────┘
   │                      │
   │ desktop VM           │
   │ XFCE, browser, games │
   │ GPU PCI passthrough  │
   └──────────────────────┘

   VPS Contabo (bare Debian)
   ┌──────────────────┐
   │ Traefik public   │  ← Phase 1.5 target
   │ edge TLS only    │
   │ backends over WG │
   └──────────────────┘
 ```

---

## 2. Root Cause Analysis of Existing Bugs

> Method: All ~40 findings from `Qwen-bugs.md` are grouped into **six systemic architectural
> flaws**. Each flaw is a design pattern that produced multiple individual symptoms. The
> individual KOPS-IDs are referenced under their parent cause so you can trace back.

### 2.1 Flaw A — "No Forward-Auth" = No Protection At All

**Root cause:** The middleware chain `authentik-forward-auth@file` bundles CrowdSec bouncer + Authentik
into a single chain. Any route that skips this chain (because the app has its own auth)
automatically loses CrowdSec too. There is no intermediate `crowdsec-only` middleware for services
that skip Forward-Auth.

| Finding | KOPS-ID | Affected Service |
|---------|---------|------------------|
| HA route has no WAF | KOPS-004 | Home Assistant primary |
| *arr/Jellyfin/Matrix/Seerr no WAF | KOPS-018, KOPS-025, KOPS-047 | Jellyfin, HA standby, Matrix/Tuwunel, Element Web, Seerr |

**Impact:** Every service with its own login (HA, Jellyfin, Seerr, Matrix federation) is exposed to the
internet with **zero IP-level threat blocking**. Brute-force, CVE exploit scans, and known-bad-IP traffic
reach the app directly. Only the app's own rate-limiting stands in the way.

**Remedy:** Create a `crowdsec-only@file` middleware chain in `middlewares.yml.j2` and apply it to every
route that skips Forward-Auth. One template change fixes 5+ findings.

---

### 2.2 Flaw B — Mutable Image Tags Default Everywhere

**Root cause:** Service image tags default to `latest` or mutable aliases via Jinja2 fallback:
```yaml
image: traefik/traefik:{{ traefik_version }}          # group_vars/all.yml: latest
image: ghcr.io/goauthentik/server:{{ authentik_version | default('latest') }}
image: ollama/ollama:rocm                               # mutable alias, not versioned
image: jevolk/tuwunel:latest                             # obscure single-dev project
```
Renovate is deployed but cannot track what isn't pinned. When no explicit version variable exists in
`group_vars` or `host_vars`, the template falls through to `latest`.

| Finding | KOPS-ID | Services |
|---------|---------|----------|
| Traefik uses `latest` | KOPS-005 | Traefik edge (single ingress point for ALL services) |
| Multiple services default `latest` | KOPS-013 | Dozzle, Kopia, n8n, Headscale, CrowdSec, Authentic, Signal CLI, Sunshine, Pi-hole |
| Ollama `:rocm` mutable alias | KOPS-027 | Ollama GPU inference (direct /dev/dri + /dev/kfd access) |
| Tuwunel `:latest` + obscure | KOPS-030 | Matrix homeserver (internet-facing federation) |

**Impact:** Any `docker pull` or container restart pulls an unknown revision. For Traefik — the single
ingress point for all public services — this means silent deployment of breaking changes, bugs, or
(compromised) images. Ollama with GPU device access amplifies supply-chain risk.

**Remedy:** Pin every service to a specific semver tag. Set explicit version variables in `group_vars`.
Update `renovate.json` to track `-rocm` suffix and non-docker managers (ansible-galaxy, pip).

---

### 2.3 Flaw C — Docker Host Ports Bind to 0.0.0.0 Without Auth

**Root cause:** Multiple compose templates map container ports directly to the Docker host using
`"hostport:containerport"` syntax (which binds `0.0.0.0`). These ports are reachable from any device
on any VLAN that has routing to the host — including Home VLAN devices operated by family members.
The port mapping often duplicates functionality already available on the Docker overlay network.

| Finding | KOPS-ID | Port Binding | Risk |
|---------|---------|-------------|------|
| Signal REST API host bind | KOPS-002 | `8080:8080` | Impersonate Domen via Signal; social engineering against family contacts |
| Prometheus host bind | KOPS-017 | `9090:9090` | Infrastructure intelligence leakage (internal IPs, topology, alert rules) |
| Technitium DNS host bind | KOPS-015, KOPS-032, KOPS-064 | `53:53` + `NET_ADMIN` | DNS takeover if Technitium web UI compromised; open resolver amplification |
| Sunshine game-streaming | KOPS-007 | `47989-48010:…` | RCE via streaming protocol CVEs; GPU + input device access |
| qBittorrent via gluetun | KOPS-019 | shares gluetun namespace | VPN tunnel DNS exfiltration; connection leak during server rotation |

**Impact:** LAN-based attacks don't need WAN access. Any device on VLAN 10 (Home) can reach these
services directly, bypassing Traefik entirely.

**Remedy:** Remove unnecessary host port bindings when the Docker network suffices (Signal → n8n,
Prometheus → Alloy). Bind remaining ports to specific VLAN IPs (`10.10.1.30:9090:9090`) or loopback
(`127.0.0.1:9090:9090`).

---

### 2.4 Flaw D — Elevated Container Privileges Without Proportional Need Assessment

**Root cause:** Containers are granted broad host-level capabilities (`privileged`, `NET_ADMIN`, host
network mode, docker.sock write access) without a documented assessment of minimum required privileges.
Some capabilities are inherited from upstream examples rather than derived from actual functional needs.

| Finding | KOPS-ID | Privilege | Actual Need |
|---------|---------|-----------|-------------|
| HA primary `privileged: true` + `network_mode: host` | KOPS-014 | Full root on Pi, all devices, cgroup escape | Device access for HmIP-RFUSB + mDNS/SSDP discovery |
| Technitium `NET_ADMIN` + root + port 53 | KOPS-015, KOPS-032 | Network interface manipulation, DHCP control | RouterOS handles DHCP; Technitium only needs DNS resolution |
| Doco-CD host network + docker.sock rw + Forgejo token | KOPS-024 | Full container lifecycle management | GitOps deployment (needs docker.sock rw but not host network) |
| RaspberryMatic USB path wildcard | KOPS-040 | Won't start — glob doesn't resolve in Docker | Exact `/dev/serial/by-id/` path needed per host |

**Impact:** A vulnerability in any of these containers gives the attacker disproportionate access.
HA primary with `privileged: true` on the Pi = full root on the smart-home controller + keepalived
control + VRRP manipulation + potential split-brain triggering.

**Remedy:** Replace `privileged: true` on HA with targeted `devices:` + `cap_add:`. Remove
`NET_ADMIN` from Technitium (RouterOS owns DHCP). Pin exact USB device paths in `host_vars`.
Move Doco-CD to a dedicated network instead of host mode where possible.

---

### 2.5 Flaw E — Incomplete Backup Coverage

**Root cause:** The automated daily database backup (`db-backup`) covers only Authentik and Forgejo
PostgreSQL databases. Immich and OpenCloud databases are **commented out**, leaving critical metadata
unprotected. Separate from DB backups, the immich photo library originals are ZFS-backed but face
thumbnails pushed over NFS lack Kopia coverage in some paths.

| Finding | KOPS-ID | Gap |
|---------|---------|-----|
| db-backup missing immich + opencloud DBs | KOPS-026 | Immich photo metadata (albums, faces, labels, smart search embeddings) — irreplaceable if lost |
| Loki auth disabled | KOPS-023, KOPS-051 | Any container on `db-internal` can inject or read logs (credential leaks in error messages) |

**Impact:** If Immich's Postgres dies, all photos survive on ZFS but lose albums, face recognition
results, labels, smart-search embeddings, and timeline organization. Re-importing originals into a fresh
DB does NOT reconstruct this metadata automatically.

**Remedy:** Uncomment DB03+ blocks in `db-backup/docker-compose.yml.j2` with correct hostname
`immich-postgres`. For OpenCloud: tar of `/var/lib/opencloud` data dir (embedded DB, not external).
Enable Loki auth as Phase 2 hygiene.

---

### 2.6 Flaw F — Bootstrap/Preseed Defaults Deploy Insecure State If Run As-Is

**Root cause:** Bootstrap scripts and preseed files contain placeholder values that work functionally
but deploy insecure configurations. If someone runs these without reading comments carefully (or if
Ansible fails to overwrite them in the bootstrap window), the system enters service with known weaknesses.

| Finding | KOPS-ID | Issue |
|---------|---------|-------|
| Identical root password hash on nas + oldsrv preseed | KOPS-044 | Same emergency console password on two hosts |
| Switch role empty port map → all ports on VLAN 99 | KOPS-043 | Complete loss of VLAN segmentation at L2 |
| Router API enabled without TLS or interface binding | KOPS-003, KOPS-042 | RouterOS admin API reachable from WAN during bootstrap window |
| AP ethernet ports on Management VLAN | KOPS-046 | Any wired device on AP port gets full Management VLAN access |
| Pi-hole WEBPASSWORD defaults to empty | KOPS-010 | Admin UI unprotected if 1Password lookup fails |
| Loki schema date set to 2026-01-01 | KOPS-065 | Log collection silently fails until schema activates |
| Pi first-boot hostname path assumption | KOPS-045 | Silently skipped if partition mount differs |
| post_install.sh sshd_config append without dedup | KOPS-012 | Config drift on re-run |
| bootstrap.sh OP token saved to ~/.bashrc plaintext | KOPS-011 | Token persistence risk |
| Preseed root login enabled | KOPS-044 | Emergency attack surface beyond key-only ansible-admin |

**Impact:** During the gap between initial boot and Ansible convergence, multiple insecure states are
live. Some (switch VLAN, router API) remain insecure indefinitely if the Ansible role is never run or
fails partway. The empty switch port map means the **first** successful switch deploy wipes all VLAN
segmentation.

**Remedy:** Render unique root hashes per host at preseed time (Jinja2 + random). Create
`group_vars/switch.yml` with actual port mapping before deploying. Fail loudly on missing secrets
(remove `default('')` from Pi-hole). Set Loki schema `from:` to current date. Restrict router API to
Management VLAN interface in the bootstrap template itself, not just the Ansible role.

---

### 2.7 Cross-Cutting Summary Table

| Flaw | Findings | Severity Spread | Common Fix Pattern |
|------|----------|----------------|-------------------|
| A: No Forward-Auth = No Protection | 5 | HIGH × 2, MEDIUM × 3 | Add `crowdsec-only@file` middleware; apply to all non-Forward-Auth routes |
| B: Mutable Image Tags | 4 | MEDIUM × 1, LOW × 3 | Pin versions everywhere; update renovate.json managers |
| C: Unprotected Host Ports | 5 | HIGH × 1, MEDIUM × 4 | Remove host binds or restrict to VLAN-specific IPs |
| D: Elevated Container Privileges | 4 | HIGH × 2, MEDIUM × 2 | Minimum privilege audit per container; remove unused caps |
| E: Incomplete Backup Coverage | 2 | MEDIUM × 1, LOW × 1 | Uncomment DB backups; enable Loki auth |
| F: Insecure Bootstrap Defaults | 10 | MEDIUM × 6, LOW × 4 | Fail-loudly on missing config; render unique values per host |

---

*Sections 1–2 complete. Ready for Section 3 — Security & Secrets Management Audit.*


## 3. Security & Secrets Management Audit

### 3.1 1Password Integration Assessment

**Overall verdict: Well-designed, minor operational risks.** The secrets management architecture is
one of the strongest parts of this design.

**Strengths:**
- **Single vault `Homelab`** — no scattered secrets across multiple stores or `.env` files
- **Consistent naming convention** `<service>_<type>` with a clear type map (login/password/api/db/ssh)
- **`field=` always explicit** — avoids the common pitfall of defaulting to wrong field
- **30 canonical items** with a rename map documenting legacy → canonical transitions
- **SSH key separation** — three independent ED25519 keys (personal / Ansible / AI) with different users
- **AI access locked down** — `ai-debug` user has `from="10.10.0.0/16"`, no forwarding, no agent
- **Fail-closed Ansible guard** — playbooks refuse to run as `ai-debug` or unknown users
- **Paper backup in family safe** — 1Password master + recovery codes + Git mirror link
- **Secrets resolved at render time** via 1Password lookup — never cached on disk

**Risks and Gaps:**

| Risk | Severity | Detail |
|------|----------|--------|
| OP token in plaintext `~/.bashrc` | LOW | KOPS-011: `bootstrap.sh` writes service account token to bashrc. Acceptable for single-user WSL laptop |
| Single 1Password SA token for Doco-CD + Actions | MEDIUM | Same `op_api` token drives both GitOps CD and Forgejo Actions. If leaked, both pipelines compromised. Consider separate SA tokens per pipeline |
| Missing fail-loud pattern | MEDIUM | KOPS-010: Pi-hole falls back to empty password if lookup fails. Templates should fail loudly if secret absent rather than deploy unprotected |
| n8n_password dual-purpose | MEDIUM | KOPS-031: same secret is N8N_ENCRYPTION_KEY AND webhook auth token. Split into two items |
| Kopia `--without-password` | HIGH | KOPS-001: Any container on `services-internal` can access backup repo with zero auth. Add server-level auth layer |

### 3.2 GitHub Leakage Risk

**Assessment: Minimal risk — no raw credentials detected.**

| Check | Result |
|-------|--------|
| Hardcoded passwords in group_vars/host_vars | None found — all use 1Password lookup at render time |
| `.env` files committed | None found |
| Secret values in compose templates | All references are Jinja2 lookups at render time |
| API tokens in bootstrap scripts | Only variable placeholder `$OP_TOKEN` passed as argument; actual value not stored |
| SSH private keys in repo | None — public keys only, referenced by name from 1Password |
| Root password hash in preseed | Placeholder hash present (KOPS-044) marked as CHANGE ME; identical on two hosts if deployed as-is |

**Recommendation:** Add a pre-commit hook or CI check that scans for common secret patterns before allowing commits.

### 3.3 Edge Security — Traefik + CrowdSec + Authentik Chain

**What works well:**
- CrowdSec bouncer parses Traefik logs for community blocklist + behavioral detection
- Wildcard cert via DNS-01 covers all subdomains cleanly
- Split-horizon DNS: internal services have no public record; WAN firewall blocks them
- Cloudflare DNS-only (no proxy): real client IPs reach CrowdSec for accurate blocking
- Security headers comprehensive (HSTS, X-Frame-Options, X-XSS-Protection, X-Robots-Tag)

**Critical gap (Flaw A):** The middleware chain bundles CrowdSec + Authentik into one chain.
When a route skips Forward-Auth, it also loses CrowdSec entirely. Six services have zero edge protection:

| Service | Subdomain | Own Auth? | Has Middleware? |
|---------|-----------|-----------|-----------------|
| Home Assistant | `ha.kogler.si` | Yes (HA native) | **None** (KOPS-004) |
| Jellyfin | `media.kogler.si` | Yes (Jellyfin login) | **None** (KOPS-018) |
| Seerr | `seerr.kogler.si` | Yes (Seerr login) | **None** (KOPS-047) |
| Matrix/Tuwunel | `matrix.kogler.si` | Yes (Matrix-native OIDC) | **None** (KOPS-018) |
| Element Web | `chat.kogler.si` | Via homeserver SSO | **None** (KOPS-025) |
| HA standby | `ha.kogler.si` (VIP) | Yes (HA native) | **None** (KOPS-018) |

**Fix:** Create `crowdsec-only@file` middleware chain with just the CrowdSec bouncer. Apply to all six routes above. One template change eliminates entire Flaw A class.

**Additional edge concerns:**

| Issue | Severity | Detail |
|-------|----------|--------|
| HA `trusted_proxies` too broad (/16) | MEDIUM | KOPS-039: Trusts entire Docker network CIDR. Shrink to Traefik container IPs |
| OpenCloud `OC_INSECURE: true` | MEDIUM | KOPS-006: Internal container traffic unencrypted |
| Grafana dual auth paths | MEDIUM | KOPS-008: Admin login available at `/login` in parallel with Authentik proxy |

### 3.4 Network Security — VLAN Segmentation Design

**Design strengths:**
- Default-deny forwarding between VLANs with explicit exceptions
- Per-VLAN upstream DNS filtering (Kids → Cloudflare Families, IoT → Quad9)
- Management VLAN 99 fully isolated — no Home/IoT/Guest access
- Address-lists (`trusted-admin`, `trusted-ha`) control which IPs cross boundaries

**Gaps (not yet live — HD-03):**

| Issue | Severity | Detail |
|-------|----------|--------|
| Switch port map empty = all VLAN 99 | MEDIUM | KOPS-043: First deploy of switch role puts all 24 ports on Management VLAN. Must create `group_vars/switch.yml` first |
| Router INPUT chain missing | MEDIUM | KOPS-009: Extensive FORWARD rules but no INPUT chain restricting management services to VLAN 99 |
| AP ethernet ports on Mgmt VLAN | LOW | KOPS-046: Wired devices on AP ports get full Management access |
| Router API without interface binding | HIGH | KOPS-003: API service listens on all interfaces including WAN during bootstrap |

### 3.5 Container-to-Container Network Security

| Network | Members | Auth Between Members |
|---------|---------|---------------------|
| `traefik-public` (172.20.0.0/16) | Traefik, exposed services | No auth — flat bridge |
| `services-internal` (172.21.0.0/16) | App ↔ app | Mostly none (Ollama, Technitium, Signal CLI, n8n APIs) |
| `db-internal` (172.22.0.0/16) | Databases, Prometheus, Loki | Loki auth disabled; DBs rely on individual password auth |

**Key findings:**

| Issue | Severity | Detail |
|-------|----------|--------|
| Ollama no auth, all containers reachable | MEDIUM | KOPS-016: Any container calls Ollama API without key. GPU resource consumption + prompt injection risk |
| Signal REST API no auth on Docker network | MEDIUM | Already on host port (Flaw C). On Docker network also no auth |
| Kopia server --without-password | HIGH | KOPS-001: Combined with flat network, any container gets unrestricted backup repo access |
| Loki auth disabled | LOW | KOPS-023/051: Acceptable for Phase 1 with trusted containers |
| Headscale auto-approves clients | MEDIUM | KOPS-022: Comment says "requires admin approval" but config auto-approves all OIDC registrations |

---

*Sections 1–3 complete. Ready for Section 4 — Infrastructure & HA Audit.*

## 4. Infrastructure & HA Audit

### 4.1 Home Assistant Failover — Architecture Review

**Design: Manual active/standby with VIP (keepalived VRRP).** This is well-considered for the constraints.

**What works well:**
- **VIP mechanism eliminates per-device reconfiguration** — `ha.kogler.si → 10.10.1.200` always points to active node. Devices, Companion apps, Traefik, and DNS all reference the VIP, never a node-specific IP.
- **traefik-ha edge on Pi rides the VIP** — when oldsrv is down, Pi's own edge keeps `ha.kogler.si` reachable. When Pi is down, oldsrv's edge takes over. No DNS flip needed.
- **Cert sync from oldsrv → Pi** — single ACME issuer on oldsrv; Pi syncs PEM pair. Works fully offline after last sync (critical: WAN loss not a failover trigger).
- **Manual trigger accepted** — no false negatives from automation. Two actions: move HmIP-RFUSB stick + press Homepage button.
- **Identical config from one source** — same `configuration.yaml` template renders both nodes.
- **DNS redundancy** — Technitium primary on oldsrv, secondary on Pi. HA resolution works in both failure scenarios.

**Critical risks:**

| Risk | Severity | Detail |
|------|----------|--------|
| HA primary `privileged: true` + `network_mode: host` | HIGH | KOPS-014: Full root on Pi = cgroup escape + all devices + host network sniffing. If compromised, attacker controls keepalived + VRRP + potential split-brain |
| RaspberryMatic port 80 conflict | MEDIUM | KOPS-038: Both Traefik and CCU try to bind :80 during failover. Map CCU to alternate port (`8085:80`) |
| RaspberryMatic USB path wildcard | MEDIUM | KOPS-040: Glob won't resolve in Docker. Need exact `/dev/serial/by-id/` path per host in `host_vars` |
| HA boot sequencing on Pi | MEDIUM | KOPS-063: Both HA and RaspberryMatic start simultaneously at reboot. RMat must respond on XML-RPC 2001 before HA starts to avoid missed automations |
| State sync gap = 15 minutes | LOW | Config + SQLite rsync every ~15 min means last 15 min of events/config changes lost on failover. Accepted trade-off per design doc |
| Homematic requires physical stick move | MEDIUM | Non-automatable step means Homematic devices stay down until someone is physically present. KNX/Shelly fail over cleanly but Homematic does not |

### 4.2 Network Dependencies and Failure Scenarios

| Scenario | What Survives | What Breaks | Recovery |
|----------|--------------|-------------|----------|
| **Pi 4 dies** | Technitium primary (oldsrv), ALL Docker services (oldsrv), NAS/ZFS | HA primary, RMat primary, Technitium secondary, traefik-ha edge | Manual forward takeover → oldsrv standby HA starts |
| **oldsrv dies** | Technitium secondary (Pi), HA primary, RMat primary, traefik-ha edge, NAS/ZFS | ALL Docker services: Traefik, Authentik, Immich, OpenCloud, Matrix, Grafana, etc. | Services unavailable until oldsrv recovers or rebuilt from ZFS backup |
| **NAS dies** | All compute services (Pi + oldsrv) | NFS mounts, ZFS data, NUT master → UPS doesn't shut down servers gracefully | Pools self-describing: reinstall preseed → zpool import |
| **Router dies** | Local LAN communication within each VLAN | All inter-VLAN routing, WAN internet, DHCP, CAPsMAN AP management | Restore `.rsc` from Git to replacement RB4011 |
| **Switch dies** | Devices wired directly to router (if any) | All switched devices including servers and APs | Restore switch config from bootstrap template |
| **UPS failure** | Nothing — all hardware loses power protection | Everything | Battery replacement; no graceful shutdown coordination |

**Single point of failure: oldsrv hosts everything.** In Phase 1, oldsrv carries ~40 containers, Technitium DNS primary, Traefik edge, Grafana/Prometheus/Loki observability, and HA cold standby. If oldsrv goes down, only HA + DNS survive (on Pi). **Acceptable for Phase 1 by design.** Phase 2 moves public edge to VPS per `services-vps.md`.

### 4.3 Storage Architecture — NAS HP MicroServer Gen8

**ZFS pool layout:**
- `tank` (mirror): User data — immich originals, documents, service configs, DB dumps
- `bulk` (RAIDZ2, SilverStone external): Media library + local copy of tank/data via syncoid

**What works well:**
- sanoid/syncoid snapshot schedule: hourly to monthly retention
- Documents get extra 5-min tier (96 snapshots × 5min = 8h fine-grained versioning)
- Media intentionally unbacked (redownloadable) — reduces snapshot churn
- Kopia off-site is NAS-independent (runs from oldsrv scratch, not NAS mounts)
- Hybrid storage on Immich: originals on NFS (write-once), thumbs/local data on NVMe

**Risks:**

| Risk | Severity | Detail |
|------|----------|--------|
| Media on single RAIDZ2 pool | LOW | If all drives in bulk pool fail simultaneously, media lost. Acceptable — redownloadable |
| NFS dependency for *arr stack | MEDIUM | If NAS unreachable, Jellyfin/Sonarr/Radarr can't access media library. Container stays up but library empty |
| db-backup missing immich/opencloud DBs | MEDIUM | KOPS-026: Photo metadata and document versions unprotected. Uncomment commented-out blocks |

### 4.4 UPS / Power Management

**NUT master-client topology:**
- Master: nas (USB HID UPS driver, upsd on :3493, nut_exporter host binary on :9199)
- Clients: oldsrv (60s shutdown delay), Pi (0s immediate)
- Notification: SMTP email + Signal via upssched-cmd (independent of Grafana/n8n)

**What works well:**
- Separate monitoring exporter user from client auth
- Notification independent of Docker services (host binary on nas)
- Battery runtime/charge thresholds configured

**Risks:**

| Risk | Severity | Detail |
|------|----------|--------|
| UPS not shut down gracefully if NAS fails first | LOW | NUT master runs on NAS. If NAS USB link breaks, clients don't know battery state |
| SNMP community string undecided | MEDIUM | HD-53: Alloy assumes v2c `public`. Needs dedicated read-only community + mgmt VLAN ACL |
| UPS web UI firewall rule not deployed | LOW | HD-09: IaC done but not deployed. Opens 80/443 Home→Mgmt for 10.10.99.9 only |

### 4.5 Ansible Infrastructure Health

| Aspect | Status | Notes |
|--------|--------|-------|
| Role count | 15 roles shipped, 1 TODO (proxmox) | Well-organized, clear separation of concerns |
| Inventory | Clean groups matching physical topology | router/switch/home_servers/storage/raspberry_pi/vps |
| SSOT enforcement | `group_vars/all.yml` has network_static_hosts, vlan_subnets, ha_vip | Templates derive IPs from this list — good |
| Idempotency | assert guards, `state: present`, docker compose pull before up | Good pattern throughout |
| Tags per service | Each docker_services loop item tagged `{item.name}` | Enables targeted `--tags` deploys |
| Fail-closed admin guard | Every role asserts `ansible_user in ansible_admin_users` | AI debug user cannot run playbooks |

**Risks:**

| Risk | Severity | Detail |
|------|----------|--------|
| Ansible crashes on Windows | BLOCKER for live deploys | Must run from WSL/Debian or Forgejo Actions runner. Documented in deployment-ansible.md |
| Host network config-manager undecided | MEDIUM | HD-56: systemd-networkd vs netplan blocks network role's static-IP/VLAN trunk provisioning |
| docker_services enables ALL services unconditionally | LOW | KOPS-021: Standby services marked `enabled: false` still get systemd unit enabled. Should skip disabled services entirely |

---

## 5. Updated Strategic Roadmap

> Consolidates all audit findings with existing `todo.md` milestones into a unified priority plan.
> Existing HD-XX IDs retained where applicable; new items marked `NEW`.

### HIGH Priority — Blockers to Safe Deployment

| ID | D | Item | Source | Why Now |
|----|---|------|--------|---------|
| **NEW-S01** | 2 | Create `crowdsec-only@file` middleware chain in `middlewares.yml.j2`; apply to ha, jellyfin, seerr, matrix, element-web routes | KOPS-004/018/025/047 | Eliminates Flaw A entirely. One template change fixes 6 findings. Zero operational risk |
| **NEW-S02** | 1 | Pin `traefik_version` to specific semver tag (e.g., `v3.3`) in `group_vars/all.yml`. Set explicit versions for all services defaulting to `latest` | KOPS-005/013 | Traefik is single ingress point for ALL services. `latest` = unknown revision on every restart |
| **NEW-S03** | 2 | Replace HA primary `privileged: true` + `network_mode: host` with targeted `devices:` + `cap_add:`. Remove from compose template | KOPS-014 | Full root on smart-home controller = cgroup escape + keepalived control + VRRP manipulation |
| HD-03 | 5 | Network redo: VLAN segmentation deploy on RB4011 + CRS328 | todo.md | Cannot safely expose services to internet without inter-VLAN firewall. Current flat network defeats all isolation |
| HD-04 | 5 | Pi redo: HAOS → Debian + HA Container | todo.md | Required for VRRP/keepalived on Pi. Blocks failover mechanism. Dependent on HD-03 (network redo) |
| **NEW-S04** | 1 | Create `group_vars/switch.yml` with actual physical port-to-VLAN mapping before first switch role deploy | KOPS-043 | Without this, first switch deploy puts all 24 ports on Management VLAN — complete loss of segmentation |
| **NEW-S05** | 1 | Remove host port bindings for Signal CLI (`8080:8080`), Prometheus (`9090:9090`). Bind Technitium to VLAN IP only. Map RaspberryMatic CCU to alternate port | KOPS-002/007/015/017/038 | LAN-level attacks bypass Traefik entirely. Zero auth on raw container ports |
| **NEW-S06** | 1 | Uncomment immich-postgres and opencloud DB blocks in `db-backup/docker-compose.yml.j2`. Fix hostname to `immich-postgres` | KOPS-026 | Immich photo metadata (albums, faces, labels, embeddings) unprotected if Postgres dies |
| **NEW-S07** | 1 | Set Loki schema `from:` date to current/past date (not 2026-01-01). Remove `default('')` from Pi-hole WEBPASSWORD lookup | KOPS-065/010 | Loki silently drops all logs until schema activates. Pi-hole deploys unprotected if 1Password lookup fails |

### MEDIUM Priority — Required Before Going Live

| ID | D | Item | Source | Dependency |
|----|---|------|--------|------------|
| HD-02 | 3 | Activate Doco-CD (GitOps CD pipeline) | todo.md | After docker_services stable |
| HD-06 | 3 | NUT master on nas (live deploy + battery test) | todo.md | NAS must be provisioned first |
| HD-16 | 3 | Authentik compose template + Traefik Forward-Auth middleware | todo.md | Hard prerequisite for all Forward-Auth services |
| **NEW-M01** | 2 | Split `n8n_password` into `n8n_password` (encryption key) + `n8n-webhook_api` (webhook auth token). Update templates | KOPS-031 | Key rotation independence |
| **NEW-M02** | 2 | Add INPUT chain firewall rules on router restricting management services (API, SSH, WinBox, www) to Management VLAN only | KOPS-003/009 | Router role deploy |
| **NEW-M03** | 2 | Pin exact USB device path per host for RaspberryMatic in `host_vars`. Add udev rule or symlink approach | KOPS-040 | Physical HmIP-RFUSB stick needed |
| **NEW-M04** | 2 | Render unique root password hash per host at preseed time (Jinja2 template). Or disable root login entirely since ansible-admin has NOPASSWD sudo | KOPS-044 | Preseed files only |
| **NEW-M05** | 2 | Shrink HA `trusted_proxies` from `/16` CIDR to Traefik's specific container IPs | KOPS-033 | Requires knowing actual Docker bridge IPs |
| **NEW-M06** | 2 | Enable `GF_AUTH_DISABLE_LOGIN_FORM: "true"` on Grafana to force single auth path through Authentik proxy | KOPS-008 | Grafana compose template |
| **NEW-M07** | 2 | Restrict router API to Management VLAN interface in bootstrap template itself (not just Ansible role). Disable API if TLS cert unavailable | KOPS-003/042 | Bootstrap scripts |
| **NEW-M08** | 2 | Update Headscale config to either enable real ACL policy OR fix misleading comment (currently auto-approves despite comment saying "requires admin approval") | KOPS-022 | Headscale config |
| HD-13 | 3 | Homematic full-local (HmIP-RFUSB + RaspberryMatic): replace HAP cloud mode with local XML-RPC | todo.md | HD-04 (Pi redo) |
| HD-17 | 3 | Single failover button + `ha-failover.sh` orchestrator on Homepage | todo.md | HD-04 (Pi redo), HD-13 |
| HD-53 | 2 | Decide SNMP community string (dedicated RO + mgmt ACL vs default public) | todo.md | Router role deploy |
| HD-56 | 3 | Decision: systemd-networkd vs netplan for host network config | todo.md | Blocks network role static-IP/VLAN provisioning |
| HD-51 | 2 | Decide family desktop user accounts (UID/group strategy, auto-login target) | todo.md | Desktop role deploy |

### LOW Priority — Good Hygiene, Not Blocking

| ID | D | Item | Source |
|----|---|------|--------|
| NEW-L01 | 1 | Move CrowdsSec collections beyond just traefik+linux: add home-assistant, matrix, grafana parsers | KOPS-041 |
| NEW-L02 | 1 | Use `op signin --account` instead of persisting token in `~/.bashrc` for production (bootstrap OK as-is) | KOPS-011 |
| NEW-L03 | 1 | Pin CrowdSec Traefik bouncer plugin version explicitly in group_vars instead of hardcoded default | KOPS-029 |
| NEW-L04 | 1 | Dedup sshd_config append in `post_install.sh` (guard against double-run) | KOPS-012 |
| NEW-L05 | 1 | Disable unused AP ethernet ports or move to Home VLAN instead of Management | KOPS-046 |
| NEW-L06 | 1 | Update Renovate config to track ansible-galaxy managers + pip_requirements (not just docker) | KOPS-062 |
| NEW-L07 | 1 | Add `fail: msg=` guards in templates when critical secrets are missing (fail-loudly pattern) | Cross-cutting |
| HD-19 | 2 | Pi SD-card wear: trim HA recorder + log strategy | todo.md | Already implemented in IaC |
| HD-39 | 1 | Decide watchtower for Pi HA container update automation | todo.md | After HA container migration |
| HD-52 | 1 | Decide OpenCloud sync client packaging (AppImage vs Debian client vs skip) | todo.md | Desktop role |

### Phase 2 / Deferred

| ID | Item | Notes |
|----|------|-------|
| HD-40 | VPS (Contabo) + public stack incl. Cloudflare layer | Moves public edge off oldsrv. Reduces SPOF |
| HD-41 | Proxmox role + VM lab | Implementation step 10 |
| HD-42 | Phase-2 hardware build (Ryzen 9) | Only if Phase 1 insufficient |
| HD-45 | Re-evaluate Homelable (topology/rack visualizer) | Keep deferred until services live |
| HD-48 | Requested-only bridges (WhatsApp/Messenger/Signal) | Deferred, best-effort only if family asks |

---

## 6. Technical Open Questions

> Filtered from `todo.md` open questions, `Qwen-bugs.md` discussion items, and architectural gaps discovered
> during this audit. Only unresolved design blockers remain — items marked `done` or with clear decisions in
> `todo.md` are excluded.

### Critical — Blocks Deployment

| # | Question | Impact | Owners |
|---|----------|--------|--------|
| **Q1** | **systemd-networkd vs netplan** for host network config (HD-56)? The `network` role's static-IP + VLAN trunk provisioning cannot ship until this is decided. oldsrv needs VLANs 10/20/50 tagged + 99 native; nas needs 10 + 99; Pi needs static on VLAN 10. | Blocks HD-03 deploy (VLAN segmentation — HIGH priority) and all host-level network configuration. Without proper trunking, VLAN firewall rules exist but traffic can't flow between segments. | Human decision → AI implements |
| **Q2** | **Switch port-to-VLAN mapping** — what is the actual physical wiring? The Rack.canvas has estimates but conflicts noted (HAP/RPi on switch vs router, sfp+ sweep, printer/AP-garage ports). Without `group_vars/switch.yml`, first switch deploy destroys VLAN segmentation (KOPS-043). | Blocks HD-03 deploy. All 24 ports default to Management VLAN if map is empty. | Human provides physical layout |
| **Q3** | **Kopia server auth model** — is the intent that clients authenticate using stored repo password while server stays open (`--without-password`)? Or should server require its own independent auth layer? (KOPS-001) | If left as-is, any container on `services-internal` accesses backup repo unrestricted. Add `--password` flag + 1Password secret to close Flaw D + E overlap. | Human design decision |

### High — Blocks Specific Services

| # | Question | Impact | Owners |
|---|----------|--------|--------|
| **Q4** | **HA Container privilege model** — is `privileged: true` truly required given device set (KNX via GIRA router IP, Shelly native, Homematic via XML-RPC)? Could targeted `devices:` + `cap_add:` suffice? (KOPS-014) | Full root on Pi = cgroup escape + keepalived control. Must decide before Pi migration (HD-04). | Research HA docs for minimal caps needed for mDNS/SSDP discovery |
| **Q5** | **Actual `/dev/serial/by-id/` path** for HmIP-RFUSB stick? Current template uses glob that won't resolve in Docker. Need exact path per host for RaspberryMatic compose. (KOPS-040) | RaspberryMatic won't start without exact device path. Blocks Homematic functionality on both Pi and oldsrv standby. | Physical inspection of stick |
| **Q6** | **SMTP relay provider** for Grafana alert fail-safe email? `grafana_smtp_host` undecided — alert delivery cannot work until chosen. (HD-54) Related: Infomaniak kSuite signup (HD-30). | Alert fail-safe (email tier) silent until relay configured. Signal path works independently via n8n/signal-cli. | Human purchase decision (Infomaniak ~€3-5/mo) |
| **Q7** | **Family desktop user accounts** — UID/group strategy for 4 family members + guest + neutral shared media account? Not using personal account as uid/gid 1000/1000. (HD-51) | Blocks desktop role auto-login deployment and NFS ownership alignment for *arr stack (currently PUID/PGID 1000:1000). | Human design decision |
| **Q8** | **Router API access model** — plan to get Let's Encrypt cert for RB4011, or design around SSH-key-only access and disable API entirely? (KOPS-003) | API currently enabled on all interfaces including WAN during bootstrap. Even if TLS added later, interface restriction is urgent. | Human design decision |

### Medium — Operational Decisions

| # | Question | Impact | Owners |
|---|----------|--------|--------|
| **Q9** | **Headscale client approval**: Fix misleading comment OR add real ACL policy? Currently auto-approves all OIDC-authenticated registrations despite comment saying "requires admin approval" (KOPS-022). | Anyone with @kogler.si email joins Headscale mesh after auto-approve. Decide: trust OIDC = trust mesh access, or add manual gate. | Human policy decision |
| **Q10** | **Matrix federation enabled**: Is open federation intentional, or should it be disabled for maximum isolation? Any Matrix user from any server can DM your family. (KOPS-033) | Social engineering / unsolicited messages risk. Expected behavior for federated homeserver. | Human policy decision |
| **Q11** | **SNMP community string**: Default v2c `public` acceptable for homelab Management VLAN, or create dedicated read-only community? (HD-53 / KOPS-034) | Cleartext SNMP on Mgmt VLAN. Low risk physically but poor practice. | AI recommends high-entropy RO string |
| **Q12** | **Sunshine game-streaming exposure**: Reachable only via Headscale/Tailscale overlay instead of Home VLAN directly? (KOPS-007) | Direct GPU + input device access on host port. Consider VPN-only access for remote gaming. | Human preference |
| **Q13** | **CrowdSec collection scope**: Beyond traefik+linux, which service-specific parsers to add? Prioritize: home-assistant, matrix, grafana, jellyfin. (KOPS-041) | Incremental improvement to WAF coverage. Each parser catches service-specific attack patterns. | AI recommends top 3 by exposure |
| **Q14** | **Bulk media off-site backup**: Does iDrive e2 have space/cost headroom for full media library? Or keep bulk local-only (ZFS RAIDZ2 only)? (HD-29) | Media not backed up at all currently. Redownloadable but time-consuming. | Human cost/benefit decision |
| **Q15** | **OpenCloud sync client packaging**: AppImage → /opt + .desktop entry, Debian nextcloud-desktop (protocol-equivalent), or skip? (HD-52) | Blocks office role's desktop sync capability. | AI research + human choice |

### Resolved — Explicitly Closed (from Qwen-bugs.md Discussion)

The following questions from `Qwen-bugs.md` are **resolved** per decisions in `todo.md` or design docs:

| Original Question | Resolution | Source |
|-------------------|------------|--------|
| Kids VLAN bedtime restriction pending implementation | Accepted design; firewalls rule exists in IaC (Kids → WAN drop 22:00–07:00). Not deployed yet (HD-03). | network-vlans.md |
| VIP address / notation / firewall IP-set | Decided: `10.10.1.200/32`, DHCP pool ≤ .199, router lists `trusted-ha` + `trusted-admin`. | smart-home-failover.md, todo.md HD-05 done |
| Takeover trigger & failback mechanism | Manual accepted. No false negatives from automation. | smart-home-failover.md |
| Stale state on takeover (15-min snapshot) | Acceptable trade-off explicitly documented. | smart-home-failover.md |
| WAN access in fallback mode | Not required. LAN/VPN only. | smart-home-failover.md |
| HA OS vs Debian/Docker on Pi | Debian + Docker chosen (enables VRRP/keepalived). | home-assistant-current.md |
| Dozzle scope and purpose | Viewer only, Loki stays log store. Forward-Auth protected. Internal only. | observability.md |
| Cockpit behind Authentik? | No — own login, management surface must stay reachable if Authentik down. | services-traefik.md |
| Portainer/Dockge included? | Excluded — conflicts with GitOps model (Doco-CD + Ansible). | services.md |

### Questions Deferred to Phase 2

| # | Question | Reason |
|---|----------|--------|
| Q-P2-1 | Proxmox deployment model for Phase 2 hosts? | Phase 1 uses bare-metal Debian. Proxmox role is TODO stub. |
| Q-P2-2 | Cloudflare layer beyond DNS-only (DDoS/WAF/geo)? | Traefik + CrowdSec handles edge security for now. |
| Q-P2-3 | VPS public stack composition (which services move to Contabo)? | Depends on Phase 1 validation and performance observations. |
| Q-P2-4 | Watchtower vs Renovate for container update automation? | Renewate handles image tracking; watchtower optional for hot-redeploy. HD-39. |

---

*Audit complete. All 6 sections written.*
