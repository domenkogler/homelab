# Architecture Audit (Round 2)

> **Role:** Audit deliverable — assessment of the homelab architecture as documented and implemented,
> with ranked improvement proposals. Produced 2026-08-21 per `prompt.md`.
> **Linked from:** `prompt.md`; siblings: `docs-vs-iac.md`, `docs-changes.md`, `iac-changes.md`,
> `conventions-sugestions.md`, `tracking-sugestions.md`, `security.md`.
> **Scope note:** the VPS is live-provisioned but the service stack is not deployed; home hosts are
> unprovisioned. This audits the *design + IaC*, not a running system.

---

## 1. Architecture digest (as implemented)

**Planes / hosts**

| Host | Plane | Runs |
|------|-------|------|
| `vps` (netcup root server) | Public edge + live-data tier | Traefik+CrowdSec edge, Authentik SSO, public apps (OpenCloud, Immich-app, Forgejo, ONLYOFFICE-Docs), AI gateway stack (LiteLLM/Open WebUI/OpenClaw/Docling/PGVector), observability backend (Prometheus/Loki/Grafana/blackbox), alert brain (n8n+signal delivery target), Matrix (Tuwunel+Element), Headscale, GitOps (Forgejo+Renovate), Kopia/db-backup agents |
| `oldsrv` | LAN compute / GPU | Ollama (llm-backend overlay), Immich-ML, Technitium DNS primary + Pi-hole, Homepage, Dozzle, signal-cli gateway, Sunshine, Jellyfin + *arr media stack on NFS, HA standby (cold), thin Alloy collector |
| `nas` | Storage | ZFS tank/bulk, NFS+Samba exports, sanoid/syncoid replication, NUT master + nut_exporter, zfs_exporter, Cockpit — no Docker |
| `pi` | Smart-home controller | HA primary (container) + keepalived VIP, Technitium secondary, traefik-ha VIP-bound mini-edge — survives oldsrv-down for HA+DNS-UI |
| router/switch/APs | Network | RB4011 inter-VLAN + WG S2S + CAPsMAN; CRS328 L2 PoE |

**Key flows**
- Home↔VPS: single WG S2S tunnel (`wg-s2s`), least-access AllowedIPs both sides + RouterOS forward ACL.
- Cold/bulk data: Hetzner live Box (CIFS on VPS) for Immich originals/encoded-video + OpenCloud files;
  hot state on VPS NVMe; NAS holds snapshots/dumps/state pushes + media library.
- Backup: Kopia (VPS + oldsrv) → backup Box over SFTP; ZFS send/recv tank→bulk; media deliberately
  unbacked (redownloadable).
- Deploy: Renovate PRs → Forgejo Actions deploy button → Ansible (single path, idempotent re-render);
  compose rendered per service from group_vars with fail-loud 1Password lookups.
- HA: keepalived VIP on Home VLAN; identical configuration.yaml rendered to both nodes; manual
  takeover/failback runbooks; Pi mini-edge keeps `ha` + DNS-secondary UI alive when oldsrv is down.

**Assessment:** the shape is sound and unusually disciplined for a homelab: clear plane split,
SSOT direction (IaC → generated docs), validation gate, explicit deploy-gating, accepted-risk log.
The weaknesses below are mostly coupling and drift-management, not design errors.

## 2. Structural weaknesses

| # | Weakness | Impact |
|---|----------|--------|
| W1 | **Single WG S2S tunnel couples the planes.** Immich uploads (VPS) round-trip ML inference to oldsrv; LiteLLM→Ollama chat quality depends on home uplink; Alloy telemetry dies with the tunnel. Documented as accepted for observability, but the photo-upload path makes home connectivity a dependency of the *public* tier's core feature. | Family-visible degradation when home internet is down; hard-to-diagnose latency complaints. |
| W2 | **Cert-issuer ambiguity** (VPS vs oldsrv ACME) leaves the wildcard-cert lifecycle undefined — renewal, DR, and the Pi sync design all hinge on it. | Renewal failure = total TLS outage; ambiguous DR steps. |
| W3 | **Derived-data duplication across IaC**: VLAN map ×3, AllowedIPs ×2, host IPs in host_vars + SSOT lookups. Comments say "keep in sync" — that is manual work with silent-failure mode. | A VLAN/IP edit that misses one copy produces half-applied network config. |
| W4 | **Docs/IaC drift after big decisions** (HD-135 split, HD-13 parking): README/deployment-tasks/services-matrix still describe pre-split placement. The validation gate catches template/IP drift but not *prose* drift. | Rebuild-from-docs produces the wrong system; audit cost stays high (this whole report exists because of it). |
| W5 | **Version-pin law vs reality gap**: 21 templates on bare latest + mutable aliases while the convention says otherwise and HD-134 is marked done. | Supply-chain exposure + false confidence in the tracker. |
| W6 | **Monitoring role monolith** (Alloy+Prometheus+Loki+Grafana in one role): any dashboard/rule tweak redeploys the whole backend chain. | Slower iteration on the most-frequently-tuned layer. |
| W7 | **Public-record migration half-done**: cloudflare_dns vars manage only `vps`; live zone and file are acknowledged dual sources of truth. | DNS changes are hand-coordinated; split-horizon guarantee rests on discipline. |
| W8 | **No automated Ansible-level check in the gate** (compose/blueprint/docs are linted; role logic is not). HD-137 (nonexistent modules) class bugs reach deploy time. | Late failure discovery on the least-testable layer. |
| W9 | **Homepage public-path under-specified**: homepage runs on oldsrv but is documented as the public root behind Forward-Auth; no route/backends entry defines how VPS edge reaches it. | First deploy of the root URL will require an undocumented decision mid-flight. |
| W10 | **Bootstrap-window exposures** on switch/AP templates (unbound mgmt services) and placeholder-driven preseeds without loud guards. | Small but real windows of misconfiguration during the irreversible Phase 1.5 cutover. |
| W11 | **ACME dual-issuer is structural, not textual** (deep-dive escalation of W2): the same traefik template — self-declared single issuer, with ACME + certs-dumper enabled — deploys unmodified on both oldsrv and the VPS. Until an issuer parameter exists, the wildcard-cert lifecycle has two competing state machines. | Cert renewal races, divergent cert outputs, silent Pi-sync breakage. |
| W12 | **oldsrv off-site backup path missing from the SSOT** (deep-dive): backup.md's Kopia-on-oldsrv story has no deploying service in `group_vars/home_servers.yml`. | oldsrv-local state (dumps, service state, configs) is single-copy on NAS pushes until fixed. |

## 3. Improvement proposals

### Quick wins (hours, no design change)
1. Decide the cert issuer (W2/W11) — one changelog entry, an `acme_issuer` host flag in the traefik
   template, and four text fixes; unblocks Phase 1 verification.
2. Add `vps` to site.yml guard scope; bind mgmt services in crs328/ap bootstrap templates (W10).
3. Fix todo.md broken tables + deployment-tasks phase sweep (W4's worst offenders).
4. Define the Homepage public route explicitly (W9): either a VPS Traefik route → oldsrv over WG
   (documented backend), or move Homepage to the VPS and keep an internal-only launcher on oldsrv.
5. Fix the two deploy-blocking template bugs (immich ML URL; Pi HA file-ordering — `iac-changes.md`
   §11 D1/D2) before their phases run.
6. Add the oldsrv Kopia agent (or re-scope backup.md) before Phase 8 (W12).

### Medium (days)
5. Version-pin completion sweep (W5) — mechanical, biggest risk-reduction per hour.
6. Derive router/switch VLAN views + AllowedIPs from the SSOT lists (W3).
7. Split monitoring role task-files + tags (W6) — no structural move, just include_tasks layout.
8. Add `--syntax-check` (and optionally `ansible-lint`) to validate-all.sh (W8).
9. Complete the cloudflare_dns record migration so the file becomes the full public SSOT (W7),
   then render the human mirror into a `-generated` doc.

### Bigger reworks (only if pain materializes)
10. **ML-path decoupling (W1):** if upload-time ML latency over the tunnel proves annoying, options in
    order of cost: (a) queue ML jobs asynchronously (Immich does this natively — verify smart-search
    lag is acceptable); (b) run a second immich-ml instance on the VPS CPU for search-critical
    embeddings while GPU stays on oldsrv for faces; (c) accept and document. Do nothing preemptively.
11. **Second local node (Phase 2)** remains the real fix for oldsrv SPOF (media/DNS-primary/GPU);
    already planned as HD-41/42 — no change proposed, just confirming the trigger condition
    ("when Phase 1 proves insufficient") is still the right bar. It is.
12. **Config management for the family desktop side** (client/office-bridge distribution is
    Headscale-served today): if more client-side tooling appears, consider promoting it into the
    Ansible inventory as `desktop_clients` hosts rather than ad-hoc scripts. Not needed at current
    scope (one bridge app).

## 4. What is deliberately *not* a problem

- **Manual HA failover** — correct choice; automation would add false-positive risk to the most
  safety-critical flow in the house.
- **Media unbacked by design** — redownloadable; storage.md documents the exception honestly.
- **Ansible-only deploy (Doco-CD dropped)** — one path beats two; the docker.sock argument was right.
- **No Alertmanager** — Grafana Unified Alerting + NUT-side notify fallback covers Phase 1; the
  escape hatch is recorded.
- **49 individual compose templates** — verbose but greppable and Renovate-friendly; resist the urge
  to abstract beyond shared fragments for logging/restart.

## 5. Verdict

Architecture is coherent, security-conscious, and honest about trade-offs. The dominant risk to it
is not technical debt in code but **documentation drift from its own decisions** — every [H] finding
in `docs-vs-iac.md` traces to a decision that updated IaC without sweeping prose. The conventions
amendments in `conventions-sugestions.md` (derived pointers, audit lifecycle, single cert issuer)
attack exactly that class; adopting them is cheaper than running this audit again next quarter.
