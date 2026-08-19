# Architecture — Audit & Recommended Changes

> **Role:** Architecture audit — review of the current homelab architecture (as designed) + recommended changes.
> **Scope:** hosts, network, services placement, Docker networks, observability, back-up/recovery, GitOps.
> **Pairs with:** `docs-vs-iac.md` (drift), `iac-changes.md` (IaC rework), `security.md` (security-specific).
> **Current state:** planning phase; VPS provisioned; nosrv/pi/nas not yet live.

## 1. What is solid (keep)

- **Single DNS namespace `kogler.si` / split-horizon.** Clean, one wildcard cert, Technitium primary+secondary on two hosts. Well-designed failure-domain split for DNS.
- **Docker overlay network isolation** (`traefik-public` / `services-internal` / `db-internal` / `llm-backend`). Segmented by trust — good.
- **IaC-as-source + Ansible-only deploy** (HD-150): one path, idempotent, `docker_compose_v2`, Renovate→Forgejo→Ansible button. This removes the Doco-CD risk (docker.sock root) — a real win.
- **VPS public edge** (HD-93/135): authentic/traefik/crowdsec/AI/observability on the reliable netcup tier, oldsrv GPU/LAN/storage. Correct direction of travel for exposure minimization.
- **ZFS + Kopia dual-layer backup** with 3-2-1 + off-site Hetzner Boxes — well considered.
- **Admin/ai-debug least privilege** (guards, one sudo allowlist, LAN-only AI). Strong.

## 2. Current architecture (condensed)

```
Internet ── NAT/Cloudflare(DNS-only) ──► VPS (netcup, public edge)
                                        ├─ Traefik + CrowdSec + Authentik
                                        ├─ live-data apps (OpenCloud, Immich, Forgejo)
                                        ├─ AI stack (LiteLLM, Open WebUI, Docling, OpenClaw, PGVector)
                                        ├─ observability backend (Prometheus, Loki, Grafana)
                                        ├─ GitOps (Renovate) + n8n + backup agents
                                        └─ live Box (Hetzner CIFS) + backup Box (Kopia SSH/SFTP)

        wg-s2s (WireGuard, home router ↔ VPS; 10.255.40.0/30)
                    │
        Home RB4011 ── VLANs 10/20/21/30/40/50/99
              ├─ nas (HP MicroServer, ZFS tank+bulk, NUT master)
              ├─ oldsrv (i7-7700K, GPU/LAN core: ollama/immich-ml/jellyfin/*arr/DNS/HA-standby)
              ├─ pi (HA primary + Technitium secondary + traefik-ha VIP edge)
              └─ APs/Switch (Mgmt VLAN 99), family clients
```

## 3. Architectural strengths to preserve

| Aspect | Why it's right |
|--------|----------------|
| Ansible-only deploy | single idempotent path; no Docker-socket agent on hosts; Renovate→Forgejo button |
| VPS edge tier | public surface on the reliable/isolated netcup; oldsrv GPU/LAN box behind it |
| Docker network isolation | per-domain trust boundaries; DB truly isolated |
| NUT + observability separation | alerting independent of shutdown (upsmon owners own power) |
| Kopia to off-site | local ZFS + off-site encrypted Kopia = genuine 3-2-1 |
| The "works without Domen" priority | docs/manual + paper-in-safe = recoverable |

## 4. Risks / gaps worth changing

### 4.1. SPOF review post-HD-135
- **VPS is now the observability backend + edge + GitOps.** If the VPS (or the `wg-s2s` tunnel / last-mile to home) is down, **live home metrics are unreachable in Grafana**, though NUT-side NotifyCMD independently emails. That's a **documented accepted SPOF** (see `observability.md` §Placement). **Recommend:** keep it, but **add an independent internet-facing liveness probe** (blackbox already does `probe_success` — extend to also watch the *home↔*plex link path: router CLI + WG handshake) so tunnel-down is a first-class alert, not a Grafana-gone scenario.

### 4.2. Edge-internal split is clean but **the `wireguard` VPS role is gated on an empty pubkey**
- Covered in `iac-changes.md` #1 — the WG tunnel is listed as a living component across docs/README but silently skips until `wg_s2s_*` public keys are provisioned. **Recommend:** explicit deploy-gate wording + fail-loud (see IaC changes).

### 4.3. **Couch virtualized network + renders** — the `docs/network-addresses.md`(SSOT generated) vs `switch.yml` WIP port-map
- Not architecture-critical; part of the "SSOT honesty" (docs-vs-iac §8). Keep `network-addresses.md` as **IP-SSOT**, don't promote physical ports until `switch_port_map_verified`.

### 4.4. **Service placement** — the catalog `docs/services.md` is the SSOT, but only `group_vars` re-renders into `inventory.md`. 
- **Recommendation:** keep. But add a **single "placement matrix"** row per service (host + docker-network + subdomain + public/internal) so an engineer reads one table — this is where the S3→CIFS and VPS/oldsrv blob lived. `services.md` already has most of it; keep it as the one truth and keep `services-vps.md` focused.

### 4.5. **Media/*arr** — deliberately unbacked (`bulk/media` redownloadable) — accepted, but **verify the Grafan rules know it** (no false "media missing" alert) and that SABnzbd/gluetun egress is the only VPN(external) path.

### 4.6. **Matrix federation** — open federation is a **deliberate accepted risk** with hardening (require_auth_for_profile_requests + no public-room-dir) — keep, but **the homeserver + Element + live-verify are ⏳ deploy-gated** (§2.6 HD-46/47/122/149) — document as "not live yet" in all matrix docs.

## 5. Recommended architectural improvements

### 5.1. **Add a generated "status/placement registers" doc** (★)
As a single answer to "is X live, where, what's its flow": render from `group_vars` (service → host → docker-network → subdomain → public-exposure) + HD ⏳ markers. Reduces the "who runs what / where's the caveat" drift the audit found. Owner: `render-docs.yml` + a new `status.md` template.

### 5.2. **Formalize a "two-plane" architecture note in `services.md`/`services-vps.md`**
- Make the **VPS-plane vs home-plane** split an explicit first-class section (it's implicit in the catalog). Add per-service "Plane: VPS | Home | Nas | Pi | Edge-Dual" so a new agent can't misplace. This is the single biggest architectural fact of the post-HD-135 era and deserves an explicit diagram + plane column.

### 5.3. **Cluster decision: docker network isolation should be documented as the *enforcement boundary*, not a convenience**
- Add to `deployment-compose.md` a short "why these networks matter" (already partially there via HD-59). Confirm `llm-backend` isolation stays (Ollama no-native-auth) and that **no service is on two networks unless it must be** (the audit showed Flaw C / host-port class mostly resolved).

### 5.4. **Backup topology is sound; add a restore-drill cadence as a non-negotiable**
- `backup.md` says yearly restore drill — make it **an HD-level recurring task** (or a Grafana calendar/label) so it isn't forgotten. Also `backup.md §10 Open questions` mentions "Kopia Web GUI vs CLI" — decide at first drill and close.

### 5.5. **Flag the "not yet live" gap cleanly in architecture docs**
- Because the repo is mid-planning, many .md read as live. Add a short **"Deployment status"** block at the top of each *service* doc (🔴 planned / 🟢 IaC done ⏳ / ✅ live) so no reader mistakes design for reality. This is the architecture-readability fix that `conventions-proposal.md` C encodes.

## 6. Architecture decision-matrix (keep vs change)

| Layer | Decision | Verdict |
|-------|----------|---------|
| Edge | Netcup VPS public, Traefik+CrowdSec+Authentik | ✅ keep |
| Apps | Live-data/AI on VPS; media/dGPU/DNS home | ✅ keep (HD-135) |
| Storage | NAS ZFS (local) + live Box CIFS + backup Box Kopia | ✅ keep |
| Deploy | Ansible-only + Renovate/Forgejo button | ✅ keep (HD-150) |
| HA | Pi primary + oldsrv standby + keepalived VIP | ✅ keep |
| Network | VLAN segmentation + split-horizon DNS | ✅ keep (° HD-03 pending live-gear) |
| NOT IN SCOPE / decided-away | Doco-CD, watchtower, TileBoard, Proxmox-single-box, /chat bridges, S3/MinIO | ✅ correctly excluded — list in appendix |

> See `security.md` for the dedicated hardening-thread (+ `iac-changes.md` for the IaC-side architecture reworks).