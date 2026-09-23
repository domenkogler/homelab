---
title: Admin — Ops, GitOps, Security & Backup
role: detail
domain: services
status: active
tags: [services, admin, ops, gitops, security, backup]
---
# Admin — Ops, GitOps, Security & Backup

> **Role:** Detail — the operational/admin slice of the services stack: GitOps (Forgejo, Renovate), edge security (CrowdSec), VPN mesh (Headscale), backup (Kopia, DB Backup), the **network/rack topology dashboard (Homelable, HD-45)** and the **family remote-desktop server (RustDesk, HD-412)**.
> **Links to:** `services-traefik.md`, `services-authentik.md`, `backup.md`, `deployment-renovate.md`, `observability.md`, `network-rack.md`, `services.md`
> **Linked from:** `services.md`, `index.md`

> **Status: 🟢 live on the VPS** — Forgejo, CrowdSec, Headscale + Headplane admin UI, kopia-server,
> db-backup, Renovate. ⏳ **Open:** the kopia-agent connect gate on oldsrv (it needs the kopia-server leg
> wired end to end), Forgejo repo creation/migration, and the owner's kopia seed/wiring decisions (HD-230).
> **RustDesk (HD-412) is 🟢 IaC only — ⏳ deploy-gated** (`enabled: false`); see §RustDesk.
> **Metabase is retired** — it is not in the running stack; see §Metabase for the revival path.

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Forgejo | git | I | 150–250 / 450 | Git hosting, Issues, PRs (+ Actions runner). **GitOps / upgrade-automation trigger** — Forgejo Actions → Renovate → Ansible. **Auth (HD-148): native OIDC → Authentik** (web SSO + per-user API/token); client via Blueprint + glue |
| Renovate Bot | — | I | 150–300 / 600 | Docker image version tracking (GitOps upgrade automation) |
| CrowdSec | — | P | 100–200 / 400 | WAF + brute-force protection; its dashboard surface is **CrowdSec Web UI** (`csui.kogler.si`, tailnet-only) |
| Headscale | vpn | P | 60–120 / 250 | Tailscale coordination server |
| Kopia | — | I | 150–250 / 500 | Encrypted off-site backup (kopia-server on the VPS + oldsrv agent, HD-191) → Hetzner Storage Box (backup, far DC); agent reach = WG-only `:51515`, no subdomain |
| DB Backup | — | D | 30–60 / 200 | Database dumps (tiredofit/db-backup) |
| Homelable | — | host (Home VLAN) | ~200–400 / 800 | Network/rack topology visualizer (HD-45) — oldsrv, internal-only, **deploy-gated** (`enabled:false`). nmap discovery + live healthchecks + device inventory/docs + rack canvas; complements the HD-343 network-clients Grafana view. Reached at `http://<oldsrv-home-ip>:3000`. Auth = local admin (`homelable_login`). |
| RustDesk server | — (no subdomain) | **host** (VPS) | ~30–80 / 300 | Family remote desktop — hbbs (rendezvous) + hbbr (relay) in one s6-supervised container (**HD-412**), **IaC authored ⏳ deploy-gated** (`enabled:false`). Public `21115/21116/21117` at the nftables input chain (no Traefik route, no web console); access = the server keypair + a per-machine password/consent. Bandwidth-capped. Owning section: §RustDesk |

## Homelable — network/rack topology visualizer (HD-45)

> **Status: 🟢 IaC authored, not yet live — ⏳ deploy-gated.** Homelable (Pouzor/homelable, MIT) is the owner's chosen "network dashboard" — an interactive canvas of **who is on the network + how it is connected + live status** in one tool. Registered in `home_servers.yml` `docker_services` with `enabled: false`; nothing runs until the owner signs off + the secrets are seeded (Stage 9 below).

**Why this tool:** the Grafana **Network Clients** dashboard (HD-343) answers "who is on the network" but cannot express topology. Grafana stays the metrics/alerting view (per-VLAN tables + time series); Homelable adds the **topology/rack canvas**. Both run on the LAN; neither is public.

### The i/ii/iii mapping
| Want | Delivered by | Detail |
|------|--------------|--------|
| (i) who is on the network + per-VLAN | **HD-343 Grafana** (`stats.kogler.si`, network-clients dashboard) **AND** Homelable device inventory + nmap Pending queue | HD-343 = SSOT-accurate `mikrotik_client` union (DHCP/ARP/FDB/wifi). Homelable = its own scan/discovery + inventory; approve discovered devices into its canvas. Keep HD-343 authoritative for *leases*; use Homelable's canvas for the *curated map* |
| (ii) topology / connection map | **Homelable** (network diagram + rack canvas + port patching) | The tool's core. Import/curate the router/switch/APs + every VLAN's devices; draw links; watch live status (ping/http/health) on the canvas |
| (iii) combined view | **Homelable canvas** with HD-343-derived context | Homelable nodes carry IP/MAC + live status; where a node is also in `mikrotik_client`, its VLAN/source is visible. A combined "all-in-one" single pane is the Homelable canvas itself; Grafana stays the tabular/metrics pane |

**Integration with the HD-343 network-clients exporter:** Homelable does **not** consume `mikrotik_client` directly (no Prometheus import in v3.4.x upstream). The integration is *curation*: seed the Homelable inventory from the same reality HD-343 reflects — the static hosts in the SSOT (`network_static_hosts`) and the HD-343 live view — then let Homelable's own scanner + healthchecks keep it live. Do not double-source truth: `network_static_hosts` (IaC) is the SSOT for what *should* exist; HD-343 shows what *does*; Homelable is the *map + status* layer over both. (If upstream later ships a Prometheus/VictoriaMetrics import, wire it to the same `mikrotik_client` series.)

### Access model (fleet-exposure policy, HD-251)
- **Internal-only, never public** — no DNS record, no WAN allow, no VPS edge route. Same posture as the tailnet-only admin dashboards, with one structural difference: those live on the VPS `traefik-tailnet` edge, whereas Homelable must live **on oldsrv on the Home VLAN** to scan the LAN (nmap + ARP + ping need L2/LAN presence — see compose header).
- **Reach:** LAN clients on VLAN 10 → `http://<oldsrv-home-ip>:3000`. Remote/tailnet: oldsrv **is** a tailnet node as of 2026-09-20 (HD-405, `roles/tailscale-node`, `tag:dev`) — but that node serves **tcp/443 only** (plus one `udp 53` rule on its node address for the resolver role, HD-415 — not a service surface) and, on 443, only `ha.ts.kogler.si`. Cockpit is NOT exposed there: a **Pattern-A sidecar / tailnet route** remains the open tail for this service (HD-45 deploy tail); not built yet. (The claim on this line read "is a tailnet node" for years while it was aspirational — corrected against the live tailnet, 2026-09-20.)
- **Auth:** Homelable's local admin login (username + bcrypt `AUTH_PASSWORD_HASH`). Native OIDC is available but deliberately OFF for now (single-owner admin tool behind the LAN ACL). Revisit only if family members get accounts.
- **Network placement:** `network_mode: host` for backend + frontend, both **binding only the Home-VLAN IP** (never 0.0.0.0) — the actual-budget / mcp-* narrow-bind precedent. The optional MCP container joins `services-internal` (off by default).

### Ports / services
| Container | Image | Host bind | Purpose |
|-----------|-------|-----------|---------|
| homelable-backend | `ghcr.io/pouzor/homelable-backend:{{ homelable_version }}` | host-net, uvicorn on `127.0.0.1:8000` (nginx fronts it) | FastAPI: scan, healthchecks, DB |
| homelable-frontend | `ghcr.io/pouzor/homelable-frontend:{{ homelable_version }}` | host-net, nginx on `<oldsrv-home-ip>:3000` | React SPA (proxies `/api` → loopback backend) |
| homelable-mcp *(optional)* | `ghcr.io/pouzor/homelable-mcp:{{ homelable_version }}` | `services-internal` | MCP server for AI-tool topology read/write (off by default) |

### State & backup
- SQLite DB + uploads under `/srv/docker/homelable/data` (host bind). Covered by the oldsrv **kopia-agent** snapshot scope (`/srv/docker`, backup.md) — add a source line when the service goes live.
- Disposable/regenerable by design: the canvas is *curated* data, not a service SSOT. Keep it backed up but never treat it as authoritative for IPs/VLANs (`network_static_hosts` is).

### Secrets (1Password `Homelab-ansible`, catalog-generated — provision-secrets.py)
| Item | Category/fields | Consumed as | Notes |
|------|-----------------|-------------|-------|
| `homelable_login` | Login — `username`, `password`, `bcrypt_hash` | `AUTH_USERNAME`, `AUTH_PASSWORD_HASH` | `bcrypt_hash` = bcrypt(password), written at item creation (see `homelable_login_item()`). Compose escapes `$`→`$$` (HD-270). Rotate rewrites password + hash together. |
| `homelable_secret` | Password — `password` (48-char gen) | `SECRET_KEY` (+ `MCP_SERVICE_KEY` when MCP on) | ≥32 bytes for JWT. Rotatable (sessions reset). |
| `homelable_mcp` | API Credential — `credential` | `MCP_API_KEY` | Only consumed when `homelable_mcp_enabled`; catalog-created so the flag flip never needs a manual seed. |

### Onboarding stage (CONVENTIONS §5)
Authored against upstream **v3.4.1** (registry-verified on GHCR for backend/frontend/mcp). Register the row as **Stage 8/10** — steps 1–8 (exposure/secrets/compose/registry/edge-decision/state/observability/validation) are authored in this section + the compose + the docs; **step 9 (deploy gate) is owner-gated** and step 10 (docs close) follows the live verify.

| # | Onboarding step | State |
|---|-----------------|-------|
| 1 | Exposure & auth decision | ✅ internal-only, Home-VLAN narrow-bind, local admin (OIDC deferred) — this section |
| 2 | Secrets | ✅ names + docs + CATALOG authored (`homelable_login`/`homelable_secret`/`homelable_mcp`); items must be created before first converge |
| 3 | Compose template | ✅ `templates/docker_services/homelable/` (compose + nginx.conf.j2), pins in `versions.yml`, scanner vars in `home_servers.yml` |
| 4 | Registry | ✅ `home_servers.yml` row `enabled:false` + catalog row here + `services.md` |
| 5 | Edge (if exposed) | ✅ none (internal-only; no Traefik on oldsrv — HD-331). Direct Home-IP :3000 |
| 6 | State & backups | ✅ `/srv/docker/homelable/data` → kopia scope (add live source at deploy) |
| 6.5 | Storage / data location | ✅ oldsrv local bind (not NAS) — canvas is host-local curated data |
| 7 | Observability | ✅ image healthcheck + `Up` status visible; node metrics flow via Alloy (host exporter) |
| 8 | Validation | ✅ `validate-all.sh` green (compose + registry + version pin) |
| 9 | **Deploy gate (owner)** | ⏳ seed 1P items → `ansible-run.sh playbooks/home_servers.yml -e docker_services_scope=homelable` (or full oldsrv converge) → owner creates admin + approves first scan |
| 10 | Docs close | ⏳ after live verify — confirm this section's ✅/⏳ and delete any open todo row |

### Owner deploy checklist (what unblocks this)
1. **Seed the three 1P items**: `OP_SERVICE_ACCOUNT_TOKEN=… python3 scripts/provision-secrets.py --create --yes` (creates `homelable_login` w/ bcrypt, `homelable_secret`, `homelable_mcp`) — or `scripts/provision-vault.sh` on the WSL runner.
2. **Deploy**: `ansible-run.sh playbooks/home_servers.yml --tags docker_services -e docker_services_scope=homelable` (surgical) — first apply is human-gated per CONVENTIONS §5.9.
3. **First-run**: open `http://<oldsrv-home-ip>:3000`, log in with the `homelable_login` creds, trigger the first scan, approve discovered devices into the canvas; sketch the rack + draw links.
4. **(Optional, later)** flip `homelable_mcp_enabled: true` + converge for AI-tool access once the canvas is curated; add a tailnet Pattern-A route for remote use.

### Known gaps / upstream caveats
- **v3.4.x is young and fast-moving** — pin is `3.4.1`; re-verify the image/tag and re-check the release notes at first deploy (HD-134/§7 discipline).
- Scanner MAC caveat: with host networking the backend sees real MACs; without it every device is MAC-less (avoided here by design).
- No upstream Prometheus/VictoriaMetrics import yet — HD-343 integration is curation-based (see i/ii/iii above).
- The tool is not a metrics/logs/alert backend — Grafana/VictoriaMetrics stay authoritative for that (observability.md).

## RustDesk — family remote desktop (HD-412)

> **Status: 🟢 LIVE on the VPS since 2026-09-21 — ⏳ client enrolment + the two live sessions remain.**
> `rustdesk_login` seeded (44 / 88 base64 chars, verified by length + field shape), registry row
> `enabled: true`, converged `--tags hardening,docker_services,rustdesk-server`, and verified on the box:
> `Up (healthy)`; hbbs listening 21115 / 21116 tcp+udp, hbbr 21117; `/data` holds `id_ed25519` + `.pub`
> at 0600 inside a 0700 dir; hbbr logged its **effective** caps `TOTAL_BANDWIDTH: 48Mb/s`,
> `SINGLE_BANDWIDTH: 24Mb/s`, `LIMIT_SPEED: 8Mb/s`, `DOWNGRADE_THRESHOLD: 0.66`,
> `DOWNGRADE_START_CHECK: 1800s`; loopback consoles answer (`hbbr tb` → `48Mb/s`,
> `hbbs always-use-relay` → `false`); from the public internet **21117 OPEN / 21118 REFUSED**. Caps
> confirmed by the owner the same day (short sessions by design ⇒ quota pressure negligible).
> ⛔ Still to prove before the row closes: one relay session (phone on mobile data → a Path-B family
> machine) and one Path-A session with the relay provably uninvolved — both need a human at both ends.
> Procedure: [deployment-manual.md](../deployment-manual.md) §1.11.

**The need:** the owner must be able to sit at a family member's machine from wherever he is, and keep a
desktop-rescue path for the homelab's own GUI surfaces — **without** putting a new public listener on the
host that holds the vault token.

**Placement is decided — do not re-argue it** (logged in [services-rejected.md](services-rejected.md),
2026-09-20): the server (hbbs rendezvous + hbbr relay) runs on the **VPS**; **never on oldsrv** — a rescue
tool that lives behind the thing it rescues is not a rescue (if the home link or oldsrv *is* the broken
thing, so is the support path), and making it reachable there would need a public listener on the
crown-jewel host. The reflex "VPS RAM is tight" objection does not apply: upstream's own floor is *"the
minimum configuration of a basic cloud server… you can also use a Raspberry Pi"*, and the measured
working set here is tens of MB. What this service really costs is **bandwidth** when hole-punching fails
— the durable constraint is the port quota, so it is capped (§Relay bandwidth cap).

### Exposure & auth (CONVENTIONS §5 step 1)

| Surface | Decision | Why |
|---------|----------|-----|
| hbbs 21115/tcp (NAT-type test), 21116/tcp+udp (rendezvous/heartbeat/hole-punch), hbbr 21117/tcp (relay) | **public on the VPS**, allowed at the nftables **input** chain (host-net ⇒ no docker DNAT, so input is the only gate) | Family machines must introduce themselves from networks we do not control; a source-allow would defeat the purpose |
| The credential | **the server keypair, not the source address**: `ENCRYPTED_ONLY=1` puts `-k _` on **both** hbbs and hbbr | Without it hbbr runs its deliberate empty-key default = ANY client may relay through it. An ID alone buys an attacker nothing: sessions still need the per-machine password or an interactive accept |
| hbbs 21118 + hbbr 21119 (WebSocket) | **NOT allowed** (stays dropped by the input policy) | They exist only for the RustDesk **web client**, which we do not run, and upstream warns hbbs/hbbr trust unvalidated `X-Real-IP`/`X-Forwarded-For` on those ports — reachable = anyone can forge the client IP in our logs and skip IP-based blocking |
| Web console | **does not exist at this tier** | The `:21114`-class HTTP console is **Pro**-only. The OSS server is administered over its **loopback command console** (`printf 'always-use-relay Y' \| nc 127.0.0.1 21115`; `printf 'h' \| nc 127.0.0.1 21117` lists hbbr commands incl. live `tb`/`sb` bandwidth reads). There is therefore **no HTTP admin surface, no Traefik route, no middleware tier, no CrowdSec bouncer** for this service — `public: false` in the registry |
| Fail2ban / CrowdSec | none apply | No HTTP/auth-log surface for either to read. Mitigation is the keypair + hbbr's own `blocklist.txt` (refuse) / `blacklist.txt` (bandwidth-limit), editable live from the loopback console |
| Rate limiting in nftables | deliberately **none** | A silent drop under a burst is a dead support session — the exact failure this service exists to prevent. The abuse surface is bounded by key validation instead |
| `network_mode: host` | required, justified in-template | UDP rendezvous + TCP hole punching must see the real source address; Docker's userland-proxy SNAT would destroy it. First host-net container on the VPS — it is the documented exception to the "no public container host-net" line in [security.md](security.md) §8 / [services-vps.md](services-vps.md) §VPS-Specific Firewall |

### The two client paths — family onboarding procedure

**Path A — tailnet member (preferred; ZERO relay, zero quota).** For any machine that can run a
Tailscale/headscale client. The reachability half is HD-405, which has landed.
1. Enrol the machine in headscale (same procedure as every other node — [network-vpn.md](network-vpn.md)),
   then install RustDesk on it.
2. On the machine that will be *controlled*: Settings → Security → **Enable direct IP access**, set a strong
   password, and set the **IP whitelist to the tailnet range only** (`100.64/10` — the headscale overlay,
   SSOT [network-addresses-generated.md](network-addresses-generated.md)).
3. Connect by its tailnet address (not by ID). **hbbs and hbbr are both uninvolved** — no third-party
   introduction, no relay hop, no quota spend. ⏳ Verify this on the **pinned** version at first deploy:
   upstream has shipped regressions in exactly the direct-IP-without-relay path.

**Path B — ID access (the VPS server's only real job).** For machines that cannot join the tailnet.
1. Client → Settings → ID/Relay Server: **ID server** = the VPS public IPv4 (`dns_primary_ip`), **Key** =
   the public half of `rustdesk_login` — read it with
   `op read "op://Homelab-ansible/rustdesk_login/username"` (the live copy is
   `/srv/docker/rustdesk-server/data/id_ed25519.pub`, 44 base64 chars; the two never diverge unless
   someone rotates the pair). Relay server stays empty — hbbs hands clients the relay address.
2. Read the machine's 9-digit ID over the phone; connect; **the remote user accepts the prompt** (see
   §Consent posture — this is the whole auth story for a family machine).
3. hbbs introduces, the peers hole-punch; hbbr relays **only** when punching fails, under the cap.
The ID is not a secret and must never be treated as one.

### Consent posture on a shared family desktop

oldsrv is the family desktop with **auto-login on the primary family account** (HD-51), and RustDesk
mirrors the **current** desktop session — a support session therefore **takes over the family's screen**
mid-use. Decided deliberately, so it is not discovered during a live family call:
- **Session-start client only** on oldsrv: never install it as an always-on/system service there. If nobody
  is logged in, there is no desktop to rescue and the session must simply fail.
- **Interactive confirmation stays ON** ("Accept incoming connection requests", never "Always accept") and
  the client's on-screen "your screen is being shown" notice is never disabled — the family must see it.
- **No unattended password on oldsrv.** Unattended access is for the owner's own headless/owned machines
  only. A family call is booked, so consent costs nothing.
- Tell the family before the first session that the support tool shares the screen they are using.
- X11 only: oldsrv is Xorg/XFCE ([hardware-oldsrv.md](hardware-oldsrv.md)); Wayland is upstream's pain
  source and a containerised client is the "unsupported display server" trap — **never containerise the
  client**. The iGPU drives the desktop and the dGPU stays pinned to the AI tier; nothing here changes
  that split ([hardware-gpu.md](hardware-gpu.md)) — a remote session is only a viewer of it.

### Relay bandwidth cap — the quota arithmetic (the number is the owner's to confirm)

Quota SSOT = `vps_host.specs` in `group_vars/vps.yml`: 2.5 Gbit flatrate, **throttled to 300 Mbit/s beyond
3 TB rolling / 24 h** (soft throttle — no overage bill, but the whole VPS gets slow). Cost per session
(HD-412 row): **30 KB/s idle → 3 MB/s for a full 1080p** session, spent **only** when hole-punching fails.

Upstream's defaults are the wrong policy for a quota-bound box: `TOTAL_BANDWIDTH=1024` Mb/s ≈ 128 MB/s,
which reaches the 3 TB knee in **~6.5 h**. The caps are hbbr's own knobs (no nftables shaping needed —
verified in `src/relay_server.rs` at the pinned 1.1.16; unit is Mb/s counted as 1024² bit/s, so each
"Mb/s" is 1.05 Mbit/s):

| Knob (`svc.*` in the registry row) | Value | Consequence |
|------|------|------|
| `relay_single_mbps` → `SINGLE_BANDWIDTH` | **24** | 3.0 MB/s per connection = exactly the 1080p upper bound: one session runs at full quality |
| `relay_total_mbps` → `TOTAL_BANDWIDTH` | **48** | 6.0 MB/s aggregate. Flat-out for 24 h = **~527 GiB = 17 % of the 3 TB knee**, so the throttle is unreachable even in the worst case; 2 sessions concurrently at full quality, ~200 at the 30 KB/s idle floor (family need = 1–2) |
| `relay_limit_mbps` → `LIMIT_SPEED` | **8** | post-downgrade 1.05 MB/s — still a usable session, but a long hog stops eating the quota |
| `relay_downgrade_threshold` | **0.66** (upstream default, set explicitly) | a connection is downgraded once its lifetime average exceeds 15.8 Mb/s |
| `relay_downgrade_start_check_s` | **1800** (30 min) | only long-lived connections are eligible — a normal support call is never throttled mid-call |

Plus `ALWAYS_USE_RELAY=N`: direct/hole-punched first, so the quota is not spent on sessions that do not
need the relay, and Path A never spends it at all. Evidence the caps took effect: hbbr logs its effective
values at start-up (`TOTAL_BANDWIDTH: 48Mb/s`), and `printf 'tb' | nc 127.0.0.1 21117` reads them live.

### Keys, state & backup (CONVENTIONS §5 step 6)

- The **only** state is `/srv/docker/rustdesk-server/data`: `id_ed25519` + `id_ed25519.pub` (the keypair),
  `db_v2.sqlite3` (client registrations) and optional `blacklist.txt`/`blocklist.txt`.
- `rustdesk_login` (1Password, **manual-value**, Login item: `username`=public / `password`=secret: `rustdesk-utils genkeypair` mints it — never
  catalog-random). Seed-once by design: the s6 `key-secret` step copies `KEY_PUB`/`KEY_PRIV` into /data
  **only when the file is absent**, then `chmod 0600` + `validatekeypair` (and halts on a half/mismatched
  pair). So the live file is authoritative while /data survives and a vault edit alone changes nothing →
  **`NOT_AUTO_ROTATABLE`**: rotating orphans every enrolled client, whose stored key stops matching.
  Rotation = replace the vault value **and** delete `/data/id_ed25519*` **and** re-enrol every client.
- **Restore path:** the 1P item *is* the restore — wipe /data, re-converge, the pair is re-seeded and
  clients keep working (that is the whole point of seeding it). The policy row is written:
  [backup.md](backup.md) §What Gets Backed Up (`RustDesk server keypair + client registrations`) — the
  identity needs no snapshot, only `db_v2.sqlite3` does, and the snapshot leg waits on the VPS-side
  backup client (named in that doc's coverage gap).

### Observability (CONVENTIONS §5 step 7)

Infrastructure, never a family tile (homepage shows no RustDesk tile; security.md §10).
Container signal = the image's **own** `HEALTHCHECK` (`s6-svstat` on the hbbs + hbbr service dirs) —
inherited, not overridden, because it checks supervision state, which is the only signal these binaries
expose (no HTTP surface to probe; contrast the whisper lesson in [services-ai.md](services-ai.md) §3a-3).
Reachability signal = a blackbox `tcp_connect` probe of 21116/21117 from the VPS blackbox-exporter —
⛔ **owed**: scrape targets live in `roles/monitoring/**`, whose owning brief is
[`prompt-420.md`](../prompt-420.md) (it carries this probe as named, undispatched debt), and it rides on any
future `--tags monitoring` change rather than a lane of its own.

### Onboarding stage (CONVENTIONS §5)

| # | Step | State |
|---|------|-------|
| 1 | Exposure & auth | ✅ this section (public rendezvous/relay, keypair-gated, no console, 21118/21119 closed) |
| 2 | Secrets | ✅ item + docs row authored (`rustdesk_login`, NOT_AUTO_ROTATABLE); ⚪ the item itself is `[MANUAL]`-seeded — the render is fail-closed without it |
| 3 | Compose template | ✅ `templates/docker_services/rustdesk-server/` — host-net justified in-template, `cap_drop: ALL`, `no-new-privileges`, `read_only` + /data bind, pinned tag |
| 4 | Registry + catalog | ✅ `vps.yml` row (`enabled: false` = the gate) + this catalog row + [services.md](services.md) |
| 5 | Edge | ✅ **no Traefik route by design**; reach = `roles/vps-hardening/templates/nftables.conf.j2` input allow 21115/21116(tcp+udp)/21117 |
| 6 | State & backups | ✅ this section; ⚪ the backup.md policy row is owed to lane 394 |
| 7 | Observability | ⚪ blackbox probe owed to lane 420 (`roles/monitoring/**`) |
| 8 | Validation | ✅ `bash scripts/validate-all.sh` green in-lane |
| 9 | **Deploy gate** | ⏳ owner: seed the keypair → flip `enabled: true` → converge VPS (first apply is human-gated, CONVENTIONS §5 step 9) |
| 10 | Docs close | ⏳ after the two live sessions below; the `todo.md` row keeps its ⏳ tail until then (CONVENTIONS §4(b)) |

**Acceptance still owed (both live, both fail-closed on presence):** a support session **from the phone to
a family machine**, and a **direct-IP tailnet session to oldsrv with the relay demonstrably uninvolved**
(`printf 'ls' | nc 127.0.0.1 21117` shows no active relay during it).

## Metabase — retired (revival path documented)

Metabase is **not part of the running stack**: it was never used and the VPS is RAM-constrained. Retained on
purpose so a revival is cheap: the compose template, the **disabled** VPS `docker_services` entry, the vault
item `metabase-forgejo_ro` and the `metabase_ro` role in forgejo-db (no longer re-synced — the db_ro keys are
commented out in `vps.yml`). Revival target is **oldsrv**, not the VPS (owner: *"if it will be needed it will
be on oldsrv"*).

- **CrowdSec's dashboard surface is CrowdSec Web UI** (`csui.kogler.si`, HD-272) — it is not a Metabase
  consumer, and CrowdSec's own bundled Metabase image is not used.
- **Auth posture (settled, HD-243):** Metabase OSS has **no OIDC/SSO** (paid tier only), and LDAP would mean
  a second login plus an extra outpost's blast radius for a single-user tool ⇒ **Forward-Auth at the edge +
  local admin**. See [services-rejected.md](services-rejected.md).
- **First boot (wizard):** language → admin account → data-source (**skip it**) → usage prefs. Anonymous
  tracking OFF, HTTPS-redirect OFF, admin account from the `metabase_login` vault item.
- **SMTP:** `MB_EMAIL_SMTP_*` from the smtp2go SSOT + the shared `smtp_login`, From = `notify@kogler.si`.
  Working values: **port 2525**, host as used by `grafana_smtp_host`, and `MB_EMAIL_FROM_ADDRESS` must be set
  explicitly or the reset mail is rejected.
- **Revival steps:** add an oldsrv `docker_services` entry (`template_dir: metabase`, `public: false`) →
  decide reach/auth (LAN direct vs a future oldsrv edge) → re-add LAN data sources to the template (the old
  VPS CrowdSec/db-internal sources are gone) → seed `smtp_login` + `metabase_login` → converge oldsrv.

## Open item — stale DNS record after a service retirement

The `technitium-seed` role only **adds** records (`zones/records/add`) — it never deletes. So the VPS primary
Technitium still carries the internal `sec.kogler.si` A-record pointing at the dead tailnet-sidecar IP
(harmless — it 404s — but it contradicts the SSOT). Fix either way: delete via the Technitium API
(`/api/zones/records/delete`, the HD-324 path) next time Technitium is touched, **or** fold a record-prune
into the seed role so future retirements cannot leave orphans.

## Notes

- **CrowdSec** runs on the Traefik edge (middleware chain in [`services-traefik.md`](services-traefik.md));
  its only dashboard surface is **CrowdSec Web UI** (`csui.kogler.si`).
- **Admin dashboards are tailnet-only** over the `traefik-tailnet` edge — clean subdomain URLs, no ports, no
  public record: Traefik dashboard `traefik.kogler.si` / `.ts.`, CrowdSec UI `csui.kogler.si` / `.ts.`
  ([`services-traefik.md`](services-traefik.md) → traefik-tailnet). **Portainer / Dockge are excluded** —
  there is one Ansible-templated compose model.
- **GitOps:** Forgejo Actions + Renovate drive the Ansible deploy chain —
  see [`deployment-renovate.md`](deployment-renovate.md), [`deployment.md`](deployment.md).

## Related
- [Backup](backup.md) — Kopia / DB-backup policy
- [Observability](observability.md) — CrowdSec dashboards / analytics overlap