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
> **Update 2026-09-22 (owner decision, HD-406):** one admin path is coming back, as **MikroTik Back To Home** —
> WireGuard with MikroTik relay fallback — **not yet built**. It is a deliberate exception to the sentence above and
> it does not restore the *family* road-warrior surface; the two caveats the implementing lane must clear first (it
> writes router config outside `roles/router`, which the converge rebuilds; and it adds a vendor relay) are in the
> HD-406 row and [todo.md](../todo.md).

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

> **The VPS-side tunnel is not a plain systemd-networkd setup (HD-306 / HD-285) — mechanism, do not "simplify" it:**
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
> - **Router forward ordering (HD-155):** the `VPS S2S -> scoped home targets` accept must sit **above** the
>   `Default deny inter-VLAN` rule, or it is shadowed (see [network-ops.md](network-ops.md) §Ordering pitfall).

## Layer 2: Headscale (Mobile Mesh)

> **Naming + policy contract:** headscale ≥ 0.24 REJECTS a
> `server_url` inside `base_domain`, so node names live under the dedicated subtree
> **`<node>.ts.kogler.si`** (`base_domain: ts.kogler.si`); the control plane stays
> `https://vpn.kogler.si`. **The ACL is deny-by-default (HD-252 ④):**
> each family user (by OIDC email) may reach only their OWN nodes (see `policy.hujson.j2`; currently single user
> `domen@kogler.si`). Enrolment itself remains Authentik-OIDC-gated; add one accept rule
> per family member as they join.

- Runs on the **VPS** as a Docker container (HD-135: public coordination server, VPS residency)
- Overlay subnet: `headscale` (CIDR per SSOT)
- Clients: Android/iOS Tailscale app, laptops
- **Home RB4011:** static route + firewall rules so the Headscale overlay reaches the Home VLAN
- **MagicDNS (HD-135b follow-up):** `dns.extra_records` maps the tailnet dashboard
  subdomains (and their `*.ts.kogler.si` twins) to the
  `vps-obs` tailnet IP (`tailnet_sidecar_ip`, group_vars/vps.yml).
  **Answer scope:** Tailscale client MagicDNS ANSWERS only its
  `base_domain` (`ts.kogler.si`) — the `*.ts.kogler.si` twins work out of the box. For a FQDN
  matching a `search_domain` (`kogler.si`), the client queries its **configured nameserver for
  that domain**, NOT MagicDNS — so unless the MagicDNS loop is first in `dns.nameservers` (HD-371,
  see §Tailnet-exposed services) the plain `*.kogler.si` names resolve through Technitium
  (VPS primary), which carries the split-horizon A records → `tailnet_sidecar_ip`
  (see [`network-dns.md`](network-dns.md) static-records section).
  `dns.search_domains: [kogler.si]` is set (helps short-name resolution) but does NOT make MagicDNS
  serve the plain names.
- **VPS:** routes the home `site` + `wg-vps-services` over the S2S tunnel to reach home resources
- **Mesh clients** → VPS Headscale (public, its purpose) → over S2S → home LAN; each node has an ACL-gated path home
- **Registration & ACL (HD-84 / KOPS-022):** OIDC-authenticated clients are **auto-approved** by
  Headscale (no separate registration gate in `config.yaml`). The traffic boundary is therefore a **real
  ACL policy** (`policy.hujson`, rendered alongside `config.yaml`). **User-based (current, HD-252 ④):**
  deny-by-default — each OIDC user's email may reach only that user's own nodes; `tagOwners` stays empty
  because headscale v2 requires tags be DECLARED before an ACL may reference them and there is no
  `autogroup:admin` source here, so ACLs are user-email-based. **Tag model for later (HD-84 target):** if/when a shared-service `tag:kogler` is wanted, declare it + its owner in `tagOwners` and
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

### Transition
1. Family installs the Tailscale app (one-by-one migration off the removed road-warrior / travel-router paths)
2. WireGuard road-warrior and the travel router are **gone** — no fallback surface to maintain

---

## Tailnet-exposed services (management plane)

> **Policy (security.md §10 Capability-tiering):** internet-facing surfaces hold only limited-capability
> credentials; full-power access requires tailnet membership. **New admin/UI surfaces default tailscale-first**
> -- never Traefik-public unless explicitly decided. Applied to the AI stack
> ([services-ai.md](services-ai.md)) and the **observability admin dashboards** (HD-135b follow-up) —
> `stats`/`traefik`/`logs`/`csui`/`auto` are tailnet-only with **no public records**.
>
> **Laptop access:** with the Tailscale app connected, the dashboards resolve on the tailnet — headscale
> **MagicDNS** on the `ts.kogler.si` base domain answers the `*.ts.kogler.si` twin names (e.g.
> `stats.ts.kogler.si`), and `dns.extra_records` maps every tailnet subdomain (incl. `llm`/`db-spark`/
> `litellm`) in BOTH namespaces to the `vps-obs` edge (`tailnet_sidecar_ip`).
> **HD-371:** the `dns.nameservers` list puts the **MagicDNS loop first** — so a tailnet client resolves
> EVERY `*.kogler.si` / `*.ts.kogler.si` name **locally on any network** (hotspot/travel), not only when the
> Technitium VPS primary is reachable. The Technitium entries (VPS primary + oldsrv + Pi) follow, giving the
> full namespace + per-subnet filtering on the LAN. Without the loop-first ordering the plain names depend on
> the configured nameserver for `kogler.si` (Technitium VPS primary, reachable only from home-WAN /
> tailnet-CGNAT — source-allow HD-299), so a remote mobile network falls through to the system resolver →
> NXDOMAIN / `ERR_NAME_NOT_RESOLVED`, while the `.ts` twins keep working. On Windows the client also needs
> the loop pushed onto the Tailscale adapter (`netsh … set dnsservers Tailscale 100.100.100.100`).
> There is **no public `*.kogler.si` record** for these names. The tailnet Traefik edge (`traefik-tailnet`,
> node `vps-obs`) is the only tailnet surface for the admin dashboards (see the compose template
> `docker_services/traefik-tailnet` for the routing + serve details).
>
> **Mgmt-99 SSH from the laptop — same-site only (HD-398 owner decision A):** the laptop reaches the Mgmt
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
-- nothing on `services-internal` can even reach it. Live example planned: DSH cockpit (:3080).

### Pattern B -- apps bound to `0.0.0.0`
Dedicated per-service docker network containing ONLY app + tailscale sidecar (never `services-internal` for the UI leg);
sidecar serves to the app over that private network. Functional service-to-service legs stay on their own overlays.

| Node | Serves | App-level auth | ACL tag |
|------|--------|----------------|---------|
| ~~dsh (on oldsrv)~~ | ~~cockpit :3080~~ | **PARKED (HD-386)** — harness removed by the owner; the row + its tailnet route/DNS record remain and answer 502. Pattern-A, not B. |
| vps-obs (`traefik-tailnet` + its userspace sidecar, HD-135b follow-up) | **clean subdomain URLs over the tailnet** — `stats`, `traefik`, `logs`, `csui`, `auto` (n8n), and the AI names `db-spark`, `llm`, `litellm` (HD-370/HD-372) plus their `*.ts.kogler.si` twins: `https://stats.kogler.si` / `https://stats.ts.kogler.si`, `https://logs.kogler.si`, `https://csui.kogler.si`, `https://traefik.kogler.si`, `https://auto.kogler.si`, `https://db-spark.kogler.si`, `https://llm.kogler.si` (spark OpenAI-API, bearer-gated), `https://litellm.kogler.si` (spine admin) — **no ports** (wildcard certs + second Traefik edge). `litellm` reaches the edge through the `tailnet-apps` app→edge overlay (HD-372), not `services-internal`. **`/ui/login` deep-link 404s (no nginx SPA fallback) → use `/fallback/login` (intended flow, HD-373)** | plain `*.kogler.si` = Authentik Forward-Auth (AI names: engine/LiteLLM own-login, no forward-auth); **`*.ts.kogler.si` = ACL-gated** (tailnet-only names, `tag:sidecar:443` is the gate) | tag:sidecar |
| ~~pi-dev (on oldsrv)~~ | ~~TUI/CLI agent~~ | **PARKED (HD-386)** — same; its LiteLLM consumer was deleted in both DBs (`dsh_api` remediation, HD-383). |
| litellm-ui | admin :4000/ui | bearer keys | tag:litellm |
| owui-int (`ai.kogler.si`, HD-248) | internal OWUI | Authentik OIDC | tag:owui-int |
| openclaw | control/gateway | gateway token | tag:openclaw |
| headplane (HD-251 candidate) | mesh admin `/admin` | OIDC | tag:mgmt |

- Serve mode: plain TCP forward is simplest (WireGuard already encrypts); HTTPS mode needs Headscale TLS config -- verify at deploy.
- ACL defaults: inbound-only per node (e.g., DSH needs ZERO outbound tailnet destinations); tag hygiene audit quarterly.
- Rollout: HD-251 (phase-2 fleet rework); first applications: litellm-ui + owui-int (HD-247/248);
  **tailnet dashboard edge (HD-135b follow-up) LIVE** — `traefik-tailnet` (consumer-mode Traefik + a userspace
  tailscale sidecar sharing its netns, node `vps-obs`) serves the admin dashboards over the tailnet with clean
  subdomain URLs on port 443 (`tailscale serve --tcp=443` → the edge's TLS listener), see
  `docker_services/traefik-tailnet` + `policy.hujson.j2`. The old port-based skeleton (a `tailscale-sidecar`
  dir with fixed `:8080–8085` ports) is gone — see [network-rejected.md](network-rejected.md).
- **HD-333 (WG/tailnet reach for the internal edge — this doc is the SSOT):** ✅ LIVE. the internal all-app edge
  (`traefik-tailnet` growth, HD-331/332) is reached two ways:
  - **Tailnet (existing):** the `vps-obs` userspace sidecar already serves `--tcp=443` → the edge's TLS listener; family nodes are ACL-allowed (`policy.hujson`, deny-by-default + per-user own nodes). No change unless the ACL needs extending for a new family member.
  - **WireGuard S2S:** the internal edge's TLS listener (:443, the edge container IP pinned per HD-240) is published **only on the `wg-s2s` VPS address** (`{{ wg_s2s_vps.ip }}:{{ wg_internal_edge_port }}`, the vps.yml SSOT port) via the traefik-tailnet compose `ports:` (docker's own PREROUTING DNAT → container `:443` — same precedent as `kopia-server :51515`, HD-62; no manual nftables DNAT). An **nftables input allow** (vps-hardening, HD-313 pattern: `iifname "wg-s2s" ip saddr <router peer> tcp dport {{ wg_internal_edge_port }} accept`) is added for defense-in-depth. SSOT: `wg_internal_edge_port` / `wg_internal_edge_target_ip` in `group_vars/vps.yml` (derived-values ban — never re-type in compose/nftables/docs).
  - **Reach scope (HD-155 least-access):** the VPS wireguard peer `wg_s2s_vps.allowed_ips` accepts ONLY home infra hosts (`nas/ha-vip/oldsrv/pi/router/switch` — group_vars/all/main.yml). So the internal edge is reachable over WG **from those scoped home hosts**. End-user devices (laptop/phone) at home use the **tailnet** path (sidecar + headscale ACL) — WG is the infra/automation path, not the family path.
  - **Deploy verify (after a VPS `docker_services` converge `docker_services_scope=traefik-tailnet` + `vps-hardening`):**
    1. VPS-side listener: `ss -ltnp | grep :{{ wg_internal_edge_port }}` → bound to the `wg-s2s` VPS address (`{{ wg_s2s_vps.ip }}:{{ wg_internal_edge_port }}`).
    2. From a scoped home host over WG (e.g. `oldsrv`/`nas`/`pi`): `curl -k -I https://<wg-s2s VPS address>:{{ wg_internal_edge_port }}` → HTTP/2 302 (or the edge's TLS response); split-horizon alternative once the `vpn/home/dns` records (HD-334) are seeded: `curl -k -I https://kogler.si -H 'Host: kogler.si'` resolved via the tunnel, or `https://{{ wg_internal_edge_target_ip }}:{{ wg_internal_edge_port }}` from a scoped home host.
    3. Tailnet path unchanged: tailnet device → `https://stats.kogler.si` / `https://<app>.ts.kogler.si` still works.
    4. Heading home with Tailscale on reaches `ha.kogler.si` via the LAN (Option A).
  - **Tailnet ACL:** `policy.hujson` already allows family nodes → `tag:sidecar` on :443 (deny-by-default + per-user own nodes). No extension needed for the existing owner set; extend only if a new family member node is added.

**Parked names stay published, and their 502 is the design (HD-386).** `dsh.kogler.si` / `pi-dev.kogler.si` and
their `.ts` twins keep their headscale `extra_records` **and** their `traefik-tailnet` routers, even though the
backends are gone (HD-355 moved them off the VPS; the `dsh-backend` / `pi-backend` load-balancer URLs still
point at `oldsrv:3080` / `oldsrv:8080` over the WG S2S, where nothing listens any more). So the names resolve
and the edge answers **502** — that is not an outage to chase, and `group_vars/vps.yml` says so where the
records live. Deleting them is a decision of its own, because it deletes MagicDNS records: do it as ONE change
that drops the `tailnet_subdomains` entries, the routers and the two service blocks together.
Also note what the overlay is actually for now: `tailnet-apps` is no longer the sidecar trick its compose header
describes — its live user is `litellm`.

### Reach matrix for the tailnet-only admin names (HD-382 / HD-389)

> The symptom this documents: **a tailnet-only name works on the phone but 404s on the laptop with Tailscale
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
> `traefik-internal` router proxying over WG S2S to the internal edge (`:4443`, the HD-350 double-hop) —
> that **exposes the key-holding spine's admin UI on the LAN edge**, a design change that needs its own
> decision; NOT done.
>
> **The spark AI names (`llm`/`db-spark`) had a DIFFERENT root cause (HD-389, fixed):** for them "use the
> `.ts` twin" is a dead end by itself — MagicDNS answers both namespaces to the tailnet edge and the edge's
> `llm-tailnet`/`db-spark-tailnet` routers match, but the
> TLS-in-TLS backend hop **forwards the client's SNI** to spark's own edge — and spark's Traefik had **no
> router for the `.ts` names** (only `Host(`llm.kogler.si`)`), so `llm.ts.kogler.si` got a routerless-vHost
> 404 *before* auth while `litellm.ts` (VPS-container backend, no TLS-in-TLS) stayed 200. Fix = spark's name
> edge now routes the `.ts` twins + serves the `*.ts.kogler.si` pair (HD-389). Verify:
> `curl -sk -o /dev/null -w '%{http_code}' https://db-spark.ts.kogler.si/` → 200;
> `curl -sk -H "Authorization: Bearer <spark-llm_api>" https://llm.ts.kogler.si/v1/models` → 200.
>
> **Client-side half (HD-389) — plain names failing from WSL/Windows is a workstation resolver problem, not a
> service bug.** With Tailscale connected, the **plain** `*.kogler.si` names fail from WSL/Windows when the
> plain namespace is not routed to MagicDNS **on that client**:
> WSL's auto-generated `resolv.conf` carried only the NAT forwarder, and the Windows NRPT carved only
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

## Tailnet boundary — mobile devices + ONE home host, never a LAN bridge

The tailnet is **not a home-LAN bridge**. Two distinct reach shapes exist, and the difference matters:

* **Via the VPS edge (the family default):** `mobile → tailnet → VPS traefik-tailnet → (WG S2S) → home backends`.
  Every `*.{ts.,}kogler.si` app name works this way, and it survives a home-WAN outage but **not a VPS outage**.
* **Node-direct (HD-405, 2026-09-20):** `mobile → oldsrv's own tailnet node`. The VPS carries **no byte of the
  data plane** — only the control plane (registration/netmap, and DERP if hole-punching fails). This exists so
  the owner's own remote development does not stop when the VPS does, and it is possible because
  [network.md](network.md) §WAN is a **static public IPv4** — P2P is available and we had been routing around it.

**The one host on the tailnet is `oldsrv`** (node `oldsrv`, `tag:dev`, headscale node id 11, joined by
`roles/tailscale-node`). Pi and NAS are still off the tailnet. The scope is enforced, not intended:
no `--advertise-routes` (so `headscale routes list` stays empty and no home subnet is reachable from the
tailnet at all), no exit node (§Exit-node stays the Pi — HD-408 is an open owner call), no Tailscale SSH,
`--accept-dns=false` (oldsrv *runs* a Technitium instance; a DNS takeover would put a resolver in front of
the tier it serves), and the ACL admits **`tag:dev:443`** plus **one DNS rule** — `udp 53` to that node's own
address, written on the address rather than on the tag so a second `tag:dev` node cannot inherit a resolver
grant (HD-415, 2026-09-22; docs/network-dns.md §The resolution requirement). Port 443 and UDP/53 on one node,
not `:*` on the box that holds the vault token — and no TCP/53, no other port, nothing by tag. The boundary's
purpose survives on purpose: Shelly/KNX/IoT/guest stay
non-tailnet-reachable, and VLAN 99 keeps its seal (HD-398 decision A).

Because a preauth-key node lands in headscale's synthetic `tagged-devices` user rather than the owner's
user, `dst: ["domen@kogler.si:*"]` cannot reach it — the ONLY path in is the explicit `tag:dev:443` rule in
`policy.hujson.j2`. Joining by interactive OIDC login instead would put the node under the user and inherit
`:*`; the preauth key is therefore a security control, not just a bootstrap convenience.

**What oldsrv serves on that node** is its own home edge (`traefik-internal`, new `websecure-ts` entrypoint
bound to the **node's tailnet IP** — never `0.0.0.0`), with TLS from the already-synced `*.ts.kogler.si`
pair, and — since HD-415 — the internal zone on **`udp 53`** at that same address (the container's published
port reached by DNAT from `tailscale0`, which is what makes the node usable as a tailnet nameserver).
Today exactly one route is exposed there: `ha-ts` → `ha.ts.kogler.si` (+ the free node name
`oldsrv.ts.kogler.si`) → the HA VIP. Home Assistant was the one service with **no** away-from-home path at
all: no public record, no `traefik-tailnet` route, and a VIP-only listener. The plain `ha.kogler.si` name
stays LAN/VIP-only — see [network-dns.md](network-dns.md) §Split-Horizon for why overloading it was rejected.

**First-run record (2026-09-20, join + node-direct path):** node `oldsrv` joined on its assigned tailnet
address (`tailnet_oldsrv_ip`, group_vars/all/main.yml), headscale node id 11, user `tagged-devices`,
`tag:dev`, **zero advertised routes**; tailscaled control URL asserted to be our headscale (the `vps-obs`
public-control-plane incident is now a fail-loud guard in the role); `/etc/resolv.conf` on oldsrv untouched
(`--accept-dns=false` proven, not assumed); the headscale policy re-render left `headscale` at restarts=0 with
MagicDNS still answering (`stats.kogler.si` → the sidecar's tailnet address, edge 302).
`dig @<MagicDNS loop> ha.ts.kogler.si` on a node → the oldsrv node address. To that node: **443 open,
80/22/8081 blocked** (the ACL is really port-scoped); `https://ha.ts.kogler.si` → **200**, TLS
`CN=*.ts.kogler.si`, ~70 ms.

> ⛔ **That `→ 200` is not true and cannot have been true when it was written (measured 2026-09-22).** The
> `ha-ts` rule shipped, in the very commit that introduced it, with literal spaces inside the matcher —
> `Host(`ha. {{ tailnet_base_domain }} `)` — so it rendered as `Host(`ha. ts.kogler.si `)`. Traefik compares
> a Host matcher **byte-for-byte**, so the router could never match a request and answered its default
> **404** while everything around it was healthy: entrypoint bound to the node's tailnet address, ACL
> accepting 443, MagicDNS extra_record published, backend pointed at the HA VIP. Reproduced at 404 from an
> off-site laptop and again from an on-LAN laptop reaching the node over the tailnet. Fixed the same day (one
> line, the spaces) and re-measured: `https://ha.ts.kogler.si/api/` → **401**, and the node-name host in the
> same rule likewise — 401 is Home Assistant answering behind the proxy, which is the intended answer.
> Two consequences that matter more than the typo: **the 2026-09-21 ✅ acceptance matrix could not have
> exercised T1 through this router**, so that T1 is unverified history rather than a closed fact (re-verify
> on the phone, HD-433); and the bug class — Jinja whitespace inside a matcher — passes `--check`, survives
> review, and is silent at runtime, so it now has a validator, `scripts/check_traefik_host_rules.py`,
> mutation-tested by re-injecting the space.
>
> ⛔ **…and that was only the first of two. The name was unreachable for a second, independent reason
> (found the same evening, 2026-09-22): the `*.ts.kogler.si` certificate never loaded.** The `tls:` block in
> the same template read `certFile: "/etc/traefik/certs/ {{ wildcard_ts_cert_file }} "` — spaces around the
> expression — so the rendered path was `…/certs/ ts.kogler.si.pem `, which does not exist. Traefik does not
> fail on a certificate it cannot open, so the listener came up and answered that SNI with its generated
> `CN=TRAEFIK DEFAULT CERT` (SAN `…traefik.default`). Effect: **no browser has ever loaded a `.ts` name at
> home** — every client rejects the chain — while `curl -k` returned the backend's 401 and made the router
> look healthy. That is how the first fix's acceptance test passed on a name that still did not work: `-k`
> switched off the only check that mattered. The pair itself was already on the host (`/opt/traefik-internal/
> certs/ts.kogler.si.pem`, carried by the cert-pull timer since HD-135b put it on the VPS edge) — nothing was
> missing but two spaces. After the fix, browser-grade verified against the node's tailnet address: SNI
> `ha.ts.kogler.si` → `CN=*.ts.kogler.si`, issuer Let's Encrypt, `ssl_verify_result=0`, **HTTP 401** and
> `curl` exit **0** without `-k`; the LAN edge is unchanged (`CN=*.kogler.si`, media 302). The gate now covers
> quoted certificate paths as well as matchers for exactly this reason — 11 self-test cases, both shipped
> instances among them, each mutation-killed.

> ✅ **T1 RE-RUN FOR REAL — 2026-09-22, the owner's phone, both radios under test.** After both fixes the
> name serves Home Assistant to a phone on cellular: **`https://ha.ts.kogler.si` works with Wi-Fi off and
> the tailnet connected** — and the home cell was measured on its own afterwards, Wi-Fi on + tailnet on,
> because an expected cell is not a measured one and that exact combination is what failed pre-fix. The pass was a full 4-state matrix (Wi-Fi × Tailscale), which is the shape this
> acceptance should have had from the start:
>
> | name | Wi-Fi on + tailnet on | Wi-Fi on + tailnet off | Wi-Fi off + tailnet on | Wi-Fi off + tailnet off |
> |---|---|---|---|---|
> | `ha.ts.kogler.si` | ✅ measured | ✗ by design (the name lives in the netmap) | ✅ **T1, measured** | ✗ by design |
> | `ha.kogler.si` | ✅ | ✅ | ✗ (HD-432: advisory chain) | ✗ (no LAN DNS, no WAN) |
> | `media.kogler.si` | ✅ | ✅ | ✗ (HD-432: advisory chain) | ✗ |
>
> What that pins down beyond HA: Android answers the `.ts` extra_record **client-side from the netmap** (so
> the tailnet twin needs no resolver reachability at all), the per-address `443` grant carries a real user
> node's browser session, and the `*.<ts>` listener serves a publicly-trusted chain with no internal CA on
> the device. Consequence for the twin design: **the pattern is portable** — any home app can get an away
> path by adding a `.ts` twin + a router on the same listener, which is a cheaper route to "apps work away"
> than making the whole zone resolve over the tailnet (the argument that opened HD-432).
>
> The 2026-09-21 ✅ above stands as history, but it verified a router that could not match a request; T1 was
> closed then on a measurement that could not have produced its result. This is the first run that did.

> ✅ **Decided 2026-09-22 — the tailnet's job is to hand out *reachable answers*, and HA has one URL.**
> With the plain `ha.kogler.si` published as an extra_record (plus the existing `.ts` alias) the same URL
> serves home and away: at home with the tailnet off the LAN zone answers the VIP, with the tailnet on the
> netmap answers a home node address and the path is direct over the LAN, and away it is the node path this
> matrix just proved. The HA Companion app holds exactly one URL, which is what forced the decision rather
> than preference. `dns.nameservers.split` was evaluated and **declined** ([network-dns.md](network-dns.md)
> §The answer-plane model, HD-432), as was `override_local_dns: true`.
> **Opened as HD-435:** the Pi joins the tailnet and `ha.kogler.si` is published with **two A records**
> (Pi + oldsrv), so the answer survives either box. Both home proxies target the VIP, so after the manual
> takeover the surviving box serves both planes. ⚠ **Not yet measured:** multi-A fall-over on a real client
> (expect a timeout on the dead first answer, not an instant switch) and MagicDNS actually returning both
> records — both are acceptance criteria of that row, not assumptions of this one.
>
> **HD-415 is closed on this evidence.** Its case (a) and case (c) passed; case (b) — a phone on cellular
> failing to resolve an internal-zone name — was re-scoped: the cause is `override_local_dns: false` making
> the delivered chain advisory, and the fix is a reachable answer per name (this design), not a resolver
> ordering. Recorded rather than dropped, because "the chain is advisory" is the finding, not a footnote.


> ⚠ **The verification host was NOT off-LAN.** The laptop chosen for this pass had a *wired* home path live:
> its Windows default route pointed at the home router over the `VLAN-Switch` vNIC (a Home-VLAN address per
> [network-addresses-generated.md](network-addresses-generated.md)), so probes to Home-VLAN and IoT-VLAN
> addresses from it tested the router's inter-VLAN firewall, **not** the tailnet — and any "it resolved / it
> connected" result there says nothing about being away. Probes to tailnet addresses are valid, because those
> destinations always ride the Tailscale interface. **The published acceptance matrix still requires the
> phone on cellular** (headscale stopped / tailnet off / IoT+guest unreachable); until that runs, this row is
> ⏳ open, not done. Reading the hotspot off the owner's description instead of off the routing table was the
> mistake here — check the routing table before trusting any "away" claim.
> *(The matrix has since run — see the ✅ block below. The routing-table lesson stands: it is why the T2
> window was validated from the containers and the control-plane HTTP code, not from a description.)*

> ✅ **Acceptance matrix RUN on the owner's phone on cellular — 2026-09-21. HD-405 is closed.**
> **T1** `https://ha.ts.kogler.si` reachable on mobile data with the tailnet connected. **T2 — the control-plane
> test, the one the row actually existed for:** headscale + headplane stopped on the VPS
> (`docker compose -p headscale … stop` — `stop`, never `down`) for **162 s** (21:54:25Z → 21:57:07Z), with the
> plane *provably* dead (`vpn.kogler.si` → **404**, no backend); during the window the phone reloaded the same
> URL **and opened a new incognito session** — both worked. The data plane therefore never touches the VPS,
> which is the whole premise of the row. Home side throughout: cached netmap intact (3 nodes), node edge
> answering 200 in 21 ms. Restore verified — `restarts=0`, both containers healthy, nodes 5/6/11 `online`,
> control plane back to 200, and the temporary stop scripts deleted: **no hand-applied delta left**.
> ⚠ **What T2 proves, and what it does not:** clients cache their netmap, so this is *data-plane independence*
> for already-enrolled nodes — **not** cold enrollment. A fresh enrollment fails while the plane is down, by
> design, and must not be logged as a fault. **T3** HA Companion works on `https://ha.ts.kogler.si` (no
> LAN-URL arbitration problem). **T4** IoT stays unreachable — an IoT-VLAN (20) device address failed from the phone (address per [network-addresses-generated.md](network-addresses-generated.md)), and the
> strong form re-measured client-side: **`PrimaryRoutes` empty on every peer** (`tailscale status --json`).
> **Two measurement traps found:** `headscale routes list` **does not exist** in this headscale build (no
> `routes` subcommand — use the netmap view), and a loopback `curl` to `ha.ts.kogler.si` returns **HTTP 000**
> because `websecure-ts` binds the node's tailnet IP only — probe `tailnet_oldsrv_ip` (group_vars) and you get 200 in ~21 ms.

> 🔎 **Two pre-existing faults surfaced by the new path, neither caused by it.** (a) **HA rejects requests
> proxied from oldsrv**: any `X-Forwarded-For` from a source outside `ha_trusted_proxies` gets
> `400 Bad Request` (proven: `Host: ha.kogler.si` + XFF → 400, without → 200), which means the standby edge's
> `ha` router has never worked and the same would bite during a takeover. The tailnet router strips the
> forwarding headers instead of changing smart-home config — the honest fix is adding `oldsrv_home_ip` to
> `ha_trusted_proxies` (needs a HA restart, so it is an owner call, not a transport-lane side effect).
> (b) **`media.kogler.si` answers 502 from the home edge** (also locally on oldsrv): jellyfin publishes no
> host port on `oldsrv_home_ip`, unlike the `actual-budget:5006` / `immich-ml:3003` precedent. Owner call.

> 📡 **Measured 2026-09-20: the away session RELAYS — the assumption this section was written under did not survive.** > The first real away session to the home node ever run (owner's phone, cellular, tailnet connected) reported > **`Relayed connection (FRA)`, 60–90 ms RTT**: the data path left the VPS as designed and landed on a **public Tailscale DERP relay in Frankfurt** instead. > Home-side `tailscale netcheck`: `UDP: true`, external address = the home static IPv4 with a **rewritten source port** (the RB4011 is NATing, single NAT — the > observed external address is the public one, so there is no routing-modem double NAT), `MappingVariesByDestIP: false`, **no UPnP/PCP mapping**, **no IPv6 > anywhere on the LAN**, nearest DERP fra ≈18 ms. Endpoint-independent mapping is the *punchable* case, so the block was attributed to the carrier and/or the router > dropping the punch — and the honest reading is that **"static public IPv4 ⇒ P2P always wins" was never measured until now, and it is false for cellular clients here.** > Consequences: HD-410 (self-hosted DERP) must not be decided before the IPv6 experiment (HD-414, a static /56 is available), because a VPS-hosted DERP would > re-insert the VPS into the data path this section exists to remove; and HD-412 (remote desktop) should not ship onto a relayed path. **Relayed still works** — > `ha.ts.kogler.si` answered 200 over it — so this is a quality finding, not an outage.

> 🔬 **2026-09-21, same pass: "the home side is the *punchable* case" was overstated.** `tailscale ping` from
> oldsrv: the laptop answered **direct on a site-local Mgmt-VLAN (99) endpoint in 2 ms** — but that is a *site-local*
> Mgmt-VLAN address, so it proves same-site discovery, **not** a WAN punch; the phone answered `via DERP(fra)`
> in 104 / 188 ms with "direct connection not established". The off-site probe that would settle it is
> unavailable **by design**: `vps-obs` is not an `oldsrv` peer at all (*"no matching peer"*), because `tag:dev`
> and `tag:sidecar` have no path between them — correct ACL behaviour, inconvenient measurement surface. And
> the router converge as written (checked 2026-09-21) has `chain=input action=drop in-interface=pppoe-telekom`
> with the **WG S2S listen port as its only UDP exemption**, **no `dstnat` and no accept for tailscale's UDP**
> (`41641` appears nowhere in the converge), while `tailscaled` runs unpinned — so an unsolicited punch packet
> dies in *our own* input chain. The relayed result therefore **cannot** be attributed to the carrier on this
> evidence; both causes stay open. HD-414 (IPv6) is what forces the answer, and if v6 also comes back relayed
> the cheap next experiment is a v4 `dst-nat` + input accept on one pinned UDP port to one host — not a DERP.
>
> 📡 **Updated 2026-09-22: HD-414 landed, so that precondition is now true — and one of the two open causes is
> already closed.** IPv6 is live on the Home VLAN ([network-vlans.md](network-vlans.md) §IPv6), oldsrv took a GUA
> by SLAAC, and `tailscale netcheck` on it went from `IPv6: no, but OS has support` to **`IPv6: yes`, fra 14.5 ms**.
> Two corrections to the paragraph above, both measured rather than inferred: (1) it is true that **`41641`
> appears nowhere in the converge, and that is correct** — the "unsolicited punch packet dies in our own input
> chain" argument does not hold, because the punch makes the far side's packets *replies* from oldsrv's point of
> view and `established,related` is rule 1 in both v6 chains; so no inbound accept was needed for the common case
> and none was shipped (HD-414's deliberate non-implementation: oldsrv's Home NIC is stable-privacy +
> temporary-address, so there is no destination to pin). (2) `tailscaled` is no longer unpinned —
> `/etc/default/tailscaled` `PORT="41641"` is owned by the `tailscale-node` role and `ss` confirms
> `0.0.0.0:41641` + `[::]:41641`. ⚠ **Do not read netcheck's trailing port as the disco port:** the
> `IPv6: yes, [<GUA>]:<port>` line is the *DERP-side STUN observation* and it differed between two runs minutes
> apart; the socket a peer must reach is 41641. ⛔ **The one number that decides HD-406/HD-410 is still
> unmeasured:** whether the phone on cellular now negotiates **Direct**. That is a 3-minute owner measurement
> (`tailscale ping <oldsrv's tailnet address, SSOT `tailnet_oldsrv_ip`>` over LTE + the app's session-type line, with `/ipv6 firewall filter print stats`
> before/after on the router). ✅ **Corrected 2026-09-24 (HD-448): the VPS can take a v6 probe now.** It had a GUA
> and a v6 default route but no working IPv6, and this file attributed that to the provider; it was our own
> `vps-hardening` input chain discarding the router's NDP replies (`ip protocol icmp` is the IPv4 upper-proto
> field, so everything v6 met `policy drop`). Fixed and measured live, so the VPS is usable as the off-net v6
> probe host again. **The punch conclusion does not move:** the two live causes are the phone leg (carrier NAT —
> upstream, proven by the counter test) and the VPS `tailscale-sidecar`'s ephemeral listen sockets, and neither is
> a firewall rule. Method + the counter technique: [network-ops.md](network-ops.md) §IPv6.
>
> 📡 **Measured 2026-09-22 (owner's phone on cellular, plus the reciprocal test from oldsrv): IPv6 did NOT make the
> away session direct.** Phone→oldsrv **relayed via FRA, 70–90 ms**; phone→VPS **relayed via NUE, 50–70 ms**;
> oldsrv→phone `via DERP(fra)` with **`direct connection not established`** at 73→244 ms. The hypothesis this
> section carried — "static IPv4 + carrier blockage, IPv6 is the fix" — is **falsified for this path**: the home
> side now has everything a puncher wants (GUA, EIM IPv4, disco on 41641, free egress) and still cannot establish.
> Two causes were untangled from that one report, and they are **not** the same: **(1) the phone leg** lacks
> unsolicited inbound to the UE (carrier NAT / APN behaviour — not ours to fix); **(2) the VPS leg** is ours —
> `tailscale-sidecar` shares another container's netns with `ports=map[]` and its tailscaled binds **ephemeral**
> sockets (`0.0.0.0:39417`, `[::]:35131`) instead of 41641, so no firewall could ever allow it and that node is
> permanently relayed; pinning + publishing its listen port is the cheap win and **has no row yet**. ⛔ Neither is
> an argument for a self-hosted DERP: a DERP is another relay leg and the cost lives on the phone↔FRA/NUE leg, which
> the VPS's location does not shorten — HD-410's decision holds.
>
> **The discriminator ran minutes later (same day) and the block is upstream of this network — nothing we open
> here can produce a direct session.** Two things make that test easy to fake, so they are recorded with it.
> First, **no hole is needed**: put `log=yes` on the WAN drop rules and read whether the packets arrive at all.
> Second, **validate the instrument before believing its silence** — a rule that known traffic certainly
> crossed logged 83 entries, and internet scan traffic produced 17 drops in the same window, so "nothing" is
> evidence here rather than an absent probe. Measured over three punch bursts with the phone online: **zero
> packets from the phone arrived on either family.** Nothing touched the v6 WAN drops; on v4 the only `41641`
> traffic was a scanner repeating every 6 s from a hosting provider, correctly dropped. Meanwhile `netcheck`
> reports our side as textbook-punchable — `UDP: true`, `MappingVariesByDestIP: false`, disco on 41641 on both
> families, unrestricted egress. ⇒ Both remedies this file carried are **retired**: the single inbound v6 accept
> (its destination would receive nothing) and the v4 `dst-nat` experiment (same reason — the scan traffic proves
> the mechanism works, it is the phone that cannot ask). The only levers left are the VPS listen-port fix above
> and **phone-initiated** WireGuard (HD-406), which survives carrier NAT because the UE's own NAT state carries
> the reply instead of requiring unsolicited inbound to it. **Chosen vehicle (owner, 2026-09-22): MikroTik Back To
> Home, deferred.** That reasoning is why it works where the punch did not — the router is the responder with a
> public address, so the phone's carrier has no unsolicited inbound to block. Unproven part, to check when it is
> built: whether BTH picks the **direct** WireGuard path or silently uses a **MikroTik relay**, because a vendor
> relay is the same 70–240 ms shape measured above.
> ⚠ **Chain correction, written wrong here once already:** a WAN packet addressed to a *host* (old-srv, not the
> router) traverses **`chain=forward`**; `chain=input` only ever sees traffic addressed to the router itself. A
> future inbound-v6 exception therefore belongs in `forward`, above the `no unsolicited v6 into any VLAN` drop —
> an `input` rule would silently never match, show zero counters, and look like success.
>
> **Side-fact worth more than the test it came from: no unsolicited inbound IPv6 reached the delegated prefix
> at all** in those windows, while v4 scans arrive continuously. Consistent with the ISP filtering inbound v6 on
> a delegated prefix (egress and replies granted, inbound not). Not proven — the clean proof is an external v6
> prober, which this site has never had (network-ops §IPv6) — but act on it now: **an `AAAA` record pointing at a
> home service would be unreachable from the v6 internet**, which makes `nagios-dns-v6`'s ban on AAAA at home
> correct rather than conservative, and means "publish something over v6 from home" is unavailable at any amount
> of firewall effort.
>
> **RouterOS traps that cost three aborted attempts**, so the next person does not relive them: `place-before=`
> is **silently ignored** when handed the printed rule number (rule ids are hex `*N` and do **not** equal the `#`
> column — resolve ids with `find`); `find where connection-state=established,related` matches **nothing**
> (because the value contains a comma), so match on `comment` instead; and `/log` is memory-capped while a
> **non-default `/system logging` rule (`ssh → memory`) floods ~1000 packet-dump lines per 3 min**, rotating the
> buffer in seconds and silently erasing the window under measurement. That ssh rule is foreign config, not
> repo-managed, and has no row.

**Mobile/media reach — home-hosted services:** home apps (jellyfin, *arr, downloads, seerr, seerrng, and the
moved `dsh`/`pi-dev`) remain reachable by **publishing a host port bound to `oldsrv_home_ip`** + a
`traefik-tailnet` edge route proxying over WG — the `actual-budget:5006` / `immich-ml:3003` precedent. Still
**behind Authentik forward-auth** on the edge (private, not public).

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
| **nas** | jump in the alias **and** in `group_vars/storage.yml` (HD-397 created that file — the `storage` group had no group_vars at all) | ✅ `ssh` + `ansible` both green |
| **pi** | alias + jump; `group_vars/raspberry_pi.yml` carries it for the runner too | ✅ both green |
| **spark** | `group_vars/spark.yml` + the identical play-level copy in `playbooks/spark.yml` | ✅ both green (the precedent the others copy) |
| router / switch / APs / any `*99` alias | **none, by design** — Mgmt plane = same-site (decision A below) | ❌ by design: `ssh router` → connect timeout. **Never add a jump to these** |

**Services (not SSH): never a port forward.** `*.{ts.,}kogler.si` on the tailnet → VPS
`traefik-tailnet` edge → WG S2S → the home backend, per the boundary decision above — verified to work
end-to-end from a hotspot with no home reachability at all (`llm.ts.kogler.si`).

### The settled rule — HD-398 = **owner decision A**: the Mgmt plane is a same-site plane

**VLAN 99 does not accept traffic from the site-to-site tunnel, and that is policy, not a fault**
(decision row: [network-rejected.md](network-rejected.md)). **A — the seal stays:** management is a
physical-presence plane and **off-LAN admin is always the Home leg (VLAN 10)**. Option **B** (add the mgmt
/32s to `wg_s2s_vps.allowed_ips` **and** extend the router's `available-from`) was declined: it spends two
deliberate boundaries — **HD-155** least-access AllowedIPs and **HD-310** admin-plane scoping — to fix a
symptom the Home leg already solves.

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
  host** (oldsrv was `Up`, 34 containers running, `enp0s31f6.99` `UP` with the right address, while its
  mgmt address answered nothing).

### Where the jump lives (HD-397, the durable fix)

The jump is a property of **the inventory**, not of a runner: `ansible_ssh_common_args: "-o ProxyJump=vps"`
in `group_vars/home_servers.yml`, `group_vars/storage.yml`, `group_vars/raspberry_pi.yml` and
`group_vars/spark.yml` (`playbooks/spark.yml` keeps its identical play-level copy — play vars win over
group vars, same value, no conflict). **A laptop-local `~/.ssh/config` is not a durable artifact** — it is
the convenience layer, specified in §The laptop alias contract below. Proven off-LAN with a stub config that
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
# The recorded `delegate_to` victim task, now green off-LAN (no -e at all):
#   ok: [oldsrv.kogler.si -> pi.kogler.si(<the Pi Home address>)]   # Fetch Pi ha-sync public key
#   (--limit oldsrv.kogler.si --check --tags home_assistant,ha_failover → failed=0)
```

### The laptop alias contract (SSOT — rebuild a new laptop from this; do not copy an old `~/.ssh/config`)

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
| `nas`, `….1.10` | Home | `vps` | the group var AND the alias must both carry the jump |
| `oldsrv`, `….1.30` | Home | `vps` | `ssh oldsrv` = the **Home** address; mgmt access is `oldsrv99` |
| `spark`, `….1.40` | Home | `vps` | the precedent both the play and the group var copy |
| `pi99`, `oldsrv99`, `nas99`, `router`, `switch`, `ap-spalnica`, `ap-dnevna`, `ap-spare` | Mgmt (VLAN 99) | **none — never add one** | on-site admin paths only (decision A); `oldsrv99`/`nas99` are the explicit on-site legs |

Both copies of the contract live on the one laptop and must agree: WSL `~/.ssh/config` and
`C:\Users\domen\.ssh\config` (Windows OpenSSH).

### The tailnet is not observable from the VPS host

**There is no `tailscale` CLI on the VPS** — its tailnet presence is the `traefik-tailnet` container's
userspace sidecar, so `tailscale status` there returns nothing (and `sudo tailscale` is "command not
found"). **Empty output from that host is not "no peers"** — it is the wrong instrument. Inspect the
network from a tailnet-attached client, or from the Headscale control server itself (it runs as a Docker
container on the VPS, per §Two Layers above).

### Traps, all hit while measuring this
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
3. **`-e ansible_host=<ip>` is a GLOBAL extra-var — it corrupts `delegate_to`.** Using it to reach
   oldsrv's Home leg produced `ok=367 changed=52 failed=1`, where the one failure was a
   `delegate_to: pi` task that connected to **oldsrv's** address looking for `/root/.ssh/ha-sync.pub`.
   The file exists on the Pi; the task never ran there. A scoped override needs
   `--limit` + a per-host `host_vars` change or a group-level var — not a global `-e`.
   **Moot by construction (HD-397):** oldsrv's `ansible_host` IS the Home leg, so no run needs the override
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
| **Office MCP bridges (Windows clients)** | Expose the per-client **Office MCP server** over the Headscale interface only (token-auth, no public) so a server-side **Open WebUI** can call Word/Excel/PowerPoint tools. See [`services-office.md`](services-office.md) (HD-106–111). |