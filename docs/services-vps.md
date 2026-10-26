---
title: Deferred VPS Infrastructure
role: reference
domain: services
status: active
sensitivity: infra
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
> **Live**: all enabled services deployed behind real LE TLS
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
> (live).** `tailscale-sidecar` shares `traefik-tailnet`'s netns
> (`network_mode: service:traefik-tailnet`) and compose **ignores `ports:` on a netns dependent**, so an
> unpinned sidecar binds **ephemeral** sockets (measured inside the netns: `39417` + `52926`) and no
> amount of firewall work can publish them. The pair that works: publish `41641/udp` on the **NETNS
> OWNER** (`traefik-tailnet`) **and** pin the daemon with `TS_TAILSCALED_EXTRA_ARGS=--port=41641`.
> ⚠ **`TS_EXTRA_ARGS` is the wrong variable** — it goes to `tailscale up` (login flags), not to the
> daemon, so the intuitive place for `--port` silently does nothing.
> ✅ Measured: netns UDPv4 + UDPv6 both on `41641`, host `ss -lun` shows `0.0.0.0:41641`,
> and a peer reads `active; direct …:41641` instead of relayed. ✅ **Confirmed from a real away
> network:** an owner on LTE reached this node **directly, 45 ms**. ⚠ One residue left: the host publishes
> **IPv4 only** (no `[::]:41641`), so the v6 disco path stays unreachable from outside despite the socket
> being pinned inside the netns.

---

## Application Stack

```
                         INTERNET
                            │ :443   Cloudflare is DNS-only for kogler.si — the records
                            │        answer with this VPS address, no proxy in front
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

## Git hosting roles — GitHub and Forgejo

Two git surfaces run, and **neither mirrors the other**. `domenkogler/homelab` — the IaC + docs repo — has
exactly one remote, and it is GitHub.

- **Repo content — GitHub.** Every tree's `origin` is `git@github.com:domenkogler/homelab.git` for fetch AND
  push, and it is the only remote anything pushes to. The VPS Forgejo holds **no copy of this repo**: its whole
  repository list is one sandbox repo (`domen/test`) and `domen/homelab` does not exist there. Nothing
  replicates between the two surfaces, in either direction.
- **Issues and PRs — GitHub.** The tracker is on for the repo (`api.github.com` → `has_issues: true`). Forgejo's
  issues serve whatever actually lives in Forgejo (the Renovate sandbox repo), never this repo's work items.
- **CI — neither surface, and that is the measured state.** GitHub reports **0 workflows** for the repo because
  the only workflow file in the tree sits at
  [`spark/.github/workflows/ansible-ci.yml`](../spark/.github/workflows/ansible-ci.yml), a nested path GitHub
  never reads (there is no root `.github/`), and no Forgejo runner is installed on `vps`, `oldsrv` or `spark`
  (no container, no unit). So the check that guards a change is the local one: `scripts/validate-all.sh` before
  commit. Moving CI onto either surface is a change to make, not a switch to flip.
- **Off-site copy for disaster recovery — GitHub**, the public remote the family-safe link resolves to. There is
  no second git remote, so "the repo is in Git" is one copy, not two.

**What `git.kogler.si` (Forgejo, this VPS) is for:** self-hosted git for repos that stay on-box, and the API
platform Renovate is wired to (`RENOVATE_PLATFORM: gitea` over the internal endpoint). It is not a backup of the
homelab repo, not its review surface, and not its CI.

### Git transport, as measured

- **GitHub leg — SSH over 22, outbound, for both fetch and push.** Credentials:
  [`deployment-secrets.md`](deployment-secrets.md) §Master Secret List (`GitHub-homelab-deploy_ssh` = the seat's
  write path, `github-homelab-deploy_api` = the runner's read-only pull). The repo is public, so an anonymous
  HTTPS *read* of the tree also works — which is why the no-literal-secrets rule is disclosure control, not
  hygiene.
- **Forgejo leg — HTTPS only.** The service surface is `https://git.kogler.si`. The image does run its own
  OpenSSH server inside the container (`app.ini`: `DISABLE_SSH = false`, `SSH_LISTEN_PORT = 22`,
  `SSH_PORT = 22`, `SSH_DOMAIN = git.kogler.si`), **but no host publishes that port**: `docker port forgejo`
  prints nothing, and the host's `:22` belongs to the host `sshd` — that is what the firewall's
  `tcp dport 22 accept` rule in `inet filter` input reaches. So `22/tcp` open on the VPS means **admin SSH,
  never git**, and the `git@git.kogler.si:<owner>/<repo>.git` URL the UI advertises connects to the admin daemon
  and fails. The working transport to Forgejo is HTTPS with a token: `forgejo_api` for the API, a per-user PAT
  for a push. Probe: `docker port forgejo` (empty) and `ss -tlnp | grep ':22 '` (sshd, not the container).
- **Publishing Forgejo SSH would require** — none of it authorized by this split: a published host port that does
  not collide with the host sshd on `0.0.0.0:22` (an alternate port), `SSH_PORT`/`SSH_DOMAIN` aligned so the
  advertised clone URL matches reality, a public firewall accept for that port, fail2ban coverage for a git sshd
  (the `sshd` jail guards the admin daemon only), and a decision to run an internet-facing git SSH daemon at
  all. A push to Forgejo needs none of that — a PAT over the existing HTTPS surface is enough.

---

## Security Hardening

### Layer 1: Edge exposure — direct, Cloudflare is DNS-only
- `kogler.si` resolves straight to the VPS address: Cloudflare is **DNS-only** here, no proxy (orange
  cloud) in front — CrowdSec bans on the real client IP, which a proxy would replace with its own
  ([`services-rejected.md`](services-rejected.md) row *Cloudflare proxy (orange cloud)*).
- So the filtering is host-side: Traefik headers (§Layer 2), CrowdSec bans (§Layer 3), the nftables
  input chain (§VPS-Specific Firewall). No CDN / DDoS-absorption layer sits in front of this box.

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
- **Machine learning runs on oldsrv**: the `immich-ml` container on the RX 7600, dialed cross-host
  from the VPS over the WG S2S tunnel (`immich_ml_url` → `oldsrv_home_ip`). It is **not** a spark
  workload — spark holds the generation tier only
  ([`hardware-spark.md`](hardware-spark.md) §Current role in the AI tier)

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
| 7 | **Published-port bypass closed** — no port is published on a public/WAN interface; the only publishes are WG-address-bound (the internal edge on `:4443`) or loopback — there is no LDAP listener on this box. Docker DNAT'd traffic traverses the *forward* chain (`oifname "docker*" accept`), so the input default-deny alone does NOT cover published ports — the control is publish-scoping. **DNS primary exception:** the Technitium `53:53` publish is intentionally public (the LAN/tailnet resolver is the VPS public IP); its exposure is closed by **source-restricting the forward path** in the nftables FORWARD chain (tailnet CGNAT `100.64/10` + home-WAN `@dns-allow-home` set; everything else dropped) — see security.md §8 + network-dns.md | compose templates (victoria-metrics/victoria-logs WG-bound binds) + `vps-hardening` nftables forward chain | From an external host `nc -vz <vps-public-ip> <published>` → REFUSED for every non-DNS publish (no LDAP listener exists to probe); `nft list ruleset` shows input policy drop + forward `oifname docker* accept`, **and** forward `dport 53` rules source-restricted to `100.64/10` + `@dns-allow-home` (external `dig @<vps-public-ip> example.com` → refused/no-answer, home-WAN + tailnet resolve) |
| 8 | **RustDesk host-net ports** — `21115/tcp`, `21116/tcp+udp`, `21117/tcp` reachable; `21118`/`21119` NOT. Host-net means there is **no docker DNAT**, so unlike every other service the input chain is the whole gate (row 3). The container still *binds* 21118/21119 (upstream builds them in; `-b/--bind` needs 1.1.17), so the firewall is what closes them — they are web-client-only and upstream trusts unvalidated `X-Real-IP`/`X-Forwarded-For` there | `vps-hardening` nftables input allow-list + `templates/docker_services/rustdesk-server/` | From an external host: `nc -vz <vps-public-ip> 21117` → OPEN, `nc -vz <vps-public-ip> 21118` → **REFUSED**, `nc -vzu <vps-public-ip> 21116` + a RustDesk client registration succeeds; `docker logs rustdesk-server` shows `TOTAL_BANDWIDTH: 48Mb/s` (the caps took effect — hbbr prints its effective values at start-up) |
| 9 | **IPv6 stateless control traffic** — the `inet` input chain must accept NDP + the ICMPv6 error types + MLD, or the box discards its own neighbour replies and IPv6 is dead in both directions while every v4 rule reads correct. ⚠ **Ruled (owner 2026-10-12): the parity is kept, not scoped** — fixing NDP makes the family-agnostic `:22`/`:443`/`:51820`/RustDesk accepts reachable over v6 as well, and they stay family-agnostic (`meta nfproto ipv4` is NOT added); the duty moved to the proof that a real v6 client address reaches a ban log. Measured state and the half still owed: [network-ops.md](network-ops.md) §IPv6 on the RB4011 and [services-vps.md](services-vps.md) §IPv6 dual-stack on the VPS | `vps-hardening` nftables input chain | `nft list chain inet filter input \| grep -c icmpv6` → ≥ 3; `ip -6 -s neigh show dev eth0` → the gateway **`REACHABLE`**, not `FAILED`; `curl -6 -m 10 -o /dev/null -w '%{http_code}' https://dns.quad9.net/` → a real status code, not a timeout; `nstat -az \| grep Icmp6InNeighborAdvertisements` → non-zero (a zero here with `REACHABLE` means RAs are periodic, not that the rule fails — do not chase it) |

---

## IPv6 dual-stack on the VPS

> **Design of record for the VPS v6 leg** (ruled 2026-10-12). The provider is not the blocker: the SCP
> network page delegates the **whole `2a0a:4cc0:60:fcc::/64`** to this box (the host's own global address is
> that NIC's EUI-64) and its firewall is Active with 0 policies, so container addresses come out of our own
> /64 and nothing is owed upstream.

**The chosen mechanism — `ipvlan-l2` on the delegated /64 (shape A).** A dedicated docker `ipvlan` network on
`parent=eth0` (`ipvlan_mode=l2`) handing containers addresses from the delegated /64. Chosen because it keeps
the three things this edge is judged on: a true global provider address per container, **real client source
addresses** in Traefik/CrowdSec/fail2ban (which is what the accept-parity ruling in
[network-ops.md](network-ops.md) §IPv6 on the RB4011 depends on), and a direct tailscale path. Its two known
costs are accepted with it: ipvlan **refuses on-host parent↔child traffic** — so a host→container v6 read is
not a valid test of the path — and the v6 default must be routed via that interface only, never widened.

**The standing fallback — docker `ipv6` + `fixed-cidr-v6` + NAT66 (shape B).** Pre-authorized, to be used
without going back to the owner **only if** ipvlan's on-host parent↔child block breaks the Traefik backends.
It keeps no provider address in the container tier, so it costs tailscale its direct path, and the ban and
attribution logic across the fleet may only be trusted after the client-source visibility is **PROVEN** (the
access log must show the real client v6 address, not the gateway). **Never both shapes in one commit** — the
one that lands is the one recorded here, with the read that shows why.

**What must be true first.** The prefix read (step 1) is the precondition for either shape, and it is
read-only: `ip -6 addr/route/neigh`, `sysctl net.ipv6.conf.all.accept_ra net.ipv6.conf.all.autoconf`,
`docker network ls`, `cat /etc/docker/daemon.json`, `ip6tables -S`, `ss -lun` on the host **and** inside the
edge netns, plus which traefik publishes 80/443. Measured 2026-10-13 (read-only, `ssh vps`): the host holds
`2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5/64` with `default via fe80::1 dev eth0`; `daemon.json` carries
`"ip6tables": true` but **no `"ipv6": true` and no `fixed-cidr-v6`**; every docker network is driver `bridge`;
the publishes bind v4-only (`0.0.0.0:80`/`0.0.0.0:443`, the tunnel-bound `:4443`), so nothing binds
`[::]:443` and the publish is v4-only; `ip6tables -S` shows the DOCKER chains present and empty of v6 rules.
Only `sshd` (`[::]:22`) and RustDesk (`*:21115`–`*:21119`) are dual-stack today, and `udp 51820` listens on
`[::]`.

**⛔ Apply is authored and parked — no VPS network change runs unattended.** The VPS is the edge, so this
runs in an owner-present window, one shape at a time, with the rollback written down first. Shape A, exactly:

```bash
# ⛔ parked: owner-present window, nothing else changed in the same sitting
docker network create -d ipvlan -o ipvlan_mode=l2 -o parent=eth0 -o com.docker.network.driver.mtu=1450 \
  --enable_ipv6=true --subnet 2a0a:4cc0:60:fcc::/64 traefik-v6
docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' traefik-v6   # must read the /64 back
# rollback, complete and reversible in one command:
docker network rm traefik-v6
```

Acceptance is the reads, not the config: the `--resolve` read answers from a proven v6 source, a listener
binds `[::]:443` on the host, a peer reads the tailscale peer as `active; direct [<v6>]:41641`, and a
container still logs a real client address — then the blackbox-exporter `preferred_ip_protocol: ip4` pin comes
out. Decision log for the shape declined: [network-rejected.md](network-rejected.md).

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

> ⚠ **Superseded 2026-10-19 — read the count from the command, not from this paragraph.** Live today:
> **47 volumes, 10 in use, 37 dangling**, 2.16 GB with 671.5 MB reclaimable. The dangling set is not a
> mystery and nothing in it is unattributed — see §The dangling-volume table below.

| Item | Live state | What would break if removed | Verdict |
|------|-------------------------------|-----------------------------|---------|
| `confident_shamir` — a hand-run `traefik:v3.7.11` with no networks, ports or compose labels | **Gone** — not in `docker ps -a` (which includes exited), and no unlabeled container exists on the host. Its image is still present because it *is* the pinned image of the real `traefik` container — in use, not orphaned | Nothing | **Nothing to remove** |
| `pgvector` — project `pgvector`, `/opt/pgvector/docker-compose.yml`, image `pgvector/pgvector:0.8.6-pg16-trixie` | ✅ **RETIRED** — the one live project absent from `group_vars/vps.yml`; Qdrant superseded it ([services-rejected.md](services-rejected.md) row *PGVector as the RAG vector store*) | Nothing — probed empty: DB `pgvector` is 7.5 MB (= `template1` size) with **0 user tables**, `pg_extension` lists only `plpgsql` (the `vector` extension was never created), `pg_stat_activity` shows **no external client connections**, and no rendered compose references it — `db-backup`'s own header states "no pgvector/qdrant Postgres target exists to dump" | Render → `/opt/.retired-pgvector`, data → `/srv/docker/.retired-pgvector` (47 MB); delete both once the next green converge agrees (manual.md §1.12 step 6) |
| `/opt/loki`, `/opt/prometheus` | Rendered compose + config dirs on disk; no containers, no projects. **No registry row, no repo template** — so, unlike `/opt/metabase`, nothing can re-render them | Nothing — VictoriaMetrics/VictoriaLogs replaced the stack | ✅ **RETIRED** — dirs moved to `/opt/.retired-loki`, `/opt/.retired-prometheus`; their volumes `loki_loki-data` + `prometheus_prometheus-data` removed (0 container references) |
| `/opt/metabase` | Nothing — the dir and its render target are gone, and no registry row names this host | Nothing: with no metabase entry in `group_vars/vps.yml`, no converge can re-render it back into existence | ✅ **REMOVED** — the service runs on oldsrv; the rendered project dir was deleted with it (no containers, no volumes, no app DB on disk) |
| **Unlabeled anonymous volumes** + dangling named volumes | ⚠ **Void as written (2026-10-19).** Anonymous volumes carry no *labels*, which is not the same as no provenance: Docker labels only compose's named volumes, so every anonymous volume — compose-created or not — carries just `com.docker.volume.anonymous`. Content + timestamps + the image's `Config.Volumes` attribute all 37. And they are back: 0 dangling then, **37** now | Unknown by construction; the named ones were `loki_loki-data` / `prometheus_prometheus-data` (retired stack) and `dsh_dsh-home` (dsh browser/session profiles — recreated empty by design) | ✅ **CLEARED** — every dangling volume removed after a per-volume re-check that no container, running or stopped, referenced it → `docker volume ls`: **11, all in use, 0 dangling**; 930 MB local volume storage. Rule: **inventory first, `prune --all` never** (manual.md §1.12 step 3) |
| `authentik-ldap` | ✅ **RETIRED** — no LDAP listener on this box; removed from the `authentik` compose, nothing consumes LDAP. ⚠ An `Up` container plus a quiet 24 h of logs reads as "almost deployed": the outpost backs off exponentially, so a quiet window is normal — trust `State.Health.FailingStreak`, never log absence | ⛔ Nothing — the Samba passdb is local tdbsam | Evidence: [storage-rejected.md](storage-rejected.md) row *Authentik LDAP outpost as the Samba passdb (ldapsam)* |

### The dangling-volume table — provenance for every dangling volume (re-derived 2026-10-19, read-only)

**The count is the command's, not this doc's.** `ssh vps 'docker volume ls -q --filter dangling=true | wc -l'`
→ **37**; `du -sh -c` over their `_data` dirs → **644 MB**; `docker system df` → `Local Volumes 47, 2.16 GB,
671.5 MB reclaimable`, of which **10 volumes are in use**. Every dangling volume is `driver=local` and
**anonymous** (64-hex name). None carries a compose label — and that is NOT evidence of a hand-run container:
Docker labels the *named* volumes compose creates, so a compose-created anonymous volume carries exactly one
label, `com.docker.volume.anonymous` (verified on the five in-use ones). "Anonymous volumes carry no
provenance at all", the claim in the census table above, is therefore **void**: provenance is content +
timestamp + the image's `Config.Volumes`, and it resolved for all 37.

Two mechanisms account for everything in the table:

1. **recreate churn on an image `VOLUME` path.** A service that maps no source for a path the image declares
   in `Config.Volumes` gets a **fresh anonymous volume at every container create**, seeded from that image's
   content at that path; the previous one is orphaned where it stands. Every same-second timestamp burst is
   one recreate (2026-08-23 22:35, 2026-10-17 10:08, 2026-10-17 16:01).
2. **a one-off `docker run postgres` with no pinned data path** — initdb wrote the cluster into the anonymous
   volume instead of into a bind. This is the anonymous-volume class the ledger feared, and it is bounded: 14 clusters,
   every one holding a user database whose body is template1's size (7–11 MB) — created, **never loaded** —
   and untouched since its first-start burst.

**Why 47 MB copies are not lost state.** `litellm-db` and `authentik-postgres` mount the image path
`/var/lib/postgresql` as an anonymous volume **and** `/var/lib/postgresql/data` as a bind. The bind is nested
inside the volume mount, so it is mounted second and it wins: `PGDATA=/var/lib/postgresql/data` in
`Config.Env` on every postgres container on this box, the live data paths hold 64–332 MB each and carry their
service's own `datname`, and the anonymous halves hold 8 KB of empty skeleton. A cluster living inside an
anonymous volume therefore means "this run had no bind" — an experiment, never a service.

| volume (12-hex) | created | size | content class | what serves that path today | verdict | last write |
|---|---|---|---|---|---|---|
| `1cc70e008061` | 2026-10-07 02:49 | 50M | postgres cluster (PG_VERSION=16), user db `forgejo` body=11M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:49 |
| `23cb413b2bad` | 2026-10-17 10:08 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-17 10:08 |
| `3b71ffe46b27` | 2026-08-23 22:35 | 240K | rabbitmq mnesia + erlang cookie | named volume onlyoffice-docs_onlyoffice-rabbitmq-data | prune-when-proven | 08-23 22:35 |
| `3f0e79e25f7d` | 2026-10-08 19:56 | 16K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 19:56 |
| `4007af1e2a21` | 2026-02-24 04:46 | 4.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 02-24 04:46 |
| `406090fd41a8` | 2026-10-07 02:45 | 46M | postgres cluster (PG_VERSION=16), user db `forgejo` body=7.2M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:46 |
| `407ec6164f85` | 2026-08-23 22:35 | 4.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 08-23 22:35 |
| `49e041f375b0` | 2026-10-07 02:49 | 50M | postgres cluster (PG_VERSION=16), user db `forgejo` body=11M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:49 |
| `4cc4279a6ea4` | 2026-10-07 02:47 | 46M | postgres cluster (PG_VERSION=16), user db `forgejo` body=7.4M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:47 |
| `4e6a6df9e92d` | 2026-10-07 02:48 | 46M | postgres cluster (PG_VERSION=16), user db `forgejo` body=7.4M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:48 |
| `4f8a2cced787` | 2026-10-08 22:20 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 22:20 |
| `5444b783f43b` | 2026-10-17 16:02 | 20K | onlyoffice WOPI/JWT keypair | the anonymous volume now mounted at onlyoffice-docs:/var/www/onlyoffice/Data | prune-when-proven | 10-17 16:02 |
| `5604fa0ce848` | 2026-10-17 16:02 | 36K | onlyoffice docservice logs (logrotate archives) | the anonymous volume now mounted at onlyoffice-docs:/var/log/onlyoffice | prune | 10-18 04:19 |
| `580682655bf6` | 2026-10-08 19:20 | 47M | postgres cluster (PG_VERSION=18), user db `probe` body=7.6M | nothing — the scratch PG-18 attempt; no live cluster carries this datname | prune-when-proven | 10-08 19:20 |
| `582452b0b4e9` | 2026-10-17 10:08 | 4.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-17 10:08 |
| `6648a8e0b3cb` | 2026-10-17 10:08 | 20K | onlyoffice WOPI/JWT keypair | the anonymous volume now mounted at onlyoffice-docs:/var/www/onlyoffice/Data | prune-when-proven | 10-17 10:08 |
| `6952c4a2555e` | 2026-10-08 19:21 | 47M | postgres cluster (PG_VERSION=18), user db `probe` body=7.6M | nothing — the scratch PG-18 attempt; no live cluster carries this datname | prune-when-proven | 10-08 19:21 |
| `6a022e411261` | 2026-08-23 22:35 | 39M | postgres cluster (PG_VERSION=16), user db `onlyoffice` body=7.4M (no user-db dir) | named volume onlyoffice-docs_onlyoffice-pgdata — live, 47 MB, same datname | prune-when-proven | 08-23 22:35 |
| `760a72464bce` | 2026-10-08 19:21 | 47M | postgres cluster (PG_VERSION=18), user db `probe` body=7.6M | nothing — the scratch PG-18 attempt; no live cluster carries this datname | prune-when-proven | 10-08 19:21 |
| `83721c4acd62` | 2026-10-07 02:48 | 46M | postgres cluster (PG_VERSION=16), user db `forgejo` body=7.4M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:48 |
| `85866a74be54` | 2026-10-08 22:25 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 22:25 |
| `8c508da6951d` | 2026-08-23 22:35 | 316K | onlyoffice docservice logs (logrotate archives) | the anonymous volume now mounted at onlyoffice-docs:/var/log/onlyoffice | prune | 10-17 09:53 |
| `8dd3c94f9b02` | 2026-10-08 19:20 | 47M | postgres cluster (PG_VERSION=18), user db `probe` body=7.4M | nothing — the scratch PG-18 attempt; no live cluster carries this datname | prune-when-proven | 10-08 19:20 |
| `975c0ff9c1e2` | 2026-10-08 19:17 | 16K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 19:17 |
| `9e9ca7c5cf3d` | 2026-10-08 20:07 | 16K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 20:07 |
| `a324dc67d31d` | 2026-10-17 10:08 | 36K | onlyoffice docservice logs (logrotate archives) | the anonymous volume now mounted at onlyoffice-docs:/var/log/onlyoffice | prune | 10-17 16:01 |
| `a4edec661743` | 2026-10-07 02:44 | 46M | postgres cluster (PG_VERSION=16), user db `forgejo` body=7.2M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:44 |
| `ac9839fc7dbe` | 2026-10-07 02:49 | 46M | postgres cluster (PG_VERSION=16), user db `forgejo` body=7.4M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:49 |
| `acd58df614ad` | 2026-10-08 21:39 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 21:39 |
| `cd272b207530` | 2026-10-08 22:48 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 22:48 |
| `d2478277e0b2` | 2026-10-08 19:18 | 16K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-08 19:18 |
| `e778b635265e` | 2026-10-17 16:01 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-17 16:01 |
| `eb4b30e403cb` | 2026-08-23 22:35 | 20K | onlyoffice WOPI/JWT keypair | the anonymous volume now mounted at onlyoffice-docs:/var/www/onlyoffice/Data | prune-when-proven | 08-23 22:35 |
| `f04c62127919` | 2026-10-17 16:01 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-17 16:01 |
| `f545c862df59` | 2026-10-07 02:48 | 46M | postgres cluster (PG_VERSION=16), user db `forgejo` body=7.4M | bind /srv/docker/forgejo/postgres — live, 71 MB, same datname | prune-when-proven | 10-07 02:48 |
| `fa9a8ebdf666` | 2026-10-17 10:08 | 8.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-17 10:08 |
| `fb989e058b5b` | 2026-10-17 16:01 | 4.0K | image skeleton, **0 files** | the live mount of the same image VOLUME path (a bind, or the recreate's own new anonymous volume) | prune | 10-17 16:01 |

**Verdict legend.** `prune` = provably empty (0 files) or log-only. `prune-when-proven` = holds bytes, but the
same data is provably live elsewhere or the producer no longer exists. `keep` = unresolved — **none of the 37**.
`last write` is the newest mtime inside the volume: the whole table's state argument is that in every case it
sits inside the creation minute, i.e. one first-start burst and nothing since.

⛔ **Nothing was deleted to produce this table.** The set is approved for removal **per row, by name** — one
`docker volume rm <name>` per row the table marks `prune`, and `prune-when-proven` rows only once the named-volume
fix below has landed. A blanket `docker volume prune -f` stays refused: it takes the `keep` rows with the rest, and
its exit code says nothing about which volumes it chose. Destroying live host state still runs in a VPS window with
the read-backs below, not in an unattended overnight lane.

**Two findings the table exposes; the named-volume half is the fix that must land FIRST:**

1. `onlyoffice-docs` keeps `/var/www/onlyoffice/Data` — the **WOPI/JWT keypair** — in an *anonymous* volume,
   so every container recreate mints a fresh keypair and strands the old one (three stranded copies here:
   2026-08-23, 2026-10-17 10:08, 2026-10-17 16:01). Anything that cached the previous public key fails on the
   next recreate. State that must outlive a recreate lives in a **named volume or a bind**, never in an anonymous
   one; give the path one of those before pruning, or the prune removes the only copies of the minted keys.
2. Same shape at `/var/log/onlyoffice`: the docservice logs live in an anonymous volume, so the running
   container's log history is discarded at every recreate and the stranded copies are the only history left.

Re-derive (read-only, every claim above):

```bash
ssh vps 'docker volume ls -q --filter dangling=true | wc -l'                     # the live count
ssh vps 'docker volume ls -q --filter dangling=true | while read v; do
        docker volume inspect -f "{{.Name}} {{.Driver}} {{.CreatedAt}} {{.Labels}}" $v; done'
ssh vps "sudo -n find /var/lib/docker/volumes/<id>/_data -printf '%T@\n' | sort -g | tail -1"   # last write
ssh vps "sudo -n sh -c 'for v in \$(docker volume ls -q --filter dangling=true); do
        pg=\$(find /var/lib/docker/volumes/\$v/_data -maxdepth 3 -name PG_VERSION | head -1);
        [ -n "\$pg" ] && echo \$v \$(dirname \$pg)/base \$(ls \$(dirname \$pg)/base) \
          \$(strings \$(dirname \$pg)/global/1262 | grep -vE "^(template0|template1|postgres)$") | sort -u; done'"  # a user db?
ssh vps 'docker inspect -f "{{.Name}} {{range .Config.Env}}{{println .}}{{end}}" <pg-container>' | grep PGDATA
```

---

## Database Backup

1. **tiredofit/db-backup** — long-lived service with internal cron (`DB01..DB06` blocks in
   `templates/docker_services/db-backup/`); dumps PostgreSQL, compresses (zstd), checksums.
2. ⚠ **There is no Kopia snapshot of these dumps: the VPS has no Kopia client** (no `kopia` binary,
   no client config, no `kopia-agent` container; the host runs only `kopia-server`, which is the
   *repository endpoint* other hosts' agents push through — oldsrv has its own `kopia-agent`
   container, the VPS has none). Verified:
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