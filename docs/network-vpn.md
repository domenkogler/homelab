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
> `stats.ts.kogler.si`). The **plain `*.kogler.si` names resolve via the tailnet's configured nameserver
> for `kogler.si` (Technitium VPS primary, HD-299)** — requires the static **Technitium A records →
> `tailnet_sidecar_ip` on EVERY instance** ([`network-dns.md`](network-dns.md) static-records section;
> without them the plain names NXDOMAIN on tailnet devices while the `.ts` twins work). There is NO public
> `*.kogler.si` record for these. The tailnet Traefik edge (`traefik-tailnet`, node `vps-obs`) is the
> only tailnet surface for the admin dashboards (see the compose template
> `docker_services/traefik-tailnet` for the routing + serve details).
>
> **Mgmt-99 SSH from the laptop — direct (2026-09-08, replaces the Pi-hop):** the laptop now reaches the Mgmt
> plane **directly** via the Windows **Mgmt99 vNIC** (`wsl-nat-resolv.ps1 -EnableMgmt99`: `.99.80` + forwarding),
> so **no ProxyJump `pi` hop is needed anymore**. Preconfigured `~/.ssh/config` aliases (concrete IPs:
> [`network-addresses-generated.md`](network-addresses-generated.md)):
> - **SSH console:** `ssh router` (→ router mgmt .99.1, user `ansible`), `ssh switch` (→ CRS328 mgmt .99.2),
>   `ssh oldsrv` (→ .99.30), `ssh pi` / `ssh pi99` (→ Pi Home .1.20 / Mgmt .99.20 — the one dual-leg exception),
>   `ssh ap-spalnica/ap-dnevna/ap-spare` (→ APs .99.4/.5/.6). **All direct — no ProxyJump.**
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
| dsh | cockpit :3080 | **none** (ACL is the gate) | tag:dsh |
| vps-obs (`traefik-tailnet` + its userspace sidecar, HD-135b follow-up) | **clean subdomain URLs over the tailnet** — `stats`, `sec`, `traefik`, `logs`, `csui`, `auto` (n8n) and their `*.ts.kogler.si` twins: `https://stats.kogler.si` / `https://stats.ts.kogler.si`, `https://logs.kogler.si`, `https://csui.kogler.si`, `https://sec.kogler.si`, `https://traefik.kogler.si`, `https://auto.kogler.si` — **no ports** (wildcard certs + second Traefik edge) | plain `*.kogler.si` = Authentik Forward-Auth; **`*.ts.kogler.si` = ACL-gated** (tailnet-only names, `tag:sidecar:443` is the gate) | tag:sidecar |
| pi-dev | TUI/CLI agent (`services-internal`) | scoped LiteLLM key + PR-only Forgejo | tag:pi-harness |
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

## Family Usage Scenarios

| Situation | How to Connect |
|-----------|---------------|
| **At home** | "Kogler" SSID, `kogler.si` dashboard |
| **Traveling** | Tailscale app → tap Connect (mobile mesh) |
| **Remote (anywhere)** | Tailscale → access Immich, OpenCloud, HA |
| **Office MCP bridges (Windows clients)** | Expose the per-client **Office MCP server** over the Headscale interface only (token-auth, no public) so a server-side **Open WebUI** can call Word/Excel/PowerPoint tools. See [`services-office.md`](services-office.md) (HD-106–111). |