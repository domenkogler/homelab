# prompt.md — Deployment Execution Handoff #22 — crypto-keys hygiene + NAS read-token rename landed (2026-08-26); NEXT: laptop-only HD-256 portability sweep · VPS Lane C (HD-247 etc.) still deploy-gated

> **Active lanes:** ① **DONE (2026-08-26):** HD-211 placeholder-keys sub-item CLOSED — `openrouter_api`/`cohere_api`/`forgejo_api` verified in vault (owner-confirmed); future NAS read token **renamed `authentik-api_token` → `authentik-nas_api`** (correct `<service>_<type>`; `_oidc` rejected). ② **NEXT (laptop, no-deploy): HD-256** — Debian/WSL portability sweep of `scripts/` (+ `bash -n`/`py_compile` validate gate), then **HD-254** (skill-sync guard). ③ **STILL deploy-gated (VPS):** Lane C converge wave → HD-247 LiteLLM cutover (unblocks HD-250/248). ④ **HD-216 tail:** `authentick-nas_api` minted durable (`expiring=False`) at NAS provisioning — not yet automated.

> **Role:** Entry point for the next session. Session 2026-08-26 (handoff #22) — HD-211 placeholder-keys CLOSED (owner-confirmed, verified in vault) + **renamed the future Authentik→NAS read token to `authentik-nas_api`** across `deployment-secrets.md`, `services-authentik.md`, `security.md`, the `sync-authentik-users.sh.j2` glue + `samba.yml` (correct `<service>_<type>`: `-nas` consumer role, `_api` API-Credential; old `_token` suffix was a field — violated the convention; `_oidc` correctly rejected since the glue does NO OIDC, it is a plain read-only Bearer). **Recommended next laptop task: HD-256** (Debian/WSL portability sweep) — a self-contained tooling/docs item that also *prerequisites* HD-254 (skill-sync guard). Prior shipped work (handoff #21) — headscale_api rotation + runbook, and the HD-257/259/258 deploy-speed class — remains in effect.
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [scripts/guard-session.sh](scripts/guard-session.sh) · [changelog.md](changelog.md) HD-211 + HD-257/HD-258 rows · owning docs: [docs/deployment-secrets.md](docs/deployment-secrets.md) (item naming + `authentik-nas_api`), [docs/services-authentik.md](docs/services-authentik.md) (rotation recipe), [todo.md](todo.md).

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

- **main @ `39d22d2`** — this session committed `39d22d2` (HD-211 placeholder-keys CLOSED + `authentic-nas_api` rename, ff-merged; worktree removed, branch deleted). **Push:** verify `origin/main` is caught up (push with `gh auth`/credential helper/netrc if behind — non-interactive WSL may lack creds).
- **HD-216 tail clarification (2026-08-26):** `authentik-nas_api` (formerly `authentik-api_token`) is the future Authentik→NAS read token — **not yet in the vault**, minted durable (`expiring=False`) at NAS provisioning (Phase 2) via `ak shell`; **not automated yet** (manual at provisioning unless a mint-glue is added). This closes HD-216's deferred "one-time expiring=False verify" as a Phase-2 item.
- **Worktree rule ENFORCED** (unchanged from #19): start every session with the worktree ritual (README §0).
- **✅ IN-FLIGHT ROTATION — CLOSED (2026-08-26):** `headscale_api.credential` sha256 `28f53d33…` == Authentik DB secret; on-disk `/opt/headscale/config.yaml` + `headplane-config.yaml` re-rendered to `28f53d33…` (surgical converge ok=29 changed=6 failed=0); headscale + headplane restarted; token-endpoint replay `invalid_grant`; `/health` 200. **Runbook captured** in [docs/services-authentik.md](docs/services-authentik.md) — next rotation follows it (incl. the `docker cp`-broken + `op --template`-stdin gotchas). Full record: deployment-journal.md Phase 1, 2026-08-26.
- **AI stack v2: HD-247 is BUILT (IaC, deploy-gated); HD-248–251 remain planned-not-built.**
  - **HD-247 remaining ⏳ legs (Lane C):** converge vps.yml → bootstrap-keys glue mints the 7 scoped sks into 1P → Admin-UI model recreation (compose-header runbook step, incl. HD-246-corrected embed-v4.0@1536/rerank-v4.0-pro params) → live-verify scoped keys + open-webui/openclaw against them → trim tail. Unblocks HD-250/HD-248.
  - **HD-248:** parametrize open-webui compose to render twice; `chat.kogler.si` public / `ai.kogler.si` internal (drop public `ai.` DNS) + Element→`msg.kogler.si`; public-KB restriction pins.
  - **HD-249:** n8n internal (audit webhook deps first). **HD-250:** DSH (depends HD-247; verify `tailscale serve` TCP-mode works on your Headscale). **HD-251:** fleet exposure phase-2.
- **Vault state (confirmed 2026-08-26):** provision-vault.sh idempotent run created ONLY `litellm_db`; 35 others skipped-as-existing — real `openrouter_api`/`cohere_api`/`forgejo_api` values IN PLACE (HD-211 core resolved), `metabase-forgejo_ro` present, zipline items present. Scanner live baseline: needed 36 / MISSING `ha-failover_api` only.
- **Renovate:** Forgejo install wizard DONE; `domen/test` repo exists → Lane C re-enables renovate pointed at the test repo and validates PR creation; flip to `domen/homelab` when the owner migrates it (DELAYED by decision).
- **Still-open HD-211 tails:** `prometheus-internal_api` password exposed into an agent transcript TWICE (rotate → delete DS → re-run `--tags monitoring`); **`crowdsec-bouncer_api` LAPI key** (exposed via traefik debug dump 2026-08-25); `opencloud-collab_password` exposure window; persisted-Authentik-token `expiring=False` sweep (HD-216). (HD-211's `openrouter_api`/`cohere_api`/`forgejo_api` real-key swap CONFIRMED DONE — values in place 73/40/40 chars. The `headscale_api` re-rotation that used to be the top item is now DONE + runbooked.)
- **Carried legacy (from #16/#18):** HD-112 go-live legs (below) · Kopia source wiring (**HD-230d framing: agent-on-VPS vs server-managed; orchestrator recommends option (a) kopia-agent mirroring HD-191 — awaiting owner sign-off**) · LDAP HD-132 authoring · Phase 1.5 cutover (dnevna/garage swaps + capsman rsc) · HD-238 DR runbook · HD-57 bank-token legs · HD-30 purchase (delayed).
- **ID registry:** next free = max(HD)+1 in [todo.md](todo.md) — always re-derived at write time per CONVENTIONS §1; NEVER type a literal number here (the HD-253 lesson, codified as a §4 close-out ban).
- **Coordination:** headplane/headscale = SEPARATE lane (D) — coordinate, never fold into other converges.

## 3. Next-session execution order

### 3-R. ✅ RESOLVED (2026-08-26): finish the `headscale_api` rotation — DONE, see §2.
The mid-flight rotation is CLOSED and verified; the runbook that replaced this section lives in
docs/services-authentik.md (*Rotating a shared Authentik OIDC client secret*). Remaining from this
lane folds elsewhere: re-enroll dropped nodes under Lane D (3b). Do NOT reopen — vault == DB == on-disk.

### 3-P. LAPTOP-ONLY (no deploy): HD-256, then HD-254

- **HD-256** — Debian/WSL portability sweep of `scripts/` (26 script files): classify each for Windows-only idioms (`py -3`/`python` launcher assumptions, `C:\…`/`D:/`/%TEMP%/cygdrive, backslash separators, CRLF/BOM, cmd/PS syntax in `#!/usr/bin/env` scripts); verify bash `bash -n` + python `python3 -m py_compile`; add a `bash -n` + `py_compile` sweep to `validate-all.sh`; produce the per-script portability table in `scripts/README.md`. Initial triage flags 7 likely candidates: `ansible-run.sh`, `collect-disk-facts.sh`, `git-bootstrap.sh`, `guard-session.sh`, `install-pi-wsl.sh`, `validate-all.sh`, `provision-secrets.py` (several may be false-positives — classify).
- **HD-254** (do AFTER HD-256) — skill-sync guard `scripts/sync-skills.sh` (`--check`/`--push`/`--pull`, artifact ignore-list) + wire `--check --strict` into `validate-all.sh`.
- Depends on NO live host — pure tools/docs.

### 3a. THEN: Lane C — Phase-1 converge wave on the VPS (owner-gated, interactive)

One orchestrated pass
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

✅ **① container recycle DONE live 2026-08-26** (branch `session-headscale-oidc`): headscale force-recreated (`up -d --no-deps --force-recreate headscale`, Started 2026-08-26T14:05Z, RestartCount 0); on-disk already carried the 128-char rotated secret; token-endpoint replay now `invalid_grant` (client auth OK, was `invalid_client`) + `/health` 200 + laptop node `Domen_P14s` reconnected online. Full evidence: journal entry 2026-08-26 HD-252 Lane D. ⚠ New blocker HD-255 `--tags "docker_services,<service>"` does NOT per-service filter (include-tag cascades) AND the extras restart guard aborts on `selectattr('item')` — **RESOLVED (IaC 2026-08-26, merged `310d6b8`):** added `docker_services_scope` (default `all`; `-e docker_services_scope=<svc>` gates the direct-role platform tasks off AND narrows the deploy loop to that service) + hardened the restart guard (`(extra_templates_result.results | default([]))`, `map(attribute='extra')` — the extra-.j2 loop's `loop_var: extra` means results carry key `extra`, not `item`). A true single-service converge (`--tags docker_services -e docker_services_scope=<svc>`) is now possible; ⏳ deploy-gated live verify pending (HD-255 tail). Also still tracked: strict-default-preserving Authentik ScopeMapping (`email_verified: True`) for headscale provider pk 13. ✅ **② core + ③ DONE (2026-08-26):** second blocker fixed — Authentik default `email` scope mapping hardcodes `email_verified: False` × headscale default `email_verified_required: true` → 401 `unverified email`; fixed live + in template via `oidc.email_verified_required: false` (family-trusted users behind `allowed_domains: kogler.si`; strict-default-preserving Authentik-side fix tracked in HD-255). **First-ever successful `/oidc/callback`: phone enrolled** under OIDC-linked user `domen@kogler.si` (node 3 `Naprava A54`, 17:44:06Z, NO error). Owner deleted the hand-created user ID 1 in Headplane → only OIDC user ID 2 `domen@kogler.si` remains (③ resolved). ⏳ **Re-enroll remaining:** the cleanup also removed the laptop node (node 1) and the just-added phone (node 3) — `nodes list` is EMPTY; both devices re-enroll via the now-working OIDC flow under `domen@kogler.si`. ✅ ④ DONE 2026-08-26: ACL tightened at first enrolment — `policy.hujson.j2` interim `*:*` → deny-by-default user-based `{"src":["domen@kogler.si"],"dst":["domen@kogler.si:*"]}` (validated `policy check --bypass-grpc` = Policy is valid, applied + restarted; `tagOwners` empty → user-email-based, tag model documented as later). Both devices re-enrolled under the OIDC user; phone online under tightened ACL, 0 denials; **all Lane-D objectives (①②③④) CLOSED**.

### 3c. Carried queue (non-blocking)

- **HD-238** oldsrv→VPS DR runbook authoring for non-GPU services (todo §2.9) — laptop-doable; pairs with next backup.md touch.
- **HD-246** RAG env pins land WITH HD-247's first converge (absorbed; details live in todo row + services-ai.md §5).
- Zipline `/drop` static glue page — Phase 2, only if the owner asks; NOT queued.
- Owner-action chase (still open): prometheus-internal_api + crowdsec-bouncer_api rotations, persisted-Authentik-token `expiring=False` sweep (incl. minting `authentik-nas_api` durable at NAS provisioning — Phase 2; laptop-cleanup note: still manual, not automated), LDAP HD-132 authoring, Phase 1.5 hardware swaps, HD-57 bank legs, HD-30 (delayed), homelab repo migration (delayed).

## 4. Working rules (binding)

Fresh worktree per session BEFORE any edit — now mechanically enforced (`bash scripts/guard-session.sh` refuses edits on primary+main; `validate-all.sh` hard-fails primary+main+DIRTY); merge back only committed+green, ff-only; primary = merge station only. 9P gate before every converge; surgical `--tags`; secrets 1P-item.field only + `>-` for YAML; persisted Authentik tokens always `expiring=False` (HD-216); journal append-only; owning doc + changelog row in same change; English; relative links; Authentik blueprint pin array attrs (HD-231); don't touch headplane/headscale unless asked. **Handoff diff-rule (CONVENTIONS §4): edit the previous handoff, never rewrite from scratch; computable pointers are derived at write time, never typed.** No multi-line bash heredocs with backslashes/backticks on this host — write+run temp script files instead.
