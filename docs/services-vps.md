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
> **Status:** ✅ the VPS is in place **before go-live** and the public edge is on it from **day one**
> (public Traefik + CrowdSec + Authentik + public apps terminate TLS on the VPS over WG S2S →
> oldsrv backends); the rest of this doc is the implementation spec for what ships there.
>
> **Live** (Phase 1): all enabled services deployed behind real LE TLS
> (wildcard `*.kogler.si`). Only the WG S2S tunnel stays ⏳ deploy-gated.

### netcup edge firewall (SCP-verified)

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
- **Console/kmsg noise (benign, accepted):** Debian 13's `systemd-ssh-generator`
  logs `Failed to query local AF_VSOCK CID: Cannot assign requested address` on every PID1
  generator pass (boot + each `daemon-reload`, so every Ansible run repeats it) — netcup KVM
  exposes no vsock transport to the guest. TCP sshd (`:22`) and all services are unaffected;
  the lines go to kmsg/console only and are not retained in the journal. Known-noise, do not
  chase (verified read-only); silencing via a `modprobe` blacklist or a generator stub is declined.

---

## Provider & Specs

| Item | Provider | Specs | Cost |
|------|----------|-------|------|
| VPS | **netcup RS 2000 G12** (root server) | **AMD EPYC™ 9645** ·**8 dedicated cores** ·**16 GB DDR5 ECC** ·**512 GB NVMe SSD** ·**2,5 GBit/s** iface (flatrate, **throttled to 300 Mbit/s beyond 3 TB rolling / 24 h** — quota SSOT = `vps_host.specs` in `group_vars/vps.yml`; the whole-traffic knee is what bounds any bandwidth-heavy service, e.g. the RustDesk relay cap in [services-admin.md](services-admin.md)) | **263,52 €/12 mo** (21,96 €/mo) |
| Local Block Storage | netcup add-on | Expandable up to **8 TB** (candidate bulk tier alongside Hetzner Storage Box) | *variable* |
| Bulk Storage | **Hetzner Storage Box** (live; secret `Hertzner-SB-Data`) — **SB-Data** BX11 1 TB · `FSN1-BX2190` (Falkenstein, DE, `eu-central`) | CIFS-mounted for photos/files, served from VPS | **3,90 €/mo** |

> **Why netcup RS over Hetzner dedicated:** A root server gives dedicated compute for 4+4 users
> without the overhead/pricing of a full Hetzner dedicated box. Storage Box handles bulk files economically.

---

## OS: Debian (Docker)

Plain Debian with Docker CE — no hypervisor. The netcup RS is a root server (already virtualized at the provider). Same Docker networks as oldsrv ([`services.md`](services.md)).

> **Wildcard-cert issuer:** this host's Traefik is **THE single ACME (DNS-01) issuer** for `*.kogler.si` (`traefik_acme_issuer: true` — the only host with ACME flags + certs-dumper). The internal all-app edge here (`traefik-tailnet`) and the Pi `traefik-ha` edge consume the synced cert pair (bind-mount / ha-cert-sync pull timer); verify first issuance + consumer sync at deploy.

> 📡 **The tailnet node on this host is reachable DIRECTLY, and it takes TWO edits at once
> (live since 2026-09-25).** `tailscale-sidecar` shares `traefik-tailnet`'s netns
> (`network_mode: service:traefik-tailnet`) and compose **ignores `ports:` on a netns dependent**, so an
> unpinned sidecar binds **ephemeral** sockets (measured inside the netns: `39417` + `52926`) and no
> amount of firewall work can publish them. The pair that works: publish `41641/udp` on the **NETNS
> OWNER** (`traefik-tailnet`) **and** pin the daemon with `TS_TAILSCALED_EXTRA_ARGS=--port=41641`.
> ⚠ **`TS_EXTRA_ARGS` is the wrong variable** — it goes to `tailscale up` (login flags), not to the
> daemon, so the intuitive place for `--port` silently does nothing.
> ✅ Measured 2026-09-25: netns UDPv4 + UDPv6 both on `41641`, host `ss -lun` shows `0.0.0.0:41641`,
> and a peer reads `active; direct …:41641` instead of relayed. ✅ **Confirmed from a real away network
> 2026-09-26:** an owner on LTE reached this node **directly, 45 ms**. ⚠ One residue left: the host publishes
> **IPv4 only** (no `[::]:41641`), so the v6 disco path stays unreachable from outside despite the socket
> being pinned inside the netns.

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
- Phase 2: targets **spark** (ThinkStation PGX / GB10 — [`hardware-spark.md`](hardware-spark.md))

---

## VPS-Specific Firewall (nftables) — mandatory pre-deploy checklist

> **Enforced by the `vps-hardening` Ansible role** (`playbooks/vps.yml`, before `docker_services`) — this is an
> executable checklist, not prose (security.md §8). Committed as IaC in `roles/vps-hardening/`.

| # | Check | Enforced by | Verify |
|---|-------|-------------|--------|
| 1 | **SSH hardening** — `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3`, `AllowUsers ansible-admin` only, key-only | `post_install.sh` + role assert | `sshd -T \| grep -E 'maxauthtries\|passwordauthentication\|permitrootlogin'` → `3`/`no`/`no` |
| 2 | **fail2ban** — SSH jail (`maxretry 3`) + `http-auth` jail for public login pages (n8n/Grafana/Forgejo) — http-auth reads the Traefik accesslog (`/opt/traefik/logs/access.log`, `traefik-http-auth` Traefik-CLF filter for 401/403) | role (`/etc/fail2ban/jail.local` + `filter.d/traefik-http-auth.conf`) | `fail2ban-client status sshd` → active; `fail2ban-client status http-auth` → active + `tail /opt/traefik/logs/access.log` has lines |
| 3 | **Firewall default-deny** — inbound deny-all except `:22` (SSH) + `:443` + `:51820` (WG S2S) + `:21115/:21116/:21117` tcp + `:21116/udp` (the RustDesk rendezvous/relay — the ONLY non-edge public accepts, host-net, see row 8) + loopback + established/related; ICMP echo limited | role (`/etc/nftables.conf`) | `nft list ruleset` → input policy `drop`, accepts as above |
| 4 | **Docker daemon** — `iptables: true`, `userland-proxy: false`, `live-restore: true`, capped json-file logs; no public container `privileged`; host-net ONLY for the documented `rustdesk-server` exception (justified in-template — UDP rendezvous/hole-punch fidelity) | role (`/etc/docker/daemon.json`) + compose policy | `docker info` → `userland-proxy=false`, log driver capped; `docker inspect -f '{{.HostConfig.NetworkMode}}' rustdesk-server` → `host` (and no other host-net container) |
| 5 | **SSO admission** — root disabled, per-host keys only (Domen + Ansible), no `ai-debug` on a public box | `post_install.sh` | `grep AllowUsers /etc/ssh/sshd_config` → `ansible-admin` only |
| 6 | **Docker networks isolated** — overlay networks per role (`traefik-public`/`services-internal`/`db-internal`); WG subnet → services network | compose templates + `deployment-compose.md` | `docker network ls` |
| 7 | **Published-port bypass closed (S1)** — no port is published on a public/WAN interface; the only publishes are WG-address-bound (the internal edge on `:4443`) or loopback — there is no LDAP listener on this box. Docker DNAT'd traffic traverses the *forward* chain (`oifname "docker*" accept`), so the input default-deny alone does NOT cover published ports — the control is publish-scoping. **DNS primary exception:** the Technitium `53:53` publish is intentionally public (the LAN/tailnet resolver is the VPS public IP); its exposure is closed by **source-restricting the forward path** in the nftables FORWARD chain (tailnet CGNAT `100.64/10` + home-WAN `@dns-allow-home` set; everything else dropped) — see security.md §8 + network-dns.md | compose templates (victoria-metrics/victoria-logs WG-bound binds) + `vps-hardening` nftables forward chain | From an external host `nc -vz <vps-public-ip> <published>` → REFUSED for every non-DNS publish (no LDAP listener exists to probe); `nft list ruleset` shows input policy drop + forward `oifname docker* accept`, **and** forward `dport 53` rules source-restricted to `100.64/10` + `@dns-allow-home` (external `dig @<vps-public-ip> example.com` → refused/no-answer, home-WAN + tailnet resolve) |
| 8 | **RustDesk host-net ports** — `21115/tcp`, `21116/tcp+udp`, `21117/tcp` reachable; `21118`/`21119` NOT. Host-net means there is **no docker DNAT**, so unlike every other service the input chain is the whole gate (row 3). The container still *binds* 21118/21119 (upstream builds them in; `-b/--bind` needs 1.1.17), so the firewall is what closes them — they are web-client-only and upstream trusts unvalidated `X-Real-IP`/`X-Forwarded-For` there | `vps-hardening` nftables input allow-list + `templates/docker_services/rustdesk-server/` | From an external host: `nc -vz <vps-public-ip> 21117` → OPEN, `nc -vz <vps-public-ip> 21118` → **REFUSED**, `nc -vzu <vps-public-ip> 21116` + a RustDesk client registration succeeds; `docker logs rustdesk-server` shows `TOTAL_BANDWIDTH: 48Mb/s` (the caps took effect — hbbr prints its effective values at start-up) |
| 9 | **IPv6 stateless control traffic** — the `inet` input chain must accept NDP + the ICMPv6 error types + MLD, or the box discards its own neighbour replies and IPv6 is dead in both directions while every v4 rule reads correct. ⚠ Fixing it makes the family-agnostic `:22`/`:443`/`:51820`/RustDesk accepts reachable over v6 as well — that parity is an open owner question, not an accident to leave implicit | `vps-hardening` nftables input chain | `nft list chain inet filter input \| grep -c icmpv6` → ≥ 3; `ip -6 -s neigh show dev eth0` → the gateway **`REACHABLE`**, not `FAILED`; `curl -6 -m 10 -o /dev/null -w '%{http_code}' https://dns.quad9.net/` → a real status code, not a timeout; `nstat -az \| grep Icmp6InNeighborAdvertisements` → non-zero (a zero here with `REACHABLE` means RAs are periodic, not that the rule fails — do not chase it) |

---

## Container census — unowned stacks on the VPS

> Run **read-only before any further VPS work**. Procedure (repeatable, non-destructive):
>
> ```bash
> # 1. every container with its ownership label (empty P= = owned by nothing)
> ssh vps 'docker ps -a --format "{{.Names}}|{{.Image}}|{{.Status}}|P={{.Label \"com.docker.compose.project\"}}|{{.Ports}}"' | sort
> # 2. live projects the registry does not own (run from the repo root)
> comm -13 <(awk -F'name: ' '/- \{ name:/{split($2,a,","); gsub(/[ ,]/,"",a[1]); print a[1]}' \
              IaC/ansible/group_vars/vps.yml | sort -u) \
>          <(ssh vps 'docker ps -a --format "{{.Label \"com.docker.compose.project\"}}"' | sed '/^$/d' | sort -u)
> # 3. provenance of anything left over
> ssh vps 'docker inspect <name> --format "{{.Config.Image}} created={{.Created}} restart={{.HostConfig.RestartPolicy.Name}} nets={{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}"'
> ```
> **Registry invariant this enforces:** every container on a managed host belongs to a compose project
> named by an `enabled` entry of that host's `docker_services` registry — or it is a finding. The
> invariant matters because an unlabeled container is invisible to *every* converge: `compose up`
> prunes only what its own project declares and `deploy-service.yml` iterates the registry, so such a
> container is never stopped, never removed, and outlives reboots if it carries a restart policy.
> Ownership is measured against the **registry**, not only against the compose label — a labelled
> project the registry stopped describing passes the label test and is still unowned. Retire a stack
> through the registry (`enabled: false`), never `docker rm`.

**Census result:** **zero unlabeled containers**; every running project maps to an enabled registry
entry (navidrome, matrix and zipline included) — `pgvector` was the one exception. `docker volume ls`
→ **11 volumes, all in use, 0 dangling**; 930 MB of local volume storage.

| Item | Live state | What would break if removed | Verdict |
|------|-------------------------------|-----------------------------|---------|
| `confident_shamir` — a hand-run `traefik:v3.7.11` with no networks, ports or compose labels | **Gone** — not in `docker ps -a` (which includes exited), and no unlabeled container exists on the host. Its image is still present because it *is* the pinned image of the real `traefik` container — in use, not orphaned | Nothing | **Nothing to remove** |
| `pgvector` — project `pgvector`, `/opt/pgvector/docker-compose.yml`, image `pgvector/pgvector:0.8.6-pg16-trixie` | ✅ **RETIRED** — the one live project absent from `group_vars/vps.yml`; Qdrant superseded it ([services-rejected.md](services-rejected.md) row *PGVector as the RAG vector store*) | Nothing — probed empty: DB `pgvector` is 7.5 MB (= `template1` size) with **0 user tables**, `pg_extension` lists only `plpgsql` (the `vector` extension was never created), `pg_stat_activity` shows **no external client connections**, and no rendered compose references it — `db-backup`'s own header states "no pgvector/qdrant Postgres target exists to dump" | Render → `/opt/.retired-pgvector`, data → `/srv/docker/.retired-pgvector` (47 MB); delete both once the next green converge agrees (manual.md §1.12 step 6) |
| `/opt/loki`, `/opt/prometheus` | Rendered compose + config dirs on disk; no containers, no projects. **No registry row, no repo template** — so, unlike `/opt/metabase`, nothing can re-render them | Nothing — VictoriaMetrics/VictoriaLogs replaced the stack | ✅ **RETIRED** — dirs moved to `/opt/.retired-loki`, `/opt/.retired-prometheus`; their volumes `loki_loki-data` + `prometheus_prometheus-data` removed (0 container references) |
| `/opt/metabase` | On disk, not running — and legitimately so: the registry entry exists with `enabled: false` | The re-enable path (`enabled: true` + converge re-renders from the template; the dir is the render target) | **Keep** — registry-owned; `enabled: false` is the disabled state the invariant allows |
| **Unlabeled anonymous volumes** + dangling named volumes | Anonymous volumes carry **no provenance at all** — no name, no project, no labels | Unknown by construction; the named ones were `loki_loki-data` / `prometheus_prometheus-data` (retired stack) and `dsh_dsh-home` (dsh browser/session profiles — recreated empty by design) | ✅ **CLEARED** — every dangling volume removed after a per-volume re-check that no container, running or stopped, referenced it → `docker volume ls`: **11, all in use, 0 dangling**; 930 MB local volume storage. Rule: **inventory first, `prune --all` never** (manual.md §1.12 step 3) |
| `authentik-ldap` | ✅ **RETIRED** — no LDAP listener on this box; removed from the `authentik` compose, nothing consumes LDAP. ⚠ An `Up` container plus a quiet 24 h of logs reads as "almost deployed": the outpost backs off exponentially, so a quiet window is normal — trust `State.Health.FailingStreak`, never log absence | ⛔ Nothing — the Samba passdb is local tdbsam | Evidence: [storage-rejected.md](storage-rejected.md) row *Authentik LDAP outpost as the Samba passdb (ldapsam)* |

---

## Database Backup

1. **tiredofit/db-backup** — long-lived service with internal cron (`DB01..DB06` blocks in
   `templates/docker_services/db-backup/`); dumps PostgreSQL, compresses (zstd), checksums.
2. ⚠ **There is no Kopia snapshot of these dumps: the VPS has no Kopia client** (no `kopia` binary,
   no client config, no `kopia-agent` container; the host runs only `kopia-server`, which is the
   *repository endpoint* other hosts' agents push through — oldsrv has its own `kopia-agent`
   container, the VPS has none). Verified 2026-09-21:
   `/var/lib/docker/volumes/db-backup_db-backups/_data` holds **767 MB of daily dumps, on the same
   NVMe as the databases they protect**, and the storage box mounted at `/mnt/storagebox` contains
   only `music`. **The dumps are a single copy.** Consequence for DR is in
   [backup.md](backup.md) §VPS-side coverage gap — it is the reason the scope rows there are still
   pending, and it is the one finding on this host that changes what a real VPS loss would cost.
3. Retention is therefore the container's own `KEEP_*` window, not a snapshot lifecycle — it is bounded
   by NVMe free space, which is the failure mode to watch.

---

## What Stays on Home Server

- Home Assistant (Raspberry Pi 4) + HA standby
- GPU-bound AI: spark generation + the pinned embed/rerank/STT legs on oldsrv (never a VPS inference
  endpoint — inference has no public ingress by design)
- Immich ML (needs GPU)
- DNS: Technitium primary **here** on the VPS, secondary/tertiary at home (the home instances are
  authoritative for split-horizon LAN names; ad blocking is Technitium Advanced Blocking — there is no
  second blocker to keep patched)
- Media/*arr, jellyfin, sunshine (GPU/LAN/storage-bound)
- Old-srv thin Alloy collector → VPS VictoriaMetrics/VictoriaLogs

> **Headscale** (VPN mesh coordination) lives on the VPS — it is public by nature and co-locates with
> the edge. So does the **observability backend** (VictoriaMetrics/VictoriaLogs/Grafana): reliable tier.