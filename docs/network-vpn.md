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
| **Mobile Mesh** | **Headscale** (self-hosted Tailscale) | VPS Docker (public coordination) | Family phones/devices — easier app, wife-friendly |

> **Strategy:** WireGuard is **site-to-site only**. User devices use Headscale. There is **no** WireGuard
> road-warrior endpoint and **no** travel router — Headscale replaces them, and nothing falls back to them.
> **Planned exception (not yet built):** one **admin-only** path — **MikroTik Back To Home**, WireGuard with
> MikroTik relay fallback. It does not restore the *family* road-warrior surface. Two caveats must be cleared before
> it is built: it writes router config outside `roles/router`, which the converge rebuilds, and it adds a vendor
> relay. Whether it takes the **direct** WireGuard path or silently uses a **MikroTik relay** is unverified and must
> be measured when it is built.

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

> **Least-access:** the VPS S2S peer's **AllowedIPs** (both sides) cover **only** the scoped home targets —
> `nas` (nut:9199 / zfs:9198), `ha-vip` (HA:8123), `oldsrv` + `pi` (probes / app backends when wired), `router`/`switch`
> (ICMP) — **not** the whole `site` /16. The RB4011 additionally enforces a forward ACL (`vps_s2s_peer` →
> `vps_scoped_home` accept, else drop). See [`security.md`](security.md) §9.

> **The VPS-side tunnel is not a plain systemd-networkd setup — mechanism, do not "simplify" it:**
>
> - **Two distinct keypairs (never one).** Each side needs its own keypair: the router uses
>   `wg_password` (pub `wg_s2s_router_public_key`), the VPS uses `wg_password_vps` (pub
>   `wg_s2s_vps_public_key`); each side's peer entry = **the other side's** pubkey. A single shared key
>   makes the interface pubkey and its own peer pubkey identical, and **WireGuard refuses to handshake
>   with your own key** — the tunnel never comes up and there is no error.
> - **networkd 257 does not apply `[WireGuardPeer]`.** On kernel `6.12.x` + systemd 257, networkd creates
>   the interface (key/address/listen) from the `.netdev` but **silently never applies the peer block**, and
>   while networkd owns the interface it strips manual `wg set peer` edits. `wg show` then shows no peer —
>   `wg setconf` also silently drops the peer if the conf carries a `PrivateKey` line.
>   **Therefore:** networkd only CREATES `wg-s2s` (minimal `.netdev` + `Unmanaged` `.network`); the role
>   renders a **peer-only** `wg-s2s.conf` (NO `PrivateKey` — the key stays in the `.netdev`, 0640) and ships
>   the `wg-ensure-s2s-peer` oneshot (`PartOf=systemd-networkd.service`) that owns the interface:
>   create-if-missing → assign address → `wg setconf` (key-only) → `wg set … peer`, verified every run.
> - **`wg set` installs NO routes.** Plain `wg set peer` populates AllowedIPs but adds no kernel route —
>   only `wg-quick`/`wg setconf` do, and only at setup. So a **newly added AllowedIPs entry gets no route**
>   and its traffic silently goes out the public interface (this is exactly how a newly added home host
>   stays unreachable from the VPS while the tunnel looks up). The oneshot therefore runs
>   `ip route replace <cidr> dev wg-s2s` for **every** AllowedIPs entry (idempotent; `replace` also
>   clobbers a stale wrong-device route back onto `wg-s2s`; non-fatal WARN on failure) on every run/boot —
>   nothing else restores them while the interface is `Unmanaged`.
> - **Router forward ordering:** the `VPS S2S -> scoped home targets` accept must sit **above** the
>   `Default deny inter-VLAN` rule, or it is shadowed (see [network-ops.md](network-ops.md) §Ordering pitfall).

## Layer 2: Headscale (Mobile Mesh)

> **Naming + policy contract:** headscale ≥ 0.24 REJECTS a
> `server_url` inside `base_domain`, so node names live under the dedicated subtree
> **`<node>.ts.kogler.si`** (`base_domain: ts.kogler.si`); the control plane stays
> `https://vpn.kogler.si`. **The ACL is deny-by-default:**
> each family user (by OIDC email) may reach only their OWN nodes (see `policy.hujson.j2`; currently single user
> `domen@kogler.si`). Enrolment itself remains Authentik-OIDC-gated; add one accept rule
> per family member as they join.

- Runs on the **VPS** as a Docker container (public coordination server, VPS residency)
- Overlay subnet: `headscale` (CIDR per SSOT)
- Clients: Android/iOS Tailscale app, laptops
- **Home RB4011:** static route + firewall rules so the Headscale overlay reaches the Home VLAN
- **MagicDNS:** `dns.extra_records` maps the tailnet dashboard
  subdomains (and their `*.ts.kogler.si` twins) to the
  `vps-obs` tailnet IP (`tailnet_sidecar_ip`, group_vars/vps.yml).
  **Answer scope:** Tailscale client MagicDNS ANSWERS only its
  `base_domain` (`ts.kogler.si`) — the `*.ts.kogler.si` twins work out of the box. For a FQDN
  matching a `search_domain` (`kogler.si`), the client queries its **configured nameserver for
  that domain**, NOT MagicDNS — so unless the MagicDNS loop is first in `dns.nameservers` (see
  §Tailnet-exposed services) the plain `*.kogler.si` names resolve through Technitium
  (VPS primary), which carries the split-horizon A records → `tailnet_sidecar_ip`
  (see [`network-dns.md`](network-dns.md) static-records section).
  `dns.search_domains: [kogler.si]` is set (helps short-name resolution) but does NOT make MagicDNS
  serve the plain names.
- **VPS:** routes the home `site` + `wg-vps-services` over the S2S tunnel to reach home resources
- **Mesh clients** → VPS Headscale (public, its purpose) → over S2S → home LAN; each node has an ACL-gated path home
- **Registration & ACL:** OIDC-authenticated clients are **auto-approved** by
  Headscale (no separate registration gate in `config.yaml`). The traffic boundary is therefore a **real
  ACL policy** (`policy.hujson`, rendered alongside `config.yaml`). **User-based (current):**
  deny-by-default — each OIDC user's email may reach only that user's own nodes; `tagOwners` stays empty
  because headscale v2 requires tags be DECLARED before an ACL may reference them and there is no
  `autogroup:admin` source here, so ACLs are user-email-based. **Tag model for later:** if/when a
  shared-service `tag:kogler` is wanted, declare it + its owner in `tagOwners` and
  switch these rules to `tag:kogler:*` (only the mesh admin applies the tag; untagged/rogue nodes are
  denied by default).

### Admin UI: Headplane (`https://vpn.kogler.si/admin`)

> Stock Headscale has **no built-in web UI** — visiting `https://vpn.kogler.si` returns a 123-byte
> empty shell (`BlankPage()` template, upstream by design). Administration happens through
> [Headplane](https://github.com/tale/headplane), co-deployed as a second service in the same
> compose project (service DNS `http://headscale:8080`, no extra exposure).

- **URL:** `https://vpn.kogler.si/admin` (dashboard prefix is built into headplane; Traefik routes
  `Host(vpn.kogler.si) && PathPrefix(/admin)` — longer rule wins priority over the control-plane
  router, so `/ts2021`, DERP and `/oidc/*` are untouched). Same crowdsec-only tier.
- **Auth:** OIDC via Authentik, deliberately the **same OAuth client as Headscale itself**
  (upstream best practice: identical `client_id`) — the `ks-oidc.yml` provider also carries the
  `…/admin/oidc/callback` redirect URI. First login becomes the Headplane **owner**; later users
  get `default_role: member`. `disable_api_key_login: true` (API-key field removed — recovery =
  temporarily set false + re-render if the IdP ever breaks).
- **Headscale API key (required for OIDC mode):** mint ONCE on the VPS —
  `docker exec headscale headscale apikeys create --expiration 8760d` — store in 1Password
  `headplane_api`.`credential`. Cookie secret (32 chars) lives in `headplane_password`.`password`
  (**Password category → lookup `field='password'`, NOT `credential`**;
  a `credential` lookup returns empty → headplane crash-loops on `missing required fields`).
- **Capabilities:** node/user management, pre-auth keys, read-only Settings view (headscale's
  rendered `config.yaml` is mounted `:ro`). Docker-socket integration (DNS editing from the UI,
  restart headscale on change) deliberately NOT wired — future hardening with a socket proxy.
- **Config = YAML-safe block scalar `>-` for every secret** (client_secret, cookie_secret, api_key) —
  a rotated secret containing `:` `"` `'` `?` breaks inline-quoted configs (`YAMLException`/`EISDIR`
  crash-loops on BOTH headscale + headplane). See
  `deployment-secrets.md` "Rendering a secret into a YAML config file" + CONVENTIONS §2.

---

## Tailnet-exposed services (management plane)

> **Policy (security.md §10 Capability-tiering):** internet-facing surfaces hold only limited-capability
> credentials; full-power access requires tailnet membership. **New admin/UI surfaces default tailscale-first**
> -- never Traefik-public unless explicitly decided. Applied to the AI stack
> ([services-ai.md](services-ai.md)) and the **observability admin dashboards** —
> `stats`/`traefik`/`logs`/`csui`/`auto` are tailnet-only with **no public records**.
>
> **Laptop access:** with the Tailscale app connected, the dashboards resolve on the tailnet — headscale
> **MagicDNS** on the `ts.kogler.si` base domain answers the `*.ts.kogler.si` twin names (e.g.
> `stats.ts.kogler.si`), and `dns.extra_records` maps every tailnet subdomain (incl. `llm`/`db-spark`/
> `litellm`) in BOTH namespaces to the `vps-obs` edge (`tailnet_sidecar_ip`).
> The `dns.nameservers` list puts the **MagicDNS loop first** — so a tailnet client resolves
> EVERY `*.kogler.si` / `*.ts.kogler.si` name **locally on any network** (hotspot/travel), not only when the
> Technitium VPS primary is reachable. The Technitium entries (VPS primary + oldsrv + Pi) follow, giving the
> full namespace + per-subnet filtering on the LAN. Without the loop-first ordering the plain names depend on
> the configured nameserver for `kogler.si` (Technitium VPS primary, reachable only from home-WAN /
> tailnet-CGNAT by source-allow), so a remote mobile network falls through to the system resolver →
> NXDOMAIN / `ERR_NAME_NOT_RESOLVED`, while the `.ts` twins keep working. On Windows the client also needs
> the loop pushed onto the Tailscale adapter (`netsh … set dnsservers Tailscale 100.100.100.100`).
> There is **no public `*.kogler.si` record** for these names. The tailnet Traefik edge (`traefik-tailnet`,
> node `vps-obs`) is the only tailnet surface for the admin dashboards (see the compose template
> `docker_services/traefik-tailnet` for the routing + serve details).
>
> **Mgmt-99 SSH from the laptop — same-site only (owner decision A, §The settled rule):** the laptop reaches the Mgmt
> plane **directly** via the Windows **Mgmt99 vNIC** (`wsl-nat-resolv.ps1 -EnableMgmt99`: the laptop's `.99.80`
> address + IP forwarding) — no ProxyJump hop, and **no away path**: the plane is sealed from the VPS tunnel on
> purpose. It is usable **on-site AND only when that adapter actually has link** — verify with `ip -br addr`
> in WSL: a VLAN-99 route must be present, not just `eth0`.
> The alias list is NOT kept here (it drifts): the SSOT is **§The laptop alias contract** below — one table
> for both `~/.ssh/config` files (WSL + Windows).
> Short version: `router`/`switch`/`ap-*`/`pi99`/`oldsrv99`/`nas99` = Mgmt, jump-less, on-site;
> `pi`/`nas`/`oldsrv`/`spark` = Home leg + `ProxyJump vps`, anywhere.
> - **Winbox GUI:** RouterOS binds winbox (8291) to the Mgmt VLAN only, so from the Mgmt plane point Winbox at
>   the device Mgmt IP (`.99.x` per [`network-addresses-generated.md`](network-addresses-generated.md)).
>   There are no `*-wb` LocalForward aliases and no Pi-dial pattern — direct from the on-site Mgmt leg.
>   **Design constraint:** because winbox binds to the Mgmt VLAN only, reaching it from the Home laptop is
>   blocked by design.

### Pattern A -- loopback-capable apps (preferred)
App binds `127.0.0.1` only; tailscale sidecar shares its network namespace (`network_mode: service:<app>`) and
`tailscale serve` proxies the tailnet socket to the loopback port. **Nothing listens on shared overlay networks**
-- nothing on `services-internal` can even reach it.

### Pattern B -- apps bound to `0.0.0.0`
Dedicated per-service docker network containing ONLY app + tailscale sidecar (never `services-internal` for the UI leg);
sidecar serves to the app over that private network. Functional service-to-service legs stay on their own overlays.

| Node | Serves | App-level auth | ACL tag |
|------|--------|----------------|---------|
| ~~dsh (on oldsrv)~~ | ~~cockpit :3080~~ | **PARKED** — backend gone; its tailnet route + DNS record remain and answer 502. Pattern-A, not B. |
| vps-obs (`traefik-tailnet` + its userspace sidecar) | **clean subdomain URLs over the tailnet** — `stats`, `traefik`, `logs`, `csui`, `auto` (n8n), and the AI names `db-spark`, `llm`, `litellm` plus their `*.ts.kogler.si` twins: `https://stats.kogler.si` / `https://stats.ts.kogler.si`, `https://logs.kogler.si`, `https://csui.kogler.si`, `https://traefik.kogler.si`, `https://auto.kogler.si`, `https://db-spark.kogler.si`, `https://llm.kogler.si` (spark OpenAI-API, bearer-gated), `https://litellm.kogler.si` (spine admin) — **no ports** (wildcard certs + second Traefik edge). `litellm` reaches the edge through the `tailnet-apps` app→edge overlay, not `services-internal` | plain `*.kogler.si` = Authentik Forward-Auth (AI names: engine/LiteLLM own-login, no forward-auth); **`*.ts.kogler.si` = ACL-gated** (tailnet-only names, `tag:sidecar:443` is the gate) | tag:sidecar |
| ~~pi-dev (on oldsrv)~~ | ~~TUI/CLI agent~~ | **PARKED** — backend gone, no LiteLLM consumer; its tailnet route + DNS record remain and answer 502. |
| litellm-ui | admin :4000/ui | bearer keys | tag:litellm |
| owui-int (`ai.kogler.si`) | internal OWUI | Authentik OIDC | tag:owui-int |
| openclaw | control/gateway | gateway token | tag:openclaw |
| headplane | mesh admin `/admin` | OIDC | tag:mgmt |

- Serve mode: plain TCP forward is simplest (WireGuard already encrypts); HTTPS mode needs Headscale TLS config -- verify at deploy.
- ACL defaults: inbound-only per node; tag hygiene audit quarterly.
- **Tailnet dashboard edge — LIVE:** `traefik-tailnet` (consumer-mode Traefik + a userspace
  tailscale sidecar sharing its netns, node `vps-obs`) serves the admin dashboards over the tailnet with clean
  subdomain URLs on port 443 (`tailscale serve --tcp=443` → the edge's TLS listener), see
  `docker_services/traefik-tailnet` + `policy.hujson.j2`.
- **WG/tailnet reach for the internal edge — this doc is the SSOT:** ✅ LIVE. The internal all-app edge
  (`traefik-tailnet`) is reached two ways:
  - **Tailnet (existing):** the `vps-obs` userspace sidecar already serves `--tcp=443` → the edge's TLS listener; family nodes are ACL-allowed (`policy.hujson`, deny-by-default + per-user own nodes). No change unless the ACL needs extending for a new family member.
  - **WireGuard S2S:** the internal edge's TLS listener (:443, the edge container IP is pinned) is published **only on the `wg-s2s` VPS address** (`{{ wg_s2s_vps.ip }}:{{ wg_internal_edge_port }}`, the vps.yml SSOT port) via the traefik-tailnet compose `ports:` (docker's own PREROUTING DNAT → container `:443` — same precedent as `kopia-server :51515`; no manual nftables DNAT). An **nftables input allow** (vps-hardening pattern: `iifname "wg-s2s" ip saddr <router peer> tcp dport {{ wg_internal_edge_port }} accept`) is added for defense-in-depth. SSOT: `wg_internal_edge_port` / `wg_internal_edge_target_ip` in `group_vars/vps.yml` (derived-values ban — never re-type in compose/nftables/docs).
  - **Reach scope (least-access):** the VPS wireguard peer `wg_s2s_vps.allowed_ips` accepts ONLY home infra hosts (`nas/ha-vip/oldsrv/pi/router/switch` — group_vars/all/main.yml). So the internal edge is reachable over WG **from those scoped home hosts**. End-user devices (laptop/phone) at home use the **tailnet** path (sidecar + headscale ACL) — WG is the infra/automation path, not the family path.
  - **Deploy verify (after a VPS `docker_services` converge `docker_services_scope=traefik-tailnet` + `vps-hardening`):**
    1. VPS-side listener: `ss -ltnp | grep :{{ wg_internal_edge_port }}` → bound to the `wg-s2s` VPS address (`{{ wg_s2s_vps.ip }}:{{ wg_internal_edge_port }}`).
    2. From a scoped home host over WG (e.g. `oldsrv`/`nas`/`pi`): `curl -k -I https://<wg-s2s VPS address>:{{ wg_internal_edge_port }}` → HTTP/2 302 (or the edge's TLS response); split-horizon alternative once the `vpn/home/dns` records are seeded: `curl -k -I https://kogler.si -H 'Host: kogler.si'` resolved via the tunnel, or `https://{{ wg_internal_edge_target_ip }}:{{ wg_internal_edge_port }}` from a scoped home host.
    3. Tailnet path unchanged: tailnet device → `https://stats.kogler.si` / `https://<app>.ts.kogler.si` still works.
    4. Heading home with Tailscale on reaches `ha.kogler.si` via the LAN (Option A).
  - **Tailnet ACL:** `policy.hujson` already allows family nodes → `tag:sidecar` on :443 (deny-by-default + per-user own nodes). No extension needed for the existing owner set; extend only if a new family member node is added.

**Parked names stay published, and their 502 is the design.** `dsh.kogler.si` / `pi-dev.kogler.si` and
their `.ts` twins keep their headscale `extra_records` **and** their `traefik-tailnet` routers, even though the
backends are gone: the `dsh-backend` / `pi-backend` load-balancer URLs point at `oldsrv:3080` / `oldsrv:8080`
over the WG S2S, where nothing listens. So the names resolve
and the edge answers **502** — that is not an outage to chase, and `group_vars/vps.yml` says so where the
records live. Deleting them is a decision of its own, because it deletes MagicDNS records: do it as ONE change
that drops the `tailnet_subdomains` entries, the routers and the two service blocks together.

**A published name is only as live as the node it points at.** `tailnet_ts_only_subdomains`
entries inherit `ip: tailnet_oldsrv_ip` unless they say otherwise, so `cockpit-nas.ts.kogler.si`
resolves to the **oldsrv node's** address while
`headscale nodes list` reports that node **offline**. Resolution succeeds and the console is unreachable anyway:
a MagicDNS record is a pointer to a *node*, not to a service, so the question a `.ts` name ever answers is
"is that node up", never "is that app up". Re-pointing such a record at a live node is a routing decision, not a
fix — the target must actually serve the route. ⚠ **And the obvious read-back instrument is missing at home:**
the Pi does not accept tailscale DNS (`/etc/resolv.conf` is `1.1.1.1`, not `100.100.100.100`), so it cannot resolve
any `.ts` name and proves nothing about a record; a `.ts` read-back needs a client with MagicDNS enabled.
The overlay's live user is `litellm`.

### Reach matrix for the tailnet-only admin names

> The symptom: **a tailnet-only name works on the phone but 404s on the laptop with Tailscale
> connected at home.** Two different resolver paths answer the same name:
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
>
> **Practical answers, in order:** (1) use the **`.ts` twin** — `litellm.ts.kogler.si` exists only in
> MagicDNS/extra_records, so it cannot be hijacked by the LAN answer;
> (2) keep Tailscale connected at home (the documented posture: end-user devices at home use the tailnet
> path); (3) a durable LAN-native fix would mean home-seeding `litellm` → `oldsrv_home_ip` + a
> `traefik-internal` router proxying over WG S2S to the internal edge (`:4443`) — that
> **exposes the key-holding spine's admin UI on the LAN edge**, a design change that needs its own
> decision; not built.
>
> **The spark AI names (`llm`/`db-spark`) work differently:** for them "use the
> `.ts` twin" is a dead end by itself — MagicDNS answers both namespaces to the tailnet edge and the edge's
> `llm-tailnet`/`db-spark-tailnet` routers match, but the
> TLS-in-TLS backend hop **forwards the client's SNI** to spark's own edge, so spark's Traefik must route the
> `.ts` twin names too (`Host(`llm.ts.kogler.si`)` alongside `Host(`llm.kogler.si`)`); a missing twin router
> answers a routerless-vHost 404 *before* auth, while `litellm.ts` (VPS-container backend, no TLS-in-TLS)
> stays 200. Spark's name edge routes the `.ts` twins and serves the `*.ts.kogler.si` pair. Verify:
> `curl -sk -o /dev/null -w '%{http_code}' https://db-spark.ts.kogler.si/` → 200;
> `curl -sk -H "Authorization: Bearer <spark-llm_api>" https://llm.ts.kogler.si/v1/models` → 200.
>
> **The client-side half — plain names failing from WSL/Windows is a workstation resolver problem, not a
> service bug.** With Tailscale connected, the **plain** `*.kogler.si` names fail from WSL/Windows when the
> plain namespace is not routed to MagicDNS **on that client**:
> WSL's auto-generated `resolv.conf` carries only the NAT forwarder, and the Windows NRPT carves only
> `*.ts.kogler.si` + the CGNAT reverse zones. Two durable client-side changes fix it (both on the laptop,
> neither in Ansible):
>
> 1. **WSL:** `/etc/wsl.conf` → `[network] generateResolvConf=false`, then a **static** `/etc/resolv.conf`
>    with `nameserver 100.100.100.100` (the MagicDNS loop) **first** and the previous forwarder after it.
>    Without `generateResolvConf=false` WSL rewrites the file on every start and the fix silently vanishes.
>    (This is what `scripts/wsl-nat-resolv.ps1` automates — see [network-vlans.md](network-vlans.md) §Port model.)
> 2. **Windows:** `netsh interface ipv4 add dnsservers name="Tailscale" address=<tailnet_magicdns_loop 100.100.100.100> index=1 validate=no`
>    from an **elevated** shell — it lands on the adapter and survives reconnects/reboots.
>
> **Diagnosis order that finds this fast:** prove the server side first (`nsenter`/on-box `curl` against
> spark's edge with an explicit SNI), then question the client's resolver. A `Host=` curl from the box that
> succeeds while the laptop fails = client DNS, every time. A routerless-vHost 404 on a `.ts` name and a 502
> on the plain name are two different layers — do not conflate them.

## Tailnet boundary — mobile devices + the home nodes, never a LAN bridge

The tailnet is **not a home-LAN bridge**. Two distinct reach shapes exist, and the difference matters:

* **Via the VPS edge (the family default):** `mobile → tailnet → VPS traefik-tailnet → (WG S2S) → home backends`.
  Every `*.{ts.,}kogler.si` app name works this way, and it survives a home-WAN outage but **not a VPS outage**.
* **Node-direct:** `mobile → a home node's own tailnet node`. The VPS carries **no byte of the
  data plane** — only the control plane (registration/netmap, and DERP if hole-punching fails). This exists so
  the owner's own remote development does not stop when the VPS does, and it is possible because
  [network.md](network.md) §WAN is a **static public IPv4** — P2P is available.

**Two home nodes are permitted on the tailnet, and the NAS is not one of them**
(the decision is logged in [network-rejected.md](network-rejected.md)). Node **`oldsrv`**: `tag:dev`,
headscale node id 11, joined by `roles/tailscale-node`. Node **`pi`**:
headscale id 13, address in SSOT `tailnet_pi_ip`, tag `tag:home-edge`, granted **`tcp/443` from
`domen@kogler.si` and nothing else** — and the tag is **read back** from `headscale nodes list -o json`
rather than trusted from the mint command, because the grant follows whatever tag the node actually landed
with.
✅ `https://pi.ts.kogler.si/` → **200** from a laptop's own tailnet client, the peer
listed as `active; direct 193.77.156.222:41641` — a direct session, no relay.

⚠ **`tag:home-edge` is deliberate, and the tag IS the reach surface.** An ACL grants by TAG, so joining the
Pi as `tag:dev` would widen every existing `tag:dev` rule to a second box (the DNS-tertiary host) and hand it
every dev-seat port someone adds later — a silent-inheritance hazard — while a
dedicated tag keeps the Pi's entire inbound tailnet surface at the one `ha` listener.
For the same reason the Pi gets **no** tailnet `udp/53` grant and none may be inferred from oldsrv's rule below: the Pi's
Technitium TERTIARY role is a LAN role (network-dns.md §The answer-plane model), and naming a tailnet
nameserver is its own address-scoped decision. What the Pi does serve there is HA, from its own `traefik-ha`
`websecure-ts` listener (`ha.ts.kogler.si` / `pi.ts.kogler.si`, XFF stripped, no Forward-Auth) — the same
node-direct shape as oldsrv's, which is what makes HA survivable when either home box dies.

⚠ **The edge survives either box; the ANSWER does not yet.** MagicDNS answers `ha.ts.kogler.si` with
**oldsrv's node address** (SSOT `tailnet_oldsrv_ip`), so when that node is not answering the away path that
still works is `pi.ts.kogler.si`. Publishing **both** addresses (`tailnet: dual`) is what makes the answer
survive either box.

`tailscale_node_expected_ip` (host_vars) is the **per-host** address the join guard compares the assignment
against — its default is `""`, which reads as "not yet asserted", not as "wrong".

The scope is enforced, not intended:
no `--advertise-routes` (so `headscale routes list` stays empty and no home subnet is reachable from the
tailnet at all), no exit node (the exit node stays the Pi — §Slovenian exit node), no Tailscale SSH,
`--accept-dns=false` (oldsrv *runs* a Technitium instance; a DNS takeover would put a resolver in front of
the tier it serves), and the ACL admits **`tag:dev:443`** plus **one DNS rule** — `udp 53` to that node's own
address, written on the address rather than on the tag so a second `tag:dev` node cannot inherit a resolver
grant (docs/network-dns.md §The resolution requirement). Port 443 and UDP/53 on one node,
not `:*` on the box that holds the vault token — and no TCP/53, no other port, nothing by tag. The boundary's
purpose survives on purpose: Shelly/KNX/IoT/guest stay
non-tailnet-reachable, and VLAN 99 keeps its seal (decision A).

Because a preauth-key node lands in headscale's synthetic `tagged-devices` user rather than the owner's
user, `dst: ["domen@kogler.si:*"]` cannot reach it — the ONLY path in is the explicit `tag:dev:443` rule in
`policy.hujson.j2`. Joining by interactive OIDC login instead would put the node under the user and inherit
`:*`; the preauth key is therefore a security control, not just a bootstrap convenience.

**What oldsrv serves on that node** is its own home edge (`traefik-internal`, a `websecure-ts` entrypoint
bound to the **node's tailnet IP** — never `0.0.0.0`), with TLS from the already-synced `*.ts.kogler.si`
pair, and the internal zone on **`udp 53`** at that same address (the container's published
port reached by DNAT from `tailscale0`, which is what makes the node usable as a tailnet nameserver).
Exactly one route is exposed there: `ha-ts` → `ha.ts.kogler.si` (+ the free node name
`oldsrv.ts.kogler.si`) → the HA VIP. This node-direct `.ts` route is HA's only away-from-home path: no public
record, no `traefik-tailnet` route, and a VIP-only listener. The plain `ha.kogler.si` name
stays LAN/VIP-only — see [network-dns.md](network-dns.md) §Split-Horizon, which owns the one-URL plan for it.

**The join is guarded:** tailscaled's control URL is asserted to be this
headscale by a fail-loud guard in `roles/tailscale-node`, and `/etc/resolv.conf` on oldsrv stays untouched
(`--accept-dns=false`). The node lands in headscale's `tagged-devices` user with **zero advertised routes**.

**What that node answers:** `dig @<MagicDNS loop> ha.ts.kogler.si` → the oldsrv node address; **443 open,
80/22/8081 blocked** (the ACL is port-scoped); SNI `ha.ts.kogler.si` → `CN=*.ts.kogler.si`, issuer Let's
Encrypt, `ssl_verify_result=0`, **401** — Home Assistant answering behind the proxy, which is the intended
answer. A loopback `curl` to the name returns **HTTP 000** because `websecure-ts` binds the node's tailnet IP
only: probe `tailnet_oldsrv_ip` (group_vars) and it answers 200 in ~21 ms. `headscale routes list` does not
exist in this headscale build (no `routes` subcommand) — read the netmap view.

> **Traefik matcher and certificate-path constraint.** A Jinja expression must sit in the same token as the
> text around it. A rendered space inside a `Host(…)` matcher makes the router unable to match any request — it
> answers its default 404 while the entrypoint, the ACL, the extra_record and the backend are all healthy — and
> a rendered space in a `certFile:` path makes Traefik serve its generated `CN=TRAEFIK DEFAULT CERT` **without
> failing to start**. Both are silent at runtime and survive `--check`, so
> `scripts/check_traefik_host_rules.py` validates matchers and quoted certificate paths (mutation-tested).
> Verify without `-k`: the flag switches off the only check that detects the certificate half.

**Reach of these names from a phone, by radio state.**

| name | Wi-Fi on + tailnet on | Wi-Fi on + tailnet off | Wi-Fi off + tailnet on | Wi-Fi off + tailnet off |
|---|---|---|---|---|
| `ha.ts.kogler.si` | ✅ | ✗ by design (the name lives in the netmap) | ✅ | ✗ by design |
| `ha.kogler.si` | ✅ | ✅ | ✗ (advisory chain) | ✗ (no LAN DNS, no WAN) |
| `media.kogler.si` | ✅ | ✅ | ✗ (advisory chain) | ✗ |

- Android answers a `.ts` extra_record **client-side from the netmap**, so a tailnet twin needs no resolver
  reachability at all, and the `*.ts.kogler.si` listener serves a publicly-trusted chain with no internal CA on
  the device. The pattern is portable: any home app gets an away path from a `.ts` twin + a router on the same
  listener — cheaper than making a whole zone resolve over the tailnet.
- **`override_local_dns: false` makes the resolver chain headscale delivers advisory:** a client keeps its own
  resolver for `kogler.si`, so a device on cellular can fail to resolve an internal-zone name. The answer is a
  reachable record per name (a `.ts` twin), not resolver ordering. `dns.nameservers.split` and
  `override_local_dns: true` are both declined — [network-dns.md](network-dns.md) §The answer-plane model.
- **The data plane never touches the VPS.** With headscale + headplane stopped
  (`docker compose -p headscale … stop` — `stop`, never `down`) an enrolled node keeps serving from its cached
  netmap, on reload and in a fresh incognito session. **Cold enrollment fails while the control plane is down,
  by design**, and must not be logged as a fault.
- **IoT and guest stay unreachable** from the tailnet: `PrimaryRoutes` is empty on every peer
  (`tailscale status --json`) and no home subnet is advertised.
- **The tailnet's job is to hand out *reachable answers*.** For HA the target is **one URL**:
  `ha.kogler.si` published as an extra_record beside the `.ts` alias, so one address serves home (LAN zone →
  VIP) and away (the node path), and the HA Companion app holds one entry. Pending: publishing **both** home
  node addresses (Pi + oldsrv) as two A records, so the answer survives either box — both home proxies target
  the VIP. ⚠ **Unmeasured:** multi-A fall-over on a real client (expect a timeout on the dead first answer, not
  an instant switch) and MagicDNS returning both records.
- **An "away" claim needs the routing table.** A host with a live wired home path is not off-LAN: probes to
  Home-VLAN and IoT-VLAN addresses from it test the router's inter-VLAN firewall, not the tailnet. Probes to
  tailnet addresses are always valid, because those destinations ride the Tailscale interface. The acceptance
  path is a phone on cellular.

> **HA answers `400 Bad Request` to a proxy it does not trust:** any `X-Forwarded-For` from a source outside
> `ha_trusted_proxies` is rejected. The tailnet router **strips the forwarding headers** rather than changing
> smart-home config; the trust-list fix (`oldsrv_home_ip` in `ha_trusted_proxies`, needs a HA restart) is owned
> by [smart-home-failover.md](smart-home-failover.md).

**An away session from a phone on cellular RELAYS.** Public DERP, 70–90 ms; the reciprocal home→phone test
reports `via DERP(fra)` with `direct connection not established`. The home side has everything a puncher wants —
IPv6 on the Home VLAN with a GUA on oldsrv, an endpoint-independent IPv4 mapping, `tailscaled` on UDP/41641,
unrestricted egress, `UDP: true` and `MappingVariesByDestIP: false` in `tailscale netcheck` — and still does not
establish. Relayed still serves the apps (a `.ts` name answers 200 over it), so this is a quality limit, not an
outage. Method and the counter technique: [network-ops.md](network-ops.md) §IPv6.

- **The block is the phone leg, upstream of this network.** With `log=yes` on the WAN drop rules, **zero**
  packets from the phone arrive on either family across punch bursts, while the same rules log internet scan
  traffic continuously — so the silence is evidence, not an absent probe. A carrier NAT/APN grants the UE no
  unsolicited inbound, and nothing opened here can produce a direct session.
- **The VPS tailnet node needs a pinned AND published listen port.** `tailscale-sidecar` shares
  `traefik-tailnet`'s netns, so `41641/udp` is published on the **netns owner** and the daemon is pinned with
  `TS_TAILSCALED_EXTRA_ARGS=--port=41641`; an unpinned sidecar binds **ephemeral** sockets, which no firewall
  rule can publish, and that node stays relayed. ⚠ Residue: the host publishes **IPv4 only** (no `[::]:41641`).
  [services-vps.md](services-vps.md). This says nothing about the home node's carrier NAT.
- **A self-hosted DERP is not the answer:** a DERP is one more relay leg and the cost lives on the
  phone↔DERP leg, which the VPS's location does not shorten.
- **No inbound hole-punch exception belongs on the router.** A punch makes the far side's packets *replies* from
  the home node's point of view and `established,related` is rule 1 in both v6 chains, so the common case needs
  no inbound accept; and oldsrv's Home NIC is stable-privacy + temporary-address, so there is no destination to
  pin. `41641` therefore appears nowhere in the router converge — by design, not an omission.
- **`tailscaled`'s listen port is pinned:** `/etc/default/tailscaled` `PORT="41641"`, owned by the
  `tailscale-node` role; `ss` shows `0.0.0.0:41641` + `[::]:41641`. ⚠ Netcheck's trailing port on the
  `IPv6: yes, [<GUA>]:<port>` line is the **DERP-side STUN observation** and it varies between runs; the socket
  a peer must reach is 41641.
- **No unsolicited inbound IPv6 reaches the delegated prefix** at all while v4 scans arrive continuously, so an
  `AAAA` record pointing at a home service would be unreachable from the v6 internet. Home publishes none, and the
  ban is enforced by an **operator-side monitoring rule named `nagios-dns-v6`** — no file in this repo implements
  it, so there is no path to cite ([network-vlans.md](network-vlans.md) §IPv6). Not proven from the inside: the
  clean proof is an external v6 prober ([network-ops.md](network-ops.md) §IPv6).
- **The lever that survives carrier NAT is phone-initiated WireGuard:** the router is the responder with a
  public address, so the phone's carrier has no unsolicited inbound to block. The chosen vehicle is **MikroTik
  Back To Home**, deferred.
- **RouterOS rules that read as success while doing nothing:** `place-before=` is **silently ignored** when
  handed the printed `#` number — rule ids are hex `*N`, resolve them with `find`; `find where
  connection-state=established,related` matches **nothing** because the value contains a comma, so match on
  `comment`; `/log` is memory-capped, so a foreign `/system logging` rule can rotate away the window under
  measurement ([network-ops.md](network-ops.md) §Central log shipping).
- **Chain placement:** a WAN packet addressed to a *host* traverses **`chain=forward`**; `chain=input` only ever
  sees traffic addressed to the router itself. An inbound exception for a host belongs in `forward`, above the
  `no unsolicited v6 into any VLAN` drop — an `input` rule would never match, show zero counters, and look like
  success.

**Mobile/media reach — home-hosted services:** home apps (jellyfin, *arr, downloads, seerr, seerrng) are
reachable because **the edge that routes them can dial them**. `traefik-internal` runs `network_mode: host`
on oldsrv and the whole routed group publishes its host port on **loopback**, so an app's bind and its
`*-backend` URL are one variable pair and only ever move together — moving one alone is a silent 502 on that
app. A backend dialled **from another box** is the exception that needs a bind routable across hosts,
`oldsrv_home_ip` — the `actual-budget:5006` / `immich-ml:3003` precedent. Nothing on the VPS dials an app port
here: the public edge carries `media` / `seerr` / `seerrng` only and proxies them to the home edge over the
WG S2S (`https://oldsrv_home_ip:443`, one `servername` transport per name). **Routed is not published:** of those
three, `group_vars/all/main.yml` marks only `media.kogler.si` `public: true`; `seerr` and `seerrng` are routed by
that edge and published nowhere, so their names answer only where a resolver is told. The *arr set and the
downloaders carry no public record at all, and they are **not** LAN-only: their names in
`tailnet_ts_only_subdomains` (`group_vars/vps.yml`) inherit `tailnet_oldsrv_ip` and publish a `.ts` twin on
oldsrv's own `websecure-ts` node listener, so the off-LAN path for that whole set is the tailnet twin, not a
public door. These apps serve their **own login** behind the `crowdsec-only` middleware with no Forward-Auth, and
`media.kogler.si` is the one name published publicly, so that login is the internet-facing surface.

## Reaching LAN nodes when away (hotspot / public Wi-Fi) — the access matrix

**The one-line answer: SSH goes through the VPS jump; service traffic goes through the tailnet edge.
Neither is a property of the laptop's network — the VPS is the only host with a public address, so it
is the door for both.** Addresses come from [network-addresses-generated.md](network-addresses-generated.md);
nothing below hard-codes one.

> **How to read the matrix:** every ✅/❌ is a verified command result, not a config reading (checked
> off-LAN on a mobile hotspot: station egress ≠ the home-WAN DDNS, direct `10.10.x.x:22` probes time out).
> The **on-site** half is a different path — the Mgmt-99 vNIC must actually carry link, so those rows are
> labelled same-site rather than asserted.

| Node | Away-from-home path for **SSH/admin** | Status |
|---|---|---|
| **vps** | direct — `vps.kogler.si` is public | ✅ the door itself |
| **oldsrv** | alias `oldsrv` → **Home leg** + jump; the jump is also carried in `group_vars/home_servers.yml`, and `ansible_host` IS the Home address | ✅ `ssh oldsrv` and `ansible … -m ping` green with **no `-e`**; `home_servers.yml --check --limit oldsrv` `unreachable=0` |
| **nas** | jump in the alias **and** in `group_vars/storage.yml` | ✅ `ssh` + `ansible` both green |
| **pi** | alias + jump; `group_vars/raspberry_pi.yml` carries it for the runner too | ✅ both green |
| **spark** | `group_vars/spark.yml` + the identical play-level copy in `playbooks/spark.yml` | ✅ both green (the precedent the others copy) |
| router / switch / APs / any `*99` alias | **none, by design** — Mgmt plane = same-site (decision A below) | ❌ by design: `ssh router` → connect timeout. **Never add a jump to these** |

**Services (not SSH): never a port forward.** `*.{ts.,}kogler.si` on the tailnet → VPS
`traefik-tailnet` edge → WG S2S → the home backend, per the boundary decision above — verified to work
end-to-end from a hotspot with no home reachability at all (`llm.ts.kogler.si`).

### The settled rule — **owner decision A**: the Mgmt plane is a same-site plane

**VLAN 99 does not accept traffic from the site-to-site tunnel, and that is policy, not a fault**
(decision row: [network-rejected.md](network-rejected.md)). **A — the seal stays:** management is a
physical-presence plane and **off-LAN admin is always the Home leg (VLAN 10)**. Option **B** (add the mgmt
/32s to `wg_s2s_vps.allowed_ips` **and** extend the router's `available-from`) is declined — the decision row
says why.

Two independent mechanisms (both verifiable from the VPS in 60 s, see below):

1. **No route.** `ip route get <oldsrv mgmt addr>` answers `via <vps default gw> dev eth0` — straight out
   to the internet — while `ip route get <VLAN-99 gateway>` answers `dev wg-s2s`. Cause:
   `wg_s2s_vps.allowed_ips` (`IaC/ansible/group_vars/all/main.yml`) is an explicit **/32 least-access list**
   (the five VLAN-10 node addresses + the router + switch mgmt addrs + the `wg-vps-services` range) and
   names **no other mgmt address**; systemd-networkd installs a route only for what AllowedIPs names
   (`sudo wg show wg-s2s` is the live confirmation).
2. **The router scopes its own control plane.** `/ip service set ssh … available-from={{ router_services_available_from }}`
   (`IaC/router/templates/rb4011_converge.rsc.j2`), and that var is **the VLAN-99 subnet and nothing else**
   (`IaC/ansible/group_vars/router.yml`) — so even the mgmt addresses that ARE routed refuse a
   tunnel-sourced SSH (src `10.255.40.x`): tagged 99 = admin plane, Home→Mgmt forward is dropped.

Re-verify in 60 s: `ssh vps 'ip route get <oldsrv-mgmt>; ip route get <vlan99-gw>; sudo wg show wg-s2s'` +
`grep -n -A9 "allowed_ips:" IaC/ansible/group_vars/all/main.yml`.

Consequences, written out:

- `pi99`, `router`, `switch`, the AP aliases and `oldsrv99`/`nas99` are **on-site admin paths** — reachable
  only with the Windows `Mgmt99` vNIC carrying link (`wsl-nat-resolv.ps1 -EnableMgmt99`) or while physically
  on the LAN. Check the link **before** blaming the router: `ip -br addr` in WSL must show a VLAN-99 route,
  not just `eth0`.
- **Never put `ProxyJump vps` on a mgmt-leg alias.** It cannot work, and it converts a fast failure into a
  ~90 s `Connection timed out during banner exchange`.
- **A banner-exchange timeout is a dead next-hop, not an sshd fault**, and **a dead address is not a dead
  host**: a box can be `Up` with its containers running and `enp0s31f6.99` `UP` with the right address, while
  its mgmt address answers nothing.

### Where the jump lives

The jump is a property of **the inventory**, not of a runner: `ansible_ssh_common_args: "-o ProxyJump=vps"`
in `group_vars/home_servers.yml`, `group_vars/storage.yml`, `group_vars/raspberry_pi.yml` and
`group_vars/spark.yml` (`playbooks/spark.yml` keeps its identical play-level copy — play vars win over
group vars, same value, no conflict). **A laptop-local `~/.ssh/config` is the convenience layer**, specified in
§The laptop alias contract below. It is durable in exactly one sense: the marker-delimited block that
[`scripts/seed-seat-ssh-config.sh`](../scripts/seed-seat-ssh-config.sh) renders from
[`ssh/aliases.tmpl`](../ssh/aliases.tmpl) is a repo-owned, digest-pinned, per-seat-class *seat plane*, and a
seat's file is reproducible from the repo. What is not durable — and what the plane exists to retire —
is the **hand-kept** copy, the part of the file no script can prove or rebuild. Proven off-LAN with a stub config that
contains **only** the `Host vps` block (`ANSIBLE_SSH_ARGS="-F <stub>" ansible <host> -m ping`): pong for all
four behind-NAT hosts — the repo alone carries the path.

Green forms (no `-e` anywhere, from a hotspot):

```bash
bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --check --tags common,network
#   oldsrv.kogler.si : ok=18 changed=0 unreachable=0 failed=0
# The FULL `--check` (same command, no --tags) also connects (unreachable=0) but reports failed=1 in
# the KNOWN check-mode breaker class: roles/docker_services/tasks/technitium-seed.yml:102 reads
# `_tech_login.json` from a `uri` task that does not run in check mode — see
# [deployment-ansible.md](deployment-ansible.md) §Dry-run Mode. Not a reachability fault.
# The `delegate_to` task this path must not break, green off-LAN (no -e at all):
#   ok: [oldsrv.kogler.si -> pi.kogler.si(<the Pi Home address>)]   # Fetch Pi ha-sync public key
#   (--limit oldsrv.kogler.si --check --tags home_assistant,ha_failover → failed=0)
```

### The laptop alias contract (SSOT — rebuild a new laptop from this; do not copy an old `~/.ssh/config`)

Two rules decide every block:

1. **Behind-NAT hosts** (`pi`, `nas`, `oldsrv`, `spark`) are reached through `ProxyJump vps` onto their
   **Home leg**, on every network. The Mgmt leg is never an away path (decision A above).
2. **OpenSSH matches the name ACTUALLY TYPED**, so each node gets an alias block **and** a `Host <ip>`
   block for the leg its `ansible_host` names. Ansible does not *need* the IP block (the jump travels in
   the inventory — proven above); the block is what `scp`/`rsync`/`git` and a human typing an address need.

| Block | Leg (see [network-addresses-generated.md](network-addresses-generated.md)) | `ProxyJump` | Notes |
|---|---|---|---|
| `vps` | public | — | the jump itself; `User ansible-admin` |
| `pi`, `….1.20` | Home | `vps` | alias uses the human user, the IP block the `ansible-admin` one |
| `nas`, `….1.10` | Home | `vps` | the group var AND the alias must both carry the jump |
| `oldsrv`, `….1.30` | Home | `vps` | `ssh oldsrv` = the **Home** address; mgmt access is `oldsrv99` |
| `spark`, `….1.40` | Home | `vps` | the precedent both the play and the group var copy |
| `oldsrv-domen` | Home | `vps` | **the coding seat**: the same leg and the same jump as `oldsrv`, but `User domen` with `IdentityFile ~/.ssh/domen_ssh` + `IdentitiesOnly yes` (§Canonical identity file names). Key-only — `PasswordAuthentication` stays `no` by policy, so a block that offers a password method can never work. There is no tailnet-direct form: the ACL grants `tag:dev:443`, not 22 |
| `pi99`, `oldsrv99`, `nas99`, `router`, `switch`, `ap-spalnica`, `ap-dnevna`, `ap-spare` | Mgmt (VLAN 99) | **none — never add one** | on-site admin paths only (decision A); `oldsrv99`/`nas99` are the explicit on-site legs |

Both copies of the contract live on the one laptop and must agree: WSL `~/.ssh/config` and
`C:\Users\domen\.ssh\config` (Windows OpenSSH). **Neither is maintained by hand: both are the
render of one [`ssh/aliases.tmpl`](../ssh/aliases.tmpl) for a declared seat class, written by
[`scripts/seed-seat-ssh-config.sh`](../scripts/seed-seat-ssh-config.sh) inside a marker block.** What has to
agree beyond the aliases is the identity FILES those aliases name — §Canonical identity
file names below, and §The Win11 `~/.ssh` retirement list for the order in which the divergent names are retired.

**A third variable decides them: WHICH `ssh` runs them.** A bare `ssh` inside a script resolves to whatever
build its PATH holds, and the builds disagree.
On the win11 seat, over five legs, the Git-Bash build (`/usr/bin/ssh`, OpenSSH 10.5p1 / OpenSSL) authenticates
everything — `vps` `nas` `pi`
`spark` `oldsrv-domen` → **rc 0 with `SSH_AUTH_SOCK` empty**, alias digest `773069cc32fb` — while
`C:/WINDOWS/System32/OpenSSH/ssh.exe` (9.5p2 / **LibreSSL**) fails on the key
file itself: `Load key "C:\Users\domen/.ssh/ansible-admin_ssh": invalid format` → `Permission denied
(publickey)`. The key is not broken and it is not a text-mode artifact: `openssl pkey` reads the file as a valid
Ed25519 **PKCS#8** PEM (the shape `op read` exports), and a CR-stripped copy fails identically. `OpenSSH_for_Windows`
cannot parse PKCS#8 — the same class the git transport already documents for `github_auth`
([deployment-secrets.md](deployment-secrets.md) §Unattended git on Win11), reproduced here on the fleet keys.
Re-encoding a copy with `ssh-keygen -p -f <key> -o` makes the System32 build load it (rc 0), but it
forks that seat's file from the vault export and from every other seat, so **the fix stays on the transport**:
namely the OpenSSL build — a bare `ssh` under Git-Bash already is one, and `git-bootstrap-win11.sh` pins it
explicitly for git. A harness that resolves `ssh` off a Windows-native PATH therefore loses legs it
proved from Git-Bash, which is why the driver's transport must never be left to PATH.
A `.pub` hint as `IdentityFile` is never self-sufficient: it selects a key an AGENT must hold, so Windows
OpenSSH authenticates (`Offering public key: … explicit agent`) while the Git-Bash build cannot load the file
(`Load key "…ansible-admin_ssh.pub": invalid format`), offers no key at all and dies `Permission denied`.
Identical config, identical host, opposite verdict — and a missing trailing newline on those `.pub` files is
NOT the cause (a newline-terminated copy fails the same way through that same binary).

**A third copy exists, and it is deliberately NOT a laptop copy: the oldsrv seat's own `~/.ssh/config`** — the box
this repo is authored on (the cockpit seat). It sits **ON the Home VLAN**, so its `nas` / `pi` blocks name the
Home address and carry **no `ProxyJump`**: on-site a jump would hairpin through the VPS for no benefit, and
`ssh nas` / `ssh pi` complete directly in under a second. **This seat is the render of the `cockpit` class**,
pushed by [`scripts/seed-seat-ssh-config.sh`](../scripts/seed-seat-ssh-config.sh); its former hand-kept stanzas
(the `seat-home-leg` marker block and two unmarked `Host spark` / `Host vps` stanzas) are gone. Two blocks stay
foreign to the plane and are preserved byte for byte: the marker-delimited
`Host github.com` deploy-key block ([`scripts/seed-seat-deploy-key.sh`](../scripts/seed-seat-deploy-key.sh)),
and `Host vps`, which `seed-runner-ssh.sh` reports as
`already present (not authored here): … names Host vps — left alone`, so a later run of that machine-managed
seeder cannot resurrect a second `Host vps` behind the plane's back. The reason the seat needs the plane at all:
**a rebuilt seat that runs only the runner seeder gets `vps` and silently has no `nas` / `pi`** — every
`ssh nas|pi|oldsrv` from it dies with `Host key verification failed`, which
is a missing-alias-and-key symptom, not a dead host (trap 1 below).
Ansible never reads this file: the jump it needs travels in `ansible_ssh_common_args` (`group_vars/storage.yml`,
`raspberry_pi.yml`, …), so a seat alias never changes how a converge reaches a host — direct aliases are a human
and `scp`/`rsync` convenience, the same role the `Host <ip>` blocks serve on the laptop.

#### Canonical identity file names (SSOT — one name per identity, the same name on every seat)

The aliases above are only half the contract; the other half is **which file they point at**.
One identity, one file name, on Windows, WSL and the cockpit seat alike. Names and
fingerprints only — this doc never carries key material, and it never will.

| Identity (what it IS) | Canonical file(s) | Vault item | Private half lives | `SHA256` fingerprint |
|---|---|---|---|---|
| **The operator** — a human, interactive, every seat | `~/.ssh/domen_ssh` + `.pub` | `domen_ssh` (`SSH_KEY`: `public key` / `fingerprint` / `private key` / `key type`) | **private on every seat**, incl. Windows | `SHA256:XTmK3tR59IMnok1HbEW7n3ZK0v4bd7miPS+0r7lSPTA` |
| **Automation** — `ansible-admin`, the fleet's SSH user | `~/.ssh/ansible-admin_ssh` + `.pub` | `ansible-admin_ssh` (same shape) | **private on every seat**, incl. Windows — a `.pub` hint cannot work here: Git-Bash's `ssh` has no agent to ask and `SSH_AUTH_SOCK` is unset, so the hint names a key that does not exist there | `SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU` |
| GitHub **auth** (the seat deploy key, repo-scoped) | `~/.ssh/github_auth` + `.pub` | `GitHub auth` | per-seat, seeded by [`scripts/seed-seat-deploy-key.sh`](../scripts/seed-seat-deploy-key.sh) | (per key) |
| GitHub **signing** | `~/.ssh/github_signing` + `.pub` (may remain on a seat) | — | **retired**: commit signing is off and nothing reads it; a local pair left on a seat is a leftover, not an identity ([deployment-secrets.md](deployment-secrets.md) §Master Secret List) | — |
| **Machine-local** host key (`HostName`/`IdentityAgent` legacy, ssh's own default) | `~/.ssh/id_ed25519` + `.pub` | — | per-machine, **never referenced by an alias** — ⚠ the *name*, not the *contents*: on WSL and on the cockpit seat this path holds the **vault's automation key**, not a machine key (step 6 of the retirement list) | `SHA256:YbldrWp8ndNOOGx7YMKJYulSoIqZmk5w9fnNkezsVOk` (Windows seat); `SHA256:1uKzm…` on WSL + cockpit, = `ansible-admin_ssh` byte for byte |
| Out-of-band console | `~/.ssh/id_rsa_ilo` + `.pub` | — | where it is used (iLO/IOMesh); not a fleet identity | — |
| Host **trust**, not identity | `known_hosts`, `allowed_signers` | — | per-seat; a `Host*` line in `allowed_signers` trusts every key | — |
| Vendor leftovers | `Hetzner-SSH-key.pub` | — | a hint of someone else's key; retire it when no alias names it | — |

**The rule, in one line:** an alias may name a file from this table and nothing else — a key file that is
neither named here nor named by an alias is an accident, and gets retired. `scripts/seed-seat-ssh-config.sh`
enforces the alias half and refuses to render an `IdentityFile` outside this list.

Facts about these files:

- **The 1Password agent matches on key bytes, not file names.** A rename of a key file is a **rename, not a
  re-issue**: no dialog, no unlock, no new enrollment, same fingerprint, same admission.
- **The vault item is `domen_ssh`** ([deployment-secrets.md](deployment-secrets.md) §SSH Key Separation and
  §Rename Map); the Windows private half is exported headless from WSL with `op read`. `dome_ssh` is not an
  item name — prose that uses it is stale.
- **This table governs seat-side FILE names for human/automation identities.** Service identities
  (`ai_ssh` → `ai-debug`, the OpenVPN peer, the Postgres roles) are registered in
  [deployment-secrets.md](deployment-secrets.md) §Master Secret List / §SSH Key Separation and have no business being named by a laptop
  alias; if one turns up in `ssh/aliases.tmpl`, that is the bug, not the exception.
- **A file that is a copy of an identity is still a second identity to a reader.** The operator key exists
  under one name per seat (`domen_ssh`); the old duplicate names are retired in the order below — not the other
  way round. The automation key on WSL and on the cockpit seat still sits at `~/.ssh/id_ed25519`, named by no
  alias, and step 6 explains why it is not renamed yet.

#### The Win11 `~/.ssh` retirement list (ordered — prove the new path BEFORE you rename the old one)

**Place, prove, then remove** — the same rule governs files as keys. Reordering those three produces an alias
pointing at a name that no longer resolves, and a
seat that can no longer authenticate because the copy it used silently became the only one. Every step keeps
a dated copy: `cp -p` to `<name>.retired-<YYYYMMDD>` for files, `config.bak-<UTC>` for the config (which
`seed-seat-ssh-config.sh` writes for you), and nothing is deleted until a later pass proves nothing read it.

**Where the seats stand.** `domen_ssh` (+`.pub`, `SHA256:XTmK3tR…`) is placed from the vault on both laptop
seats and the plane is pushed (`digest 773069cc32fb` on both, a shadow refusal cleared as step 3 describes);
the operator-key duplicates are renamed away and the legs re-proved — five rc 0 from win11 Git-Bash with
`SSH_AUTH_SOCK` empty, six rc 0 from WSL. ⚠ Those legs hold on the OpenSSL build only, which is step 2's build
caveat, not a footnote.
**Still owed on the win11 seat:** step 5's leftovers — `github_signing{,.pub}`, `Hetzner-SSH-key.pub`,
`known_hosts.old` and four `config.bak-*` sit in `~/.ssh`, read by nothing and refused by nothing. Step 6 stays
as ruled below, and its Debian `id_ed25519` carve-out is still blocked by the FQDN-leg dependence.

1. **Place** `domen_ssh` (+ `.pub`) — `op read "op://Private/domen_ssh/private key"` from WSL into
   `C:\Users\domen\.ssh\domen_ssh`, `chmod 600`, then verify the fingerprint equals the table above. Write
   nothing else, rename nothing yet.
2. **Prove** one leg per identity FROM Windows, with the exact file an alias will name: `ssh.exe -G vps` (what
   OpenSSH resolves), `ssh vps` (the agent-held `ansible-admin_ssh.pub` path), and a temporary
   `-o IdentityFile=~/.ssh/domen_ssh -o IdentitiesOnly=yes ssh oldsrv-domen` (the operator path). Record the
   build too — Windows OpenSSH and the Git-Bash `ssh` give opposite verdicts on a `.pub` hint.
3. **Push the plane**: `bash scripts/seed-seat-ssh-config.sh --push`. Expect **REFUSAL(shadow)** first, because
   the hand-kept contract region declares the same aliases outside the markers — move that region out (its
   content is now generated), keep the dated `.bak-`, re-push. Same sequence on WSL.
4. **Rename the duplicates into the canonical name**, one at a time, with a dated copy kept in place:
   `laptop-domen_ssh.pub` → `domen_ssh.pub`; on WSL `domen_ed25519` → `domen_ssh` (and `.pub`). Re-run the
   step-2 legs after each rename; the agent needs nothing, but a typo is indistinguishable from a revocation
   until something proves it.
5. **Retire the leftovers, only once no alias and no script names them**: `github_signing{,.pub}` (signing is
   retired), `Hetzner-SSH-key.pub`, `known_hosts.old`, and any `config.bak-*` past its proof window.
   `id_rsa_ilo` stays if a console leg still uses it. `known_hosts` stays: it is trust, not identity.
6. **Leave alone**: `1Password/`, `agent/` (the agent's own state, not a key), `id_ed25519` — machine-local on
   the Windows seat, and the one file that must never appear in an alias, because an alias that authenticates as
   the *machine* is how an automation ends up reading like a human (the `MaxAuthTries` failure mode).

**Step 6's `id_ed25519` carve-out is wrong on the two Debian seats, and "retire it anyway" is not safe yet.**
On WSL and on the cockpit seat `~/.ssh/id_ed25519` is **byte-identical to the vault's
`ansible-admin_ssh` private half** (`cmp` clean, `SHA256:1uKzm…`) — so it is not machine-local, it is a
superseded NAME. It stays in place, named by no alias, because the path is
also **ssh's default identity** and the repo scripts connect by **bare FQDN**, which matches no alias —
contract rule 2 says OpenSSH matches the name ACTUALLY TYPED, and the laptop classes carry the alias and the
`Host <ip>` spellings but **not the `.kogler.si` spelling**. Those legs work only by accident, because the
accident-key happens to be the fleet's automation key. **Rule: leave it in place, named by no alias, and retire
it only when that dependence is removed** — a measured dependence, not an
exemption. The four callers: `scripts/ak-shell.sh`, `scripts/provision-vault.sh`, `seed-runner-ssh.sh`'s
`KEY="$HOME/.ssh/id_ed25519"`, and `restore-runner-key.sh`, which treats that path as the canonical runner key.

**The probe, both seats, reversible** (move the file aside, put it back; never copy or edit it):

```
ssh -o BatchMode=yes -o ConnectTimeout=15 ansible-admin@vps.kogler.si hostname
  id_ed25519 in place     -> rc 0  (`vps`)
  id_ed25519 moved aside  -> rc 255 `Permission denied (publickey)`
ssh -o BatchMode=yes -o ConnectTimeout=15 -o IdentityFile=~/.ssh/ansible-admin_ssh ansible-admin@vps.kogler.si hostname
  -> rc 0 on BOTH seats even with id_ed25519 moved aside
```

The second command is the fix, proven rather than asserted: FQDN spelling + the canonical identity already
works, so retiring the path is a wiring job — add the `.kogler.si` spellings to the laptop classes in
[`ssh/aliases.tmpl`](../ssh/aliases.tmpl) and repoint those four scripts — and only then does step 6 become a
plain rename.

**No IaC blast radius — read this before grepping.** The string `laptop-domen` also appears in
`IaC/ansible/group_vars/all/main.yml`, `IaC/ansible/group_vars/router.yml`,
`IaC/ansible/roles/router/tasks/main.yml` and the `IaC/router/templates/*.j2` that render from them. That is
the router's **static-host / DNS name for this laptop** — a different namespace, not a key file and not an
alias. `network-addresses-generated.md` and `network-vlans.md` are generated from the address SSOT.

### The tailnet is not observable from the VPS host

**There is no `tailscale` CLI on the VPS** — its tailnet presence is the `traefik-tailnet` container's
userspace sidecar, so `tailscale status` there returns nothing (and `sudo tailscale` is "command not
found"). **Empty output from that host is not "no peers"** — it is the wrong instrument. Inspect the
network from a tailnet-attached client, or from the Headscale control server itself (it runs as a Docker
container on the VPS, per §Two Layers above).

### Measurement traps
1. **A dead address is not a dead host.** A mgmt leg can answer nothing (ICMP loss, port 22 closed) while the
   box is up and fully reachable on its Home leg — including the `enp0s31f6.99` sub-interface reporting `UP`
   with the right address on it. Before concluding "host down", test the **other leg**, then test a hop that
   must work (the VLAN gateway answering from the same VPS localises the fault to the host-specific path
   rather than the tunnel).
2. **OpenSSH matches on the hostname ACTUALLY TYPED — but the inventory carries the jump, so an alias
   block is not what makes Ansible work.** `ssh pi` can succeed while `ansible pi -m ping` fails: Ansible
   types the inventory IP, nothing matches, no jump is applied. The **fix is the group var**
   (`ansible_ssh_common_args`) — proven with a stub ssh config holding only `Host vps`. The `Host <ip>`
   blocks in §The laptop alias contract are for `scp`/`rsync`/`git` and for humans who type addresses —
   useful, not load-bearing.
3. **`-e ansible_host=<ip>` is a GLOBAL extra-var — it corrupts `delegate_to`.** The override applies to every
   host in the run, so a `delegate_to: pi` task connects to **oldsrv's** address looking for
   `/root/.ssh/ha-sync.pub`: the file exists on the Pi, the task never runs there. A scoped override needs
   `--limit` + a per-host `host_vars` change or a group-level var — not a global `-e`.
   **Moot by construction:** oldsrv's `ansible_host` IS the Home leg, so no run needs the override
   at all — the delegated task returns `ok: [oldsrv.kogler.si -> pi.kogler.si(<Pi Home addr>)]` off-LAN with
   no `-e`. Do not reintroduce the pattern.
4. **A `--check` that fails is not a reachability failure.** The full `home_servers.yml --check` reports
   `unreachable=0 failed=1` because `technitium-seed.yml:102` reads the result of a `uri` task that does
   not run in check mode. Read the RECAP's `unreachable` counter for the path question; read `failed`
   for the play's own defects (the class is catalogued in
   [deployment-ansible.md](deployment-ansible.md) §Dry-run Mode).
5. **A backgrounded `cd X && nohup … &` takes the `cd` into the subshell** — the foreground shell stays
   where it was. A probe written that way can silently run against the **primary** checkout instead of the
   session worktree and report stale state (e.g. "the group var does not carry the jump"). Always `cd`
   first, then background the command — and print `pwd` + `git rev-parse --abbrev-ref HEAD` in any
   measurement you intend to quote in a doc.

**Also worth knowing off-LAN:** the Pi is a **toggle-only Slovenian exit node** (egress, not ingress —
see the section below), and the tailnet does **not** bridge the home LAN, so `10.10.x.x` is unreachable
over it by design.

## Slovenian exit node — Pi, toggle-only

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
| **Office MCP bridges (Windows clients)** | Expose the per-client **Office MCP server** over the Headscale interface only (token-auth, no public) so a server-side **Open WebUI** can call Word/Excel/PowerPoint tools. See [`services-office.md`](services-office.md). |