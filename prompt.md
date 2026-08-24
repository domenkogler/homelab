# prompt.md — Deployment Execution Handoff #9 — HD-166 deeply diagnosed: `.docx` now opens BUT "Invalid access token" 401 (REVA-leg JWT split-brain); fix PARTIAL (Lane A3 branch @4976540), `OC_JWT_SECRET` change + re-login = next-session TOP item

> **Role:** Entry point for the next session. This session (2026-08-24, afternoon) drove the **HD-166 `.docx` editor fix** to a NEW state:
> **three root-cause layers found live; layers 1–3 fixed + DEPLOYED; layer 3 (REVA-leg JWT split-brain) diagnosed with exact source evidence but the final `OC_JWT_SECRET` fix is NOT yet applied.**
> Owner browser round-trip shows `.docx` now **opens the ONLYOFFICE editor** (no more "download instead", WOPI discovery 200) but DS shows **"Invalid access token" 401** — the failure moved one layer deeper.
> The partial fix is committed on branches `laneA3-hd166-wopisec` + `session-hd166-wopisec-20260824-1315` (@`4976540`, `COLLABORATION_WOPI_SECRET` added — correct, deployed), **NOT merged to main**. main == origin/main == `8f3f7d0` (pt.1–3 merged).
> **Linked from:** [README.md](README.md) §2 · journal: [deployment-journal.md](deployment-journal.md) HD-166 pt.2/pt.3/pt.4 · changelog rows HD-03 R1-editor, HD-166-pt.2/3/4 · todo: HD-166.

---

## 0. Mandatory context (read in this order)

1. [deployment-journal.md](deployment-journal.md) — **HD-166 pt.2/pt.3/pt.4** (the four-layer diagnosis + exact code evidence; pt.4 has the full REVA-leg analysis + hashes + the remaining fix).
2. [plan/20260824-netredo/t1-report.md](plan/20260824-netredo/t1-report.md) — the original fix-path report (now largely superseded by pt.2–4).
3. [docs/services-office.md](docs/services-office.md) — ONLYOFFICE/WOPI design + live status (three layers, pt.4 pending).
4. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output-hygiene (values NEVER in stdout/chat/git — hashes lengths prefixes only; probes that hit `local.json`/`opencloud.yaml` MUST redact), §4 journal loop, §6 worktree.
5. [docs/deployment-secrets.md](docs/deployment-secrets.md) — secret rendering/hygiene.
6. [docs/services-authentik.md](docs/services-authentik.md) — blueprint one-shot-apply + pin-array-attrs.

---

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`); NEVER inline through wsl.exe.
- ⚠ **9P gate MANDATORY before every playbook run**: `git ls-files -z | xargs -0 md5sum --text | md5sum` on BOTH sides EQUAL. For a WORKTREE, translate `.git` gitdir: read `cat .git`, `sed 's#^D:#/mnt/d#'`, `tr '\\' '/'`, `export GIT_DIR="$GITDIR"` — then the hash from WSL equals the Windows-side hash of the same worktree. (Verified working this session: `8f3f7d0` era hashes matched.)
- Read-only probes: temp script + `ssh -o BatchMode=yes -i ~/.ssh/id_ed25519 ansible-admin@vps.kogler.si` from WSL; sudo via `sudo -n bash -s`. **REDACT `secret/password/token/jwt` values — one probe leaked ONLYOFFICE `local.json` to a transcript this session (HD-235).**
- ⚠ Pipe-masking law: never a secret VALUE — hashes/lengths/prefixes/IDs only.

---

## 2. State snapshot (end of session)

- **main == origin/main == `8f3f7d0`** (pt.1–3 merged+pushed earlier: collaboration EXCLUDE fix + WOPI_ENABLED + docs). Working tree clean.
- **IN-FLIGHT (NOT merged):** branch `laneA3-hd166-wopisec` @ `4976540` adds `COLLABORATION_WOPI_SECRET` (1P `opencloud-collab_password`) to the opencloud compose — CORRECT + already DEPLOYED live (converge 9P ✓); branch `session-hd166-wopisec-20260824-1315` @ same. Worktrees `../homelab-wt-laneA3-hd166` + `../homelab-wt-wopisec` (the latter holds the pt.4 journal/services-office/changelog/todo edits, uncommitted).
- **Live (verified):** opencloud + onlyoffice-docs up · `collaboration` RUNNING · `/hosting/discovery` 200 (WOPI XML) · `COLLABORATION_WOPI_SECRET` env set · **but `.docx` still 401 "Invalid access token"**.
- **Diagnosis (pt.4, high confidence — source-verified):** `wopicontext.go` L125 `DismantleToken` fails ("token signature is invalid"). REVA-leg split-brain: `OC_JWT_SECRET` env ABSENT → auth mints REVA token with yaml `token_manager.jwt_secret` (`eefff1c1…`); collaboration overrides `TokenManager.JWTSecret` via `COLLABORATION_JWT_SECRET` env (`169e85ad…`) → mismatch.
- **ID registry:** last used none new beyond earlier HD-166 tail; next free HD = **HD-236** (verify against changelog at write time).
- **Coordination:** do NOT touch headplane/headscale (separate lane). Primary checkout owns `main`.

---

## 3. Next-session execution order

### 3a. Fresh worktree per §6 before ANY edit (`../homelab-wt-<date>-<HHMM>` from updated main; merge the in-flight branches first if you want to keep the partial fix).

### 3b. TOP item — finish HD-166 (.docx 401):

1. **Apply the remaining fix:** add `OC_JWT_SECRET` to the opencloud compose env, set to the SAME shared value as `COLLABORATION_JWT_SECRET` / `COLLABORATION_WOPI_SECRET` (1P `opencloud-collab_password`) — single-secret chain. Verify env names against source (`TokenManager.JWTSecret` env `OC_JWT_SECRET;COLLABORATION_JWT_SECRET`; `Wopi.Secret` env `COLLABORATION_WOPI_SECRET`; both parsed via `parser.ParseConfig` → BindSourcesToStructs then envdecode).
2. **Converge** (`--tags docker_services,opencloud`, 9P gate first). Note `opencloud.yaml` is a persistent bind mount at `/srv/docker/opencloud/config/opencloud.yaml` (mtime Aug 22, NOT regenerated by idempotent `opencloud init`); envdecode should override at service start — VERIFY the running service picked up the new env (check `opencloud list`/collab logs, or the parsed value indirectly).
3. **User RE-LOGIN required** (existing REVA tokens were minted with the old secret → invalid after the change). Owner: re-login to file.kogler.si, retry `.docx`.
4. If still 401: check whether envdecode actually won over the stale yaml (the same class as the `insecure: true` env→schema gap seen earlier). Fallback: regenerate yaml via `opencloud init` (careful — may rewrite LDAP/idm blocks; prefer env-only first), or inspect `token_manager.jwt_secret`/`collaboration.wopi.secret` hashes before/after.
5. Close the loop: owner `.docx` round-trip edit+save; update services-office.md, journal pt.5, changelog, todo; merge + push.

### 3c. Owner-action chase (reminders, not blockers)
- HD-211 rotation batch (expand with this session's leak: **onlyoffice_db, onlyoffice-rabbitmq_login, opencloud-collab_password, DS-generated WOPI keypair** — see pt.3/pt.4).
- Kopia source wiring (`/backup`); LDAP HD-132 authoring; Forgejo `domen/homelab` (renovate flip); Phase 1.5 cutover (dnevna/garage swaps + capsman rsc).

### 3d. Small engineering queue
- OpenCloud `collaboration.app.insecure: true` env→schema mapping (unresolved, secondary).
- `OC_JWT_SECRET` / `COLLABORATION_*` env→yaml behavior in 7.4 (this session's core pain — a durable doc note / runbook would help).
- csp.yaml restart-on-change; surgical-run tag gotcha; blueprint auto-apply; headplane hardening (separate lane).

---

## 4. Working rules (binding)

- New worktree before edits; merge back only committed+green; primary checkout owns `main`.
- Converges: 9P gate first (§1 GIT_DIR variant), surgical `--tags` preferred (union-tag gotcha).
- Secrets: 1Password item.field names only — NEVER values in Git/chat/output (HD-235). `>-` block scalar for YAML config secrets. If a live probe will read a config that may contain secrets, **redact** before printing (this session leaked DS `local.json` once — do not repeat).
- Journal append-only; owning doc + changelog row in the same change; English prose; relative links.
- Authentik OIDC provider/blueprint: pin array attrs (HD-231 array-wipe bug).
- Do not touch headplane/headscale unless the owning lane asks.