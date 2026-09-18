# Todo Split — AI-Runnable vs Human-Gated (planning view)

> **Role:** hand-curated planning view of [`todo.md`](todo.md) — every open row of the registry, seen as **what to do next**, split into (AI) work an agent can execute now, an (AI) **deploy-gated** chapter whose only blocker is a human step, and (Human) work that is **🚧 owner-gated**. **`todo.md` stays the registry SSOT** (CONVENTIONS §4(a): a fully-done row is deleted from the registry; this table is a view, not a second record) and **must be re-synced whenever the backlog changes**.
> **Linked from:** [`todo.md`](todo.md) · [`prompt.md`](prompt.md) · [`README.md`](README.md) · [`scripts/README.md`](scripts/README.md)
>
> **Rebuilt 2026-09-18** from the post-sync `todo.md` — every open row in it, active and parked. The previous version of this table was still describing the **2026-09-08** world — it recommended work that is long done (LiteLLM 1P wiring + scoped-key cutover: live), called already-deployed services "pending" (Matrix, Zipline, Navidrome), and marked signal alerting "closed" while the SSOT still has no recipients value. Status claims here were checked against **live state** (`docker ps -a` + label inspection on the VPS, `spark` engine/watchdog state, IaC `group_vars`/`host_vars`, owning-doc ✅ lines) rather than against the older table.

---

## Table AI — doable now (no owner step in front)

Ordered by what actually unblocks the most. ⏳ = the exact next action, not a restatement of the row.

### 🔥 Active lanes

| HD | P | ⏳ Next action | Why nothing blocks it |
|----|---|----------------|------------------------|
| **HD-386** | 1 | Converge oldsrv `--tags docker_services,lan-litellm` (**both** tags), detached, **no `--diff`**; expect `dsh`/`pi-dev` + the key glue to SKIP, `failed=0` | The park is authored + validated; only the converge is missing. ⚠ Needs oldsrv SSH (see the reachability blocker below) |
| HD-356 | 1 | Once HD-386 converges green, re-check the LAN instance (live + serving); only the scoped-key glue tail remains — parked, not fixed (→ HD-383) | The split itself is deployed + healthy |
| HD-382 | 2 | Only tails left: the scoped-key allowlist question is **HD-384** (owner), the stale `dsh` secret is **HD-383** (owner) | The model entry is live in both LiteLLM DBs + E2E verified |
| **HD-387** | 2 | Run the written probe protocol against the LAN instance (baseline → toggle → budget pair → `top_k` → the proxy's own dropped-params log) | Decides whether the simple-querier tier may rely on thinking being OFF. Master-key path, no client change |
| **HD-395** | 2 | Baseline the watchdog recycle only after `/health` 200 **and** a settle window (or max of N samples), then re-check the +8 GiB margin against the certified peak | Measured defect: the first-post-boot boot floor has been read 71,911 / 86,243 / 92,343 MiB on one config → the guard either restarts a healthy engine or goes silent |
| **HD-394** | 2 | List every running container without a `com.docker.compose.project` label, propose removal (owner OK before deleting), record in `services-vps.md` | `confident_shamir` (hand-run traefik, no nets/ports) + `pgvector` (superseded by Qdrant) are invisible to every converge |
| **HD-376** | 2 | Promote the `spark-lane` 64k profile; run the 262k needle test; measure parent-vs-lane KV contention | Engine + harness config are live; the lane profile is authored-on-paper only and the 262k test still gates agentic max-context work |

### AI / Office

| HD | P | ⏳ Next action | Why |
|----|---|----------------|-----|
| HD-369 | 2 | (c) recreate the pinned-AI catalog via the LiteLLM API (`ollama/bge-m3` @1024, `ollama/qllama/bge-reranker-v2-m3:q8_0`, `ollama/sendmeaiohyeah/whisper-large-v2`) → (d) voice re-point → (e) Sunshine priority glue → (f) `rocm-smi` VRAM/concurrency verify | (a)/(b) are live on oldsrv; the rest is admin-API + converge work. ⚠ Do **not** bump the ollama `:rocm` pin — rerank/STT leave Ollama (decision #25/#27) |
| HD-360 | 2 | Declare the LDAP provider + `svc_samba` in the Blueprint, mint a fresh `authentik-ldap_bind`, redeploy `authentik-ldap`, **then** flip `storage_samba_passdb: ldapsam` + converge nas | Pure IaC + 1P. ⚠ Order is safety-critical: smbd fails hard if the flip lands before the outpost |
| HD-268 / HD-337 / HD-335 | 1–2 | Qdrant embed/rerank + **re-index** after the bge-m3/1024 cutover, OKF wiki repo skeletons, then Mem0 + OpenHands | Qdrant is live; the harness half of HD-268 is parked with `dsh`/`pi-dev` (HD-386 + decision #26) |
| HD-336 | 2 | agent-memory.dev per-project on oldsrv + ZeroClaw runner | Spec lives in `services-ai.md` §9b; does not wait on the CrewAI decision (HD-336b) |
| HD-248 | 2 | **First settle the banner contradiction** (see watch-list), then parametrize the OWUI template and deploy the second instance | The row's premise ("x2 live") is false on the box — building on it would duplicate a service that does not exist |
| HD-104 (+ HD-160) | 2 | `openclaw onboard` → `openclaw.json`, then the OpenCloud WebDAV round-trip | Container Up/healthy; only onboarding + verify remain |
| HD-103 | 2 | Trigger the first HF model download + verify a Slovenian scan end-to-end | Docling is Up on the VPS |
| HD-111 | 2 | `ppt-mcp` first, register MCP servers in OWUI | Nothing gates it except the OWUI instance question above |
| HD-249 | 3 | Audit external webhook deps + `WEBHOOK_URL`, then mint a budget-capped LiteLLM key for AI workflow nodes | n8n live behind the tailnet edge |
| HD-251 | 3 | Roll out the tailscale-first tiers (Headplane, Dozzle, Metabase, Grafana, Traefik-dash) | The policy/doc half landed 2026-08-26 |
| HD-373 | 2 | Pick (a) nginx SPA fallback / Traefik `PathPrefix(/ui/)` rewrite, or (b) route-scoped forward-auth on `/ui/*` | Workaround (`/fallback/login`) works, so this is a real fix, not a fire |
| HD-380 | 2 | Passive: watch `samples.csv` for a curve growing > 2 GiB/h under traffic that does not return at idle — that, and only that, re-arms C3. Plus the **never-measured prefix-cache/preemption check** across the 16 GiB raise | Certified state is stable; this row is the standing watch + one cheap measurement |

### Network / platform / security

| HD | P | ⏳ Next action | Why |
|----|---|----------------|-----|
| HD-357 | 2 | Wire the Homepage tiles/widgets to the verified endpoints (home edge + VPS edge), then hand the visual check to the owner | Endpoints and route tables are final; bug #6 is wiring |
| HD-358 | 2 | Record the Seerr→\*arr API-key + URL hand-off as a runbook step (and consider automating it in IaC) | Home edge is up; the step is documentation + optional IaC |
| HD-122 | 2 | Verify Matrix profile auth **now** (the servers have been live since 2026-08-22) | The row used to wait on a deploy that already happened |
| HD-47 | 3 | Publish `matrix`/`chat` + `_matrix` well-known/SRV, then prove inbound federation from an external server | Servers are live; the records are the only missing piece |
| HD-112 | 2 | Post-up seeding: local admin → OIDC login (owner browser at that one step) → flip `bypass-local-login` → create `guestbin` + `dropzone` → round-trip + 6 h sweep verify | Deployed; the remainder is seeding |
| HD-159 | 2 | Run the deliberate `wg down` test and confirm the `wg-s2s-down` alert fires (needs a short planned tunnel-down window) | Rule + scrape are deployed; never proven |
| HD-09 | 2 | Ride the next router converge import and confirm the UPS web-UI 80/443 Home→Mgmt rule lands | IaC-only so far |
| HD-287 | 2 | Encode `cap_drop: ALL` + the ROCm-init `cap_add` set for immich-ml → oldsrv converge → verify ML inference still works | The gate that blocked it (ML leg live) is met |
| HD-318(b) | 1 | Confirm the recyclarr @daily quality-profile sync landed (after the 2026-09-15 `bind_owner_uid` fix) | Stacks are up; observation only |
| HD-280 | 2 | Observation: confirm a repeated 401/403 actually produces a ban | Jail is live; waits on natural brute-force |
| HD-14 | 2 | Enable the HA Prometheus exporter and export the entity list | The observability gate is gone (Victoria + Alloy live); feeds the HA dashboard |
| HD-17 + HD-217 | 2 | Render the Homepage **IP-only** failover button (`homepage_failover_button`; the RFUSB path is obsolete — HD-18 rejected) | `ha-failover-api` is active on oldsrv since 2026-09-08; only the render remains |
| HD-04 (tail b) | 1 | Restore the oldsrv standby keepalived conf to the **BACKUP 100** variant (the drill left the 120 failover variant) — before the next standby cold boot | A one-file revert the drill left behind; the rest of HD-04 is the owner's failover test |

### Observability

| HD | P | ⏳ Next action | Why |
|----|---|----------------|-----|
| HD-344 | 3 | Register the MCP endpoints in pi / Open WebUI / OpenClaw — **ports are `mcp_metrics_port` 8083 / `mcp_logs_port` 8084**, not :8080/:8081 | Servers live on oldsrv; registration is the whole remaining row |
| HD-345 | 2 | Find why the SNMP `ifOperStatus` walk still yields 0 series (rules on, SNMP enabled) | The only remaining `DatasourceNoData` class |
| HD-342 | 2 | Kopia client wiring for `/srv/docker/victoria-*/data` | The Victoria cutover itself is live; this is the backup tail |

### Docs / policy (no host risk)

| HD | P | ⏳ Next action |
|----|---|----------------|
| HD-238 | 3 | Write the oldsrv→VPS DR runbook for non-GPU services (backup.md section) |
| HD-49 | 3 | Add Matrix identity/media keys to the backup policy (identity reissue breaks rooms) |
| HD-191 | 2 | Run the Kopia restore drill from a snapshot + verify the volume-name pin (owner confirms the target) |
| HD-133 | 3 | Build the subscription SSOT → Homepage/calendar/n8n renewal notify |
| HD-32 | 4 | Write the Slovenian family guides (`docs/manual/*`) |

---

## ⚠ Standing blockers on the AI work above

1. **oldsrv SSH from the workstation is broken on both documented paths** — measured 2026-09-18 (connect timeout on the direct Mgmt-VLAN alias). It gates every oldsrv converge: **HD-386, HD-369(c–f), HD-287, HD-268, HD-360's nas leg, HD-344 registration, HD-318(b)**. Filed as **HD-392 on the unmerged `session/oldsrv-pinned-ai-20260918-1515` branch** — do not open a duplicate; fix or document the working path first.
2. **Never benchmark or converge spark from a session whose own model is spark** (incidents #3 + #6). Live converges run **detached** (`nohup … &` + log + poll), spark via the VPS jump.
3. **Do not merge/converge `main`'s spark values over the certified ones**: the 16 GiB KV pool is the live, certified config.

---

## Table Human — 🚧 owner step first

Grouped by *why*. Clearing these cascades into the AI table above.

### Group 1 — a browser, a phone or a physical act

| HD | P | Owner step | Then the AI does |
|----|---|-----------|------------------|
| HD-147 (+ HD-141 epic) | 1 | Browser logins: matrix / claw / cloud / foto / immich (+ Forgejo register) | Blueprint + glue are live; the AI re-renders inventory + closes the epic tail |
| HD-194 | 3 | Confirm one login + one OIDC callback end-to-end at the edge | Closes audit S17(a) |
| HD-101 | 2 | OWUI SSO → Authentik round-trip, link the local admin | AI verifies LiteLLM completion + RAG after |
| HD-350 | 1 | Authorize oldsrv `/root/.ssh/traefik-cert-sync.pub` on the VPS (the pull 401s until then) | AI verifies the wildcard pair + LAN routes |
| HD-375 | 2 | Confirm the spark host-memory rules in the Grafana UI **and** that they reach n8n | Rules are live in the ruler since 2026-09-17 22:33C |
| HD-347 | 1 | Capture the **"Homelab Alerts" group UUID** into `signal_alert_recipients` (`group_vars/all/main.yml`, non-secret) — the device is linked, the value is still empty | AI re-converges n8n + proves delivery |
| HD-316 / HD-315 / HD-343 | 1–2 | Visual verify: launchpad green, host-overview + probe tables, Network Clients panels + wifi path | AI fixes whatever the eyeball catches |
| HD-377 | 2 | Render `homelab-llm` on `stats.kogler.si` and sign off | AI deletes the three superseded vLLM boards + the three `DCGM_FI_PROF_*` panels that can never fill |
| HD-319 | 1 | Confirm the 3 rekuperator GAs (12/1/\*) answer on the KNX bus | AI closes the KNX render row |
| HD-353 / HD-354 | 2 | Jellyfin login at seerrng; **put music on the Storage Box** + create the Navidrome admin user | AI verifies Subsonic/ExtAuth at the pin |
| HD-06 | 1 | Short UPS pull → poweroff → WoL wake end-to-end | Last open thing in the UPS lane |
| HD-288 | 3 | A manual-start gaming window + Moonlight round-trip | AI pre-verifies Sunshine Up/healthy |
| HD-301 | 1 | A physical reset window on router/switch/APs | AI verifies firewall + service state after each reset |
| HD-34 | 4 | Happens at the owner-run yearly restore drill | AI assesses Kopia GUI vs CLI during it |

### Group 2 — an owner decision or an owner-seeded secret

| HD | P | Decision / seed | Blocks |
|----|---|-----------------|--------|
| **HD-384** | 1 | **Which simple querier gets what** — HomeAssistant / Docling / OWUI: `spark/*` vs `ollama/*`, with `max_budget`/`rpm`; plus hardening `spark-llm_api` (triple-used today) | The LAN `bootstrap_keys` flip back to true; any scoped consumer of `spark/*` |
| **HD-385 / #27** | 2 | Ratify decision **#27** (pinned-AI engines → the ggml/Vulkan family) — filed on the unmerged oldsrv branch with measured numbers | The two oldsrv pinned-AI services + the LiteLLM/voice re-point |
| **HD-388** | 2 | Choose the renderer shape (Jinja alongside `render_all.py` vs a standalone script) | Rendering `pi`/`continue` client config from one repo spec |
| **HD-383** | 1 | Vault + Admin-UI remediation of the stale `dsh` secret (documented in the script header; deliberately **not** automated) | Un-parking any scoped-key record; today it is unreachable, not fixed |
| HD-336b | 2 | CrewAI pilot: run the 2-week slice / later / never | Nothing else (HD-336 is unblocked) |
| HD-361 | 1 | Create the `nas_maint_login` 1P item + choose the break-glass password | AI adds the `maint` PAM identity (sudo group, NO NOPASSWD, no SSH keys, excluded from `AllowUsers`) + a `pamtester` verify path — `cockpit-nas.kogler.si` has **no working login today** |
| HD-362 | 2 | Real values for the music-pillar 1P placeholders (`slskd_login`, `soulseek_api`, `lidarr_api`, …) + wire Lidarr download clients in the UI | The music pillar's last mile |
| HD-57 | 3 | Bank tokens + Actual Budget / Enable Banking app creation | AI WG-scopes :5006 + deploys + verifies |
| HD-230 | 1 | Kopia source-wiring decision (which data sources get backed up) | AI's surgical converge + the wave-2 verifies |
| HD-207 | 1 | Final **media rename vs personal-files** call | AI's landing-zone redistribution mechanics |
| HD-386 tail | 1 | Whether to drop the `dsh`/`pi-dev` tailnet names + `dsh-backend`/`pi-backend` routes (they answer 502 by design) | — |

### Group 3 — owner-hold / deliberate non-work

| HD | P | Why it waits |
|----|---|--------------|
| HD-366 | 2 | **Deliberately untouched since 2026-09-15 by owner instruction** — JupyterLab LAN edge. Route exists; do not spend a converge on it until asked |
| HD-312 | 2 | Observation only (bedtime window + Kids-Group filtered-DNS binding) — close on the first owner sighting |
| HD-359 / HD-367 | 1–2 | Bench lane: the engine + `spark-ai.enabled` are certified; what is left is the S2/S3 NVFP4×SGLang lane + the 262k needle test (rides HD-376) — owner decides when a bench window is worth the box |

---

## ⚠ Watch-list — reads as done, is not

Checked 2026-09-18 against live state. Each of these has already fooled one document.

| Claim you might believe | Reality |
|---|---|
| "Signal alerting is closed" | Device linked ✅, workflow live ✅ — but `signal_alert_recipients` is still **empty** in SSOT, so nothing is delivered to the group (HD-347) |
| "Open WebUI ×2 is live" (`services-ai.md` banner) | The VPS runs **one** `open-webui` at `ai.kogler.si`; the `chat` service is **element-web**, not a second OWUI instance. HD-248 is open and starts by correcting that banner |
| "Navidrome never deployed" | Deployed: container Up, `/mnt/storagebox/music` → `/music` ro, scanner ran. The **library is empty** and no admin user exists (HD-354) |
| "Matrix waits on unprovisioned hosts" | Tuwunel + Element have been live since 2026-08-22; HD-46 was deleted as done, HD-47/122 are verifies now (Cloudflare records + profile auth) |
| "Zipline's first deploy is human-gated and pending" | `zipline` + `zipline-db` are Up/healthy — only post-up seeding is left (HD-112) |
| "Forgejo install wizard / Phase-1 incident batches are open" | Installed (`INSTALL_LOCK`) and the incident batches landed; HD-219/HD-220 are deleted rows |
| "The watchdog's idle recycle is a safe background detail" | It restarted the engine twice 35 min apart on a healthy box; its baseline is boot-timing-dependent (HD-395) |

---

## Park / moot

| HD | P | Status |
|----|---|--------|
| HD-45 | 3 | Homelable + network dashboard — a parallel lane owns implementation; do not re-plan |
| HD-264 | 2 | Renovate sandbox `domen/test` — parked, owner steps (external re-launch mechanism, real manifest, then flip `RENOVATE_REPOSITORIES`) |
| HD-250 | 2 | DSH onboarding — **parked with the service** (`enabled: false`, HD-386) and moot under decision #26 (harnesses go direct) |
| HD-28 | 3 | Office AI stack — not parked but **not startable**: its Ollama half is superseded by #24/#25 and its MCP half waits on HD-111 |

---

## Bottom line

- **Best pure-AI picks right now:** `HD-387` (settles a live contradiction with a 20-minute probe), `HD-395` (a measured defect that restarts a healthy engine), `HD-394` (census: two containers no converge will ever clean up), `HD-47` + `HD-122` (federation is one DNS change + one verify away), `HD-357`/`HD-358` (two named bugs on the launchpad and the media stack).
- **Highest-leverage owner steps, in order:** ① `HD-347` recipients value (one string — alerting is otherwise blind), ② `HD-350` pubkey authorization (unblocks the home-edge cert chain), ③ `HD-384` (which consumer may call what — it unblocks the LAN key glue), ④ `HD-377` + `HD-375` sign-offs (they retire three dashboards and close the alert lane), ⑤ `HD-147` browser logins (the last big OIDC tail).
- **Before any oldsrv work:** resolve the SSH reachability blocker (HD-392, unmerged branch) — six rows above are silently gated by it today.
