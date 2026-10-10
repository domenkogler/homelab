---
title: Security Hardening Posture
role: detail
domain: deployment
cross_cutting: true
status: active
tags: [security, waf, hardening, secrets, bootstrap]
---
# Security Hardening Posture

> **Role:** Security hardening posture (cross-cutting) — the durable "how we secure the homelab" reference.
> Each section states an *ongoing policy* and links the owning doc that implements it.
> **Links to:** `services-traefik.md`, `deployment-compose.md`, `deployment-secrets.md`,
> `deployment-preseed.md`, `smart-home-failover.md`, `backup.md`, `network-ops.md`, `network-vpn.md`,
> `observability.md`, `deployment-renovate.md`, `services-authentik.md`
> **Linked from:** `deployment.md`, `../README.md`, `index.md`

Each of the first six sections maps to one systemic flaw (Flaw A–F) from the architecture audit. §§8–10 cover
public-VPS host hardening, home↔VPS tunnel least-access, and capability-tiering of the management plane.

## 1. Edge WAF (Flaw A)

> **Law:** every internet- or LAN-facing route must carry **at least one** of `authentik-forward-auth@file`
> or `crowdsec-only@file`. A service that skips Forward-Auth (because it has its own login) must **still**
> get `crowdsec-only` — it must never be left with zero edge protection.
> **Exception:** the **home edge (`traefik-internal` on oldsrv)**
> carries **neither** middleware by design — Forward-Auth and CrowdSec LAPI are VPS containers, so including
> them would fail exactly when that edge must survive (WAN-out). It serves only home-hosted apps with
> **own local logins** (jellyfin/seerr own login, *arr built-in Forms auth). On the **VPS edges** the law
> above continues to apply unchanged.

**Middleware map:**
- `authentik-forward-auth@file` — bundles Authentik OIDC + CrowdSec bouncer. App-facing routes with a
  managed login (most web apps).
- `crowdsec-only@file` — CrowdSec bouncer only. Self-auth'd services that deliberately skip Forward-Auth
  (native SSO / own login).

**Routes that skip Forward-Auth and MUST carry `crowdsec-only@file`:**
- `ha.kogler.si` (HA native auth)
- `media.kogler.si` (Jellyfin login)
- `seerr.kogler.si` (Seerr login)
- `matrix.kogler.si` (Matrix-native OIDC)
- `chat.kogler.si` (Element Web, homeserver SSO)
- `file.kogler.si` (OpenCloud — native OIDC)
- `foto.kogler.si` (Immich — native OIDC)
- `ai.kogler.si` (Open WebUI — native OIDC)
- `sso.kogler.si` (Authentik itself — it IS the auth provider, so Forward-Auth would be circular; the bouncer filters by source IP only and every callback path (`/application/o/<slug>/callback/`, `/outpost.goauthentik.io/*`) arrives as an ordinary browser request from a user IP — outpost↔server API traffic runs container-direct on services-internal, never through this router; brute force is additionally covered by the fail2ban `http-auth` jail — Traefik writes an accesslog (`/opt/traefik/logs/access.log`, compose dir-bind) and the jail uses a Traefik-CLF-aware filter matching 401/403 responses)
- cockpit-nas/cockpit-oldsrv file-provider routes (own-login mgmt surface) — the only login is the
  break-glass `maint` account, and the **group is the control**: Debian/Ubuntu ship `/etc/pam.d/cockpit`
  with **no group restriction at all**, so without the line below :9090 answers "anyone holding a local
  password gets a session" — on oldsrv that would include `domen`, who is in `sudo`.
  `roles/cockpit` writes `auth requisite pam_succeed_if.so user ingroup cockpit-session` above
  `common-auth`, so **only** `cockpit-session` members can authenticate, `maint`'s membership is an
  exact set rebuilt every converge, and `sudo` for that account is password-required (a converge fails
  if any sudoers fragment gives it NOPASSWD). Enforced on nas; pending on oldsrv until its box is back.
  Lockout note: this gates Cockpit only — SSH is untouched, and
  `AllowUsers` still admits just `ansible-admin`/`ai-debug`.
- HA standby via VIP

Owning doc: [services-traefik.md](services-traefik.md).

## 2. Version pinning (Flaw B)

> **Law:** no mutable image tags in production. Every service image must use an explicit semver/manifest
> pin defined as a variable in `group_vars/*.yml`, tracked by Renovate — never `latest`, never a mutable
> alias such as `-rocm`.

- **Traefik** — pinned by `traefik_version` (currently `v3.7.13`), per the `group_vars/all/versions.yml` SSOT.
- **Every `:latest`** across the compose templates → a pinned var. All templates render `{{ *_version }}`
  pins from `group_vars/all/versions.yml` (registry-verified); the only `latest` renders left are the
  documented fluid exceptions (tuwunel, profilarr — no versioned tags upstream). The validator allowlist
  is inverted: bare-`latest` fails unless in `ALLOWED_LATEST` with a MUST-pin justification.
- **Ollama `:rocm`** mutable alias → pinned to a specific `<ver>-rocm` build tag (`ollama_version`,
  the RX 7600 needs the ROCm-bundled variant).

Owning docs: [deployment-compose.md](deployment-compose.md),
[deployment-renovate.md](deployment-renovate.md).

## 3. Host port-binding policy (Flaw C)

> **Law:** no service binds a container port to `0.0.0.0` on the host. Prefer the Docker overlay network
> (containers reach each other by service name). When a host port cannot be avoided, bind loopback
> (`127.0.0.1:p:p`) or a specific VLAN IP.

- **Signal CLI** `8080:8080` — no host bind; n8n reaches it by service name.
- **VictoriaMetrics / VictoriaLogs** `8428:8428` / `9428:9428` — bound to loopback + wg-s2s.
- **Technitium** `53:53` — **VPS primary**: this is the ONE intentional public publish (the LAN/tailnet resolver is the VPS public IP); the open-resolver exposure it creates is closed at the nftables FORWARD chain (source-restricted to tailnet CGNAT + home WAN, see §8).
- **Sunshine** `47989-48010` — host ports kept on all interfaces **by design**: Moonlight clients connect from LAN/VPN, so loopback/drop would break streaming. Exposure is time-limited (`restart: "no"` = manual-start gaming timer); if a narrower bind is ever wanted, bind the LAN/Headscale interface.
- **RustDesk server** `21115/tcp`, `21116/tcp+udp`, `21117/tcp` on the **VPS** — the only *public* host-bind exception here, and the only host-net container on that box: UDP rendezvous + TCP hole punching must see the real source address, which Docker's userland-proxy SNAT would destroy (upstream's own Linux guidance is `--net=host`). It is **not** a docker publish, so there is no DNAT path and the nftables **input** chain is the entire gate; `21118`/`21119` are deliberately left closed (web client unused + upstream trusts unvalidated `X-Real-IP`/`X-Forwarded-For` there). Future narrower form: `-b/--bind` (needs 1.1.17). Detail: [services-admin.md](services-admin.md) §RustDesk.

Owning doc: [deployment-compose.md](deployment-compose.md).

## 4. Container minimum privilege (Flaw D)

> **Law:** prefer targeted `devices:` and `cap_add:` over `privileged`, broad `NET_ADMIN`, or
> `network_mode: host`. No container runs as root, or with host networking, without a documented reason.

- **HA primary** — targeted `devices:` + `cap_add:` rather than `privileged: true` + `network_mode: host`.
  `network_mode: host` is only justified for keepalived VRRP multicast; keep the minimum VRRP
  needs. Owning doc: [smart-home-failover.md](smart-home-failover.md).
- **Technitium** — runs as root with `NET_ADMIN` on port 53; add `user:` and drop `NET_ADMIN` if not
  required (host-port policy, §3).

*(Doco-CD had its own Forgejo-token split; with Doco-CD gone the single deploy path is Ansible.)*

## 5. Backup coverage (Flaw E)

> **Law:** every stateful database must be covered by `db-backup` (or Kopia) **before** go-live. A lost DB
> loses metadata that cannot be reconstructed from the original media/bytes.

- **immich** Postgres — albums, faces, labels, smart-search embeddings; a `db-backup` DB block
  (`immich-postgres`) carries the coverage. The real service hostname is `immich-postgres`.
- **opencloud** Postgres — document versions / metadata; covered by the service-state/OpenCloud
  Kopia scope (the compose mounts the service data dir), not a separate `db-backup` block.

Owning docs: [backup.md](backup.md), [storage.md](storage.md).

## 6. Bootstrap hygiene (Flaw F)

> **Law:** nothing in the bare-metal/bootstrap path may ship with shared or default credentials, or expose
> management services beyond the Management VLAN.

- **Preseed root password** — a unique per-host hash, or `root-login false`. Owning doc:
  [deployment-preseed.md](deployment-preseed.md).
- **Router API** — restricted to the Management VLAN interface in the bootstrap `.rsc`, or disabled if
  there is no TLS. Owning doc: [network-ops.md](network-ops.md).
- **Shared RouterOS admin (accepted)** — one `mikrotik-admin_login` password across router + switch
  + APs is an **accepted** risk **because every management surface binds to the Management VLAN (99) only**
  (router `api`/`www-ssl`/`ssh` = `interface=vlan99-mgmt`; switch + APs are L2-only, no WAN egress); the shared
  credential never crosses an internet boundary. Revisit per-gear items only if a gear gains WAN-exposed
  management or the Mgmt-VLAN ACL changes. Owning docs: [deployment-secrets.md](deployment-secrets.md), [network-ops.md](network-ops.md).
- **Switch port map** — `group_vars/switch.yml` must exist before first switch deploy so unused ports
  don't all land on VLAN 99.
- **Fail-loud secrets** — no `default('')`; a missing 1Password secret must fail loudly, not deploy an
  unprotected service. Owning doc: [deployment-secrets.md](deployment-secrets.md).
- **Authentik provisioning token least-privilege** — the **write-scoped** `authentik-provision_api`
  (Blueprint apply + secret-egress glue) must be scoped to issuer/app/flow/outpost endpoints *only*.
  See [`services-authentik.md`](services-authentik.md) *OIDC client provisioning* /
  [`deployment-secrets.md`](deployment-secrets.md).
- **Preseed defaults / post_install** — the `sshd_config` append is deduplicated.

Owning docs: [deployment-preseed.md](deployment-preseed.md),
[deployment-secrets.md](deployment-secrets.md), [network-ops.md](network-ops.md).

## 6a. Internal sibling auth

> **Law:** every **data-writing `services-internal` sibling** carries per-service token/header auth, or a
> documented network-isolation decision — so a supply-chain compromise in any public image on the
> overlay can't write to a sibling.

- **Coverage map (SSOT):** [`deployment-compose.md`](deployment-compose.md) *§ Container Security →
  Sibling-auth coverage map* — every writer→receiver pair, its auth mechanism, 1Password item and
  status.
- **Deliberate isolation decisions (accepted, not gaps):**
  - **Ollama** — no native server auth (`OLLAMA_AUTH_*` is ollama.com-cloud only) → stays on the
    dedicated `llm-backend` overlay reachable only by LiteLLM.
  - **docling** — no supported API-key mechanism → treated like Ollama; consumed only by the AI
    stack over the overlay (see [`services-ai.md`](services-ai.md)).
- **Cross-host reaches** (`immich-app→immich-ml`, `n8n→signal-cli`) traverse the WG tunnel; the
  token is enforced at the **receiving** service.
- **Fail-loud:** a missing `-internal_api` / `_api` item aborts the render — never
  `default('')`.

Owning doc: [`deployment-compose.md`](deployment-compose.md).

---

## 7. Decision log

> Accepted/closed policy decisions — recorded so they are **not** re-raised as open bugs on future scans.

- **Matrix open federation** — **accepted/expected, kept by decision.** A federated Matrix homeserver
  interoperating with the wider Matrix world is the intended posture. The "any Matrix user can DM the
  family" concern is mitigated WITHOUT breaking federation via
  `require_auth_for_profile_requests=true` (stops anonymous profile/MXID scraping) + `allow_public_room_directory_over_federation=false`
  (blocks `/publicRooms` enumeration). `trusted_servers` is a **key-notary** list, not an ingress permit-list —
  there is no per-server inbound federation allow-list in Conduwuit/Tuwunel; unsolicited DMs are handled client-side
  (per-user ignore/block). IaC: `tuwunel.toml.j2`. Owning doc: [`services-matrix.md`](services-matrix.md).
- **SNMP v2c community** — a dedicated read-only community (`network-snmp_api`, in 1Password) replaces
  `public`, with SNMP (161/udp) **restricted to the Management VLAN** via the router INPUT-chain ACL.
  Owning doc: [`observability.md`](observability.md).
- **Playbook role order** (`network` before `storage` on oldsrv) — accepted; not a bug.
- **Homepage docker.sock health widget** — accepted (read-only mount, behind Forward-Auth).
- **Seerr SQLite single-file** — accepted risk (reconfig takes ~15 min; keep in Kopia scope).
- **services-internal sibling auth** — every data-writing `services-internal` sibling has per-service
  token/header auth or a documented isolation decision. Ollama isolated on `llm-backend`;
  OpenClaw→OpenCloud via scoped app-specific password (`openclaw-opencloud_api`);
  immich-app→immich-ml via native ML API key (`immich-ml-internal_api`).
  Coverage map: `deployment-compose.md` §Sibling-auth coverage map.

## 8. Public VPS host hardening

> **Law:** the VPS is the **single public trust boundary** — the biggest surface exposed to the internet.
> Its OS/SSH/Docker surface must be hardened as an explicit **checklist item at VPS deploy**, not
> left as aspirational design prose. **Enforced:** the mandatory checklist lives in
> `docs/services-vps.md` §VPS-Specific Firewall as a verify-command table, **and** is implemented as executable
> IaC by the **`vps-hardening` Ansible role** (`playbooks/vps.yml` before `docker_services`) + the
> `IaC/host/vps/post_install.sh` sshd extras. A VPS deploy that skips the role fails review.

- **SSH hardening** ✅ — `MaxAuthTries 3`, `PasswordAuthentication no`, `PermitRootLogin no`, key-only `ansible-admin`
  (post_install.sh + role assert); **fail2ban** SSH jail (`maxretry 3`) + `http-auth` jail for public login pages
  (n8n/Grafana/Forgejo). The http-auth jail reads the **Traefik accesslog**
  (`/opt/traefik/logs/access.log`) through a Traefik-CLF filter matching 401/403 responses — the stock
  `nginx-http-auth` filter does not match this log path, and a fail2ban jail pointed at a missing
  file is not a failure, it is a lie. **Deploy order is load-bearing:** the jail crash-loops with
  `Have not found any log file for http-auth` until the accesslog file exists, so **re-render Traefik first,
  then start fail2ban**, and keep `--accesslog` enabled on the edge or this jail dies again.
  Owned by [deployment-preseed.md](deployment-preseed.md) (VPS) + [services-vps.md](services-vps.md)
  §VPS-Specific Firewall + `roles/vps-hardening/`. ✅ **enforced.**
- **Container/escape hardening** ✅ — the VPS `docker_services` compose uses `cap_drop`/`read_only`/`tmpfs` where
  possible; no public container gets `privileged` / host networking without a documented reason (§4 applies);
  daemon `userland-proxy: false` + `live-restore: true`. ✅ **enforced (daemon) + compose-policy.**
- **VPS firewall default-deny** ✅ — inbound **deny-all except :22 (SSH) + :443 + :51820 (WG)** (+ the host-net RustDesk trio :21115/:21116/:21117 — see §3 and the `services-vps.md` checklist rows 3/8) via the `vps-hardening` role's
  `/etc/nftables.conf` (nftables, input policy drop). Committed as an executable checklist, not prose. ✅ **enforced.**
- **Published-port bypass (S1):** docker-published ports traverse the *forward* chain (`oifname "docker*" accept`), so the input default-deny does not cover them. **No public publishes** — authentik does not publish LDAP `3389` on any interface; the outpost binds only the WG S2S address (prometheus/loki precedent), and Samba (nas, the client) pulls over the tunnel. Verify row in the `services-vps.md` §VPS-Specific Firewall checklist (external `nc`/`ldapsearch` must refuse; WG-side must connect). Documented future-hardening option if a public publish is ever required: a **DOCKER-USER filter chain** restricting forwarded dports (443 from any; specific ports from the WG peer only) — implement only then, as its own gated task. ✅ IaC; ⏳ live-verify at deploy.
- **DNS primary published-port gate:** the Technitium `53:53` publish is the ONE intentionally-public host publish (the LAN/tailnet resolver is the VPS public IP). Because input default-deny cannot see published-port traffic (same S1 bypass as above), the `:53 → {{ tchnitium_dns_overlay_ip }}` forward path is **source-restricted in the nftables FORWARD chain** (tailnet CGNAT `100.64/10` + home-WAN `@dns-allow-home` set; everything else dropped) — a FORWARD drop is authoritative over Docker's accept. Template `vps-hardening/templates/nftables.conf.j2`; apply `playbooks/vps.yml --tags hardening`. Same allow-set as the input rules. **SSOT doc: `network-dns.md`; security: this §8.**
- **IPv6 stateless control traffic — live 2026-09-24** ✅ — an `inet` table under `policy drop` that accepts
  only `ip protocol icmp` (IPv4 upper-proto field) silently discards IPv6 NDP/MLD/PMTUD: the host cannot see its
  own neighbour replies, so IPv6 fails in *both* directions while every v4 rule reads correct. The accepts are
  stateless and (for ND) link-local-scoped, so they open **no** service surface. ⚠ **The consequence is a
  decision, not a detail:** the `:22`, `:443`, `:51820` and RustDesk accepts are family-agnostic, so they have
  been IPv4-only *in practice* only while NDP was broken — they are reachable over v6 from the moment it works.
  Confirm that parity or scope them `meta nfproto ipv4`; the `ip saddr …` rules (the DNS allow-set, the wg-s2s
  scoping) stay IPv4-only by the shape of the match itself. **⏳ owner verdict outstanding.**
- **SSO on VPS admission** ✅ — the netcup `post_install.sh` SSH config matches the preseed defaults; root-login
  disabled, per-host keys (Domen + Ansible), no `ai-debug` on a public box
  (see [deployment-preseed.md](deployment-preseed.md) → VPS Deviations). ✅ **enforced.**

## 9. Home↔VPS tunnel least-access

> **Law:** the `wg-s2s` home↔VPS tunnel must be **least-access**, not a wide-open bridge — routing only
> the specific home targets bounds the compromised-VPS blast radius; the whole `site` /16 is too broad.
> Enforcement:
>
> - **WireGuard AllowedIPs** scoped on BOTH sides (`all.yml` `wg_s2s_vps.allowed_ips` + `router.yml` `wireguard_s2s_vps.allowed_ips`)
>   to the **specific home targets** only — nas (nut:9199/zfs:9198), ha-vip (HA:8123), oldsrv + pi (probes/backends),
>   router/switch (ICMP) — **NOT** the whole `site` /16. Derived from `network_static_hosts` by name (no literals).
> - **RouterOS forward ACL:** a `vps_s2s_peer` address-list may reach only `vps_scoped_home`; everything else from
>   the VPS peer is **DROPPED** (fail-loud blast radius on the router, independent of crypto AllowedIPs).
> - **fail-loud WG gate:** the `wireguard` role already asserts an **empty peer pubkey aborts** (assert task) —
>   a run never looks like it configured WG when it didn't. (`playbooks/vps.yml` also gates the role on
>   `wg_s2s_vps.peer_public_key` non-empty.)
>
> Owning docs: [network-vpn.md](network-vpn.md), [services-vps.md](services-vps.md), `router.yml`, `all.yml`
> (`wg_s2s_vps.allowed_ips`).

## 10. Capability-tiering / management-plane separation

> **Invariant:** internet-facing surfaces hold ONLY limited-capability credentials (budget-capped, model-scoped,
> no agent access). Full-power credentials -- agent-capable LiteLLM keys, coding cockpits, automation engines with
> AI nodes -- exist exclusively behind tailnet membership. A compromise of any public box yields bounded spend and
> bounded data, never capability escalation.

- New admin/UI surfaces default **tailscale-first** (Patterns A/B in [network-vpn.md](network-vpn.md) §Tailnet-exposed
  services); going public requires an explicit recorded decision.
- Enforcement is structural, not behavioral: scoped virtual keys minted once via bootstrap glue, separate
  RAG databases per exposure tier (`rag_public`/`rag_internal`), public knowledge restricted to the shared manuals KB.
- Applied in: AI stack v2 ([services-ai.md](services-ai.md) §6) -- OWUI split into `chat.` (public,
  limited) and `ai.` (internal, full power); DSH + OpenClaw control planes tailnet-only.
- **RustDesk is the deliberate exception to "admin surfaces are tailnet-first", and it stays
  capability-poor by construction**: the server must be public *because* the family machines
  introduce themselves from networks we do not control, so it carries **no credential of its own** — no
  console (the HTTP console is Pro-only), no API, no middleware tier, no bouncer, no HTTP surface at all,
  and nothing a compromise of it yields except relay bandwidth (bounded by the quota caps). The capability
  sits on the *controlled* endpoint, which is why the client-side rules are the real control: IP whitelist
  = tailnet range on direct-IP machines, interactive confirmation always, **no unattended password on the
  shared family desktop (oldsrv)**, never installed as a system service there. Posture + procedure:
  [services-admin.md](services-admin.md) §RustDesk.
