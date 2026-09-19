---
title: VPN & Remote Access
role: detail
domain: network
status: active
tags: [network, vpn, wireguard, headscale]
---
# VPN & Remote Access

> **Role:** Detail — WireGuard site-to-site, Headscale mobile mesh, remote access.
> **Links to:** `network.md`, `hardware-oldsrv.md`
> **Linked from:** `network.md`, `index.md`

---

## Two Layers, Two Subnet Families

| Layer | Technology | Endpoint | Purpose |
|-------|-----------|----------|---------|
| **Site-to-Site** | WireGuard (native RouterOS) | RB4011 ↔ VPS, port 51820 | Home LAN ↔ VPS services, always on |
| **Mobile Mesh** | **Headscale** (self-hosted Tailscale) | Home server Docker | Family phones/devices — easier app, wife-friendly |

> **Strategy:** WireGuard is **site-to-site only**. User devices use Headscale.
> The old WireGuard road-warrior endpoint and the travel router were **removed** —
> Headscale fully replaces them.

### Reserved Subnets

| Family | Name (see SSOT) | Allocations |
|--------|-----------------|-------------|
| **WireGuard / tunnel** | `wireguard` | `wg-s2s` link (home `.1` ↔ VPS `.2`) · `wg-vps-services` (VPS services) · `wg-vps-dmz` (VPS DMZ) · `wg-vps-lab` (VPS lab) |
| **Headscale overlay** | `headscale` | CGNAT (Tailscale-compatible) — router routes this to Home LAN |
| **Home LAN** | `site` | VLANs `10.10.x.0/24` (see `network-vlans.md`) |

All concrete CIDRs: [`network-addresses-generated.md`](network-addresses-generated.md) → *Infrastructure networks* (SSOT).

---

## Layer 1: WireGuard Site-to-Site (Home ↔ VPS)

- **Home RB4011:** `wg-s2s` peer `.1`
- **VPS WireGuard endpoint:** `wg-s2s` peer `.2`
- Always on, no on-demand
- Home router: static route `wg-vps-services` → via the VPS S2S peer
- VPS: route `site` → via the home S2S peer

> **Least-access (HD-155):** the VPS S2S peer's **AllowedIPs** (both sides) cover **only** the scoped home targets —
> `nas` (nut:9199 / zfs:9198), `ha-vip` (HA:8123), `oldsrv` + `pi` (probes / app backends when wired), `router`/`switch`
> (ICMP) — **not** the whole `site` /16. The RB4011 additionally enforces a forward ACL (`vps_s2s_peer` →
> `vps_scoped_home` accept, else drop). See [`security.md`](security.md) §9.

> **HD-306 (VPS-side peer bind, RESOLVED 2026-09-01):** on VPS kernel `6.12.101` + systemd 257, networkd creates the
> `wg-s2s` interface (key/address/listen) but **never applies the `[WireGuardPeer]` block to the kernel** — `wg show`
> shows no peer (the module still loads; `wg setconf` silently drops the peer when the conf carries a `PrivateKey`
> line — live-verified).**Root cause + fix:** the role renders a peer-only `wg-s2s.conf` (NO `PrivateKey` — the key
> stays in the `.netdev`, 0640) and ships a `wg-ensure-s2s-peer` oneshot that runs `wg setconf wg-s2s
> /etc/wireguard/wg-s2s.conf` after networkd init (`PartOf=systemd-networkd.service` → auto re-runs on networkd
> restart/boot). Live-verified: peer attaches + persists across `networkctl reconfigure` and a networkd restart; the
> oneshot re-attaches it automatically. Handshake still requires the **router side** (HD-285, Phase 1.5).

> **HD-285 — RESOLVED 2026-09-02 (two-key design + oneshot-owned iface + firewall rule fix).**
> Root cause was TWO layered bugs, both now fixed and live-verified (handshake UP, traffic flows):
>
> **(a) Shared-key design flaw (the real reason no handshake ever fired):** the SSOT used ONE key
> (`wg_password`) on BOTH ends — so the router's interface pubkey AND its VPS peer pubkey were
> identical (`gwXAk+…`), and WireGuard refuses to handshake with your own key. **Fix:** distinct
> per-side keypairs — router uses `wg_password` (pub `wg_s2s_router_public_key`), VPS uses its own
> `wg_password_vps` (NEW 1P item, pub `wg_s2s_vps_public_key`); each side's peer = the OTHER side's pubkey.
>
> **(b) networkd 257 netdev quirks on the VPS:** networkd applies the `.netdev` `[WireGuard] PrivateKey`
> but silently NEVER applies `[WireGuardPeer]`; and while networkd owns the iface it strips any manual
> `wg set peer`. **Fix:** networkd only CREATES wg-s2s (minimal .netdev + Unmanaged .network); the
> `wg-ensure-s2s-peer` oneshot OWNS it (create-if-missing → assign address → key via `wg setconf`
> key-only → peer via `wg set … peer`), verified every run.
>
> **(b2) Host routes are NOT installed by `wg set` (HD-370 live gap 2026-09-15):** plain `wg set peer`
> populates the peer's AllowedIPs but installs NO kernel routes — only `wg-quick`/`wg setconf` do
> (and only at setup). The pre-HD-285 `[WireGuardPeer]`-era `.netdev` had left stale `10.10.x dev wg-s2s`
> routes; adding a NEW AllowedIPs entry (spark `spark_home_ip/32`, HD-370) never got a route, so the VPS
> sent spark traffic out the public `eth0` and spark stayed unreachable (laptop SSH hop failed too).
> **Fix:** the oneshot now runs `ip route replace <cidr> dev wg-s2s` for every AllowedIPs entry
> (idempotent; `replace` also clobbers a stale wrong-device route back onto wg-s2s; non-fatal WARN on
> failure), rebuilding routes on every run/reboot (networkd is Unmanaged so nothing else restores them).
> Live-proof: `ip route replace spark_home_ip/32 dev wg-s2s` on the VPS made spark :443 instantly reachable.
>
> **(c) Router forward-rule ordering (HD-155):** the `VPS S2S -> scoped home targets` accept sat BELOW the
> `Default deny inter-VLAN` and was shadowed. **Fix:** moved above the deny (rule 29 · before 30).
>
> **Live evidence (all verified 2026-09-02):** VPS `wg show wg-s2s` — fresh handshake (keepalive-25
> maintained, ts renewed), peer = router key `gwXAk+…`, endpoint home WAN; router peer `vps-s2s` =
> VPS key `NeEeWi…`, `rx/tx` counters moving. VPS → the router mgmt IP (`router` host) pings 0% loss over the
> tunnel. `nas` (host) not answering = nas is Phase-2 gated, unrelated.
>
> The tunnel (§1.5.5) is UP. Router side re-converged via the role (public-key + endpoint = SSOT
> `vps.kogler.si` FQDN now, not a literal IP).
> Owned by: HD-285 (closed).

## Layer 2: Headscale (Mobile Mesh)

> **Naming + policy contract (Wave-3 R5, 2026-08-22):** headscale ≥ 0.24 REJECTS a
> `server_url` inside `base_domain`, so node names live under the dedicated subtree
> **`<node>.ts.kogler.si`** (`base_domain: ts.kogler.si`); the control plane stays
> `https://vpn.kogler.si`. **ACL TIGHTENED at first enrolment (HD-252 ④, 2026-08-26):**
> the interim `*:*` is replaced by a deny-by-default policy — each family user (by OIDC
> email) may reach only their OWN nodes (see `policy.hujson.j2`; currently single user
> `domen@kogler.si`). Enrolment itself remains Authentik-OIDC-gated; add one accept rule
> per family member as they join.

- Runs on the **VPS** as a Docker container (HD-135: public coordination server, VPS residency)
- Overlay subnet: `headscale` (CIDR per SSOT)
- Clients: Android/iOS Tailscale app, laptops
- **Home RB4011:** static route + firewall rules so the Headscale overlay reaches the Home VLAN
- **MagicDNS (HD-135b follow-up, 2026-08-28):** `dns.extra_records` maps the tailnet dashboard
  subdomains (`stats/logs/csui/sec/traefik/auto` **and** their `*.ts.kogler.si` twins) to the
  `vps-obs` tailnet IP (`tailnet_sidecar_ip`, group_vars/vps.yml).
  **Answer scope (verified live 2026-08-28):** Tailscale client MagicDNS ANSWERS only its
  `base_domain` (`ts.kogler.si`) — the `*.ts.kogler.si` twins work out of the box. For a FQDN
  matching a `search_domain` (`kogler.si`), the client queries its **configured nameserver for
  that domain** (Technitium — now the VPS primary, HD-299), NOT MagicDNS — so the plain
  `*.kogler.si` names resolve through the VPS Technitium (nameserver first entry = `dns_primary_ip`)
  which carries the split-horizon A records → `tailnet_sidecar_ip` (see [`network-dns.md`](network-dns.md)
  static-records section). `dns.search_domains: [kogler.si]` is still set (helps short-name
  resolution) but does NOT make MagicDNS serve the plain names.
- **VPS:** routes the home `site` + `wg-vps-services` over the S2S tunnel to reach home resources
- Mesh clients → VPS Headscale (public, its purpose) → over S2S → home LAN; each node has an ACL-gated path home
- **Registration & ACL (HD-84 / KOPS-022):** OIDC-authenticated clients are **auto-approved** by
  Headscale (no separate registration gate in `config.yaml`). The traffic boundary is therefore a **real
  ACL policy** (`policy.hujson`, rendered alongside `config.yaml`). **User-based (current, HD-252 ④):**
  deny-by-default — each OIDC user's email may reach only that user's own nodes; `tagOwners` stays empty
  because headscale v2 requires tags be DECLARED before an ACL may reference them and there is no
  `autogroup:admin` source here, so ACLs are user-email-based. **Tag model for later (original HD-84
target):** if/when a shared-service `tag:kogler` is wanted, declare it + its owner in `tagOwners` and
  switch these rules to `tag:kogler:*` (only the mesh admin applies the tag; untagged/rogue nodes are
  denied by default).

### Admin UI: Headplane (HD-233, `https://vpn.kogler.si/admin`)

> Stock Headscale has **no built-in web UI** — visiting `https://vpn.kogler.si` returns a 123-byte
> empty shell (`BlankPage()` template, upstream by design). Administration happens through
> [Headplane](https://github.com/tale/headplane), co-deployed as a second service in the same
> compose project (service DNS `http://headscale:8080`, no extra exposure).

- **URL:** `https://vpn.kogler.si/admin` (dashboard prefix is built into headplane; Traefik routes
  `Host(vpn.kogler.si) && PathPrefix(/admin)` — longer rule wins priority over the control-plane
  router, so `/ts2021`, DERP and `/oidc/*` are untouched). Same crowdsec-only tier.
- **Auth:** OIDC via Authentik, deliberately the **same OAuth client as Headscale itself**
  (upstream best practice: identical `client_id`) — the `ks-oidc.yml` provider gained a second
  redirect URI `…/admin/oidc/callback`. First login becomes the Headplane **owner**; later users
  get `default_role: member`. **LIVE-VERIFIED 2026-08-24** (owner SSO login works);
  `disable_api_key_login: true` (API-key field removed — recovery = temporarily set false +
  re-render if the IdP ever breaks).
- **Headscale API key (required for OIDC mode):** mint ONCE on the VPS —
  `docker exec headscale headscale apikeys create --expiration 8760d` — store in 1Password
  `headplane_api`.`credential`. Cookie secret (32 chars) lives in `headplane_password`.`password`
  (**Password category → lookup `field='password'`, NOT `credential`** — migrated during HD-233/235;
  a `credential` lookup returns empty → headplane crash-loops on `missing required fields`).
- **Capabilities:** node/user management, pre-auth keys, read-only Settings view (headscale's
  rendered `config.yaml` is mounted `:ro`). Docker-socket integration (DNS editing from the UI,
  restart headscale on change) deliberately NOT wired — future hardening with a socket proxy.
- **Config = YAML-safe block scalar `>-` for every secret** (client_secret, cookie_secret, api_key) —
  live lesson HD-233: the rotated `headscale_api` secret contains `:` `"` `'` `?` which broke
  inline-quoted configs (`YAMLException`/`EISDIR` crash-loops on BOTH headscale + headplane). See
  `deployment-secrets.md` "Rendering a secret into a YAML config file" + CONVENTIONS §2.

### Transition
1. Deploy Headscale on the VPS (public edge; remote nodes reach it directly)
2. Family installs the Tailscale app (one-by-one migration from the removed road-warrior / travel-router paths)
3. WireGuard road-warrior and the travel router are **gone** — no fallback surface to maintain

---

## Tailnet-exposed services (management plane)

> **Policy (security.md §10 Capability-tiering):** internet-facing surfaces hold only limited-capability
> credentials; full-power access requires tailnet membership. **New admin/UI surfaces default tailscale-first**
> -- never Traefik-public unless explicitly decided. Mechanism below; first application = AI stack v2
> ([services-ai.md](services-ai.md)); **observability admin dashboards (HD-135b follow-up, 2026-08-28) are
> the second live application** — stats/sec/traefik/logs/n8n are now tailnet-only, no public records.
>
> **Laptop access:** with the Tailscale app connected, the dashboards resolve on the tailnet — headscale
> **MagicDNS** on the `ts.kogler.si` base domain answers the `*.ts.kogler.si` twin names (e.g.
> `stats.ts.kogler.si`). The **plain `*.kogler.si` names resolve via the same MagicDNS** — headscale appends
> the search domain `kogler.si` to its local domains, and `dns.extra_records` maps every tailnet
> subdomain (incl. `llm`/`db-spark`/`litellm`, HD-370) in BOTH namespaces to the `vps-obs` edge
> (`tailnet_sidecar_ip`). **HD-371 (2026-09-15, ✅ LIVE):** the `dns.nameservers` list now puts the **MagicDNS loop
> `100.100.100.100` FIRST** — so a tailnet client resolves EVERY `*.kogler.si` / `*.ts.kogler.si` name
> **locally on any network** (hotspot/travel), not just when the Technitium VPS primary is reachable.
> The Technitium entries (VPS primary + oldsrv + Pi) follow for the full namespace + per-subnet
> filtering when on the LAN. **Before HD-371** the plain names depended on the configured nameserver
> for `kogler.si` = Technitium VPS primary (HD-299) — reachable only from home-WAN/tailnet-CGNAT (the
> source-allow gate); a **remote mobile network** source (hotspot) fell through to the system resolver
> → NXDOMAIN/`ERR_NAME_NOT_RESOLVED` on Windows while the `.ts` twins (MagicDNS) still worked. **Live-verified
> 2026-09-15:** laptop-on-hotspot + client DNS re-pull (`netsh … set dnsservers Tailscale 100.100.100.100`)
> → `llm/stats/litellm.kogler.si` all resolve; phone too. There is
> NO public `*.kogler.si` record for these. The tailnet Traefik edge (`traefik-tailnet`, node `vps-obs`)
> is the only tailnet surface for the admin dashboards (see the compose template
> `docker_services/traefik-tailnet` for the routing + serve details).
>
> **Mgmt-99 SSH from the laptop — same-site only (corrected 2026-09-19, HD-398 owner decision A):** the
> laptop reaches the Mgmt plane **directly** via the Windows **Mgmt99 vNIC** (`wsl-nat-resolv.ps1
> -EnableMgmt99`: `.99.80` + forwarding) — no ProxyJump `pi` hop, and **no away path**: the plane is sealed
> from the VPS tunnel on purpose. That is only usable **on-site AND when that adapter actually has link**
> (Disconnected on 2026-09-19 — verify with `ip -br addr` in WSL, a VLAN-99 route must be present).
> The alias list is NOT kept here (it drifted once): the SSOT is
> **§The laptop alias contract** above — one table for both `~/.ssh/config` files (WSL + Windows).
> Short version: `router`/`switch`/`ap-*`/`pi99`/`oldsrv99`/`nas99` = Mgmt, jump-less, on-site;
> `pi`/`nas`/`oldsrv`/`spark` = Home leg + `ProxyJump vps`, anywhere (`ssh oldsrv` means the Home address
> since 2026-09-19; it used to point at `.99.30` + a jump that could never reach it).
> - **Winbox GUI (device binds winbox 8291 to Mgmt VLAN only):** because the Mgmt plane is reachable from the
>   laptop directly, point Winbox at the device Mgmt IP (`.99.x` per [`network-addresses-generated.md`](network-addresses-generated.md)) — no tunnel needed
>   (the old `switch-wb`/`ap-*-wb` LocalForward aliases were removed; the Pi-dial pattern is retired).
>   **Design constraint (unchanged):** RouterOS mgmt services bind winbox to the Mgmt VLAN only, so direct access to
>   the device winbox port from the Home laptop is blocked — the tunnel is required.

### Pattern A -- loopback-capable apps (preferred)
App binds `127.0.0.1` only; tailscale sidecar shares its network namespace (`network_mode: service:<app>`) and
`tailscale serve` proxies the tailnet socket to the loopback port. **Nothing listens on shared overlay networks**
-- nothing on `services-internal` can even reach it. Live example planned: DSH cockpit (:3080).

### Pattern B -- apps bound to `0.0.0.0`
Dedicated per-service docker network containing ONLY app + tailscale sidecar (never `services-internal` for the UI leg);
sidecar serves to the app over that private network. Functional service-to-service legs stay on their own overlays.

| Node | Serves | App-level auth | ACL tag |
|------|--------|----------------|---------|
| ~~dsh~~ *(moved to oldsrv 2026-09-10)* | cockpit :3080 | **none** (ACL is the gate) | tag:dsh |
| vps-obs (`traefik-tailnet` + its userspace sidecar, HD-135b follow-up) | **clean subdomain URLs over the tailnet** — `stats`, `sec`, `traefik`, `logs`, `csui`, `auto` (n8n), and the AI names `db-spark`, `llm`, `litellm` (HD-370/HD-372) plus their `*.ts.kogler.si` twins: `https://stats.kogler.si` / `https://stats.ts.kogler.si`, `https://logs.kogler.si`, `https://csui.kogler.si`, `https://sec.kogler.si`, `https://traefik.kogler.si`, `https://auto.kogler.si`, `https://db-spark.kogler.si`, `https://llm.kogler.si` (spark OpenAI-API, bearer-gated), `https://litellm.kogler.si` (spine admin) — **no ports** (wildcard certs + second Traefik edge). **HD-372 (2026-09-15, ✅ LIVE):** the `litellm.kogler.si` 502 (edge couldn't Docker-DNS `litellm` — spine on `services-internal` only) is fixed by joining `litellm` to the `tailnet-apps` app→edge overlay; live-verified (edge `http://litellm:4000/health/liveliness` → "I'm alive!"; `litellm.kogler.si` → LiteLLM Swagger/UI 200). **`/ui/login` deep-link 404s (no nginx SPA fallback) → use `/fallback/login` (intended flow, HD-373)** | plain `*.kogler.si` = Authentik Forward-Auth (AI names: engine/LiteLLM own-login, no forward-auth); **`*.ts.kogler.si` = ACL-gated** (tailnet-only names, `tag:sidecar:443` is the gate) | tag:sidecar |
| ~~pi-dev~~ *(moved to oldsrv 2026-09-10)* | TUI/CLI agent (`services-internal`) | scoped LiteLLM key + PR-only Forgejo | tag:pi-harness |
| litellm-ui | admin :4000/ui | bearer keys | tag:litellm |
| owui-int (`ai.kogler.si`, HD-248) | internal OWUI | Authentik OIDC | tag:owui-int |
| openclaw | control/gateway | gateway token | tag:openclaw |
| headplane (HD-251 candidate) | mesh admin `/admin` | OIDC | tag:mgmt |

- Serve mode: plain TCP forward is simplest (WireGuard already encrypts); HTTPS mode needs Headscale TLS config -- verify at deploy.
- ACL defaults: inbound-only per node (e.g., DSH needs ZERO outbound tailnet destinations); tag hygiene audit quarterly.
- Rollout: HD-251 (phase-2 fleet rework); first applications: litellm-ui + owui-int (HD-247/248), dsh (HD-250); **tailnet dashboard edge (HD-135b follow-up) LIVE 2026-08-28** — `traefik-tailnet` (consumer-mode Traefik + a userspace tailscale sidecar sharing its netns, node `vps-obs`) serves the admin dashboards over the tailnet with clean subdomain URLs on port 443 (`tailscale serve --tcp=443` → the edge's TLS listener), see `docker_services/traefik-tailnet` + `policy.hujson.j2`. The old port-based skeleton (`tailscale-sidecar` dir, :8080–8085) is removed.
- **HD-333 spec (WG/tailnet reach for the internal edge — this doc is the SSOT):** **✔️ LIVE 2026-09-07** (VPS `docker_services` + `vps-hardening` converge; nftables `iifname "wg-s2s" ip saddr <wg_s2s_vps.router_ip, SSOT> tcp dport 4443 accept` landed after the STALE pre-HD-333 ruleset was re-rendered; internal edge answers on `https://<wg_s2s_vps.ip, SSOT>:{{ wg_internal_edge_port }}`).** the internal all-app edge (`traefik-tailnet` growth, HD-331/332) is reached two ways:
  - **Tailnet (existing):** the `vps-obs` userspace sidecar already serves `--tcp=443` → the edge's TLS listener; family nodes are ACL-allowed (`policy.hujson`, deny-by-default + per-user own nodes). No change unless the ACL needs extending for a new family member.
  - **WireGuard S2S:** the internal edge's TLS listener (:443, the edge container IP pinned per HD-240) is published **only on the `wg-s2s` VPS address** (`{{ wg_s2s_vps.ip }}:{{ wg_internal_edge_port }}`, the vps.yml SSOT port) via the traefik-tailnet compose `ports:` (docker's own PREROUTING DNAT → container `:443` — same precedent as `kopia-server :51515`, HD-62; no manual nftables DNAT). An **nftables input allow** (vps-hardening, HD-313 pattern: `iifname "wg-s2s" ip saddr <router peer> tcp dport {{ wg_internal_edge_port }} accept`) is added for defense-in-depth. SSOT: `wg_internal_edge_port` / `wg_internal_edge_target_ip` in `group_vars/vps.yml` (derived-values ban — never re-type in compose/nftables/docs).
  - **Reach scope (HD-155 least-access):** the VPS wireguard peer `wg_s2s_vps.allowed_ips` accepts ONLY home infra hosts (`nas/ha-vip/oldsrv/pi/router/switch` — group_vars/all/main.yml). So the internal edge is reachable over WG **from those scoped home hosts**. End-user devices (laptop/phone) at home use the **tailnet** path (sidecar + headscale ACL) — WG is the infra/automation path, not the family path.
  - **Deploy-gated verify:** after the next VPS `docker_services` converge (`docker_services_scope=traefik-tailnet`) + `vps-hardening` converge:
    1. VPS-side listener: `ss -ltnp | grep :{{ wg_internal_edge_port }}` → bound to the `wg-s2s` VPS address (`{{ wg_s2s_vps.ip }}:{{ wg_internal_edge_port }}`).
    2. From a scoped home host over WG (e.g. `oldsrv`/`nas`/`pi`): `curl -k -I https://<wg-s2s VPS address>:{{ wg_internal_edge_port }}` → HTTP/2 302 (or the edge's TLS response); split-horizon alternative once the `vpn/home/dns` records (HD-334) are seeded: `curl -k -I https://kogler.si -H 'Host: kogler.si'` resolved via the tunnel, or `https://{{ wg_internal_edge_target_ip }}:{{ wg_internal_edge_port }}` from a scoped home host.
    3. Tailnet path unchanged: tailnet device → `https://stats.kogler.si` / `https://<app>.ts.kogler.si` still works.
    4. Heading home with Tailscale on reaches `ha.kogler.si` via the LAN (Option A).
  - **Tailnet ACL:** `policy.hujson` already allows family nodes → `tag:sidecar` on :443 (deny-by-default + per-user own nodes). No extension needed for the existing owner set; extend only if a new family member node is added.

### Reach matrix for the tailnet-only admin names (HD-382, live 2026-09-17) + spark AI names (HD-389, live 2026-09-18)

> Owner symptom: **`litellm.kogler.si` works on the phone (mobile data AND home Wi-Fi with Tailscale on),
> but 404s on the laptop with Tailscale connected at home.** Measured, not guessed:
>
> | where the answer comes from | `litellm.kogler.si` → | result |
> |---|---|---|
> | MagicDNS `extra_records` (Android/iOS answer these **client-side**) | the tailnet edge IP (`tailnet_sidecar_ip`, vps-obs) | **200** — the edge's `litellm-tailnet` router matches |
> | Technitium (what Windows/WSL uses for the plain `*.kogler.si` namespace on the LAN) | `dns_primary_ip` (VPS public) | **404 `page not found`** — Traefik's no-matching-router reply: the public edge has **no** `litellm` route *by design* (never public) |
>
> So this is **not** hairpin/NAT, not a cert problem and not the tailnet: the laptop's LAN resolver answers
> the name before MagicDNS does, and that target is a deliberately unrouted edge. `stats/logs/…` do not
> show the symptom because their Technitium A record already points at the edge IP; `litellm` points at
> the public IP (split-horizon parity per `network-dns.md`), which is exactly where no router exists.
> Confirms and extends HD-371 (same client-side asymmetry, observed there on a hotspot).
>
> **Practical answers, in order:** (1) use the **`.ts` twin** — `litellm.ts.kogler.si` exists only in
> MagicDNS/extra_records, so it cannot be hijacked by the LAN answer (verified 200 from the laptop);
> (2) keep Tailscale connected at home (the documented posture: "end-user devices at home use the tailnet
> path"); (3) a durable LAN-native fix would mean home-seeding `litellm` → `oldsrv_home_ip` + a
> `traefik-internal` router proxying over WG S2S to the internal edge (`:4443`, the HD-350 double-hop) —
> that **exposes the key-holding spine's admin UI on the LAN edge**, a design change that needs its own
> decision; NOT done here.
>
> **HD-389 (2026-09-18, LIVE) — the `llm`/`db-spark` variant is a *different* root cause and is FIXED:**
> for the spark AI names the earlier "use the .ts twin" guidance pointed at a dead end: MagicDNS answered
> both namespaces to the tailnet edge, the edge's `llm-tailnet`/`db-spark-tailnet` routers matched, but the
> TLS-in-TLS backend hop **forwards the client's SNI** to spark's own edge — and spark's Traefik had **no
> router for the `.ts` names** (only `Host(`llm.kogler.si`)`), so `llm.ts.kogler.si` got a routerless-vHost
> 404 *before* auth while `litellm.ts` (VPS-container backend, no TLS-in-TLS) stayed 200. Fix = spark's name
> edge now routes the `.ts` twins + serves the `*.ts.kogler.si` pair (`todo HD-389`). Verify:
> `curl -sk -o /dev/null -w '%{http_code}' https://db-spark.ts.kogler.si/` → 200;
> `curl -sk -H "Authorization: Bearer <spark-llm_api>" https://llm.ts.kogler.si/v1/models` → 200.
>
> **HD-389 client half (2026-09-18) — the OTHER root cause, on the laptop, and it is NOT a service bug.**
> With Tailscale connected, the **plain** `*.kogler.si` names still failed from WSL/Windows while
> `litellm.kogler.si` worked, because the plain namespace was never routed to MagicDNS **on that client**:
> WSL's auto-generated `resolv.conf` carried only the NAT forwarder, and the Windows NRPT carved only
> `*.ts.kogler.si` + the CGNAT reverse zones. Two durable client-side changes fix it (both on the laptop,
> neither in Ansible):
>
> 1. **WSL:** `/etc/wsl.conf` → `[network] generateResolvConf=false`, then a **static** `/etc/resolv.conf`
>    with `nameserver 100.100.100.100` (the MagicDNS loop) **first** and the previous forwarder after it.
>    Without `generateResolvConf=false` WSL rewrites the file on every start and the fix silently vanishes.
> 2. **Windows:** `netsh interface ipv4 add dnsservers name="Tailscale" address=<tailnet_magicdns_loop 100.100.100.100> index=1 validate=no`
>    from an **elevated** shell — it lands on the adapter and survives reconnects/reboots.
>
> **Diagnosis order that finds this fast:** prove the server side first (`nsenter`/on-box `curl` against
> spark's edge with an explicit SNI), then question the client's resolver. Here the server was fine and the
> 502/404 pair was two different layers: routerless-vHost 404 on the `.ts` name (server) and plain-name 502
> from the client's resolver path. A `Host=` curl from the box that succeeds while the laptop fails =
> client DNS, every time.

## Tailnet boundary (decided 2026-09-10) — mobile devices only, via the VPS edge

The tailnet is **not a home-LAN bridge**. Clients reach it as: **mobile → tailnet → VPS `traefik-tailnet` edge → (WG S2S) → home backends**. No home host runs a tailnet node (except the exit-node below, toggle-only). oldsrv/Pi/NAS stay off the tailnet so Shelly/KNX/IoT/guest devices are never tailnet-reachable, and the LAN stays the LAN.

**Mobile/media reach — home-hosted services:** home apps (jellyfin, *arr, downloads, seerr, seerrng, and the moved `dsh`/`pi-dev`) are reachable from a phone by **publishing a host port bound to `oldsrv_home_ip`** + a `traefik-tailnet` edge route proxying over WG — the `actual-budget:5006` / `immich-ml:3003` precedent. Still **behind Authentik forward-auth** on the edge (private, not public).

## Reaching LAN nodes when away (hotspot / public Wi-Fi) — matrix measured 2026-09-19

**The one-line answer: SSH goes through the VPS jump; service traffic goes through the tailnet edge.
Neither is a property of the laptop's network — the VPS is the only host with a public address, so it
is the door for both.** Addresses come from [network-addresses-generated.md](network-addresses-generated.md);
nothing below hard-codes one.

> **How to read the matrix:** every ✅/❌ is a command result, not a config reading. The pass below was
> taken **abroad on a mobile hotspot** (station egress ≠ the home-WAN DDNS; direct `10.10.x.x:22` probes
> all timed out). The **on-site half was not measured** that day — the station had no Mgmt-99 link, so the
> same-site rows are labelled as such instead of being asserted ✅.

| Node | Away-from-home path for **SSH/admin** | Measured 2026-09-19, off-LAN |
|---|---|---|
| **vps** | direct — `vps.kogler.si` is public | ✅ `REMOTE_OK vps` — the door itself |
| **oldsrv** | alias `oldsrv` **→ Home leg** + jump; the jump is also carried in `group_vars/home_servers.yml`, and `ansible_host` is now the Home address | ✅ `ssh oldsrv` **and** `ansible oldsrv.kogler.si -m ping` green with **no `-e`**; `home_servers.yml --check --limit oldsrv` `unreachable=0` |
| **nas** | jump in the alias **and** in `group_vars/storage.yml` (file created by HD-397 — the `storage` group had no group_vars at all) | ✅ both green. **Was ❌**: `ssh nas` had no `ProxyJump` anywhere → no route from a hotspot |
| **pi** | alias + jump; `group_vars/raspberry_pi.yml` now carries it for the runner too | ✅ both green. **Was split**: `ssh pi` ✅ while `ansible pi -m ping` ❌ (the jump lived only in the alias) |
| **spark** | `group_vars/spark.yml` + the identical play-level copy in `playbooks/spark.yml` | ✅ both green (the one host that always worked — the precedent this copies) |
| router / switch / APs / any `*99` alias | **none, by design** — Mgmt plane = same-site (decision A below) | ❌ by design: `ssh router` → connect timeout. Never add a jump to these |

**Services (not SSH): never a port forward.** `*.{ts.,}kogler.si` on the tailnet → VPS
`traefik-tailnet` edge → WG S2S → the home backend, per the boundary decision above. Measured
2026-09-19 from a hotspot: `llm.ts.kogler.si` served spark inference end-to-end with no home
reachability at all.

### The settled rule — HD-398 closed as **owner decision A** (2026-09-19): the Mgmt plane is a same-site plane

**VLAN 99 does not accept traffic from the site-to-site tunnel, and that is policy, not a fault.**
The owner chose **A — the seal stays** on 2026-09-19 (decision row: [network-rejected.md](network-rejected.md)):
management is a physical-presence plane and **off-LAN admin is always the Home leg (VLAN 10)**, which is
what `pi`/`spark` already relied on. Option **B** (add the mgmt /32s to `wg_s2s_vps.allowed_ips` **and**
extend the router's `available-from`) was declined: it spends two deliberate boundaries — **HD-155**
least-access AllowedIPs and **HD-310** admin-plane scoping — to fix a symptom the Home leg already solves.

Two independent mechanisms, both re-verified from the VPS on 2026-09-19:

1. **No route.** `ip route get <oldsrv mgmt addr>` answers `via <vps default gw> dev eth0` — straight out
   to the internet — while `ip route get <VLAN-99 gateway>` answers `dev wg-s2s`. Cause:
   `wg_s2s_vps.allowed_ips` (`IaC/ansible/group_vars/all/main.yml`) is an explicit **/32 least-access list**
   (the five VLAN-10 node addresses + the router + switch mgmt addrs + the `wg-vps-services` range) and
   names **no other mgmt address**; systemd-networkd installs a route only for what AllowedIPs names.
   Live `sudo wg show wg-s2s` agrees, and the netdev's mtime is **2026-09-03** — nothing changed since.
2. **The router scopes its own control plane.** `/ip service set ssh … available-from={{ router_services_available_from }}`
   (`IaC/router/templates/rb4011_converge.rsc.j2`), and that var is **the VLAN-99 subnet and nothing else**
   (`IaC/ansible/group_vars/router.yml`) — so even the mgmt addresses that ARE routed refuse a
   tunnel-sourced SSH (src `10.255.40.x`): tagged 99 = admin plane, Home→Mgmt forward is dropped.

Re-verify in 60 s: `ssh vps 'ip route get <oldsrv-mgmt>; ip route get <vlan99-gw>; sudo wg show wg-s2s'` +
`grep -n -A9 "allowed_ips:" IaC/ansible/group_vars/all/main.yml`.

Consequences, written out (this is the sentence two sessions on 2026-09-19 were missing):

- `pi99`, `router`, `switch`, the AP aliases and `oldsrv99`/`nas99` are **on-site admin paths** — reachable
  only with the Windows `Mgmt99` vNIC carrying link (`wsl-nat-resolv.ps1 -EnableMgmt99`; it was
  **Disconnected** on 2026-09-19) or while physically on the LAN. Check the link **before** blaming the
  router: `ip -br addr` in WSL must show a VLAN-99 route, not just `eth0`.
- **Never put `ProxyJump vps` on a mgmt-leg alias.** It cannot work, and it converts a fast failure into a
  ~90 s `Connection timed out during banner exchange`. `pi99` carried exactly that line until 2026-09-19 —
  measured result of the alias as it stood: `Connection timed out during banner exchange`.
- **A banner-exchange timeout is a dead next-hop, not an sshd fault**, and **a dead address is not a dead
  host** (oldsrv was `Up`, 34 containers running, `enp0s31f6.99` `UP` with the right address, while its
  mgmt address answered nothing).

### Where the jump lives (HD-397, the durable fix)

The jump is a property of **the inventory**, not of a runner: `ansible_ssh_common_args: "-o ProxyJump=vps"`
in `group_vars/home_servers.yml`, `group_vars/storage.yml`, `group_vars/raspberry_pi.yml` and
`group_vars/spark.yml` (`playbooks/spark.yml` keeps its identical play-level copy — play vars win over
group vars, same value, no conflict). Before this, only spark carried it in the repo, which is exactly why
spark was the only host convergible from a hotel room. **A laptop-local `~/.ssh/config` is not a durable
artifact** — it is the convenience layer, specified in §The laptop alias contract below.

Proven the same day off-LAN with a stub config that contains **only** the `Host vps` block
(`ANSIBLE_SSH_ARGS="-F <stub>" ansible <host> -m ping`): **pong for all four behind-NAT hosts** — the
repo alone carries the path.

Green forms (no `-e` anywhere, from a hotspot):

```bash
bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --check --tags common,network
#   oldsrv.kogler.si : ok=18 changed=0 unreachable=0 failed=0
# The FULL `--check` (same command, no --tags) also connects (unreachable=0) but reports failed=1 in
# the KNOWN check-mode breaker class: roles/docker_services/tasks/technitium-seed.yml:102 reads
# `_tech_login.json` from a `uri` task that does not run in check mode — see
# [deployment-ansible.md](deployment-ansible.md) §Dry-run Mode. Not a reachability fault.
# The recorded `delegate_to` victim task, now green off-LAN (no -e at all):
#   ok: [oldsrv.kogler.si -> pi.kogler.si(<the Pi Home address>)]   # Fetch Pi ha-sync public key
#   (--limit oldsrv.kogler.si --check --tags home_assistant,ha_failover → failed=0)
```

### The laptop alias contract (SSOT — rebuild a new laptop from this, do not copy an old `~/.ssh/config`)

Two rules decide every block:

1. **Behind-NAT hosts** (`pi`, `nas`, `oldsrv`, `spark`) are reached through `ProxyJump vps` onto their
   **Home leg**, on every network. The Mgmt leg is never an away path (decision A above).
2. **OpenSSH matches the name ACTUALLY TYPED**, so each node gets an alias block **and** a `Host <ip>`
   block for the leg its `ansible_host` names. Ansible no longer *needs* the IP block (the jump travels in
   the inventory — proven above); the block is what `scp`/`rsync`/`git` and a human typing an address need.

| Block | Leg (see [network-addresses-generated.md](network-addresses-generated.md)) | `ProxyJump` | Notes |
|---|---|---|---|
| `vps` | public | — | the jump itself; `User ansible-admin` |
| `pi`, `….1.20` | Home | `vps` | alias uses the human user, the IP block the `ansible-admin` one |
| `nas`, `….1.10` | Home | `vps` | gained the jump 2026-09-19 (was the broken one) |
| `oldsrv`, `….1.30` | Home | `vps` | **the alias moved mgmt → Home on 2026-09-19**; mgmt access is `oldsrv99` now |
| `spark`, `….1.40` | Home | `vps` | the precedent both the play and the group var copy |
| `pi99`, `oldsrv99`, `nas99`, `router`, `switch`, `ap-spalnica`, `ap-dnevna`, `ap-spare` | Mgmt (VLAN 99) | **none — never add one** | on-site admin paths only (decision A); `oldsrv99`/`nas99` were re-added 2026-09-19 as the explicit on-site legs |

Both copies of the contract live on the one laptop and must agree: WSL `~/.ssh/config` and
`C:\Users\domen\.ssh\config` (Windows OpenSSH). Both were brought to this table on 2026-09-19.

### The tailnet is not observable from the VPS host

**There is no `tailscale` CLI on the VPS** — its tailnet presence is the `traefik-tailnet` container's
userspace sidecar, so `tailscale status` there returns nothing (and `sudo tailscale` is "command not
found"). **Empty output from that host is not "no peers"** — it is the wrong instrument. Inspect the
network from a tailnet-attached client, or from the Headscale control server itself (it runs as Docker on
the home server, per §Two Layers above).

### Traps, all hit while measuring this
1. **A dead address is not a dead host.** `oldsrv`'s mgmt leg answered nothing (ICMP loss, port 22
   closed) while the box was up **9 d 21 h** (re-probed 2026-09-19; the "12 days" in the first draft of
   that note was not reproducible) and fully reachable on its Home leg — including `enp0s31f6.99`
   reporting `UP` with the right address on it. Before concluding "host down", test the
   **other leg**, then test a hop that must work (the VLAN gateway answered from the same VPS, which
   localised the fault to the host-specific path rather than the tunnel).
2. **OpenSSH matches on the hostname ACTUALLY TYPED — but the inventory carries the jump, so an alias
   block is not what makes Ansible work.** The observed split before 2026-09-19: `ssh pi` ✅ (alias with
   `ProxyJump`) while `ansible pi -m ping` ❌ (Ansible types the inventory IP; nothing matched, no jump).
   The **fix is the group var** (`ansible_ssh_common_args`), and that was proven with a stub ssh config
   holding only `Host vps`: all four behind-NAT hosts ponged. The `Host <ip>` blocks in §The laptop alias
   contract are for `scp`/`rsync`/`git` and for humans who type addresses — useful, not load-bearing.
   (The old wording here said a node "needs BOTH"; measured 2026-09-19 that is over-strict.)
3. **`-e ansible_host=<ip>` is a GLOBAL extra-var — it corrupts `delegate_to`.** Using it to reach
   oldsrv's Home leg produced `ok=367 changed=52 failed=1`, where the one failure was a
   `delegate_to: pi` task that connected to **oldsrv's** address looking for `/root/.ssh/ha-sync.pub`.
   The file exists on the Pi; the task never ran there. A scoped override needs
   `--limit` + a per-host `host_vars` change or a group-level var — not a global `-e`.
   **Now moot by construction (HD-397):** oldsrv's `ansible_host` IS the Home leg, so no run needs the
   override at all — re-verified 2026-09-19: the same delegated task returned
   `ok: [oldsrv.kogler.si -> pi.kogler.si(<Pi Home addr>)]` off-LAN with no `-e`. Do not reintroduce
   the pattern.
4. **A `--check` that fails is not a reachability failure.** The full `home_servers.yml --check` reports
   `unreachable=0 failed=1` because `technitium-seed.yml:102` reads the result of a `uri` task that does
   not run in check mode. Read the RECAP's `unreachable` counter for the path question; read `failed`
   for the play's own defects (the class is catalogued in
   [deployment-ansible.md](deployment-ansible.md) §Dry-run Mode).
5. **A backgrounded `cd X && nohup … &` takes the `cd` into the subshell** — the foreground shell stays
   where it was. Measured 2026-09-19: a reachability probe written that way silently ran against the
   **primary** checkout instead of the session worktree and reported "the group var does not carry the
   jump" (it saw the pre-change mgmt address). Always `cd` first, then background the command — and
   print `pwd` + `git rev-parse --abbrev-ref HEAD` in any measurement you intend to quote in a doc.

**Also worth knowing off-LAN:** the Pi is a **toggle-only Slovenian exit node** (egress, not ingress —
see the section below), and the tailnet does **not** bridge the home LAN, so `10.10.x.x` is unreachable
over it by design.

## Slovenian exit node (decided 2026-09-10) — Pi, toggle-only

**Purpose:** when abroad, reach `rtvslo.si` and other Slovenia-only content without geo-limitations — a **genuine Slovenian residential IP** (home WAN) is the most geo-acceptable egress (datacenter IPs are often blocked).

- **Node:** the **Pi** (reliable tier) runs **native `tailscaled` in kernel mode** (`/dev/net/tun`) as a tailscale exit node — `tailscale up --advertise-exit-node`. **Not** the router (RouterOS has no tailscaled; would be a manual WireGuard peer, losing the app toggle) and **not** oldsrv (disposable tier — the exit node must be available exactly when travelling).
- **Selection is client-side and toggled:** the phone/laptop picks the Pi as exit node in the Tailscale app **only when** a Slovenian IP is needed (then switches back). Not always-on — so home power/ISP is never a dependency for everyday phone traffic.
- **Headscale double opt-in:** the Pi advertises `0.0.0.0/0`, the control server must **approve the route** (manual, headscale CLI), and the policy needs an **`autogroup:internet`** rule (new concept for the user-email-based `policy.hujson`) so tailnet members may use it.
- **Ceiling while on:** the Pi 4 CPU + the home upload cap mobile throughput (~100–300 Mbit/s, single stream OK). Android tailscale supports **per-app split tunneling** to scope it; iOS is all-or-nothing.
- **Alternative (future, only if home fails acceptance/speed):** a Slovenian VPS terminated at the VPS, policy-routed for RTV-bound traffic.

## Family Usage Scenarios

| Situation | How to Connect |
|-----------|---------------|
| **At home** | "Kogler" SSID, `kogler.si` dashboard |
| **Traveling** | Tailscale app → tap Connect (mobile mesh) |
| **Remote (anywhere)** | Tailscale → access Immich, OpenCloud, HA |
| **Office MCP bridges (Windows clients)** | Expose the per-client **Office MCP server** over the Headscale interface only (token-auth, no public) so a server-side **Open WebUI** can call Word/Excel/PowerPoint tools. See [`services-office.md`](services-office.md) (HD-106–111). |