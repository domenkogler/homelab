# Todo Split — Pure AI vs Blocked/Owner (planning view)

> **Role:** hand-curated planning view of [`todo.md`](todo.md) split into (A) tasks an AI can execute now with no owner step and (B) tasks ⏳ blocked on an owner action — "what to do next" at a glance. **`todo.md` stays the registry SSOT** (row deleted when fully done, CONVENTIONS §4(a)); this table only cross-links owning-doc status blocks and must be kept in sync with todo.md on every backlog change. Content reflects the 2026-09-08 handoff state; authoritative detail lives in `todo.md` rows + owning docs.
> **Linked from:** [`todo.md`](todo.md) · [`prompt.md`](prompt.md) · [`README.md`](README.md)

---

## Table A — Pure AI / unblocked (no owner step needed)

Rows where the AI can act **now** without any new human input. Inline notes flag the only soft gates (maintenance windows / deploy points).

| HD | P | Task | Why AI can do it now |
|----|---|------|----------------------|
| **Network** ||||
| HD-03 | 1 | Final inter-VLAN matrix audit + Kids forced-DNS / Home-drop live-verify | Read-only router audit + live-verify via RouterOS API — no owner action |
| HD-182 | 2 | Kids VLAN firewall live-verify (forced-DNS hijack, Kids→Home drop) | Rules are IaC'd; verify against live RB4011 via API |
| HD-217 | 2 | Homepage failover-button gate off on next green vps.yml | The IaC + owner sign-off are done; just render/deploy |
| HD-159 | 2 | `wg-s2s-down` alert live-verify | AI can run the deliberate `wg down` test (needs a brief planned tunnel-down window) |
| **Storage / UPS** ||||
| HD-132 | 2 | Authentik-LDAP provider + outpost + seed `authentik-ldap_bind` + live-verify Samba | nas (Phase 2) is live; provider/outpost creation + seeding are API/1P work |
| HD-207 | 1 | Landing-zone redistribution **mechanics** | Moving data is AI-work; only the final *media rename vs personal-files* call is owner (split) |
| HD-191 | 2 | oldsrv Kopia **restore drill** + volume-name pin (first snapshot DONE 2026-09-08) | Machine-recover one snapshot; owner confirms the restore target |
| **Platform / secrets** ||||
| HD-211 | 1 | `expiring=False` verification of every persisted Authentik API token | ✅ Done 2026-09-08 (Authentik API audit) — only on-exposure rotation of `vps-op-write_api` remains = owner, Table B |
| HD-160 | 2 | Create `immich-ml-internal_api` + `openclaw-opencloud_api`, verify Immich v3 env names | ✅ items created + env verified; ⏳ live-verify round-trips ride oldsrv GPU leg → **Table B** |
| HD-280 | 2 | Confirm a 401/403 triggers a fail2ban ban | Observation job — waits for natural SSO brute-force (no work product) |
| HD-287 | 2 | `cap_drop: ALL` live cap verification | **Re-scoped**: ollama removed (spark); immich-ml is deploy-gated on the oldsrv GPU leg → **Table B** |
| **Services / edge** ||||
| HD-288 | 1 | Reconcile stale `security.md` §3 port note — ✅ **DONE 2026-09-08** (security.md §3 now matches in-template HD-62: all-interface host ports by design, time-limited manual-start) | Pure AI doc fix done; Sunshine live-verify (gaming timer + Moonlight round-trip) stays Phase-3-gated → Table B |
| **AI / Office** ||||
| HD-100 | 2 | Create `litellm_master_key` + pin `litellm_version` (+ live-verify completions) | Provider keys were confirmed real in HD-211; item creation is AI |
| HD-247 | 1 | LiteLLM scoped-keys cutover: seed db → converge → model recreation → live-verify | All AI (ollama backend rides oldsrv Phase 3) |
| HD-103 | 2 | Docling OCR first start + Slovenian scan verify | AI (oldsrv live) |
| HD-104 | 4 | OpenClaw `onboard` + round-trip | AI |
| HD-111 | 2 | Office MCP via OWUI (`ppt-mcp` first) | AI |
| HD-248 | 2 | OWUI two-instance split + subdomain remap | AI (depends HD-247) |
| HD-249 | 3 | n8n: audit external webhooks + scoped budget-capped LiteLLM key | AI |
| HD-250 | 2 | DSH onboarding: thin image, compose, Forgejo PAT, headscale serve | AI (depends HD-247) |
| HD-251 | 3 | Fleet-exposure phase-2 rollout (tailscale-first) | Doc policy already landed; rollout is AI |
| HD-336 | 2 | agent-memory.dev per-project on oldsrv | oldsrv live; AI (CrewAI pilot is owner-gated → Table B) |
| **Smart Home** ||||
| HD-14 | 2 | Enable HA Prometheus exporter (entity list) | AI |
| HD-17 | 2 | Create `ha-failover_api` + deploy failover button | RFUSB-move tail is **obsolete (HD-13 rejected)**; standby is already rendered live (HD-318c) |
| HD-185 / HD-124 | 1/2 | secrets.yaml renderer + keepalived deploy-verify | ✅ done+live (Pi Phase-4 2026-09-03; re-verified) — verify tails closed |
| **Obs / backup / docs** ||||
| HD-342 | 2 | Kopia client wiring for `/srv/docker/victoria-*/data` | AI; oldsrv MCP tail = HD-344 (Table B) |
| HD-343 | 2 | Network Clients: wifi-path verify (`registration-table` vs legacy) + VPS Grafana converge | Router-side + converge are AI; **panel render-verify is owner** (Table B) |
| HD-49 | 3 | Matrix identity/media backup policy | AI doc (policy before live deploy) |
| HD-238 | 3 | oldsrv→VPS DR runbook for non-GPU services | AI doc |
| HD-32 | 4 | Family guides `docs/manual/*` (Slovenian) | AI doc |
| HD-133 | 3 | Subscription renewal reminders (SSOT + Homepage + n8n) | AI |
| HD-40A/40B/135, HD-43/44, HD-46/47/122 | 1–4 | VPS-edge / media-ops / Matrix tails | Read **stale** vs the 2026-09-04 world (Phase 1 live, Phase 2/4 live) — worth a close-out audit pass rather than new work; Matrix deploys still chain on Phase-3 hosts |

---

## Table B — ⏳ Blocked / needs an owner step

Grouped by *why* it's blocked. The first two groups are the real unblockers — clearing them cascades to the rest.

| HD | P | Task | Owner step required |
|----|---|------|---------------------|
| **Group 1 — oldsrv Phase-3 blockers (the big chain)** ||||
| HD-318 | 1 | oldsrv Phase-3 provision | ① ONLYOFFICE repo/key, ② **ROCm pins decision**, ③ 1P `pihole_password` / `sonarr_api` / `radarr_api`. (kopia tail auto-unblocks once the VPS leg converges — post-Victoria) |
| HD-318a | 1 | kopia-agent crash-loop | ✅ **VPS leg done** (fingerprint seeded 2026-09-08, kopia-server Up); ⏳ **oldsrv re-render pending** — scoped `docker_services_scope=kopia-agent` converge → live-verify Up + first snapshot
| HD-344 | 3 | MCP Victoria servers on oldsrv (pi/OWUI/OpenClaw registration) | Chains on oldsrv Phase-3 + HD-342 backend |
| HD-288 | 3 | Sunshine live-verify (Moonlight round-trip) | Chains on oldsrv Phase-3 (manual-start test) |
| HD-46 / HD-122 | 4/2 | Matrix IaC deploy + federation live-verify | Chains on Phase-3 hosts + owner OIDC records (HD-147) |
| **Group 2 — owner manual / physical / browser / 1P seeding** ||||
| HD-08 / HD-06 | 1/2 | UPS battery-pull test | Owner **physical** test — all client legs (nas/oldsrv/pi) now ACTIVE (2026-09-08), so the pull exercises OB/RB + alerts end-to-end |
| HD-319 | 1 | Confirm 3 rekuperator GAs (12/1/*) answer on the KNX bus | Owner verify (HA UI / panel warnings) |
| HD-316 | 1 | Homepage launchpad — family sees apps green; technical section renders | Owner **visual** verify |
| HD-315 | 1 | Grafana dashboard render-verify with data (post-Victoria) | Owner **visual** verify (panels + data sanity; **data now flowing** — all 4 hosts + probes, HD-346 closeout) |
| HD-343 | 2 | Network Clients dashboard — panels render + visible on `stats.kogler.si` | Owner **visual** verify (pre-work is AI — Table A) |
| HD-242 | 2 | Metabase SELECT-only feeds | Owner seeds `metabase-forgejo_ro` **first** (fail-loud otherwise) → then AI converge + verify |
| HD-112 | 2 | Zipline public bin | **First deploy human-gated** + local-admin → OIDC login → flip bypass-local-login (then AI round-trip verify) |
| HD-101 | 2 | OWUI SSO → Authentik round-trip → local-admin linked | Owner **browser login** step after AI deploy |
| HD-147 | 1 | OIDC live-verify: matrix / claw / cloud / foto / immich / forgejo-register | Owner **browser logins** (Phase-3-gated for the host-side parts) |
| HD-194 | 1 | `sso` middleware: confirm login + one OIDC callback e2e at deploy | Owner browser confirmation |
| HD-219 | 1 | Forgejo install wizard | Owner **browser** (renovate/kopia tails then close) |
| HD-220 | 1 | Renovate token validity check | Owner confirms once Forgejo green (kopia seed is AI — Table A) |
| HD-230 | 1 | Phase-1 wave-2 batch | Kopia **source-wiring decision** (owner); the rest is converge/verify = AI |
| HD-211 | 1 | Secret hygiene | ✅ rotation + `expiring=False` audit done (2026-09-08) — only on-exposure re-rotation of `vps-op-write_api` remains (owner, no-op today) |
| HD-57 | 3 | Finance: Actual Budget / Enable Banking | Owner: **human tokens + EB app creation** (then AI WG scope + deploy at Phase 3) |
| HD-296 | 1 | `dsh` / `pi-dev` tailnet A-records | Row is **labeled owner**: scoped converge `docker_services_scope=headscale` + `dig` verify |
| HD-268 | 1 | Tailnet sidecar enable-flow (Qdrant swap, pi-dev/DSH UIs) | Owner 4-step: mint preauth keys → seed 1P → flip flags → converge → verify UIs (then AI embed/re-index) |
| HD-264 | 2 | Renovate → real repos | Owner: commit versioned manifest to `domen/test`, verify PR path, **flip `RENOVATE_REPOSITORIES`** |
| HD-207 | 1 | Landing-zone redistribution | Owner: final **media rename vs personal-files** decision (mechanics = AI, Table A) |
| **Group 3 — owner-gated / high-risk / hardware / parked** ||||
| HD-04 | 1 | Pi redo: HAOS → Debian + HA Container (in-use migration) | **Owner-gated execution** — live-family HA; needs a scheduled window + sign-off |
| HD-312(4) | 2 | n8n firmware workflow — flow authoring (temp `iot-wan-allow` toggles) | **OWNER-GATED, joint AI+owner** (the `n8n` router API user is **LIVE** — 1P item created + router converged, HD-312(4) closeout) |
| HD-335 / HD-337 | 2 | spark (ThinkStation PGX / GB10) bring-up | Owner **physical**: DGX OS install → then AI role/placement/Triton/Mem0 |
| HD-336 | 2 | CrewAI epic orchestration pilot | Owner milestone gate ("homelab-finished") — agent-memory part is AI (Table A) |
| HD-34 | 4 | Kopia Web GUI vs CLI assessment | At the owner-run yearly restore drill |
| HD-243 | 4 | Metabase LDAP auth | Parked — owner **trigger**: second regular human user needs Metabase |
| HD-261 / HD-262 / HD-45 / HD-36 / HD-41 / HD-48 / HD-129 | — | Optional / Phase-2 / superseded | Deferred by design — no owner action pending |

---

## Bottom line

- **Best pure-AI starters right now:** HD-03 + HD-182 (router read-only audit/verify using the mikrotik skill — zero risk), HD-211/160 (1P + auth wiring), HD-342 (Victoria kopia tail).
- **The single highest-leverage owner step** is HD-318 group: ① ONLYOFFICE repo/key, ② ROCm pins decision, ③ the three 1P items — it cascades to HD-344, HD-288, HD-46/122, HD-101, HD-147. After that, the 1P seeds in HD-242/268/296 unblock the rest of the deploy-gated batch.
- **Stale rows note:** HD-40A/40B/135/43/44 read stale versus the README's "state of the world" (Phase 1 live, Phase 2/4 live) — an AI close-out audit (verify live state, then delete/trim per todo.md §4(a)) is itself a good pure-AI table-A task.