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
> **Status:** ✅**Decision (2026-08-16, HD-93):** the VPS is to be **purchased before go-live** and the
> public edge moves onto it from **day one** (public Traefik + CrowdSec + Authentik + public apps terminate
> TLS on the VPS over WG S2S → oldsrv backends). This supersedes the older "deferred to Phase 2+" wording
> below, which is retained as the implementation spec for what actually ships there.
>
> **Live** (Phase 1): all enabled services deployed behind real LE TLS
> (wildcard `*.kogler.si`). Only the WG S2S tunnel stays ⏳ deploy-gated (HD-03).

> **Container census (read-only `docker ps -a` + label inspection)** — the registry is the
> intended state; the box is the actual state, and they differ. Recorded here so the next session does not
> re-audit from zero (**tracked as HD-394**):
>
> | Container | Actual state | Verdict |
> |---|---|---|
> | `confident_shamir` | `traefik:v3.7.11` (Up), `nets=none`, no port bindings, `restart=no`, **no compose labels** | hand-run `docker run` leftover — inert but invisible to compose/converge; remove with owner OK |
> | `pgvector` | Up (healthy) | **superseded by Qdrant** (HD-267/268) — prove no RAG path reads it, then tombstone via the registry (`enabled: false`), never `docker rm` |
> | `authentik-ldap` | Up **(unhealthy)** | owned by **HD-360**, do not re-diagnose — but note the symptom shape changed: on 2026-09-25 there was NO `403 Token invalid/expired` left in its logs; it now sits Up, serves nothing (3389 REFUSED) and fails its own healthcheck on a missing metrics socket |
>
> Everything else running carries `com.docker.compose.project` and maps to an enabled registry entry
> (navidrome + matrix + zipline included — three services several rows still described as un-deployed).

### netcup edge firewall (SCP-verified, Wave-3)

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
  chase (verified read-only ; silencing via modprobe blacklist/generator stub
  explicitly declined for now).

---

## Provider & Specs

| Item | Provider | Specs | Cost |
|------|----------|-------|------|
| VPS | **netcup RS 2000 G12** (root server) | **AMD EPYC™ 9645** ·**8 dedicated cores** ·**16 GB DDR5 ECC** ·**512 GB NVMe SSD** ·**2,5 GBit/s** iface (flatrate, **throttled to 300 Mbit/s beyond 3 TB rolling / 24 h** — quota SSOT = `vps_host.specs` in `group_vars/vps.yml`; the whole-traffic knee is what bounds any bandwidth-heavy service, e.g. the HD-412 RustDesk relay cap in [services-admin.md](services-admin.md)) | **263,52 €/12 mo** (21,96 €/mo) |
| Local Block Storage | netcup add-on | Expandable up to **8 TB** (candidate bulk tier alongside Hetzner Storage Box) | *variable* |
| Bulk Storage | **Hetzner Storage Box** (live) — **SB-Data** BX11 1 TB · `FSN1-BX2190` (Falkenstein, DE, `eu-central`), bought 2026-08-18 (`Hertzner-SB-Data`) | CIFS-mounted for photos/files, served from VPS | **3,90 €/mo** |

> **Why netcup RS over Hetzner dedicated:** A root server gives dedicated compute for 4+4 users
> without the overhead/pricing of a full Hetzner dedicated box. Storage Box handles bulk files economically.

---

## OS: Debian (Docker)

Plain Debian with Docker CE — no hypervisor. The netcup RS is a root server (already virtualized at the provider). Same Docker networks as oldsrv ([`services.md`](services.md)).

> **Wildcard-cert issuer (HD-178/HD-181):** this host's Traefik is **THE single ACME (DNS-01) issuer** for `*.kogler.si` (`traefik_acme_issuer: true` — the only host with ACME flags + certs-dumper). The internal all-app edge here (`traefik-tailnet`, HD-331) and the Pi `traefik-ha` edge consume the synced cert pair (bind-mount / ha-cert-sync pull timer); verify first issuance + consumer sync at deploy.

> 📡 **The tailnet node on this host is reachable DIRECTLY, and it takes TWO edits at once (HD-460,
> live since 2026-09-25).** `tailscale-sidecar` shares `traefik-tailnet`'s netns
> (`network_mode: service:traefik-tailnet`) and compose **ignores `ports:` on a netns dependent**, so an
> unpinned sidecar binds **ephemeral** sockets (measured inside the netns: `39417` + `52926`) and no
> amount of firewall work can publish them. The pair that works: publish `41641/udp` on the **NETNS
> OWNER** (`traefik-tailnet`) **and** pin the daemon with `TS_TAILSCALED_EXTRA_ARGS=--port=41641`.
> ⚠ **`TS_EXTRA_ARGS` is the wrong variable** — it goes to `tailscale up` (login flags), not to the
> daemon, so the intuitive place for `--port` silently does nothing.
> ✅ Measured 2026-09-25: netns UDPv4 + UDPv6 both on `41641`, host `ss -lun` shows `0.0.0.0:41641`,
> and a peer reads `active; direct …:41641` instead of relayed. ✅ **Confirmed from a real away network
> 2026-09-26:** an owner on LTE reached this node **directly, 45 ms** — the reading the row waited on, and the
> one no device in this repo can produce. ⚠ One residue left: the host publishes **IPv4 only** (no `[::]:41641`),
> so the v6 disco path stays unreachable from outside despite the socket being pinned inside the netns.

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
- Phase 2: targets **spark** (ThinkStation PGX / GB10 — [`hardware-spark.md`](hardware-spark.md), HD-335; supersedes the old Proxmox-R9700 plan)

---

## VPS-Specific Firewall (nftables) — HD-154 mandatory pre-deploy checklist

> **Enforced by the `vps-hardening` Ansible role** (`playbooks/vps.yml`, before `docker_services`) — this is an
> executable checklist, not prose (security.md §8). Committed as IaC in `roles/vps-hardening/`.

| # | Check | Enforced by | Verify |
|---|-------|-------------|--------|
| 1 | **SSH hardening** — `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3`, `AllowUsers ansible-admin` only, key-only | `post_install.sh` + role assert | `sshd -T \| grep -E 'maxauthtries\|passwordauthentication\|permitrootlogin'` → `3`/`no`/`no` |
| 2 | **fail2ban** — SSH jail (`maxretry 3`) + `http-auth` jail for public login pages (n8n/Grafana/Forgejo) — HD-280: http-auth reads the Traefik accesslog (`/opt/traefik/logs/access.log`, `traefik-http-auth` Traefik-CLF filter for 401/403) | role (`/etc/fail2ban/jail.local` + `filter.d/traefik-http-auth.conf`) | `fail2ban-client status sshd` → active; `fail2ban-client status http-auth` → active + `tail /opt/traefik/logs/access.log` has lines |
| 3 | **Firewall default-deny** — inbound deny-all except `:22` (SSH) + `:443` + `:51820` (WG S2S) + `:21115/:21116/:21117` tcp + `:21116/udp` (the HD-412 RustDesk rendezvous/relay — the ONLY non-edge public accepts, host-net, see row 8) + loopback + established/related; ICMP echo limited | role (`/etc/nftables.conf`) | `nft list ruleset` → input policy `drop`, accepts as above |
| 4 | **Docker daemon** — `iptables: true`, `userland-proxy: false`, `live-restore: true`, capped json-file logs; no public container `privileged`; host-net ONLY for the documented HD-412 exception (`rustdesk-server`, justified in-template — UDP rendezvous/hole-punch fidelity) | role (`/etc/docker/daemon.json`) + compose policy | `docker info` → `userland-proxy=false`, log driver capped; `docker inspect -f '{{.HostConfig.NetworkMode}}' rustdesk-server` → `host` (and no other host-net container) |
| 5 | **SSO admission** — root disabled, per-host keys only (Domen + Ansible), no `ai-debug` on a public box | `post_install.sh` | `grep AllowUsers /etc/ssh/sshd_config` → `ansible-admin` only |
| 6 | **Docker networks isolated** — overlay networks per role (`traefik-public`/`services-internal`/`db-internal`); WG subnet → services network | compose templates + `deployment-compose.md` | `docker network ls` |
| 7 | **Published-port bypass closed (S1, HD-186)** — no port is published on a public/WAN interface; the only publishes are WG-address-bound (LDAP outpost: 3389 for Samba) or loopback. Docker DNAT'd traffic traverses the *forward* chain (`oifname "docker*" accept`), so the input default-deny alone does NOT cover published ports — the control is publish-scoping. **DNS primary exception:** the Technitium `53:53` publish is intentionally public (the LAN/tailnet resolver is the VPS public IP, HD-299); its exposure is closed by **source-restricting the forward path** in the nftables FORWARD chain (tailnet CGNAT `100.64/10` + home-WAN `@dns-allow-home` set; everything else dropped) — see security.md §8 + network-dns.md | compose templates (victoria-metrics/victoria-logs/authentik-ldap WG-bound binds) + `vps-hardening` nftables forward chain | From an external host `nc -vz <vps-public-ip> 3389` → REFUSED, and `ldapsearch -H ldap://<vps-public-ip>:3389 -x -s base` → fails; from the WG/home side `ldapsearch` at the VPS WG address (:3389) connects (Samba path); `nft list ruleset` shows input policy drop + forward `oifname docker* accept`, **and** forward `dport 53` rules source-restricted to `100.64/10` + `@dns-allow-home` (external `dig @<vps-public-ip> example.com` → refused/no-answer, home-WAN + tailnet resolve) |
| 8 | **RustDesk host-net ports (HD-412)** — `21115/tcp`, `21116/tcp+udp`, `21117/tcp` reachable; `21118`/`21119` NOT. Host-net means there is **no docker DNAT**, so unlike every other service the input chain is the whole gate (row 3). The container still *binds* 21118/21119 (upstream builds them in; `-b/--bind` needs 1.1.17), so the firewall is what closes them — they are web-client-only and upstream trusts unvalidated `X-Real-IP`/`X-Forwarded-For` there | `vps-hardening` nftables input allow-list + `templates/docker_services/rustdesk-server/` | From an external host: `nc -vz <vps-public-ip> 21117` → OPEN, `nc -vz <vps-public-ip> 21118` → **REFUSED**, `nc -vzu <vps-public-ip> 21116` + a RustDesk client registration succeeds; `docker logs rustdesk-server` shows `TOTAL_BANDWIDTH: 48Mb/s` (the caps took effect — hbbr prints its effective values at start-up) |
| 9 | **IPv6 stateless control traffic (HD-448)** — the `inet` input chain must accept NDP + the ICMPv6 error types + MLD, or the box discards its own neighbour replies and IPv6 is dead in both directions while every v4 rule reads correct. ⚠ Fixing it makes the family-agnostic `:22`/`:443`/`:51820`/RustDesk accepts reachable over v6 as well — that parity is an open owner question, not an accident to leave implicit | `vps-hardening` nftables input chain | `nft list chain inet filter input \| grep -c icmpv6` → ≥ 3; `ip -6 -s neigh show dev eth0` → the gateway **`REACHABLE`**, not `FAILED`; `curl -6 -m 10 -o /dev/null -w '%{http_code}' https://dns.quad9.net/` → a real status code, not a timeout; `nstat -az \| grep Icmp6InNeighborAdvertisements` → non-zero (a zero here with `REACHABLE` means RAs are periodic, not that the rule fails — do not chase it) |

---

## Container census — unowned stacks on the VPS (HD-394)

> Run **read-only before any further VPS work** — that is the row. Procedure (repeatable, non-destructive):
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

**Census result (run 2026-09-21, read-only):** 49 containers across 37 compose projects; **zero
unlabeled containers**; **one project the registry does not own** (`pgvector`); 234 unlabeled
(anonymous) volumes of which 231 are dangling (1.84 GB reclaimable).

| Item | Live state (probed 2026-09-21) | What would break if removed | Verdict |
|------|-------------------------------|-----------------------------|---------|
| `confident_shamir` — the row's premise: a hand-run `traefik:v3.7.11` up since 2026-08-24 with no networks/ports/labels | **Gone.** Not in `docker ps -a` (which includes exited); no unlabeled container exists on the host. Its image is still present because it *is* the pinned image of the real `traefik` container — in use, not orphaned | Nothing | **Nothing to remove — but the removal is unrecorded:** no converge owns the deletion of a hand-run container, so nobody can say who removed it or when. That is the residue of the class, and the volumes row below is its remaining evidence |
| `pgvector` — project `pgvector`, `/opt/pgvector/docker-compose.yml` (rendered 2026-08-22), image `pgvector/pgvector:0.8.6-pg16-trixie` | Up (healthy) since 2026-08-23, `restart: unless-stopped` (survives reboots), on `db-internal`, `read_only` + `cap_drop ALL`. **The only live project absent from `group_vars/vps.yml`** — the registry row was deleted when Qdrant superseded it (HD-267/268), so no converge will ever stop or remove it | Nothing. Probed empty: DB `pgvector` is 7.5 MB (= `template1` size) with **0 user tables**, `pg_extension` lists only `plpgsql` (the `vector` extension was never created), `pg_stat_activity` shows **no external client connections**, and no rendered compose references it — `db-backup`'s own header states "no pgvector/qdrant Postgres target exists to dump" | ✅ **RETIRED 2026-09-21 (owner OK)** — `compose stop` + `down --remove-orphans`, image untagged/deleted, render → `/opt/.retired-pgvector`, data → `/srv/docker/.retired-pgvector` (47 MB). No other container restarted (roster diff). Delete the two `.retired-*` dirs once the next green converge agrees (manual.md §1.12 step 6) |
| `/opt/loki`, `/opt/prometheus` | Rendered compose + config dirs on disk; no containers, no projects (the stack was retired by HD-341/342 in favour of Victoria). **No registry row, no repo template** — so, unlike `/opt/metabase`, nothing can re-render them | Nothing | ✅ **RETIRED 2026-09-21** — moved to `/opt/.retired-loki`, `/opt/.retired-prometheus`; their dangling volumes `loki_loki-data` (9 MB) + `prometheus_prometheus-data` (186 MB) removed (0 container references, audit in `/root/retire-loki-prom-*.txt` on the VPS) |
| `/opt/metabase` | On disk, not running — and legitimately so: the registry entry exists with `enabled: false` | The re-enable path (`enabled: true` + converge re-renders from the template; the dir is the render target) | **Keep** — registry-owned; the difference from `pgvector` is exactly the invariant |
| **234 unlabeled anonymous volumes** (231 dangling) + 3 dangling named volumes | `docker system df`: 1.84 GB reclaimable (67 % of volume storage). Anonymous volumes carry **no provenance at all** — no name, no project, no labels | Unknown by construction; the named ones were `loki_loki-data` / `prometheus_prometheus-data` (retired stack) and `dsh_dsh-home` (dsh browser/session profiles — recreated empty by design) | ✅ **CLEARED 2026-09-21 (owner OK)** — 228 anonymous 64-hex dangling volumes removed (per-volume re-check that no container, running or stopped, referenced them; audit `/root/volume-audit-20260921-2244.txt` = name/size/ctime only), then the 3 named ones. Result: `docker volume ls` 242 → **11, all in use, 0 dangling**; local volume storage 2.77 GB → 930 MB. Rule kept for the future: **inventory first, `prune --all` never** (manual.md §1.12 step 3) |
| `authentik-ldap` | `Up (unhealthy)`. **Symptom corrected 2026-09-25 (read-only re-probe): the 2026-09-21 "crash-looping `403 Forbidden (Token invalid/expired)`" description no longer holds** — 0 matches for `token invalid\|403\|forbidden` in the last 24 h. What is true now: the container is Up but **serves nothing** (TCP connect to its WG-bound publish — port 3389 on the `wg-s2s` VPS end → REFUSED, no listener) and the Docker healthcheck fails on its own account: `/ldap healthcheck` → `Head "http://localhost/outpost.goauthentik.io/ping": dial unix /dev/shm/authentik-metrics.sock: connect: no such file or directory`, `FailingStreak` 416,996 (5 s interval ⇒ weeks) | Samba auth: it is the service Samba would authenticate against (HD-360); Samba is on `tdbsam`, so nothing regresses — but the family drives' future LDAP path depends on it. ⚠ **Do not read the red health flag as "still the 403"**: the test probes the outpost's metrics UDS, which only exists once an outpost object actually runs, so minting the token will NOT flip it green on its own | **Keep, do not delete as "cleanup".** It is the HD-360 blocker: [deployment-compose.md](deployment-compose.md) §HD-132 |

**Correction to the row's 2026-08-24 premise (recorded, not improvised around):** it described
`confident_shamir` as running and `pgvector` as "Up/healthy although Qdrant superseded it". Live
re-probing shows the opposite shape of the problem: the hand-run container is gone, and the
registry-owned stack is the one that is provably dead weight — **and it is not unlabeled at all**, it
is a *labelled project the registry stopped describing*, which the label-based ownership test alone
would have passed as clean. Ownership is therefore measured against the **registry**, not only against
the compose label.

---

## Database Backup (Pre-Kopia)

1. **tiredofit/db-backup** — long-lived service with internal cron (`DB01..DB06` blocks in
   `templates/docker_services/db-backup/`); dumps PostgreSQL, compresses (zstd), checksums.
2. ⚠ **Step 2 of the original plan — "Kopia snapshots the dump files, temp dumps cleaned up after
   successful snapshot" — is NOT live, and never has been.** There is **no Kopia client on the VPS**
   (no `kopia` binary, no client config, no `kopia-agent` container; the host runs only
   `kopia-server`, which is the *repository endpoint* other hosts' agents push through — oldsrv has
   had its own `kopia-agent` container since HD-102, the VPS has none). Verified 2026-09-21:
   `/var/lib/docker/volumes/db-backup_db-backups/_data` holds **767 MB of daily dumps going back to
   2026-08-24, on the same NVMe as the databases they protect**, and the storage box mounted at
   `/mnt/storagebox` contains only `music`. **The dumps are a single copy.** Consequence for DR is in
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
- Old-srv thin Alloy collector → VPS VictoriaMetrics/VictoriaLogs (HD-135)

> **Headscale** (VPN mesh coordination) moved to the VPS (HD-135) — it is public by nature and co-locates with the edge. The **observability backend** (VictoriaMetrics/VictoriaLogs/Grafana) also moved to the VPS (reliable tier).