# prompt.md — Deployment Execution Handoff #18 — HD-253 session-discipline enforcement SHIPPED (guard live); next: plan-task the HD-247→251 cutover chain

> **Active lanes:** none

> **Role:** Entry point for the next session. This session (2026-08-26) implemented **HD-253** mechanically per its locked decisions: `scripts/guard-session.sh` worktree guard (refuses edit-context on primary+main; `--validate-mode` hard-fails primary+main+DIRTY) wired into `validate-all.sh` with a sandboxed self-test, README §0 intent-routed start sequence, CONVENTIONS §4/§6 amendments (diff-rule, derived-values ban, branch-per-session checkbox, merge-station definition), and handoff restorations per the new diff-rule. Local tooling/docs only — NO IaC / NO deploy was touched. Source draft `process-improvements-draft.md` and `prompt-workflow.md` were deleted in the closing change (lifecycle §4). The AI-stack v2 planning from handoff #17 remains LOCKED but unbuilt — next session SHOULD `plan-task` the cutover chain before executing.
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [scripts/guard-session.sh](scripts/guard-session.sh) · [changelog.md](changelog.md) rows HD-253 + HD-247–251 · owning docs: [docs/services-ai.md](docs/services-ai.md) (v2 arch), [docs/security.md](docs/security.md) §10, [docs/network-vpn.md](docs/network-vpn.md) §Tailnet-exposed services.

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §6 worktree discipline (**now MECHANICALLY enforced** by `scripts/guard-session.sh` + validate-all hard-gate), §4 journal loop + post-task housekeeping + new close-out items ⑤–⑦, §2 secret-output hygiene + secret→YAML `>-` rendering, §5 service-onboarding checklist.
2. [docs/services-ai.md](docs/services-ai.md) — **THE v2 architecture doc** (§2 topology diagram, §4 scoped-key inventory table, §5 knowledge split, §6 exposure posture, §9 decisions #11–17).
3. [docs/security.md](docs/security.md) — **§10 Capability-tiering / management-plane separation** (the master invariant).
4. [docs/network-vpn.md](docs/network-vpn.md) — **§Tailnet-exposed services**: Patterns A/B recipes + node/tag table.
5. [changelog.md](changelog.md) — **HD-247–251** decision bundle (+ existing **HD-246** RAG lock) + fresh **HD-253** implementation record.
6. [deployment-journal.md](deployment-journal.md) — 2026-08-26 entry (decision session).

## 1. Environment (Windows 11 laptop)

Same as handoff #16 (unchanged): git-bash, forward-slash, `py -3`, UTF-8 no-BOM, LF; Ansible via WSL + 9P gate before every run; Secrets → 1Password item.field only, `>-` for YAML renders; **new self-learned rule (2026-08-26): do NOT use multi-line bash heredocs containing backslashes/backticks on this host (mangled through `bash -c`) — write patch scripts to a temp file via the `write` tool and run them instead.**

## 2. State snapshot (start of next session)

- **main carries the two HD-253 commits (feature `c13dd44` + close-out) NOT YET PUSHED** — pushing is OWNER's call. The session ran in worktree `homelab-wt-20260826-1018`, branch `session/hd253-workflow-enforcement`, merged back ff-only.
- **The worktree rule is now ENFORCED:** a session starting on the primary checkout gets refused by `guard-session.sh`; `validate-all.sh` fails on primary+main+DIRTY. Start every session with the worktree ritual (README §0).
- **AI stack v2 is PLANNED, not built.** Key dependencies/prereqs to respect:
  - **HD-247 (spine, first):** pin `litellm_version` semver (drop `main-stable` fluid tag) → LiteLLM Postgres + `STORE_MODEL_IN_DB` → migrate models to DB → bootstrap-keys glue (7 scoped keys → 1P) → swap consumers off `master_key` (retire it from all templates). *Everything else depends on HD-247.*
  - **HD-248:** parametrize open-webui compose to render twice; `chat.kogler.si` public / `ai.kogler.si` internal (drop public `ai.` DNS) + Element→`msg.kogler.si`; public-KB restriction pins.
  - **HD-249:** n8n internal (audit webhook deps first).
  - **HD-250:** DSH (depends HD-247; verify `tailscale serve` TCP-mode works on your Headscale).
  - **HD-251:** fleet exposure rework phase-2 (Headplane → tailnet, review Dozzle/Metabase/Grafana/traefik-dash).
- **Still-open legacy (from #16, unchanged):** HD-101 verify (next converge), HD-211 rotation batch: **Zipline pre-deploy:** seed vault items via `bash scripts/provision-vault.sh` (creates `zipline_password` + `zipline_db`; owner input = starting guestbin quota ~100 MB) · **HD-112 go-live legs** (below) · Kopia `/backup` decision · **LDAP HD-132 authoring** · **Forgejo `domen/homelab` repo creation** (renovate flip) · **HD-238 DR runbook** · HD-57 human legs (bank tokens / Enable-Banking app).
- **HD-211 rotation batch (full, priority):** `openrouter_api`, `cohere_api`, `forgejo_api` (real values); **`prometheus-internal_api` password exposed into an agent transcript TWICE now** (2026-08-23 probe + 2026-08-24 quoting failure) — rotate vault item then re-run `--tags monitoring` (API seed task only fires when DS absent → delete the DS first via UI/API, or extend the task with a rotate mode); **`crowdsec-bouncer_api` LAPI key** (exposed via traefik debug config dump, 2026-08-25 ~00:45); **`opencloud-collab_password` window**; **persisted-Authentik-token `expiring=False` sweep** (HD-216).
- **ID registry:** next free = max(HD)+1 in [todo.md](todo.md) — always re-derived at write time per CONVENTIONS §1; NEVER type a literal number here (the typed "next free = HD-247"/"= HD-252" pointers went stale within hours — the HD-253 lesson now codified as a §4 close-out ban).
- **Coordination:** do NOT touch headplane/headscale unless the owner asks (separate lane; HD-251 is planned but not started).

## 3. Next-session execution order

### 3a. First: decide with the owner — **plan-task the HD-247→251 cutover** (chain ①pin → ②Postgres/STORE_MODEL_IN_DB → ③sidecars+ACL → ④keys → ⑤consumers → ⑥owui-int → ⑦KB dual-ingest → ⑧dsh → ⑨openclaw onboard → ⑩dsh deploy → ⑪headplane). This is the recommended next step. (The #17 docs-commit prerequisite is DONE.)

### 3b. Owner-action chase (unchanged from #16, non-blocking)
- **HD-101 verify after the open-webui OIDC template converges:** ① "Continue with Authentik" button renders on ai.kogler.si ② owner SSO round-trip LINKS the existing local admin by email (`OAUTH_MERGE_ACCOUNTS_BY_EMAIL=true` — no duplicate account) ③ family-side sanity: local signup rejected, SSO-created accounts land `pending` ④ LiteLLM completion test + RAG verify → trim HD-101 ⏳ tail + changelog close-out.
- **HD-211 rotation batch** (see §2).
- **HD-112 go-live — partially DONE 2026-08-25** (stack deployed, zipline UP on :3000). FULL legs restored from handoff #16 per the new diff-rule (CONVENTIONS §4 close-out ⑤): ⓪ **pre-deploy vault seeding** via `bash scripts/provision-vault.sh` (creates `zipline_password` + `zipline_db`; owner input = starting guestbin quota ~100 MB) · ① **run dns.yml** (the `bin` CNAME applies ONLY there — without it bin.kogler.si does not resolve) · ② **walk the compose-header deploy gate** (`/auth/setup` admin → OIDC verify → flip bypass-local-login in Server Settings → seed `guestbin` user (small quota, no password) + `dropzone` folder `allowUploads=true`) · ③ logged-out anonymous upload→short-URL→viewer round-trip · ④ 6h sweep verify · ⑤ family drop script + manual guide entry → trim the HD-112 ⏳ tail.
- Carried owner decisions: **Kopia `/backup` source wiring**; **LDAP HD-132 authoring** (base DN/bind mode/TLS/UIDs + authentik-ldap_bind.password decoupling); **Forgejo `domen/homelab` repo** (renovate flip); Phase 1.5 cutover (dnevna/garage swaps + capsman rsc); **HD-57 bank/virtual-token legs**.

### 3c. Engineering queue (continue from #16; note AI-stack HDs now supersede HD-246's "pending" as they absorb it)
- **HD-246 RAG retrieval wiring (decided 2026-08-25, absorbed into the HD-247/248 plan)** — litellm embed-pin fix (incl. the discovered `embed-english-v3.0` mis-pin under name `cohere/embed-v4`) + rerank entry + OW compose env pins (`ENABLE_PERSISTENT_CONFIG=false`, docling extraction, Cohere embed via LiteLLM, external reranker, hybrid ON, 20→top 5, token chunks 512/64) + idempotent PGVector HNSW index task (`vector_cosine_ops`@1536; no hand-SQL per HD-220) + dual Family-Manuals ingestion.
- **HD-238** oldsrv→VPS DR runbook for non-GPU services (todo §2.9) — laptop-doable authoring; pairs with next backup.md touch (which also carries the HD-112 uploads-exclusion row).
- **HD-112 / HD-252 backlog** as they read. **Phase-2 backlog note:** Zipline `/drop` static glue page (Traefik PathPrefix-priority router, same-origin) — only if the owner asks; NOT queued.
- **Converge ride-along checks** (fold into any upcoming docker_services converge): observe residual ① extras-restart guard behavior (zero spurious restarts on unchanged extras / exactly one per changed extra, HD-236) + ② confirm the `apply-authentik-blueprints.yml` one-shot task fired green in the same run + ③ open-webui container RECREATED with the corrected OIDC env (verify `docker exec open-webui printenv OPENID_PROVIDER_URL` non-empty post-up), then walk §3b HD-101 verify; journal all three, then trim the ⏳ tails via an append-only R-row.

## 4. Working rules (binding)

Fresh worktree per session BEFORE any edit — now mechanically enforced (`bash scripts/guard-session.sh` refuses edits on primary+main; `validate-all.sh` hard-fails primary+main+DIRTY); merge back only committed+green, ff-only; primary = merge station only. 9P gate before every converge; surgical `--tags`; secrets 1P-item.field only + `>-` for YAML; persisted Authentik tokens always `expiring=False` (HD-216); journal append-only; owning doc + changelog row in same change; English; relative links; Authentik blueprint pin array attrs (HD-231); don't touch headplane/headscale unless asked. **Handoff diff-rule (CONVENTIONS §4): edit the previous handoff, never rewrite from scratch; computable pointers are derived at write time, never typed.** No multi-line bash heredocs with backslashes/backticks on this host — write+run temp script files instead.
