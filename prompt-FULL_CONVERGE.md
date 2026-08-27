# prompt-FULL_CONVERGE.md — HD-268 live deploy: one-line dsh blocker remains; then full converge + baseline

> **Active lane:** HD-268 **IaC AUTHORED + MOSTLY LIVE-CONVERGED** (2026-08-27, single session). The AI modularisation IaC (Qdrant swap + pi.dev/DSH dual harness + MCP stubs) is written, **all authoring validation green**, and the live VPS converge got *almost* through — the **LAST blocker is a one-line `{{ }}` in a dsh-comment** that the renderer trips on. Once fixed, the full converge completes and the session's requested **baseline second run** ("static time costs when nothing changed") can be captured.

> **Role:** Entry point for the next session — continue the HD-268 LIVE DEPLOY from `main` `bccfe24`. Predecessor: handoff #24a (`prompt.md`); this session did the HD-268 IaC + deploy-path fixes + a partial live converge. **Linked from:** README.md §0/§2 · CONVENTIONS.md §4/§6 · [`changelog.md`](changelog.md) (HD-268 row) · [`docs/services-ai.md`](docs/services-ai.md) (Qdrant/OKF/dual-harness) · [`deployment-journal.md`](deployment-journal.md) (this session's live evidence appended below) · [`todo.md`](todo.md) HD-268.

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §6 worktree discipline (**mechanically enforced** by `scripts/guard-session.sh` + validate-all hard-gate), §4 post-task housekeeping + close-out, §2 secret-output hygiene + `>-` YAML rendering, §5 service-onboarding.
2. [docs/services-ai.md](docs/services-ai.md) — THE HD-267 architecture (Qdrant, Forgejo-OKF wiki SSOT, dual pi.dev+DSH harness).
3. [docs/network-vpn.md](docs/network-vpn.md) — §Tailnet: **Pattern A** (loopback app + tailscale sidecar shared-ns serve). pi-dev + DSH UIs use this.
4. [changelog.md](changelog.md) — HD-247–251 decision bundle + HD-267/268 rows.
5. [deployment-journal.md](deployment-journal.md) — append this session's run (approx 12:30–22:10 UTC+2, 2026-08-27).

## 1. Environment (same as handoff #24a, unchanged)

Windows 11 laptop, but THIS session ran inside **WSL2 Debian 13 (trixie) bash** — the module in play is the WSL `ansible-run.sh` runner:
- Platform: **Debian-13/trixie in WSL2, bash**. CWD pinned `/home/domen/source/homelab`; `python3` = `/home/domen/ansible-venv/bin/python3`; UTF-8/LF.
- Windows/WSL gotchas (from #24a): multi-line bash heredocs with backslashes/backticks mangle through `bash -c` — **write scripts to a temp file via the `write` tool and scp/run them**; `MSYS_NO_PATHCONV=1` when invoking `wsl.exe` from git-bash (not needed here — we're already in WSL).
- Deploy runner: `bash scripts/ansible-run.sh playbooks/vps.yml [--tags …]` (sets ANSIBLE_CONFIG/ROLES_PATH + 1P SA token + venv). **Never edit on primary+main** — always a fresh `git worktree add ../homelab-wt-<ts>`.

## 2. State snapshot (start of next session)

- **main @ `bccfe24`** — pushed. This session's commit trail (all green, in order):
  - `34076b9` feat(ai): HD-268 IaC — Qdrant swap + dual pi.dev/DSH harness + pi-web-ui (the authoring; worktree `homelab-wt-20260827-1940`)
  - `9486797` fix(deploy): externalize Authentik blueprints + fix op-vault-pass op_derive_spec bug (Jinja both-branches + explicit op_mode)
  - `9e008bb` fix(deploy): op_export_script role default (glue-mode 'undefined')
  - `cf20b96` fix(deploy): litellm-bootstrap-keys.sh.j2 Jinja `${#KEYS[@]}` collision
  - `4eb4b50` perf(deploy): db_role_sync/ro_sync/forgejo.ini read from HD-258 vault dict (no per-task op; ~17s saved)
  - `3c6cd7d` fix(deploy): litellm mint_key models-body comma logic
  - `24064f2` fix(deploy): litellm bootstrap body — missing comma before key_alias + empty-body key
  - `8a1e4fd` chore(secrets): op-vault-export workers 15→6 + `op_vault_workers` knob
  - `568ba64` fix(deploy): litellm bootstrap — `--reveal` on master-key + scoped-key reads (masked placeholder bug)
  - `5c4c218` fix(deploy): litellm bootstrap — add `-i` to docker exec heredocs; fix body JSON expansion
  - `8e1d927` fix(deploy): litellm bootstrap vault_write — correct 1P category `API Credential` + detach stdin
  - `7c5526b` fix(deploy): litellm bootstrap probe_key — fix inverted 000/valid-code check
  - `82a3af2` fix(deploy): pi-dev node image `24-alpine` → `24` (template appends `-alpine`)
  - `31018e6` perf(deploy): docker role force:false on Docker GPG key
  - `bd9cfda` + `bccfe24` perf/fix: docker GPG key — replace 24s-hanging `get_url`(urllib) with `curl -4` + `creates` (root cause: **Python urllib IPv6→IPv4 fallback stall ~24s to CloudFront; curl -4 = 60ms**), removed invalid `warn` param.
- **Worktrees on disk (IMPORTANT — leftover):**
  - `homelab-wt-dshcomment-20260827-2155` (branch `homelab-wt-dshcomment-20260827-2155`, at `31018e6`) — **holds the UNCOMMITTED dsh fix** (see §3, step 1). The exact fix is already applied in this worktree.
  - `homelab-wt-dshfix-20260827-2210` (branch `homelab-wt-dshfix-20260827-2210`, at `bccfe24`) — **clean/empty** (nothing committed). Safe to `git worktree remove`.
  - dangling branch `homelab-wt-fix-vault-pass-20260827-2030` — a leftover branch ref (the worktree dir was deleted earlier; branch ref remains). Delete with `git branch -D` (its commit is already in main).
- **Live VPS state (verified 2026-08-27, ~21:40–21:55 UTC+2):**
  - **Qdrant deployed** (`docker compose up -d for qdrant` ok, 9.03s on the run where it deployed).
  - **pi-dev deployed** (`Docker compose up -d for pi-dev` ok, 7.83s — image now resolves `node:24-alpine`).
  - **LiteLLM bootstrap glue FULLY FIXED + idempotent** — all **8 scoped keys minted + stored to 1Password** (len 26 each): `owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `dsh_api`, `pi-harness_openai_api`, `openclaw-litellm_api`, `rag-int-svc_api`. Re-run verifies ("keep … existing key valid", RC=0, ~8s). **Reconciled**: earlier partial runs left 4 orphan server keys; deleted by alias (8 glue aliases), re-minted cleanly.
  - **dsh NOT deployed** — the converge fails at `Template docker-compose.yml for dsh`: `object of type 'dict' has no attribute 'tailscale_...'` (a `{{ vault['tailscale_...'] }}` inside a comment in dsh template, line 70). **This is THE remaining blocker.**
  - Authentik glue, forgejo OIDC source, all the standard 20 services: converged (ok=184 changed=24 failed=0 except dsh).
- **1Password rate limits (checked live mid-session):** token read 83/1000 used, account rw 114/1000, write 0/100. **Comfortable headroom** — the 15→6 workers change was cheap insurance, not a necessity.

## 3. Next-session execution order (the ONLY remaining path to a green full converge + baseline)

### Step 0 — pick up + cleanup
- `git fetch origin && git status` (main should be `bccfe24`).
- Reuse or redo: the **`homelab-wt-dshcomment-20260827-2155`** worktree already contains the uncommitted dsh fix. Safest: apply the same one-line edit in a FRESH worktree (per §1 discipline) rather than trusting the stale one; then remove the two stale worktrees + dangling branch:
  - `git worktree remove /home/domen/source/homelab-wt-dshfix-20260827-2210` (clean)
  - `git worktree remove /home/domen/source/homelab-wt-dshcomment-20260827-2155` → **but first note its change** so you don't lose it (it's the fix below).
  - `git branch -D homelab-wt-fix-vault-pass-20260827-2030`

### Step 1 — THE one-line dsh fix (BLOCKER)
File: `IaC/ansible/templates/docker_services/dsh/docker-compose.yml.j2`, **line 70** (inside the commented-out `dsh-tailscale` sidecar):
```diff
-  #     TS_AUTHKEY: "{{ vault['tailscale_...'].credential }}"
+  #     TS_AUTHKEY: "vault item tailscale_dsh.credential"   # 1P tailscale auth-key item (uncomment + wire at deploy)
```
Why: Jinja renders `{{ }}` in comments. The literal `vault['tailscale_...']` becomes a dict-attribute lookup → fails the whole dsh render. (Same class as the pi-dev comment fix earlier.)
- Validate: `bash scripts/validate-all.sh` (must exit 0) + `python3 scripts/validate-docker-services.py --only dsh`.
- Commit + merge ff-only to main + push (green only).

### Step 2 — FULL converge (should now pass end-to-end)
```
bash scripts/ansible-run.sh playbooks/vps.yml
```
Expected: ok=all, changed=small, **failed=0**. Watch: dsh deploy + pi-dev/dsh tailscale sidecars are commented (Pattern-A NOT yet enabled — by design, they need `tailscale_dsh`/`tailscale_pi_dev` 1P items + uncommenting at deploy-time; do NOT uncomment in this step).

### Step 3 — IMMEDIATE second run (the user-requested baseline)
Run the SAME full converge **again immediately** to capture **static time costs when nothing changed**:
```
bash scripts/ansible-run.sh playbooks/vps.yml
```
Record the per-task TASKS RECAP and the total wall time. This is the baseline for deciding whether the earlier-discussed **surgical op-export** (scope the derive to `docker_services_scope`) or other optimizations are worth it. (Note: the `docker` role + authentik glue + litellm bootstrap still run every full converge; expected steady-state costs: gpg ~0.1s, authentik glue ~20s (idempotent), litellm bootstrap ~8s (keep-verify), op-export ~4-5s at workers 6.)

### Step 4 — close-out (post-task housekeeping, CONVENTIONS §4)
- Append a `deployment-journal.md` entry: full converge pass + baseline timings, dsh deployment evidence, any deviations.
- Update `todo.md` HD-268 tail: ⏳ deploy-gated items remaining = tailnet sidecar wiring (Pattern-A serve + `tailscale_dsh`/`tailscale_pi_dev` items) + live-verify Qdrant embed/rerank + re-index. When the live verify lands, DELETE the row + changelog Done row per §4.
- If blueprints changed: run `bash scripts/ansible-run.sh playbooks/authentik-blueprints.yml` (they are now EXTERNALIZED from the deploy lane — blueprints apply only when a blueprint file changes; see `9486797`).

## 4. Secrets / 1P state for this lane
- `qdrant_db` (API Credential, `credential` field) — created by provision-vault.sh (2026-08-27). Qdrant compose reads `vault['qdrant_db'].credential` as `QDRANT__SERVICE__API_KEY`.
- `pi-harness_openai_api`, `dsh_api` etc — **glue-minted** (by litellm bootstrap), NOT in provision-secrets CATALOG. Now populated (len 26).
- `pi-harness_forgejo_api`, `dsh_forgejo_api` (PR-only Forgejo PATs) — created by provision-vault.sh; the compose templates reference them but the Forgejo tokens themselves must be **issued in the Forgejo UI** before those consumers work (HD-268 note).
- **NOT_AUTO_ROTATABLE** now includes `pi-harness_forgejo_api`/`dsh_forgejo_api` (Forgejo-UI-issued).

## 5. Known open decisions / what NOT to re-decide
- **Dual harness = pi.dev + DSH side-by-side** (supersedes HD-250 "DSH replaces pi.dev"). pi.dev = container running `@earendil-works/pi-coding-agent` + `pi-web-access` + `pi-web-ui` (PORT 8080, `PI_WEB_HOST=0.0.0.0` in-container; Pattern-A tailnet sidecar documented/disabled at deploy). DSH = `runzhliu/deepseek-harness-docker:0.1.1-rc.2` (verify tag+digest at deploy; isolated `/srv/docker/dsh/workspace`, UI Pattern-A to :3080).
- **OKF wiki repo skeletons NOT created** — owner creates manually (session decision). rag-mcp/forgejo-mcp are `enabled:false` STUBS (placeholders, not runnable).
- **Qdrant backup seam**: NOT a db-backup DBxx block (Qdrant isn't postgres). Documented in template header + docs/backup.md (rebuildable-cache class; snapshot API + Kopia later).
- **Verify image tags at converge**: `qdrant:v1.12.4`, `runzhliu/deepseek-harness-docker:0.1.1-rc.2`, `pi-web-ui@0.44.0`, `@earendil-works/pi-coding-agent@0.84.3` (the dsh/pi/qdrant pin lines carry TODO-deploy comments).

## 6. Did-not-close / session sandbox note
- The multi-run litellm debugging left **1 orphan server key** (a `test-probe-*`) in LiteLLM — harmless, ignore or delete via Admin UI.
- `homelab-wt-dshfix` + `homelab-wt-fix-vault-pass` leftovers — clean per Step 0.
- `prompt.md` itself is NOT updated to this handoff — this file (`prompt-FULL_CONVERGE.md`) replaces it for the next session. Rename/merge at close-out (per CONVENTIONS §4-close-out, the standing handoff is `prompt.md`; fold this in when HD-268 closes).