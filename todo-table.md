# Todo Split — AI-Runnable vs Human-Gated (planning view)

> **Role:** hand-curated planning view of [`todo.md`](todo.md) — every open row of the registry, seen as **what to do next**, split into (AI) work an agent can execute now, an (AI) **deploy-gated** chapter whose only blocker is a human step, and (Human) work that is **🚧 owner-gated**. **`todo.md` stays the registry SSOT** (CONVENTIONS §4(a): a fully-done row is deleted from the registry; this table is a view, not a second record) and **must be re-synced whenever the backlog changes**.
> **Linked from:** [`todo.md`](todo.md) · [`prompt.md`](prompt.md) · [`README.md`](README.md) · [`scripts/README.md`](scripts/README.md)
>
> **Rebuilt 2026-09-20** from `todo.md` + [`prompt.md`](prompt.md) as they stand after the HD-391 deploy and decision #28. What moved since the 2026-09-18 build of this table:
> - **Added from the docs SSOT sweep (2026-09-20):** **HD-403** (Home Assistant has no LiteLLM path — the voice LLM leg is unwired) and **HD-404** (five stale IaC strings, incl. one that feeds a generated doc), plus ⏳ tails on **HD-384** (LAN has zero scoped consumers today) and **HD-386** (parking the harnesses left their tailnet routes answering 502).
- **HD-391 is CLOSED** (2026-09-19) — the three pinned-AI legs are live on oldsrv, so it is no longer a lane, and the "owner call: ship the rerank leg or park it" question it carried here is **answered**: it ships **dormant**, because its consumer (`rag-mcp`) is the HD-268b compose STUB, not a flag to flip.
> - **HD-392 and HD-398 are deleted rows** (both closed 2026-09-19) — oldsrv SSH is not a blocker, and the Mgmt-plane question is settled as **A: the seal stays** ([network-rejected.md](docs/network-rejected.md)).
> - **Five open rows were missing from this table and are added:** **HD-396** (the last `spark-llm_api` consumer to verify), **HD-385** (now a research record, not work), and the 2026-09-20 vision-tier thread **HD-400 / HD-401 / HD-402** (decision #28).
> - **Re-worded to what the rows actually say today:** HD-393 (re-measured: one bounded episode, not a leak), HD-369 (step (c) is SUPERSEDED — do not recreate the ollama catalog), HD-356 (its glue is OFF by design, not red), HD-386 (the containers are already gone; what is missing is a `failed=0` log), HD-268 (the Vulkan embed move does **not** trigger the Qdrant re-index), HD-384 (it now also carries the HD-400 image→400 consequence).
> Claims were checked against the registry + owning-doc ✅ lines + the live SSOT values, not against the previous version of this table.

---

## Table AI — doable now (no owner step in front)

Ordered by what actually unblocks the most. ⏳ = the exact next action, not a restatement of the row.

### 🔥 Active lanes

| HD | P | ⏳ Next action | Why nothing blocks it |
|----|---|----------------|------------------------|
| **HD-399** | 2 | Make `technitium-seed` `--check`-safe (gate the block `not ansible_check_mode`) so a full `home_servers.yml --check` goes green | Pure IaC defect, found + located 2026-09-19 (`technitium-seed.yml:102`: `uri` does not run in check mode, so `_tech_login.json.token` dies); spec + evidence in [deployment-ansible.md](docs/deployment-ansible.md) §Dry-run Mode. ⛔ No `default()` / `failed_when: false` — fail-loud. Interim green form: `--check --tags common,network` |
| **HD-396** | 2 | Repo-archaeology, one question: does the Forgejo CI runner still exist, and does it still hold the pre-2026-09-19 `op_api` secret? Renew it, or DELETE the stale Phase 0/5 prerequisite lines in [deployment-tasks.md](deployment-tasks.md) | The leak itself is closed (owner rotation, four holders re-audited to one hash, superseded bearer 401s) — record: [deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md) §4a. Nothing in IaC references `op_api` any more, so this is confirmed on the Forgejo side, not from the repo |
| **HD-387** | 2 | Run the written probe protocol against the LAN instance (baseline → toggle → budget pair → `top_k` → the proxy's own dropped-params log) | Decides whether the simple-querier tier may rely on thinking being OFF. Master-key path, no client change; the harness route does not move either way (decision #26) |
| **HD-395** | 2 | Baseline the watchdog recycle only after `/health` 200 **and** a settle window (or max of N samples), then re-check the +8 GiB margin against the certified peak | Measured defect: the first-post-boot boot floor has been read 71,911 / 86,243 / 92,343 MiB on one config → the guard either restarts a healthy engine or goes silent. Drive it from the laptop, never from a spark-backed session |
| **HD-394** | 2 | List every running container without a `com.docker.compose.project` label, propose removal (owner OK before deleting), record in [services-vps.md](docs/services-vps.md) | `confident_shamir` (hand-run traefik, no nets/ports) + `pgvector` (superseded by Qdrant) are invisible to every converge; the third entry, `authentik-ldap` unhealthy, is HD-360's |
| **HD-393** | 1 | Attribute the **one** bounded episode (dmesg 774,316 s → 780,804 s) per-process — journal timestamps vs container restarts inside that window — then fix or record as accepted noise | Re-measured 2026-09-19: 1,296 `amdgpu init_user_pages: -1` lines, **all inside ~1.8 h**, **0 hang/reset** anywhere, zero new lines across the whole HD-391 deploy. ⚠ `dmesg` needs `sudo` on oldsrv (unsprivileged count silently returns 0) and `rocm-smi` lives **inside** `immich-ml`/`ollama`, not on the host |
| **HD-386** | 1 | Converge oldsrv `--tags docker_services,lan-litellm` (**both** tags), detached, **no `--diff`**; expect `dsh`/`pi-dev` + the key glue to SKIP, `failed=0` | The park is authored + validated; only the converge log is missing. ✅ Read-only sighting 2026-09-19: no `dsh`/`pi-dev` containers on the box (34 running, 0 exited) — that is the end-state but **not** the record the row asks for |
| **HD-369** | 2 | **(d)** voice re-point: Whisper → the **live whisper.cpp Vulkan leg** on oldsrv (NOT Ollama), Piper → CPU, LLM → spark; then **(e)** the Sunshine priority glue (pause/unpause pinned-AI + immich-ML) | The tier is LIVE since 2026-09-19, so (d) has something to point at. ⚠ **(c) is SUPERSEDED — do NOT recreate the ollama catalog and do NOT bump the `:rocm` pin**; (f) is done (tier measured 2475 MiB of 8 GiB, 0 hang/reset); the two retired blobs are already deleted (1.5 GB freed) |
| **HD-402** | 2 | Bench before flipping: confirm the Docling `RapidOcrOptions` adapter exposes the PP-OCR `latin` rec model → convert the **same Slovenian scan** with EasyOCR and RapidOCR-ONNX → keep only if quality ≥ EasyOCR → record the speed delta | CPU bench on the VPS, no host risk. Language was never the blocker (`latin` includes `sl`); the risks are the script-grouped model on `č ć š ž` and the adapter wiring. Close with the **HD-103** scan gate. Free lever either way: `do_ocr=False` for born-digital PDFs |
| **HD-401** | 2 | Clear the four pre-flight gates in [hardware-workstation.md](docs/hardware-workstation.md) §Pre-flight gates: pick + record the ROCm/`gfx1151` stack (7.2.1, Vulkan/RADV fallback) · prove the VL `mmproj` runs on the iGPU (measure `--image` prefill) · measure FIM trigger latency on the real Continue prompt shape · check the iGPU carve-out/GTT | The workstation IS the station this agent runs on, so three of four gates are measurable here; a decision (#28) already fixed the placement. ⚠ Every platform figure in that doc is owner-stated/community — **unmeasured on this box** — and installing a ROCm stack on the admin laptop is the owner's call (Table Human) |
| HD-356 | 1 | Re-check the LAN instance (live + serving) once HD-386 converges green; the scoped-key glue tail is **not** a fix — it is OFF by design and rides **HD-384** | The split itself is deployed + healthy. ⚠ Its model role changed with decision #26: gateway for the **simple queriers**, not the coding harnesses |
| HD-382 | 2 | Only tails left: the scoped-key allowlist question is **HD-384** (owner), the stale `dsh` secret is **HD-383** (owner) | The model entry is live in both LiteLLM DBs + E2E verified |
| **HD-388** | 2 | Decide the renderer shape (Jinja alongside `scripts/render_all.py` vs a standalone script), then render `pi` `models.json` + a Continue config from one spec, credential resolved via `op` at render time | Pure repo tooling. ⚠ The template must NOT merge the two `contextWindow` numbers (engine 262,144 vs the LiteLLM row's 245,760 = window − reserve) — they differ on purpose |
| **HD-376** | 2 | Promote the `spark-lane` 64k profile; run the 262k needle test; measure parent-vs-lane KV contention | Engine + harness config are live; the lane profile is authored-on-paper only and the 262k test still gates agentic max-context work. ⚠ Needs a spark bench window (same window as HD-359/367 + HD-400) and never an attached agent session |

### AI / Office

| HD | P | ⏳ Next action | Why |
|----|---|----------------|-----|
| HD-268 / HD-337 / HD-335 | 1–2 | Qdrant embed/rerank + **re-index** after the bge-m3/1024 cutover, OKF wiki repo skeletons (**HD-268a**), then **HD-268b = implement `rag-mcp`** (owner call 2026-09-19: its own lane), Mem0 + OpenHands | Qdrant is live. ⚠ The HD-391 Vulkan embed move does **not** trigger the re-index (same 1024 dims, cosine 0.9996). ⚠ `rag-mcp`'s compose is a TODO comment block with **no `services:` section** — its `enabled: false` is not a flag to flip; until 268b lands, the reranker leg stays dormant (~327 MiB). The harness half is parked with `dsh`/`pi-dev` (HD-386 + decision #26) |
| HD-360 | 2 | Declare the LDAP provider + `svc_samba` in the Blueprint, mint a fresh `authentik-ldap_bind`, redeploy `authentik-ldap`, **then** flip `storage_samba_passdb: ldapsam` + converge nas | Pure IaC + 1P. ⚠ Order is safety-critical: smbd fails hard if the flip lands before the outpost (that outpost is also HD-394's third census entry, Up **unhealthy** = expired token) |
| HD-403 | 2 | Give HA the gateway path: mint a `home-assistant` scoped key vault-first, render `LITELLM_BASE_URL` + key into the compose env, point the Assist pipeline at it | Voice's LLM leg currently has **nothing to call** — HA ships `environment: {}` and has no consumer in either LiteLLM; rides with HD-384 · [smart-home-voice.md](docs/smart-home-voice.md) |
| HD-404 | 3 | Text-only PR: fix the five stale strings (Victoria headers in `home_servers.yml`/`playbooks/storage.yml`, the Pi "primary DNS" comment, the `llm-backend` purpose string that feeds the generated address doc, `amd_rocm`'s `OLLAMA_KEEP_ALIVE`, `first-boot-config.sh`'s `raspi.debian.net` wording) | The docs stopped repeating these, so the comments are now the last place an agent reads the wrong truth · [deployment-ansible.md](docs/deployment-ansible.md) |

| HD-336 | 2 | agent-memory.dev per-project on oldsrv + ZeroClaw runner | Spec lives in [services-ai.md](docs/services-ai.md) §9b; does not wait on the CrewAI decision (HD-336b) |
| HD-248 | 2 | **First settle the banner contradiction** (see watch-list), then parametrize the OWUI template and deploy the second instance | The row's premise ("x2 live") is false on the box — building on it would duplicate a service that does not exist |
| HD-104 (+ HD-160) | 2 | `openclaw onboard` → `openclaw.json`, then the OpenCloud WebDAV round-trip | Container Up/healthy; only onboarding + verify remain |
| HD-103 | 2 | Trigger the first HF model download + verify a Slovenian scan end-to-end | Docling is Up on the VPS; **HD-402** (the OCR-engine bench) closes on this same gate |
| HD-111 | 2 | `ppt-mcp` first, register MCP servers in OWUI | Nothing gates it except the OWUI instance question above |
| HD-249 | 3 | Audit external webhook deps + `WEBHOOK_URL`, then mint a budget-capped LiteLLM key for AI workflow nodes | n8n live behind the tailnet edge. ⚠ Its key is a **HD-384** consumer once the allow-list exists |
| HD-251 | 3 | Roll out the tailscale-first tiers (Headplane, Dozzle, Metabase, Grafana, Traefik-dash) | The policy/doc half landed 2026-08-26 |
| HD-373 | 2 | Pick (a) nginx SPA fallback / Traefik `PathPrefix(/ui/)` rewrite, or (b) route-scoped forward-auth on `/ui/*` | Workaround (`/fallback/login`) works, so this is a real fix, not a fire |
| HD-380 | 2 | Passive: watch `samples.csv` for a curve growing > 2 GiB/h under traffic that does not return at idle — that, and only that, re-arms C3. Plus the **never-measured prefix-cache/preemption check** across the 16 GiB raise | Certified state is stable; this row is the standing watch + one cheap measurement |

### Network / platform / security

| HD | P | ⏳ Next action | Why |
|----|---|----------------|-----|
| HD-357 | 2 | Wire the Homepage tiles/widgets to the verified endpoints (home edge + VPS edge), then hand the visual check to the owner | Endpoints and route tables are final; bug #6 is wiring |
| HD-358 | 2 | Record the Seerr→\*arr API-key + URL hand-off as a runbook step (and consider automating it in IaC) | Home edge is up; the step is documentation + optional IaC |
| HD-122 | 2 | Verify Matrix profile auth **now** (the servers have been live since 2026-08-22) | The row used to wait on a deploy that already happened |
| HD-47 | 3 | Publish `matrix`/`chat` + `_matrix` well-known/SRV, then prove inbound federation from an external server | Servers are live; the records are the only missing piece (also a prerequisite inside HD-147) |
| HD-112 | 2 | Post-up seeding: local admin → OIDC login (owner browser at that one step) → flip `bypass-local-login` → create `guestbin` + `dropzone` → round-trip + 6 h sweep verify | Deployed; the remainder is seeding |
| HD-159 | 2 | Run the deliberate `wg down` test and confirm the `wg-s2s-down` alert fires (needs a short planned tunnel-down window) | Rule + scrape are deployed; never proven |
| HD-09 | 2 | Ride the next router converge import and confirm the UPS web-UI 80/443 Home→Mgmt rule lands | IaC-only so far |
| HD-287 | 2 | Encode `cap_drop: ALL` + the ROCm-init `cap_add` set for immich-ml → oldsrv converge → verify ML inference still works | The gate that blocked it (ML leg live) is met; rides the same converge as HD-386 |
| HD-318(b) | 1 | Confirm the recyclarr @daily quality-profile sync landed (after the 2026-09-15 `bind_owner_uid` fix) | Stacks are up; observation only |
| HD-280 | 2 | Observation: confirm a repeated 401/403 actually produces a ban | Jail is live; waits on natural brute-force |
| HD-14 | 2 | Enable the HA Prometheus exporter and export the entity list | The observability gate is gone (Victoria + Alloy live); feeds the HA dashboard |
| HD-17 + HD-217 | 2 | Render the Homepage **IP-only** failover button (`homepage_failover_button`; the RFUSB path is obsolete — HD-18 rejected) | `ha-failover-api` is active on oldsrv since 2026-09-08; only the render remains |
| HD-04 (tail b) | 1 | Restore the oldsrv standby keepalived conf to the **BACKUP 100** variant (the drill left the 120 failover variant) — before the next standby cold boot | A one-file revert the drill left behind; the rest of HD-04 is the owner's failover test |

### Observability

| HD | P | ⏳ Next action | Why |
|----|---|----------------|-----|
| HD-344 | 3 | Register the MCP endpoints in pi / Open WebUI / OpenClaw — **ports are `mcp_metrics_port` 8083 / `mcp_logs_port` 8084**, not :8080/:8081 | Servers live on oldsrv; registration is the whole remaining row. ⚠ Do not write a literal port — use the vars |
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

1. **HD-397 needs a physical presence for its last half** — the off-LAN matrix is measured + green (2026-09-19), the LAN/`Mgmt99` half cannot be taken from abroad. It gates nobody's code, only the on-site verification rows. Reachability itself is settled: [network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away.
2. **Never benchmark or converge spark from a session whose own model is spark** (incidents #3 + #6). Live converges run **detached** (`nohup … &` + log + poll), spark via the VPS jump.
3. **Do not merge/converge `main`'s spark values over the certified ones**: the 16 GiB KV pool is the live, certified config, and `--enforce-eager` (C3) stays off on measurement.
4. **One writer per file family:** `docs/services-ai*.md` + `IaC/ansible/templates/docker_services/**` are one-lane-at-a-time — check `git worktree list` + `git log` on the file before editing it.

---

## Table Human — 🚧 owner step first

Grouped by *why*. Clearing these cascades into the AI table above.

### Group 1 — a browser, a phone or a physical act

| HD | P | Owner step | Then the AI does |
|----|---|-----------|------------------|
| HD-397 (tail) | 2 | Be on-site: run the matrix from the LAN and with the `Mgmt99` vNIC linked | Close the row — prove the carried jump is a no-op for a LAN-attached runner and that `router`/`switch`/`ap-*`/`*99` answer again |
| HD-401 (partial) | 2 | Approve installing a ROCm/gfx1151 stack on the admin laptop + check the BIOS iGPU carve-out / GTT range | AI runs the other three gates (mmproj on GPU, FIM latency, stack pick) and only then writes config |
| HD-147 (+ HD-141 epic) | 1 | Browser logins: matrix / claw / cloud / foto / immich (+ Forgejo register) | Blueprint + glue are live; the AI re-renders inventory + closes the epic tail |
| HD-194 | 3 | Confirm one login + one OIDC callback end-to-end at the edge | Closes audit S17(a) |
| HD-101 | 2 | OWUI SSO → Authentik round-trip, link the local admin | AI verifies LiteLLM completion + RAG after |
| HD-350 | 1 | Authorize oldsrv `/root/.ssh/traefik-cert-sync.pub` on the VPS (the pull 401s until then) | AI verifies the wildcard pair + LAN routes |
| HD-375 | 2 | Confirm the spark host-memory rules in the Grafana UI **and** that they reach n8n | Rules are live in the ruler since 2026-09-17 22:33C; idle `usable` is 18.5 GiB, so the WARN margin is 6.5 GiB |
| HD-347 | 1 | Capture the **"Homelab Alerts" group UUID** into `signal_alert_recipients` (`group_vars/all/main.yml`, non-secret) — the device is linked, the value is still empty | AI re-converges n8n + proves delivery |
| HD-316 / HD-315 / HD-343 | 1–2 | Visual verify: launchpad green, host-overview (incl. the new disk-work + temperature rows) + probe tables, Network Clients panels + wifi path | AI fixes whatever the eyeball catches |
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
| **HD-384** | 1 | **Which simple querier gets what** — HomeAssistant / Docling / OWUI: `spark/*` vs `ollama/*`, with `max_budget`/`rpm`; plus hardening `spark-llm_api` (triple-used today). ⚠ New input from decision #28: if HD-400 lands, an image part becomes a hard **400**, so an OWUI-class consumer must be told | The LAN `bootstrap_keys` flip back to true; any scoped consumer of `spark/*` |
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
| HD-359 / HD-367 | 1 | Bench lane: the engine + `spark-ai.enabled` are certified; what is left is the S2/S3 NVFP4×SGLang lane + the 262k needle test (rides HD-376) — owner decides when a bench window is worth the box |
| HD-400 | 2 | **Proposed, not applied, and it is NOT a speed change.** `--limit-mm-per-prompt '{"image": 0, "video": 0}'` returns pool memory (ViT ~0.5–1 GiB + the mm-processor cache default **4 GiB host RAM**) where boot headroom binds, but C2 decode is expected FLAT. Its acceptance is BENCHMARK-PLAN §6 step 11 — the same bench window as HD-359/367, and the freed GiB must be spent in a **separate** row |

---

## ⚠ Watch-list — reads as done, is not

Checked 2026-09-20 against the registry + live SSOT. Each of these has already fooled one document.

| Claim you might believe | Reality |
|---|---|
| "Signal alerting is closed" | Device linked ✅, workflow live ✅ — but `signal_alert_recipients` is still **empty** in SSOT, so nothing is delivered to the group (HD-347) |
| "Open WebUI ×2 is live" (`services-ai.md` banner) | The VPS runs **one** `open-webui` at `ai.kogler.si`; the `chat` service is **element-web**, not a second OWUI instance. HD-248 is open and starts by correcting that banner |
| "The pinned-AI tier runs on Ollama" | Not since 2026-09-19: STT = `whisper.cpp` Vulkan, rerank **and** embed = `llama.cpp` Vulkan on the RX 7600. `ollama/bge-m3` survives only as the embed **fallback rung** — and it is a *rung*, not a LiteLLM row (`/model/info` on both gateways returns exactly one row each: `spark/qwen3.8-flash-next`). Plan of record: [services-ai.md](docs/services-ai.md) §3a, catalog runbook §4a |
| "The reranker has a consumer" | It ships **dormant** (~327 MiB idle): `rag-mcp` is the HD-268b compose STUB with no `services:` block, so `enabled: false` there is not a flag to flip. It was verified with a LiteLLM probe + a synthetic consumer, **not** live RAG traffic |
| "Making spark text-only buys throughput" | Decision #28 says the opposite: no image tokens ⇒ the tower never executes ⇒ decode is expected **flat**. It buys memory on the boot-bound side (≈32.2k KV tokens per GiB). HD-400 |
| "Vision can be split: laptop ViT → spark" | **Rejected as unbuildable**, not merely expensive — vLLM's only pre-computed-vision seam is multimodal *embeddings*, which must live in the target model's own visual-token space (Flash-Next = `Qwen4ExpForConditionalGeneration`). Vision lives on the workstation as a **text cascade**. [services-ai.md](docs/services-ai.md) §9 #28 + [hardware-workstation.md](docs/hardware-workstation.md) |
| "HD-383's stale-secret abort is a live blocker" | The `lan-litellm` glue is `bootstrap_keys: false` and the scoped-key list is empty (HD-386) — the abort is **unreachable**, and the stale 1P value is still standing in the vault. It returns with HD-384 |
| "Navidrome never deployed" | Deployed: container Up, `/mnt/storagebox/music` → `/music` ro, scanner ran. The **library is empty** and no admin user exists (HD-354) |
| "Matrix waits on unprovisioned hosts" | Tuwunel + Element have been live since 2026-08-22; HD-46 was deleted as done, HD-47/122 are verifies now (Cloudflare records + profile auth) |
| "Zipline's first deploy is human-gated and pending" | `zipline` + `zipline-db` are Up/healthy — only post-up seeding is left (HD-112) |
| "Forgejo install wizard / Phase-1 incident batches are open" | Installed (`INSTALL_LOCK`) and the incident batches landed; HD-219/HD-220 are deleted rows |
| "The watchdog's idle recycle is a safe background detail" | It restarted the engine twice 35 min apart on a healthy box; its baseline is boot-timing-dependent (HD-395) |
| "oldsrv SSH / the Mgmt plane is broken" | Closed 2026-09-19: HD-392 and HD-398 are deleted rows. The VPS jump rides in `group_vars` (no `-e` needed), `ssh oldsrv` = the **Home** leg, and VLAN 99 stays sealed by owner decision **A** — the `*99` aliases are on-site-only |

---

## Park / moot

| HD | P | Status |
|----|---|--------|
| HD-385 | 2 | **Research record, not work.** Both measurement premises failed and items (a)(b)(c)(f) are CLOSED by measurement; the implementation shipped 2026-09-19 with the pinned-AI lane. The standing **non-actions** survive: do NOT set `amdgpu.cwsr_enable=0` up front and do NOT introduce `amdgpu-dkms` on oldsrv ([hardware-gpu.md](docs/hardware-gpu.md) CWSR section). Where §9c and [services-ai-bench.md](docs/services-ai-bench.md) disagree, the bench doc wins |
| HD-45 | 3 | Homelable + network dashboard — a parallel lane owns implementation; do not re-plan |
| HD-264 | 2 | Renovate sandbox `domen/test` — parked, owner steps (external re-launch mechanism, real manifest, then flip `RENOVATE_REPOSITORIES`) |
| HD-250 | 3 | DSH onboarding — **parked with the service** (`enabled: false`, HD-386) and moot under decision #26 (harnesses go direct) |
| HD-28 | 3 | Office AI stack — not parked but **not startable**: its Ollama half is superseded twice over and its MCP half waits on HD-111 |

---

## Bottom line

- **Best pure-AI picks right now:** `HD-399` (one `not ansible_check_mode` gate, unblocks every oldsrv `--check`), `HD-396` (a single yes/no that ends a retired-secret thread), `HD-387` (settles a live contradiction with a 20-minute probe), `HD-395` (a measured defect that restarts a healthy engine), `HD-394` (census: two containers no converge will ever clean up), `HD-402` (a CPU OCR bench that gates nothing but itself), `HD-47` + `HD-122` (federation is one DNS change + one verify away), `HD-357`/`HD-358` (two named bugs on the launchpad and the media stack), and `HD-386` (one detached converge whose only missing artifact is the log).
- **Highest-leverage owner steps, in order:** ① `HD-347` recipients value (one string — alerting is otherwise blind), ② `HD-350` pubkey authorization (unblocks the home-edge cert chain), ③ `HD-384` (which consumer may call what — it unblocks the LAN key glue and now the OWUI-vision question), ④ `HD-377` + `HD-375` sign-offs (they retire three dashboards and close the alert lane), ⑤ `HD-147` browser logins (the last big OIDC tail).
- **Oldsrv reachability is no longer a blocker:** off-LAN it is the Home leg through the VPS jump, carried in `group_vars` since 2026-09-19 — `bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --check …` needs no `-e` (SSOT: [network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away). The only thing presence still buys is the on-site half of HD-397 and the `*99` aliases.
