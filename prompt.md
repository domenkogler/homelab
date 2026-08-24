# prompt.md — Deployment Execution Handoff #10 — HD-166 CLOSED ✅ (`.docx` round-trip + live co-editing PASS); office stack fully live; next-session = owner chase + small queue

> **Role:** Entry point for the next session. This session (2026-08-24, evening) **CLOSED HD-166**:
> applied the two remaining fixes (`OC_JWT_SECRET` single-secret chain on opencloud compose;
> Traefik CSP `upgrade-insecure-requests` middleware for the ONLYOFFICE mixed-content layer),
> converged, verified live, and the **owner confirmed `.docx` open + edit + save + two-browser
> live sync** — six root-cause layers total, all fixed. Branch `session-hd166-jwtfix-20260824-1859`
> merged back to main; docs/journal/changelog/todo updated in the closing change.
> **Linked from:** [README.md](README.md) §2 · journal: [deployment-journal.md](deployment-journal.md)
> HD-166 pt.5 · changelog rows HD-166-pt.5/pt.6 · owning doc: [docs/services-office.md](docs/services-office.md)

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output hygiene + secret→YAML `>-` rendering
   (now INCLUDING rendered compose env values), §4 journal loop, §6 worktree discipline.
2. [docs/services-office.md](docs/services-office.md) — final live status: six layers, all fixed,
   single-secret chain explanation, env-vs-yaml gotcha.
3. [deployment-journal.md](deployment-journal.md) — HD-166 pt.5 (this session's full record).
4. [docs/deployment-secrets.md](docs/deployment-secrets.md) — refined Docker-env rendering scope.

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`); NEVER
  inline through wsl.exe — including plain `wsl.exe -- bash /mnt/...` calls from git-bash (MSYS
  mangles leading-`/` args; use `cmd //c "wsl -d Debian -- bash /mnt/.../script.sh"` with a SCRIPT FILE).
- ⚠ **9P gate MANDATORY before every playbook run**:
  `git ls-files -z | xargs -0 md5sum --text | md5sum` on BOTH sides EQUAL. For a WORKTREE, translate
  `.git` gitdir (`cat .git` → sed `s#^D:#/mnt/d#` → tr '\\' '/') and `export GIT_DIR`.
- Read-only probes: temp script + `ssh -o BatchMode=yes ansible-admin@vps.kogler.si` from WSL; sudo via
  `sudo -n bash -s`. **REDACT secrets in any probe output — hashes/lengths/prefixes only (HD-235).**
- ⚠ Template comments must not contain literal `{{` sequences — Jinja parses them (validate-all
  catches it, but don't write them in the first place).

## 2. State snapshot (end of session)

- **main == origin/main** @ this session's merge commit (contains `3d2adda` OC_JWT_SECRET +
  `0110a74` onlyoffice-csp middleware + closing docs). Working tree clean.
- **Live (verified):** opencloud + onlyoffice-docs healthy; `collaboration` running; discovery 200;
  DS↔OC secret chain hash-identical (`eb63ab…` ×4 legs); `Content-Security-Policy:
  upgrade-insecure-requests` served on office.kogler.si; owner round-trip PASS.
- Session worktree removed after merge; no in-flight branches.
- **ID registry:** next free = **HD-236** (derived: max(todo)=HD-232, max(changelog)=HD-235 — re-derive
  at write time).
- **Coordination:** do NOT touch headplane/headscale (separate lane). Primary checkout owns main.

## 3. Next-session execution order

### 3a. Owner-action chase (reminders, not blockers)
- **HD-211 rotation batch** (still pending): onlyoffice_db, onlyoffice-rabbitmq_login,
  opencloud-collab_password (NOTE: rotating it now invalidates ALL OpenCloud sessions again — plan a
  re-login window), DS-generated WOPI keypair.
- Kopia source wiring (`/backup`); LDAP HD-132 authoring; Forgejo `domen/homelab` (renovate flip);
  Phase 1.5 cutover (dnevna/garage swaps + capsman rsc — garage wAP ac declared dead HD-232).

### 3b. Small engineering queue
- `collaboration.app.insecure: true` env→schema mapping (7.4 rolling) — still unresolved, secondary,
  no functional impact observed (documented in the opencloud compose TODO comment).
- csp.yaml restart-on-change behavior; surgical-run tag union gotcha; blueprint auto-apply;
  headplane hardening (separate lane).

## 4. Working rules (binding)

- Fresh worktree per session before ANY edit (`../homelab-wt-<date>-<HHMM>`); merge back only
  committed+green; primary checkout owns main; remove own worktree via `git worktree remove`.
- Converges: 9P gate first, surgical `--tags` preferred (remember: traefik dynamic-file changes need
  the `traefik` tag too, e.g. `--tags docker_services,onlyoffice-docs,traefik`).
- Secrets: 1Password item.field names only — NEVER values anywhere; `>-` block scalar for ALL
  1P-sourced YAML/compose-env renders. Probes print hashes/lengths/prefixes only.
- Journal append-only; owning doc + changelog row(s) in the same change; English prose; relative links.
- Authentik blueprint: pin array attrs (HD-231). Do not touch headplane/headscale unless asked.
