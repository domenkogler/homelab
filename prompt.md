# prompt.md — Deployment Execution Handoff #14 — HD-57 finance stack IaC landed (stable pin + n8n EB bridge) + 4 decisions recorded; HD-238 registered

> **Role:** Entry point for the next session. This session (2026-08-24, late night) executed **HD-57**
> Stage 1→8: new `docker_services/actual-budget/` compose template (`actualbudget/actual-server`,
> stable pin `26.8.1` registry-verified) + `home_servers.yml` registry entry + `versions.yml` pin,
> with four dated decisions recorded in [docs/services-finance.md](docs/services-finance.md):
> ① placement **oldsrv** (internal-only P+I; n8n/LiteLLM stay VPS-side over WG S2S), ② bank sync =
> **stable image + n8n Enable-Banking bridge** (nightly/native-sync rejected under §7 pin law),
> ③ credit card = monthly manual CSV first, ④ **seed-before-sync**. Stale AI path corrected to the
> LiteLLM spine (nothing targets Ollama directly — HD-59); API leg :5006 bound to `oldsrv_home_ip`
> (immich-ml precedent). Phase-3 ledger wired into deployment-tasks.md; validator got an
> `oldsrv_home_ip` mock + `actual-budget` in WEB_SERVICES. New **HD-238** (oldsrv→VPS DR runbook for
> non-GPU services) registered from the placement discussion. **Linked from:** [README.md](README.md)
> §2 · changelog row **HD-57** · owning doc: [docs/services-finance.md](docs/services-finance.md).

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output hygiene + secret→YAML `>-` rendering,
   §4 journal loop + post-task housekeeping, §6 worktree discipline.
2. [docs/deployment-ansible.md](docs/deployment-ansible.md) §Tags & surgical runs — now states the
   FIXED invariant: **every** role handler carries `tags: always`; any NEW handler must too.
3. [docs/deployment-compose.md](docs/deployment-compose.md) — extras restart-on-change guard
   (bind-mounted configs invisible to `docker compose up -d`; guarded per-service restart).
4. [docs/services-authentik.md](docs/services-authentik.md) — *API-token auto-rotation* (HD-216):
   `expiring=False` is the ONLY durable-persisted-token form.
5. [deployment-manual.md](deployment-manual.md) How-to-use — canonical `--tags` invocation tables;
   union semantics; service-tag-alone = silent no-op.

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`,
  `scripts/ak-shell.sh`); NEVER inline through wsl.exe from git-bash (MSYS mangles leading-`/`
  args); probes = throwaway temp script outside all checkouts → delete after capture.
- ⚠ **9P gate MANDATORY before every playbook run** (syntax-check included — it reads the tree
  over /mnt/d): `git ls-files -z | xargs -0 md5sum --text | md5sum` on BOTH sides EQUAL. For a
  WORKTREE, translate `.git` gitdir (`cat .git` → sed `s#^D:#/mnt/d#` → tr '\\' '/'), then
  `export GIT_DIR` (+ `GIT_WORK_TREE`) inside the WSL temp script.
- Read-only probes: `ssh -o BatchMode=yes ansible-admin@vps.kogler.si`; sudo via `sudo -n bash -s`.
  **REDACT secrets in probe output — hashes/lengths/prefixes only; booleans/paths/URIs fine (HD-235).**
- ⚠ Template comments must not contain literal `{{` sequences (Jinja parses them).

## 2. State snapshot (end of session)

- **main == origin/main? verify at close** @ handoff #14 closing commit (worktree
  `homelab-wt-2026-08-24-2235` merged back green).
- Closed this session: **HD-57 Stage 8/10** (IaC + decisions; validate-all green; ⏳ tail = human
  tokens/EB app, n8n workflows at Phase 1, AllowedIPs scope, first deploy + live verify at Phase 3).
  Registered: **HD-238** (oldsrv→VPS DR runbook, todo §2.9).
- **Still open at next converge (ride-along checks, no standalone session needed):**
  ① zero spurious restarts on unchanged extras / exactly one per changed extra (HD-236 guard);
  ② direct per-run proof that `apply-authentik-blueprints.yml` fired green (task output shows
  `== applying … ==` + Applied markers; content-side already proven server-side).
- **Flagged candidates for the NEXT small batch:** none new — the tagged-handler gap is closed.
  Remaining queue below is owner-chase + converge-ride-along only.
- **ID registry:** next free = **HD-239** (max(changelog)=HD-238; re-derive at write time per
  CONVENTIONS §1 — never re-type this pointer).
- **Coordination:** do NOT touch headplane/headscale (separate lane). Primary checkout owns main.

## 3. Next-session execution order

### 3a. Owner-action chase (reminders, not blockers)
- **HD-211 rotation batch** (refocused per HD-216): placeholder → real values for `openrouter_api`,
  `cohere_api`, `forgejo_api`; plus the original exposure list (onlyoffice_db,
  onlyoffice-rabbitmq_login, opencloud-collab_password — rotating it invalidates ALL OpenCloud
  sessions again, plan a re-login window — DS-generated WOPI keypair). Every PERSISTED Authentik
  API token created/touched here MUST be `expiring=False`
  ([services-authentik.md](docs/services-authentik.md)); include the one-time `expiring=False`
  verification of `authentik-api_token` (sync-authentik-users glue).
- Kopia source wiring (`/backup`) decision + seed; LDAP **HD-132** authoring — app passwords VANISH
  at expiry (360-day wizard default): create bind users non-expiring; Forgejo `domen/homelab` repo
  creation (unblocks renovate flip from temporary `domen/test`); Phase 1.5 cutover (dnevna/garage
  swaps + capsman rsc — garage wAP ac declared dead HD-232).

### 3b. Remaining engineering queue
- **HD-238** oldsrv→VPS DR runbook for non-GPU services (todo §2.9) — laptop-doable authoring task;
  pairs naturally with the next backup.md touch.
- **Converge ride-along checks (fold into any upcoming docker_services converge):**
  observe residual ① (extras restart guard behavior) + confirm blueprint one-shot task output
  green in the same run; journal both, then trim the ⏳ tails in changelog HD-236 row history via
  an append-only R-row.
- Headplane hardening (separate lane — only if its owning session asks).

## 4. Working rules (binding)

- Fresh worktree per session before ANY edit (`../homelab-wt-<date>-<HHMM>`); merge back only
  committed+green; primary checkout owns main; remove own worktree via `git worktree remove`.
- Converges: 9P gate first, surgical `--tags` preferred — canonical tables in
  [deployment-manual.md](deployment-manual.md)/[docs/deployment-ansible.md] (role+service tags BOTH
  required; traefik dynamic-file changes need the `traefik` tag too). Handlers can no longer be
  dropped by filters — but keep `tags: always` on every new handler (HD-237 invariant).
- Secrets: 1Password item.field names only — NEVER values anywhere; `>-` block scalar for ALL
  1P-sourced YAML/compose-env renders. Probes print hashes/lengths/prefixes only.
- **Persisted Authentik API tokens: ALWAYS `expiring=False`** (HD-216) — never store a copy of an
  expiring api-intent token; rotated server-side within minutes.
- Journal append-only; owning doc + changelog row(s) in the same change; English prose; relative links.
- Authentik blueprint: pin array attrs (HD-231). Do not touch headplane/headscale unless asked.
