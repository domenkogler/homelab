---
title: Home Assistant Failover & High Availability
role: detail
domain: smart-home
status: active
tags: [smart-home, homeassistant, failover, ha, vip, standby]
---
# Home Assistant Failover & High Availability

> **Role:** Detail — active/standby HA failover to oldsrv, takeover + reverse (failback) runbooks, DNS redundancy tie-in.
> **Links to:** `smart-home.md`, `network-dns.md`, `network-vlans.md`,
> `deployment-ansible.md`, `services.md`, `backup.md`
> **Linked from:** `smart-home.md`, `index.md`

> 🟢 **IaC done, not yet live — ⏳ deploy-gated.** The failover design + runbooks are authored but **not live** — the Pi primary + oldsrv standby + keepalived VIP deploy during Phase 4 (HD-04) / Phase 3 (HD-17); HmIP-RFUSB local-Homematic is parked (HD-13). Runbooks below are the spec to be executed at takeover time, not a live system. The Homepage failover buttons are **gated** (HD-217): they render only when group_var `homepage_failover_button: true` (false until HD-17 goes live), so the live dashboard carries no dead buttons meanwhile.

---

## Goals & Non-Goals

### Must hold (non-negotiables)
- **No WAN dependency on the critical path.** Lights/covers toggling must keep working when the internet is down.
- **WAN loss is NOT a failover trigger.** HA is fully local — internet loss does not move HA. Failover is triggered only by **Pi failure** (power, SD card, OS crash, network path) and the *mechanism* simply must work while WAN is down.
- **Exactly one active HA node at a time** (no split-brain). Two HAs driving the same Shelly/KNX/ESPHome devices conflict; HA has **no native active/active clustering or state replication**.

### Scope
- Primary: Raspberry Pi 4 (`pi.kogler.si`; HA accessed via VIP, Home VLAN 10).
- Fallback: **oldsrv** (`home-assistant-standby` Docker container, cold by default).
- Supervision: **manual** trigger + **manual** failback (accepted design — no false negatives from automation).
- Stale state on takeover is acceptable: HA re-polls devices on startup (target: controlling again in 1–3 min).
- **Homematic IP RF is physically bound to the `HmIP-RFUSB` stick (on the Pi).** Taking over Homematic **requires physically moving the stick to oldsrv** — the only non-automatable step. KNX/Shelly are IP-based and fail over purely via the VIP with no physical action.
- **Local-RF scope deferred (2026-08-18 / HD-13 parked):** until an **HmIP-RFUSB is bought**, the **HmIP-HAP stays in cloud mode** — there is no stick to move. During this interim, *IP devices (KNX, Shelly) fail over via the VIP as described; Homematic rides the cloud HmIP-HAP rather than a local RaspberryMatic.* The HmIP-RFUSB stick-move steps in the runbooks below (HD-17/HD-18) and the RaspberryMatic container pairing are **inactive/parked** until the RFUSB purchase happens.
---

## Architecture Overview

```
   ┌─────────────────────────────┐
   │  MikroTik RB4011 (always on) │   also runs DHCP; router/switch
   │                             │   independent of both HA nodes
   └──────────────┬──────────────┘
                  │ route / DHCP / optional VIP contact
   ┌──────────────▼──────────────┐
   │      HA VIP (ha-vip)       │   stable address everything points to
   └──────┬──────────────┬───────┘
          │              │
   ┌──────▼─────┐   ┌─────▼─────┐
   │   Pi 4     │   │  oldsrv   │
   │ HA PRIMARY │   │ HA STANDBY│   cold — started on takeover
   └──────┬─────┘   └─────┬─────┘
          │ keepalived VRRP — VIP follows the active node
   devices / Traefik / Technitium DNS all point at the VIP
```

### Addressing: shared Virtual IP (VIP)

- HA gets a **floating VIP ** on the Home VLAN that moves between the Pi and oldsrv via **keepalived (VRRP)**.
- **Devices, Companion apps, Traefik's `ha` route, and Technitium DNS all point at the VIP**, never a node-specific IP.
- On takeover the VIP follows the active node → **no per-device reconfiguration and no DNS flip on failover**. This is the key that makes failover practical.
- **Firewall:** Home→IoT trusted-IP rules for MQTT/HA must reference the **VIP / an IP-set**, not a per-node IP, so the standby can reach Shelly/KNX after takeover (see `network-vlans.md`).
- **VRRP auth constraint (HD-124 / KOPS-020):** keepalived uses `auth_type PASS` (an 8-char password from `ha-vrrp_password`, truncated identically on both nodes). VRRP has **no stronger in-protocol auth** — VRRPv2 offers only PASS (plaintext) or AH (discontinued), and VRRPv3 (RFC 5798) **removed Authentication Header entirely** — so `auth_type PASS` is the maximum the protocol provides, not an oversight to "fix" with a stronger cipher. The real mitigation is **network trust**: VRRP multicast runs only on the Home VLAN (10), isolated from the Management/IoT planes. Do not chase a "real auth mechanism" here (none exists); rely on VLAN isolation instead. (Likewise, keepalived image is pinned to `keepalived_version` — HD-124/KOPS-053.)

> ⚠ **VRRP requires a controllable host on both sides.** This is only possible once the Pi runs **Debian + HA Container** (see Decision: HA OS vs Debian/Docker below). If the Pi ever runs HA OS again, VRRP on it is not feasible → fall back to manual DNS/NAT steering (slower, still workable).

---

## Nodes & Deployment

| Node | Role | Deployment | VIP |
|------|------|-----------|-----|
| Pi 4 (`pi.kogler.si`) | **Primary** (active) | Debian + **HA Container** (home_assistant role) + **RaspberryMatic** + `HmIP-RFUSB` + **Technitium secondary DNS** | owns the VIP (`ha-vip`) in normal mode |
| oldsrv | **Fallback** (standby, cold) | `home-assistant-standby` + `raspberrymatic-standby` Docker compose (both `disabled` by default), same home_assistant role template | takes over the VIP on takeover |

- Each HA node is paired with a **RaspberryMatic + HmIP-RFUSB**: primary on the Pi (always-on), standby on oldsrv (cold, started by the failover button). Both RaspberryMatic instances expose XML-RPC (2001/2010) on a **fixed Home/IoT VLAN IP** so whichever HA is active reaches it identically.
- **Technitium secondary DNS moved from nas → Pi** (`pi.kogler.si`, now a Debian host; `ha.kogler.si` = VIP). Primary stays on oldsrv. See `network-dns.md`.

- **Identical config from one source:** both nodes render the **same `configuration.yaml`** from the repo (`use_x_forwarded_for: true`, `trusted_proxies: <Traefik>`), including the `owner` recovery account and Authentik OIDC settings.
- **Role/playbook:** `raspberry_pi.yml` (common → network → docker → home_assistant → docker_services → monitoring) configures the Pi as primary (incl. RaspberryMatic + Technitium secondary). The `home_assistant` role on `home_servers` renders the standby + RaspberryMatic-standby containers on oldsrv.
- **Update policy:** **Renovate + `stable` tag** (controlled/gated: Renovate → PR → review → deploy). **No watchtower** (HD-39) — preserves primary/standby version parity and the repo's deliberate update gating.

### Homematic macvlan network (prerequisite on both hosts)

Both the Pi and oldsrv need the `homematic` Docker network before RaspberryMatic can start.
This is a **macvlan** network that gives the CCU a fixed IP on the Home VLAN (10) so both
HA nodes reach XML-RPC 2001/2010 at the same address. Create it once per host:

```bash
# On Pi (primary): homematic-ccu-pi IP (see network-addresses-generated.md)
docker network create -d macvlan   --subnet=<Home VLAN subnet per SSOT>   --gateway=<Home VLAN gateway per SSOT>   --ip-range=<homematic-ccu-pi IP>/32   --parent=eth0   -o parent=eth0   homematic

# On oldsrv (standby): homematic-ccu-oldsrv IP (see network-addresses-generated.md)
docker network create -d macvlan   --subnet=<Home VLAN subnet per SSOT>   --gateway=<Home VLAN gateway per SSOT>   --ip-range=<homematic-ccu-oldsrv IP>/32   --parent=eth0.10   -o parent=eth0.10   homematic
```
The `--parent` interface on oldsrv uses a VLAN subinterface (`eth0.10`) because oldsrv's
physical port is a trunk. On the Pi it's `eth0` — the access port on VLAN 10.
The `--ip-range` reserves one IP per host so the two instances never collide.

> **Adjust `--parent` if the host interface differs** — run `ip link show` to find the
> correct device. The compose template declares `homematic: external: true`;
> the network must exist before `docker compose up -d`.

### Decision: HA OS vs Debian/Docker (Pi primary)

| | **HA OS** | **Debian + Docker (chosen)** |
|---|---|---|
| Failover enabler (VIP/VRRP) | **Not feasible** on Pi | **Native** — Pi runs keepalived |
| Config parity with standby | Separate envs | One Ansible role + one template for **both** nodes |
| Updates | Zero-touch | Your responsibility (Renovate + watchtower) |
| Add-ons | Official store | Run as separate containers (already the oldsrv pattern) |
| Migration risk | None | Small (Pi is in daily use) |

**Chosen:** Debian + HA Container on the Pi, managed by the same role as the standby. The reinstall happens opportunistically during the planned network redo (the network is currently flat / no VLANs; `network-vlans.md`).

---

## Remote & App Access (`ha.kogler.si`)

- **Route:** `ha.kogler.si` → Traefik → **VIP**. The `ha` route must **NOT** use Authentik Forward-Auth (breaks the Companion WebSocket/token flow) — see `smart-home.md`.
- **VIP↔edge coupling (hard requirement):** the VIP (`ha-vip`) is served on `:443` by whichever keepalived node owns it. In normal mode the Pi's **`traefik-ha`** edge (see below) serves `ha.kogler.si`; after takeover oldsrv's `traefik` takes over (both have an identical `ha` route → VIP:8123). HA must not leave VLAN 10, and keepalived must keep the VIP on the active HA node — otherwise the `ha` route breaks (see `services.md` accessibility SSOT).
- **Normal (Pi active):** Android app works over WAN (Cloudflare → VPS Traefik) and over VPN (Headscale).
- **Fallback (oldsrv active):** same hostname routes to the standby. **WAN access is NOT required in fallback** (accepted) — app still works on LAN/WiFi, and over VPN if needed.
- **Security:** HA `http.use_x_forwarded_for: true` + `trusted_proxies: <both Traefik edges — Pi traefik-ha and oldsrv traefik>`; one local `owner` account as recovery if Authentik is unreachable.

### Edge (`ha.kogler.si`) accessibility on node failure

> **The gap this closes:** `traefik` runs only on oldsrv → it is the single point of
> failure for the whole `:443`/TLS plane. The **Pi-down** case is already covered
> (HA, DNS-primary and Traefik all sit on oldsrv, so after the manual failover
> everything incl. the `ha` route works). The **oldsrv-down** case is the real gap:
> HA + DNS survive on the Pi, but the only HTTPS edge is down.

**Design — HA's edge is co-located with HA and rides the VIP.** Run a minimal,
VIP-bound **`traefik-ha`** edge on the Pi that serves **only** `ha.kogler.si →
VIP:8123` (no Authentik Forward-Auth — same rule as the oldsrv `ha` route, it breaks
the Companion WebSocket/token flow). Because the VIP already tracks the active HA
node, the `ha` edge moves with HA automatically — **no DNS flip on failover**:

| State | VIP owner | Serves `ha.kogler.si` via… |
|---|---|---|
| Normal | Pi | Pi `traefik-ha` → local HA |
| Pi down (manual forward takeover) | oldsrv | oldsrv `traefik` → VIP → standby HA |
| **oldsrv down** | Pi | **Pi `traefik-ha` → local HA — gap closed** |

**The same edge also serves the DNS-secondary web UI (`dns-pi.kogler.si`).**
`dns-pi.kogler.si` resolves to the **VIP** (FQDN shape borrowed from the cockpit
naming pattern, but delivery is like `ha` — NOT a file-provider route on oldsrv)
and is served by the Pi's `traefik-ha` edge → local `pi:5380` (IP per SSOT). Rationale:
when oldsrv is down, the Technitium **secondary** on the Pi is the surviving DNS,
so its web UI must be reachable without oldsrv's Traefik. Internal-only, no
Forward-Auth. Direct fallback `pi:5380` on the LAN.

**Scope (what it does NOT do):** this only keeps **HA + the DNS-secondary web UI**
reachable when oldsrv is down. Immich / Forgejo / Authentik / Grafana / … have
their backends as containers *on* oldsrv and die with it — a second Traefik cannot
rescue them. This is an **HA/DNS availability** change, not general service failover
(the public edge is on the VPS per `services-vps.md`).

**Caveats (implementation):**
- **VIP-only bind / gating:** `traefik-ha` uses `network_mode: host` with entrypoints
  explicitly bound to the VIP (`ha-vip`):80/443, and the Pi sets `net.ipv4.ip_nonlocal_bind=1`
  so Traefik can bind the VIP before/without keepalived holding the address. Only the
  keepalived MASTER (Pi in normal mode) owns the VIP → `:443`, so it never fights
  oldsrv's `traefik` for the VIP.
- **Offline-safe cert (decision):** ACME is **disabled on the Pi edge** — it is not an ACME
  issuer. The wildcard `*.kogler.si` cert pair is **synced from the issuer — the VPS Traefik**
  (single issuer per HD-178; previously written as "from oldsrv" — superseded) to
  `/opt/traefik-ha/certs/` on a timer (ha-cert-sync pulls **directly from the VPS** —
  decided HD-204, implemented HD-181; authorize the Pi's `ha-sync` key on the VPS at deploy ⏳).
  If the sync source is unreachable,
  the last synced cert still serves `ha.kogler.si` / `dns-pi.kogler.si` (ACME
  cannot renew, but it does not need to). The Companion app requires a valid cert, so it must work fully offline
  (WAN loss is not a failover trigger and is not required in fallback).
- **`trusted_proxies`:** HA must trust both edges so real client IPs are preserved.

---

## Forward Takeover (Pi → oldsrv) — MANUAL

**Prerequisites:** the `homematic` macvlan network must already exist on oldsrv
(created once during initial setup — see [Homematic macvlan network](#homematic-macvlan-network-prerequisite-on-both-hosts)).
If not present, run the `docker network create` command for oldsrv first.

> 📌 **HD-13 parked (2026-08-18):** this forward-takeover runbook below is the **local-Homematic (full)** path — it assumes the HmIP-RFUSB stick + RaspberryMatic-standby exist. **Currently the HmIP-HAP stays in cloud mode** (no stick, no RMat), so the ACTIVE `ha-failover.sh` skips steps 2 and 3a/3b entirely: failover is just *confirm Pi down → press button → VIP moves → HA-standby starts* (IP devices only). The full-with-RMat flow below (and `ha-failover.full.sh.j2`) is preserved for when the RFUSB is bought. See the deferral note at the top of this doc and [`smart-home.md`](smart-home.md).

**Two manual actions total (local-Homematic path):** (1) physically move the HmIP-RFUSB stick, and (2) press **one** failover button on Homepage (`kogler.si`). Everything after the button is a single orchestrated script — no separate VIP / standby steps.

1. **Confirm Pi is down** (human verifies — power, SD, OS, network).
2. **Physically move the HmIP-RFUSB** from the Pi to oldsrv (hot-plug; if the Pi is powered-but-dying, power-cycle it first). Pairing lives on the stick → **no re-pairing** needed.
3. **Press the single failover button** on Homepage. It runs `ha-failover.sh` on oldsrv, which:
   a. starts **RaspberryMatic** (`raspberrymatic-standby`) on oldsrv (stick pinned by `/dev/serial/by-id`),
   b. waits until the CCU answers on XML-RPC **2001/2010**,
   c. promotes keepalived (Pi MASTER demoted / oldsrv BACKUP promoted → the VIP moves to oldsrv),
   d. starts `home-assistant-standby` (re-polls KNX/Shelly; connects to the fresh RMat).
   (If the VIP path is ever unavailable — HA OS fallback — the script additionally flips the Technitium `ha.kogler.si` record + the Traefik `ha` endpoint.)
4. Verify HmIP devices reconstructed (same EUI/entity IDs) + a live control command; notify n8n → Signal/email and log the event (see `observability.md`).

> **Homematic RF note:** until the stick physically reaches oldsrv, Homematic stays down. IP devices (KNX, Shelly) fail over cleanly via the VIP **without** the stick move — only the RF subset waits on a human being physically present.

---

## Reverse Failback (oldsrv → new/repaired Pi) — MANUAL

> ⚠ **Never auto-failback in a two-node VIP setup** — that is how split-brain happens. Prefer explicit manual transfer, especially because the standby has been running and holds **newer state** than a freshly-rebuilt Pi.

1. **Build the new Pi as a peer, not master:** run the `raspberry_pi` playbook → Pi comes up with the same config as **standby** (disabled VIP, no active role).
2. **Reverse the state sync (standby → Pi):** oldOVs (former standby) now has the freshest config/DB; push it to the new Pi so no family/lights config is lost. (Normal sync direction is Pi → standby; reverse it here.)
3. **Move the HmIP-RFUSB back** to the (repaired) Pi and bring up its RaspberryMatic; verify pairing is retained (the stick carries it) and HmIP entities reconstruct.
4. **Drain the standby:** put it in maintenance (disable its VIP/watchdog/RaspberryMatic-standby), confirm the new Pi is healthy and can control a live device + HmIP.
5. **Flip the VIP back** to the Pi (manual button/script).
6. **Mark Pi = primary**, oldOVs returns to cold/disabled.
7. **Drill:** exercise forward + reverse right after the network redo, and re-test annually with the backup restore drill (see `backup.md`).

---

## Config & State Sync

- **Source of truth:** this repo (config already lives here). The standby is healthy when its rendered `/config` matches the repo + a recent Pi snapshot.
- **Normal direction (Pi → standby):** local push of `/config` to oldsrv on a timer (e.g. every 15 min), LAN-only, no WAN dependency.
- **HA recorder DB:** the recorder stays on the Pi as **local trimmed SQLite** (always available, survives oldsrv-down; `purge_keep_days: 1–2` per `observability.md` *Pi SD-card wear strategy*). A periodic **rsync** of the SQLite file Pi → `/opt/home-assistant-standby/config/` (~15 min, ~few MB) produces a best-effort remote copy — this is the **only** remote copy, not a failover primary. On standby takeover, HA reads the synced copy (best-effort) and re-polls devices; durable long-term analytics live in Grafana (Prometheus, 30d), not in the recorder DB.
- **RaspberryMatic config** is synced alongside HA config (Pi → oldsrv) so the standby RMat restores its host roles/parameters the same way; the device pairing itself travels with the physical stick.
- **Rejected: remote-primary databases for the HA recorder.** Putting the recorder's only database on oldsrv (Postgres) or on a VPS (Postgres) would make HA history depend on a remote host — violating the *Pi survives oldsrv-down* failover property and the *no WAN on critical path* rule. The **local-primary + remote-rsync** pattern above gives equivalent durability without that coupling, and trimming the recorder already defends the microSD (see `observability.md`).

---

## DNS Redundancy Tie-In (see `network-dns.md`)

- Both **Technitium** instances (primary on oldsrv, **secondary on the Pi**) serve `ha.kogler.si` → **VIP** in normal mode, so DNS is never the thing that breaks HA lookup.
- The VIP handles *steering*; the second Technitium handles *lookup availability* when oldsrv is down.

---

## Shelly / MQTT Note

- No MQTT broker exists in the design — Shelly are connected via HA's **native Shelly integration** (direct LAN HTTP/WebSocket per device), so **no broker is a failover surface**. The standby talks to each Shelly directly on takeover.
- If MQTT is ever added (e.g. a rocker switch), run a **Mosquitto** container on oldsrv and give it a stable address reachable by whichever HA is active.

---

## Decided — HA VIP (address / notation / firewall IP-set)

> Single source of truth for the value: `group_vars/all.yml` (`ha_vip`, `ha_vip_cidr`).

- **Address:** `ha-vip`, a single `/32` — keepalived VRRP VIP on Home VLAN 10; `ha.kogler.si` → VIP. Value lives only in the SSOT + config templates.
- **Reservation:** single `/32`, **no reserved block**. Home DHCP pool stays ≤ `.199` (pool per SSOT); never extend it into the VIP or assign `ha-vip` as a normal static lease.
- **Naming:** canonical name **`ha-vip`** everywhere (SSOT host row, keepalived, Technitium A records, docs). Ansible vars **`ha_vip`** + **`ha_vip_cidr: 24`** live in `group_vars/all.yml` only; all templates consume `{{ ha_vip }}` — the literal value appears only in `group_vars/all.yml` and the rendered SSOT.
- **Firewall IP-sets (RouterOS):** the VIP belongs to the **existing** address-lists in `rb4011_initial.rsc`:
  - `trusted-admin` — Home→Mgmt rules (SSH/WinBox/API + UPS web 80/443)
  - `trusted-ha` — Home→IoT rules (MQTT/HA, KNX/Shelly trusted-IP). No dedicated `ha-vip` list.

---

## Open Questions / Decisions

- [x] Takeover trigger = **manual**; failback = **manual** (accepted).
- [x] Stale state on takeover (15-min snapshot) = **acceptable**.
- [x] WAN access in fallback = **not required** (LAN/VPN only).
- [x] Pi confirmed running **HAOS** (see `home-assistant-current.md`); redo target = **Debian + HA Container**.
- [ ] Implement the **single failover button** + `ha-failover.sh` orchestrator (RMat → wait → VIP → standby) on Homepage.
- [ ] **Once**, test HmIP-RFUSB pairing transfer + entity reconstruction across the stick move.
- [x] **VIP address / notation + firewall IP-set** — **decided:** `ha-vip` (`/32`), DHCP pool stays ≤ `.199` (per SSOT); router lists `trusted-ha` + `trusted-admin`. See **Decided — HA VIP** above.
- [x] ~~Whether to add `watchtower` for the Pi's HA container update automation.~~ **Decided (HD-39):** no watchtower — keep Renovate + `stable` tag (controlled/gated), preserve primary/standby version parity.

## Related

- [Smart Home](smart-home.md)
- [Network DNS](network-dns.md)
- [Ansible Specification](deployment-ansible.md) (home_assistant role)
- [Service Catalog](services.md)
- [Backup & DR](backup.md)
