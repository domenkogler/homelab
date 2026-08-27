---
title: Deferred VPS Infrastructure
role: reference
domain: services
status: active
tags: [services, vps, netcup]
---
# Deferred VPS Infrastructure

> **Role:** Detail — reference architecture for the netcup VPS.
> **Links to:** `services.md`, `network-vpn.md`
> **Linked from:** `services.md`
>
> **Status:** ✅ **Decision (2026-08-16, HD-93):** the VPS is to be **purchased before go-live** and the
> public edge moves onto it from **day one** (public Traefik + CrowdSec + Authentik + public apps terminate
> TLS on the VPS over WG S2S → oldsrv backends). This supersedes the older "deferred to Phase 2+" wording
> below, which is retained as the implementation spec for what actually ships there.
>
> **Live since 2026-08-22** (Phase 1): all enabled services deployed behind real LE TLS
> (wildcard `*.kogler.si`). Only the WG S2S tunnel stays ⏳ deploy-gated (HD-03).

### netcup edge firewall (SCP-verified 2026-08-22, Wave-3)

- **Outgoing SMTP blocked** on ports **25 / 465 / 587** (netcup default anti-spam rule; DROP).
  → **VPS-originated mail must use an alternate submission port** — the SMTP2Go relay
  (`smtp_login`) also listens on **2525**, which is NOT blocked. Configure Grafana/NUT/n8n
  alert mail accordingly (port 587 will silently drop).
- ICMP (v4+v6) explicitly allowed both directions; **everything else implicitly ACCEPTED**
  in/out — the SCP firewall is permissive by default; hardening lives at the host (nftables/
  fail2ban/docker), not here.
- Egress addresses as seen by remote services: `159.195.111.66` (v4) and
  `2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5` (stable SLAAC v6) — both belong in any provider-side
  IP allowlist (e.g. Cloudflare token filters).
- **Console/kmsg noise (benign, accepted 2026-08-23):** Debian 13's `systemd-ssh-generator`
  logs `Failed to query local AF_VSOCK CID: Cannot assign requested address` on every PID1
  generator pass (boot + each `daemon-reload`, so every Ansible run repeats it) — netcup KVM
  exposes no vsock transport to the guest. TCP sshd (`:22`) and all services are unaffected;
  the lines go to kmsg/console only and are not retained in the journal. Known-noise, do not
  chase (verified read-only 2026-08-23; silencing via modprobe blacklist/generator stub
  explicitly declined for now).

---

## Provider & Specs

| Item | Provider | Specs | Cost |
|------|----------|-------|------|
| VPS | **netcup RS 2000 G12** (root server) | **AMD EPYC™ 9645** · **8 dedicated cores** · **16 GB DDR5 ECC** · **512 GB NVMe SSD** · **2,5 GBit/s** iface (flatrate) | **263,52 €/12 mo** (21,96 €/mo) |
| Local Block Storage | netcup add-on | Expandable up to **8 TB** (candidate bulk tier alongside Hetzner Storage Box) | *variable* |
| Bulk Storage | **Hetzner Storage Box** (live) — **SB-Data** BX11 1 TB · `FSN1-BX2190` (Falkenstein, DE, `eu-central`), bought 2026-08-18 (`Hertzner-SB-Data`) | CIFS-mounted for photos/files, served from VPS | **3,90 €/mo** |

> **Why netcup RS over Hetzner dedicated:** A root server gives dedicated compute for 4+4 users
> without the overhead/pricing of a full Hetzner dedicated box. Storage Box handles bulk files economically.

---

## OS: Debian (Docker)

Plain Debian with Docker CE — no hypervisor. The netcup RS is a root server (already virtualized at the provider). Same Docker networks as oldsrv ([`services.md`](services.md)).

> **Wildcard-cert issuer (HD-178/HD-181):** this host's Traefik is **THE single ACME (DNS-01) issuer** for `*.kogler.si` (`traefik_acme_issuer: true` — the only host with ACME flags + certs-dumper). oldsrv's internal edge and the Pi `traefik-ha` consume the synced cert pair via their own pull timers; verify first issuance + consumer sync at deploy.

---

## Application Stack

```
                         INTERNET
                            │
                    ┌───────▼────────┐
                    │   Cloudflare   │ DDoS, geo-blocking (optional)
                    └───────┬────────┘
                            │ :443
                    ┌───────▼────────┐
                    │    Traefik     │ Reverse proxy, auto-SSL, Forward Auth
                    │  + CrowdSec    │ Brute-force protection
                    └───────┬────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
  ┌─────▼─────┐      ┌──────▼──────┐     ┌──────▼──────┐
  │ Authentik │      │  OpenCloud  │     │   Immich    │
  │  (SSO)    │      │ (File sync) │     │  (Photos)   │
  └─────┬─────┘      └──────┬──────┘     └──────┬──────┘
        │                   │                   │
  ┌─────▼──────────┐  ┌─────▼──────────┐
  │  Forgejo (Git) │  │Hetzner StorBox │ ← bulk files (CIFS)
  └────────────────┘  └────────────────┘

  DBs, thumbnails → local SSD (speed)
  Raw photos      → Storage Box (economy)
```

---

## Security Hardening

### Layer 1: Cloudflare (TBD)
- Proxy (orange cloud) hides real VPS IP, WAF geo-blocking, DDoS absorption
- Alternative: direct exposure with Traefik + CrowdSec only

### Layer 2: Traefik Security Headers
(See [`services-traefik.md`](services-traefik.md))

### Layer 3: CrowdSec
- Parses Authentik + Traefik logs
- Community blocklist, free for personal use

### Layer 4: Authentik OIDC + Forward Auth
- No app exposes its own login publicly (Forward-Auth services)
- Native-OIDC services (Open WebUI, Headscale, Matrix, OpenClaw, OpenCloud) authenticate
  *inside* the app against Authentik; their providers/applications are declared in the **Authentik
  Blueprint** and seeded by the **secret-egress glue** (see [`services-authentik.md`](services-authentik.md))
- Traefik middleware blocks traffic before it reaches Forward-Auth apps

### Layer 5: Docker Security
- Separate networks per role
- Databases on isolated `db-internal` network
- `cap_drop: [ALL]` where possible

---

## Immich — Remote ML at Home Server

- Immich app server + database on VPS
- Raw photos on Hetzner Storage Box (CIFS)
- **Machine learning offloaded to home server GPU** via Immich remote ML feature
- Phase 1: targets oldsrv immich-ml container (RX 7600)
- Phase 2: targets Proxmox LXC (R9700)

---

## VPS-Specific Firewall (nftables) — HD-154 mandatory pre-deploy checklist

> **Enforced by the `vps-hardening` Ansible role** (`playbooks/vps.yml`, before `docker_services`) — this is an
> executable checklist, not prose (security.md §8). Committed as IaC in `roles/vps-hardening/`.

| # | Check | Enforced by | Verify |
|---|-------|-------------|--------|
| 1 | **SSH hardening** — `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3`, `AllowUsers ansible-admin` only, key-only | `post_install.sh` + role assert | `sshd -T \| grep -E 'maxauthtries\|passwordauthentication\|permitrootlogin'` → `3`/`no`/`no` |
| 2 | **fail2ban** — SSH jail (`maxretry 3`) + `http-auth` jail for public login pages (n8n/Grafana/Forgejo) | role (`/etc/fail2ban/jail.local`) | `fail2ban-client status sshd` → active |
| 3 | **Firewall default-deny** — inbound deny-all except `:22` (SSH) + `:443` + `:51820` (WG S2S) + loopback + established/related; ICMP echo limited | role (`/etc/nftables.conf`) | `nft list ruleset` → input policy `drop`, accepts as above |
| 4 | **Docker daemon** — `iptables: true`, `userland-proxy: false`, `live-restore: true`, capped json-file logs; no public container `privileged` / host-net | role (`/etc/docker/daemon.json`) + compose policy | `docker info` → `userland-proxy=false`, log driver capped |
| 5 | **SSO admission** — root disabled, per-host keys only (Domen + Ansible), no `ai-debug` on a public box | `post_install.sh` | `grep AllowUsers /etc/ssh/sshd_config` → `ansible-admin` only |
| 6 | **Docker networks isolated** — overlay networks per role (`traefik-public`/`services-internal`/`db-internal`); WG subnet → services network | compose templates + `deployment-compose.md` | `docker network ls` |
| 7 | **Published-port bypass closed (S1, HD-186)** — no port is published on a public/WAN interface; the only publishes are WG-address-bound (LDAP outpost :3389 for Samba) or loopback. Docker DNAT'd traffic traverses the *forward* chain (`oifname "docker*" accept`), so the input default-deny alone does NOT cover published ports — the control is publish-scoping | compose templates (prometheus/loki/authentik-ldap WG-bound binds) + this checklist | From an external host `nc -vz <vps-public-ip> 3389` → REFUSED, and `ldapsearch -H ldap://<vps-public-ip>:3389 -x -s base` → fails; from the WG/home side `ldapsearch` at the VPS WG address (:3389) connects (Samba path); `nft list ruleset` shows input policy drop + forward `oifname docker* accept`, no DOCKER-USER chain (future hardening if a public publish is ever required — security.md §8) |

---

## Database Backup (Pre-Kopia)

1. **tiredofit/db-backup** — long-lived service with internal cron
   - Dumps PostgreSQL to local SSD
   - Compresses (Gzip/Bzip2/Xz/Zstd), creates checksums
2. **Kopia** snapshots the dump files + configs
3. Temp dumps cleaned up after successful snapshot

---

## What Stays on Home Server

- Home Assistant (Raspberry Pi 4) + HA standby
- Ollama / LLM (needs GPU)
- Immich ML (needs GPU)
- DNS (Technitium + Pi-hole)
- Media/*arr, jellyfin, sunshine (GPU/LAN/storage-bound)
- Old-srv thin Alloy collector → VPS Prometheus/Loki (HD-135)

> **Headscale** (VPN mesh coordination) moved to the VPS (HD-135) — it is public by nature and co-locates with the edge. The **observability backend** (Prometheus/Loki/Grafana) also moved to the VPS (reliable tier).