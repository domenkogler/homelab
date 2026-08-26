# prompt.md — Deployment Execution Handoff #19 — HD-244/245 scanner hardened + HD-247 spine cutover AUTHORED (deploy-gated) + vault complete; next: Lane C converge wave

> **Active lanes:** Lane C (Phase-1 converge wave, VPS) QUEUED — needs owner at gates; Lane D (Headscale, separate lane) after C.

> **Role:** Entry point for the next session. Session 2026-08-26 shipped three things, ALL laptop-side — zero converges ran. **(1) HD-244+HD-245** — `check-vault-items.sh` now parses scalar `*_item:`/`vault_item:` values from enabled group_vars service entries AND routes specs inside top-level `*_scoped_keys:` lists to a GLUE set (the litellm bootstrap-keys glue is Jinja-rendered — its item names are never greppable literals), subtracts glue-minted names from NEEDED at the end (they also enter via literal consumer-template lookups), and gained `--strict` + a committed self-test (case 7 control/scoped pair proves classification rides the block name; 24 asserts). Live-confirmed against the real vault: **needed 36 / MISSING = `ha-failover_api` ONLY** (Phase-4, expected) — closes HD-244's "re-run green once present" tail. **(2) HD-247** authored end-to-end as deploy-gated IaC: pin `litellm_version v1.83.10-stable` (+`litellm_db_version 16.15-alpine`, registry-verified w/ digest), bundled litellm-db Postgres + `STORE_MODEL_IN_DB=true` (`model_list` REMOVED from config.yaml.j2 — Admin-UI recreation is a first-deploy runbook step), DB06 db-backup block + backup.md critical-state row, `bootstrap-keys` glue (vault-first idempotent: empty item → POST /key/generate → sk into 1P; stale-secret probe abort rc2; unique-alias conflict abort rc4; docker-exec HTTP @127.0.0.1:4000, no new host ports; runs BEFORE open-webui/openclaw render like prepass-authentik), scoped-key SSOT `litellm_scoped_keys` in vps.yml, master_key demoted to admin/bootstrap-only (zero consumer hits). Recorded deviations: `openclaw-litellm_api` name (collision with openclaw-opencloud_api convention); rag keys carry rerank-v4.0-pro (HD-246 routes /rerank through the same key). **(3) Vault completed**: provision-vault.sh created exactly `litellm_db`; all other catalog items confirmed present incl. real `openrouter_api`/`cohere_api`/`forgejo_api` values and `metabase-forgejo_ro`. Owner decisions logged: Forgejo install wizard DONE + `domen/test` repo exists → renovate validation targets the test repo, `domen/homelab` flip DELAYED; HD-252 laptop user `domen` was manually linked to the OIDC account → Lane D VERIFYs the provider_identifier link instead of migrating; HD-30 purchase delayed.
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [scripts/guard-session.sh](scripts/guard-session.sh) · [changelog.md](changelog.md) rows HD-253 + HD-247–251 · owning docs: [docs/services-ai.md](docs/services-ai.md) (v2 arch), [docs/security.md](docs/security.md) §10, [docs/network-vpn.md](docs/network-vpn.md) §Tailnet-exposed services.

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §6 worktree discipline (**now MECHANICALLY enforced** by `scripts/guard-session.sh` + validate-all hard-gate), §4 journal loop + post-task housekeeping + new close-out items ⑤–⑦, §2 secret-output hygiene + secret→YAML `>-` rendering, §5 service-onboarding checklist.
2. [docs/services-ai.md](docs/services-ai.md) — **THE v2 architecture doc** (§2 topology diagram, §4 scoped-key inventory table, §5 knowledge split, §6 exposure posture, §9 decisions #11–17).
3. [docs/security.md](docs/security.md) — **§10 Capability-tiering / management-plane separation** (the master invariant).
4. [docs/network-vpn.md](docs/network-vpn.md) — **§Tailnet-exposed services**: Patterns A/B recipes + node/tag table.
5. [changelog.md](changelog.md) — **HD-247–251** decision bundle (+ existing **HD-246** RAG lock) + **HD-253** implementation record + fresh **hd244+hd245** and **HD-247** Done rows (2026-08-26).
6. [deployment-journal.md](deployment-journal.md) — 2026-08-26 entries (decision session + vault seeding / scanner live-confirm).

## 1. Environment (Windows 11 laptop)

Same as handoff #16 (unchanged): git-bash, forward-slash, `py -3`, UTF-8 no-BOM, LF; Ansible via WSL + 9P gate before every run; Secrets → 1Password item.field only, `>-` for YAML renders; **new self-learned rule (2026-08-26): do NOT use multi-line bash heredocs containing backslashes/backticks on this host (mangled through `bash -c`) — write patch scripts to a temp file via the `write` tool and run them instead. Second (2026-08-26): `wsl.exe` invoked from git-bash mangles `/mnt/...` arguments into `C:/Program Files/Git/mnt/...` — always prefix with `MSYS_NO_PATHCONV=1`.**

## 2. State snapshot (start of next session)

- **main @ `b4158de`, fully pushed** — nothing unpushed; all session worktrees pruned, branches ff-merged green (guard ritual followed throughout).
- **Worktree rule ENFORCED** (unchanged from #18): start every session with the worktree ritual (README §0).
- **AI stack v2: HD-247 is BUILT (IaC, deploy-gated); HD-248–251 remain planned-not-built.**
  - **HD-247 remaining ⏳ legs (Lane C):** converge vps.yml → bootstrap-keys glue mints the 7 scoped sks into 1P → Admin-UI model recreation (compose-header runbook step, incl. HD-246-corrected embed-v4.0@1536/rerank-v4.0-pro params) → live-verify scoped keys + open-webui/openclaw against them → trim tail. Unblocks HD-250/HD-248.
  - **HD-248:** parametrize open-webui compose to render twice; `chat.kogler.si` public / `ai.kogler.si` internal (drop public `ai.` DNS) + Element→`msg.kogler.si`; public-KB restriction pins.
  - **HD-249:** n8n internal (audit webhook deps first). **HD-250:** DSH (depends HD-247; verify `tailscale serve` TCP-mode works on your Headscale). **HD-251:** fleet exposure phase-2.
- **Vault state (confirmed 2026-08-26):** provision-vault.sh idempotent run created ONLY `litellm_db`; 35 others skipped-as-existing — real `openrouter_api`/`cohere_api`/`forgejo_api` values IN PLACE (HD-211 core resolved), `metabase-forgejo_ro` present, zipline items present. Scanner live baseline: needed 36 / MISSING `ha-failover_api` only.
- **Renovate:** Forgejo install wizard DONE; `domen/test` repo exists → Lane C re-enables renovate pointed at the test repo and validates PR creation; flip to `domen/homelab` when the owner migrates it (DELAYED by decision).
- **Still-open HD-211 tails:** `prometheus-internal_api` password exposed into an agent transcript TWICE (rotate → delete DS → re-run `--tags monitoring`); **`crowdsec-bouncer_api` LAPI key** (exposed via traefik debug dump 2026-08-25); `opencloud-collab_password` exposure window; persisted-Authentik-token `expiring=False` sweep (HD-216).
- **Carried legacy (from #16/#18):** HD-112 go-live legs (below) · Kopia source wiring (**HD-230d framing: agent-on-VPS vs server-managed; orchestrator recommends option (a) kopia-agent mirroring HD-191 — awaiting owner sign-off**) · LDAP HD-132 authoring · Phase 1.5 cutover (dnevna/garage swaps + capsman rsc) · HD-238 DR runbook · HD-57 bank-token legs · HD-30 purchase (delayed).
- **ID registry:** next free = max(HD)+1 in [todo.md](todo.md) — always re-derived at write time per CONVENTIONS §1; NEVER type a literal number here (the HD-253 lesson, codified as a §4 close-out ban).
- **Coordination:** headplane/headscale = SEPARATE lane (D) — coordinate, never fold into other converges.

## 3. Next-session execution order

### 3a. FIRST: Lane C — Phase-1 converge wave on the VPS (owner-gated, interactive)

One orchestrated pass over the deploy-gated stack, following the proven diagnostics→serial-edit→surgical-converge pattern (9P gate before every run; journal each wave; tick the ledger):
- **HD-230g** disabled-service teardown loop verify + blueprint one-shot fired (ride-along checks below).
- **HD-220** db_role_sync rotation-drift guards fire on converge.
- **HD-218 Wave-3 residue** container-state re-sample.
- **HD-181** first wildcard issuance + consumer pull-key authorization (Pi ha-sync / oldsrv traefik-cert-sync pubkeys) + sync-timer delivery verify.
- **HD-183** homepage renders on the VPS edge (`kogler.si`/`home` aliases).
- **HD-184** immich-app→immich-ml round-trip over WG (smart-search job completes).
- **HD-112 go-live legs:** ⓪ vault seeding DONE (items exist) · ① run dns.yml (the `bin` CNAME applies ONLY there) · ② walk the compose-header deploy gate (`/auth/setup` admin → OIDC verify → flip bypass-local-login in Server Settings → seed `guestbin` user (small quota ~100 MB, no password) + `dropzone` folder `allowUploads=true`) · ③ logged-out anonymous upload→short-URL→viewer round-trip · ④ 6h sweep verify · ⑤ family drop script + manual guide entry → trim the HD-112 ⏳ tail.
- **HD-241/242 metabase gates:** Send test email; connect CrowdSec SQLite + Forgejo PG sources; import official dashboards; SELECT-only proof (write attempt must fail). `metabase-forgejo_ro` already seeded.
- **HD-101 verify ride-along:** "Continue with Authentik" button on ai.kogler.si → SSO round-trip LINKS local admin by email (`OAUTH_MERGE_ACCOUNTS_BY_EMAIL=true`) → family sanity (local signup rejected, SSO accounts land `pending`) → LiteLLM completion + RAG smoke → trim HD-101 ⏳ tail.
- **Renovate vs `domen/test`:** re-enable renovate scoped to the test repo; verify a PR opens against it; homelab-repo flip stays delayed.
- **HD-230d Kopia wiring** if owner approves option (a): add kopia-agent service entry covering the dumps volume (+ retention), mirroring HD-191.
- Converge ride-along checks (from #18, still binding): extras-restart guard behavior (zero spurious restarts / exactly one per changed extra, HD-236) + `apply-authentik-blueprints.yml` one-shot green in the same run + open-webui recreated with non-empty `OPENID_PROVIDER_URL`; then walk HD-101 verify; journal all three, trim ⏳ tails via an append-only R-row.

### 3b. THEN: Lane D — Headscale (separate lane, do NOT fold into C)

✅ **① container recycle DONE live 2026-08-26** (branch `session-headscale-oidc`): headscale force-recreated (`up -d --no-deps --force-recreate headscale`, Started 2026-08-26T14:05Z, RestartCount 0); on-disk already carried the 128-char rotated secret; token-endpoint replay now `invalid_grant` (client auth OK, was `invalid_client`) + `/health` 200 + laptop node `Domen_P14s` reconnected online. Full evidence: journal entry 2026-08-26 HD-252 Lane D. ⚠ New blocker HD-255: `--tags "docker_services,<service>"` does NOT per-service filter (include-tag cascades) AND the extras restart guard aborts on `selectattr('item')` — authoring fix tracked; a true surgical converge is not possible today, so on-host direct ops were the lane-correct path. Remaining: ② browser `/register`→sso→`/oidc/callback` round-trip (owner device); ③ LIVE VERIFY FAILED — the manual `domen` user has empty email/no provider_identifier (headscale `users list`), so owner deletes + re-enrolls one device via the fixed OIDC flow; ④ tighten ACL `*:*` → named users/tags in `policy.hujson.j2` per TIGHTEN promise once a real OIDC identity exists.

### 3c. Carried queue (non-blocking)

- **HD-238** oldsrv→VPS DR runbook authoring for non-GPU services (todo §2.9) — laptop-doable; pairs with next backup.md touch.
- **HD-246** RAG env pins land WITH HD-247's first converge (absorbed; details live in todo row + services-ai.md §5).
- Zipline `/drop` static glue page — Phase 2, only if the owner asks; NOT queued.
- Owner-action chase (still open): prometheus-internal_api + crowdsec-bouncer_api rotations, expiring=False sweep, LDAP HD-132 authoring, Phase 1.5 hardware swaps, HD-57 bank legs, HD-30 (delayed), homelab repo migration (delayed).

## 4. Working rules (binding)

Fresh worktree per session BEFORE any edit — now mechanically enforced (`bash scripts/guard-session.sh` refuses edits on primary+main; `validate-all.sh` hard-fails primary+main+DIRTY); merge back only committed+green, ff-only; primary = merge station only. 9P gate before every converge; surgical `--tags`; secrets 1P-item.field only + `>-` for YAML; persisted Authentik tokens always `expiring=False` (HD-216); journal append-only; owning doc + changelog row in same change; English; relative links; Authentik blueprint pin array attrs (HD-231); don't touch headplane/headscale unless asked. **Handoff diff-rule (CONVENTIONS §4): edit the previous handoff, never rewrite from scratch; computable pointers are derived at write time, never typed.** No multi-line bash heredocs with backslashes/backticks on this host — write+run temp script files instead.
