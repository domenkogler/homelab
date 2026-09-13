# Todo Split — AI-Runnable vs Human-Gated (planning view)

> **Role:** hand-curated planning view of [`todo.md`](todo.md) split into (AI) tasks an AI can execute (the last Table-AI chapter holds the rows whose **deploy is AI but wait on a human prerequisite** — they run as soon as Table Human clears), and (Human) tasks **🚧 human-gated** (need an owner step first). — "what to do next" at a glance. **`todo.md` stays the registry SSOT** (row deleted when fully done, CONVENTIONS §4(a)); this table only cross-links owning-doc status blocks and must be kept in sync with todo.md on every backlog change. Content reflects the 2026-09-08 handoff state (re-synced after the oldsrv **Phase-3 complete** close-out: HD-318a kopia tail CLOSED; HD-160/287 gates met → Table AI; HD-211 = done, owner-only on-exposure rotation); authoritative detail lives in `todo.md` rows + owning docs.
> **Linked from:** [`todo.md`](todo.md) · [`prompt.md`](prompt.md) · [`README.md`](README.md)

---

## Table AI — AI-runnable (no AI-side blocker)

Rows the AI can execute: either **now** (no prerequisite) or the **⏳ deploy-gated chapter at the bottom** (AI does the deploy/verify; only a Table-Human step is missing). Inline notes flag the only soft gates (maintenance windows / deploy points).

| HD | P | Task | Why AI can do it now |
|----|---|------|----------------------|
| **Network & DNS** ||||
| HD-217 | 2 | Homepage failover-button gate off on next green vps.yml | The IaC + owner sign-off are done; just render/deploy |
| HD-159 | 2 | `wg-s2s-down` alert live-verify | AI can run the deliberate `wg down` test (needs a brief planned tunnel-down window) |
| **Storage / UPS** ||||
| HD-132 | 2 | Authentik-LDAP provider + outpost + seed `authentik-ldap_bind` + live-verify Samba | nas (Phase 2) is live; provider/outpost creation + seeding are API/1P work |
| HD-207 | 1 | Landing-zone redistribution **mechanics** | Moving data is AI-work; only the final *media rename vs personal-files* call is owner (split) |
| HD-191 | 2 | oldsrv Kopia **restore drill** + volume-name pin (first snapshot DONE 2026-09-08) | Machine-recover one snapshot; owner confirms the restore target |
| **AI / Office** ||||
| HD-100 | 2 | Create `litellm_master_key` + pin `litellm_version` (+ live-verify completions) | Provider keys confirmed real in HD-211; item creation + version pin is AI (completion verify rides openrouter cloud — Triton-on-spark local tier is HD-335) |
| HD-247 | 1 | LiteLLM scoped-keys cutover: seed db → converge → model recreation → live-verify | Seed + converge + model recreation + scoped-key/owui/openclaw auth live-verify are AI; completion round-trip rides openrouter (cloud) now, Triton on spark later (HD-335) |
| HD-103 | 2 | Docling OCR first start + Slovenian scan verify | AI (oldsrv live) |
| HD-104 | 4 | OpenClaw `onboard` + round-trip | AI |
| HD-111 | 2 | Office MCP via OWUI (`ppt-mcp` first) | AI |
| HD-248 | 2 | OWUI two-instance split + subdomain remap | AI (depends HD-247) |
| HD-249 | 3 | n8n: audit external webhooks + scoped budget-capped LiteLLM key | AI |
| HD-250 | 2 | DSH onboarding: thin image, compose, Forgejo PAT, headscale serve | AI (depends HD-247) |
| HD-251 | 3 | Fleet-exposure phase-2 rollout (tailscale-first) | Doc policy already landed; rollout is AI |
| HD-336 | 2 | agent-memory.dev per-project on oldsrv + ZeroClaw | oldsrv live; AI (CrewAI pilot split out → HD-336b, Table Human) |
| **Smart Home** ||||
| HD-14 | 2 | Enable HA Prometheus exporter (entity list) | AI — the "wait for observability" gate is gone (Victoria stack + Alloy live, HD-342) |
| HD-17 | 2 | Create `ha-failover_api` + deploy failover button | RFUSB-move tail is **obsolete (HD-13/18 rejected)**; standby is already rendered + api active (HD-318c, 2026-09-08); deploy button + run the owner test (HD-04) |
| HD-185 / HD-124 | 1/2 | secrets.yaml renderer + keepalived deploy-verify | ✅ done+live (Pi Phase-4 2026-09-03; re-verified) — verify tails closed; the failover *exercise* stays owner (HD-04) |
| **Obs / security / backup / docs** ||||
| HD-342 | 2 | Kopia client wiring for `/srv/docker/victoria-*/data` | AI; oldsrv MCP tail = HD-344 (Table AI now) |
| HD-344 | 3 | MCP Victoria servers on oldsrv (pi/OWUI/OpenClaw registration) | Gate met (oldsrv Phase-3 + VPS Victoria backend live) — enable + oldsrv converge + register in pi/OWUI/OpenClaw is AI; only the future tailnet sidecar redo is owner |
| HD-347 | 1 | Observability false-alarm cleanup + alert-router wiring (SNMP ifName labels, n8n webhook workflow, remove mikrotik link-down + stale prometheus/loki rules, arm self-monitoring) | ✅ **CONVERGED + LIVE 2026-09-09** (VPS docker_services,n8n + monitoring already live): n8n SIGNAL_* env live, webhook 200; ⏳ **Signal device link + group UUID** = owner (HD-318d, Table Human) only |
| HD-343 | 2 | Network Clients: wifi-path verify (`registration-table` vs legacy) + VPS Grafana converge | Router-side + converge are AI; **panel render-verify is owner** (Table Human) |
| HD-318(b) | 1 | recyclarr quality-profile sync verify (all *arr + recyclarr Up 2026-09-08) | AI observation — confirm the @daily profile sync landed |
| HD-280 | 2 | Confirm a 401/403 triggers a fail2ban ban | Observation job — waits for natural SSO brute-force (no work product) |
| HD-49 | 3 | Matrix identity/media backup policy | AI doc (policy before live deploy) |
| HD-238 | 3 | oldsrv→VPS DR runbook for non-GPU services | AI doc |
| HD-32 | 4 | Family guides `docs/manual/*` (Slovenian) | AI doc |
| HD-133 | 3 | Subscription renewal reminders (SSOT + Homepage + n8n) | AI |
| HD-40A/40B/135, HD-43/44, HD-46/47/122 | 1–4 | VPS-edge / media-ops / Matrix tails | Read **stale** vs the 2026-09-08 world (Phases 1/2/3/4 all live) — worth a close-out audit pass rather than new work; Matrix deploys now chain on owner OIDC records (HD-147), not host provisioning |

**⏳ Deploy-gated chapter — waiting on a Table-Human prerequisite (AI does the deploy/verify as soon as it clears)**
The deploy/verify here is **fully AI** — the only reason the row isn't already moving is a human prerequisite listed in Table Human. When the human step lands, pick these up first.

| HD | P | Task | AI part (runs on gate-clear) | Prerequisite (Table-Human) |
|----|---|------|------------------------------|------------------------|
| HD-46 / HD-122 | 4/2 | Matrix IaC deploy + federation live-verify | Deploy from `vps.yml` (enabled:true) + federation live-verify + HD-122 hardening verify | Owner OIDC records + provider/redirect URIs — **HD-147** |
| HD-230 | 1 | Phase-1 wave-2 batch | Kopia client wiring + surgical converge + verifies | Owner **kopia source-wiring decision** (owner part of HD-230) |
| HD-57 | 3 | Finance: Actual Budget / Enable Banking | WG-scope the :5006 API leg + deploy + live-verify | Human **tokens + EB app creation** (owner part of HD-57) |

---

## Table Human — 🚧 Human-gated / needs an owner step

Grouped by *why* it's blocked. These are the real unblockers — clearing them cascades to Table AI (including its deploy-gated chapter).

| HD | P | Task | Owner step required |
|----|---|------|---------------------|
| **Group 1 — owner-manual tails on the (now-live) oldsrv GPU leg** ||||
| HD-288 | 3 | Sunshine live-verify (Moonlight round-trip) | ⏳ oldsrv GPU leg is live, but this is an owner **manual-start gaming window** + Moonlight client round-trip — owner keeps the button; AI can pre-verify Sunshine is Up/healthy |
| **Group 2 — owner manual / physical / browser / 1P seeding** ||||
| HD-08 / HD-06 | 1/2 | UPS battery-pull test | Owner **physical** test — all client legs (nas/oldsrv/pi) now ACTIVE (2026-09-08), so the pull exercises OB/RB + alerts end-to-end |
| HD-319 | 1 | Confirm 3 rekuperator GAs (12/1/*) answer on the KNX bus | Owner verify (HA UI / panel warnings) |
| HD-316 | 1 | Homepage launchpad — family sees apps green; technical section renders | Owner **visual** verify |
| HD-315 | 1 | Grafana dashboard render-verify with data (post-Victoria) | Owner **visual** verify (panels + data sanity; **data now flowing** — all 4 hosts + probes, HD-346 closeout) |
| HD-343 | 2 | Network Clients dashboard — panels render + visible on `stats.kogler.si` | Owner **visual** verify (pre-work is AI — Table AI) |
| HD-347 (owner part) | 1 | Signal alert delivery — link the Signal device + set `signal_alert_recipients` | Owner **Signal link** (HD-318d — no device linked yet): once linked, capture the "Homelab Alerts" group UUID + fill `signal_alert_recipients` (all.yml SSOT) → then the n8n Signal leg delivers (the webhook workflow + env wiring are already live, Table AI) |
| HD-242 | 2 | Metabase SELECT-only feeds | Owner seeds `metabase-forgejo_ro` **first** (fail-loud otherwise) → then AI converge + verify |
| HD-112 | 2 | Zipline public bin | **First deploy human-gated** + local-admin → OIDC login → flip bypass-local-login (then AI round-trip verify) |
| HD-101 | 2 | OWUI SSO → Authentik round-trip → local-admin linked | Owner **browser login** step after AI deploy |
| HD-147 | 1 | OIDC live-verify: matrix / claw / cloud / foto / immich / forgejo-register | Owner **browser logins** (Phase-3-gated for the host-side parts) — **also the prerequisite for the Table-AI Matrix deploy (HD-46/122)** |
| HD-194 | 1 | `sso` middleware: confirm login + one OIDC callback e2e at deploy | Owner browser confirmation |
| HD-219 | 1 | Forgejo install wizard | Owner **browser** (renovate/kopia tails then close) |
| HD-220 | 1 | Renovate token validity check | Owner confirms once Forgejo green (kopia seed is AI — Table AI) |
| HD-211 | 1 | Secret hygiene | ✅ rotation + `expiring=False` audit done (2026-09-08) — only on-exposure re-rotation of `vps-op-write_api` remains (owner, no-op today) |
| HD-230 (owner part) | 1 | Phase-1 wave-2 — **kopia source-wiring decision** | Owner decides which data sources kopia backs up → then the AI deploys/verifies the batch (Table AI) |
| HD-57 (owner part) | 3 | Finance — **human tokens + EB app creation** | Owner creates the bank tokens + Actual Budget/Enable Banking app → then the AI WG-scopes + deploys (Table AI) |
| HD-296 | 1 | `dsh` / `pi-dev` tailnet A-records | Row is **labeled owner**: scoped converge `docker_services_scope=headscale` + `dig` verify |
| HD-268 | 1 | Tailnet sidecar enable-flow (Qdrant swap, pi-dev/DSH UIs) | Owner 4-step: mint preauth keys → seed 1P → flip flags → converge → verify UIs (then AI embed/re-index) |
| HD-264 | 2 | Renovate → real repos | Owner: commit versioned manifest to `domen/test`, verify PR path, **flip `RENOVATE_REPOSITORIES`** |
| HD-207 | 1 | Landing-zone redistribution | Owner: final **media rename vs personal-files** decision (mechanics = AI, Table AI) |
| **Group 3 — owner-gated / high-risk / hardware / parked** ||||
| HD-04 | 1 | Pi redo + **owner failover test** (VIP move Pi→oldsrv + failback) | **Pi redo DONE + LIVE since 2026-09-03** — remaining = the owner **failover test** (live-HA window; short blackout OK per owner 2026-09-09); a parallel lane is finishing the button/runbook prep |
| ~~HD-312(4)~~ | 2 | ~~n8n firmware workflow — flow authoring (temp `iot-wan-allow` toggles)~~ | **✅ SUPERSEDED 2026-09-09** — permanent `wan_allow` covers cloud-IoT firmware WAN; no flow authoring (decision log: [network-rejected.md](docs/network-rejected.md)) |
| HD-335 / HD-337 | 2 | spark (ThinkStation PGX / GB10) bring-up | Owner **physical**: DGX OS install → then AI role/placement/Triton/Mem0 — **also gates the LiteLLM completion round-trip** (HD-100/247 Table-AI live-verify currently rides openrouter cloud) |
| HD-336b | 2 | **CrewAI epic orchestration pilot — owner decision** (run 2-week pilot now / later / never) | **Owner decision only** — no AI work until answered (kill criteria: 2-week slice or abandon); does NOT gate HD-336 (agent-memory/ZeroClaw = Table AI) |
| HD-34 | 4 | Kopia Web GUI vs CLI assessment | At the owner-run yearly restore drill |
| ~~HD-243~~ | 4 | ~~Metabase LDAP auth~~ | **✅ REJECTED 2026-09-09** — owner is sole Metabase user; trigger never fires; stays Forward-Auth + local admin-only |
| — | — | ~~HD-261 / HD-262 / HD-36 / HD-41 / HD-48 / HD-129~~ | **✅ CLOSED/REJECTED 2026-09-09** (Mitogen, Yacht, internal AAAA, Proxmox, Matrix bridges, DHCP-resolver) — see owning docs + decision logs; **HD-45 now OPEN as the network-dashboard + Homelable implementation (Table AI)** |

---

## Bottom line

- **Best pure-AI starters right now:** HD-100 + HD-247 (LiteLLM 1P wiring + scoped-key cutover), HD-342 (Victoria kopia tail), **Router steady-state batch = COMPLETE** (HD-03 audit + HD-182 Kids verify closed 2026-09-10 — the two IaC fixes landed, converge import is the single operator step).
- **The single highest-leverage owner (Table Human) step** is the **HD-318-responsive owner batch**: ① ~~signal-cli phone registration~~ **DONE 2026-09-10** (device linked, `homelab-alerts`, delivery owner-verified — HD-318d/HD-347 closed), ② the 1P seeds in HD-242/268/296 (`metabase-forgejo_ro`, preauth keys, headscale A-records) that unblock the rest of the deploy-gated batch, ③ the **HD-04 failover test** (VIP move + failback, being prepped by a parallel lane) — since oldsrv Phase-3 is **complete** (HD-318), the old ONLYOFFICE/ROCm/1P blocker list is retired. Clearing **HD-147 (OIDC records)** also unblocks the Table-AI Matrix deploy (HD-46/122).
- **Stale rows note:** HD-40A/40B/135/43/44 read stale versus the README's "state of the world" (Phases 1/2/3/4 all live) — an AI close-out audit (verify live state, then delete/trim per todo.md §4(a)) is itself a good pure-AI Table-AI task.