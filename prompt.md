# prompt.md — Deployment Execution Handoff #11 — HD-216 CLOSED ✅ (token rotator = upstream auto-rotation); HD-166 closed earlier today; parallel session's small queue PROBABLY ALREADY DONE — reconcile first

> **Role:** Entry point for the next session. Two lanes closed on 2026-08-24:
> **HD-166** (ONLYOFFICE `.docx`, six layers, owner round-trip PASS) and **HD-216** (the Phase-1
> "token rotator" mystery — root cause identified OFFLINE as an upstream FEATURE: authentik
> AUTO-ROTATES expiring api-intent tokens; only `expiring=False` tokens persist; docs folded into
> all owning docs). A **parallel session** was additionally working three small queue items
> (§3a) — by the time you read this they are **probably already finished and merged**.
> Your FIRST action is reconciliation, not new work.
> **Linked from:** [README.md](README.md) §2 · journal: [deployment-journal.md](deployment-journal.md)
> HD-216 entries · changelog rows HD-216 / HD-216 R2 · owning doc: [docs/services-authentik.md](docs/services-authentik.md)

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output hygiene + secret→YAML `>-` rendering
   (including rendered compose env values), §4 journal loop, §6 worktree discipline.
2. [docs/services-authentik.md](docs/services-authentik.md) — *API-token auto-rotation* section
   (HD-216): ≈5-min sweep rotates expiring api-intent tokens (`SECRET_ROTATE` event),
   app_passwords vanish at expiry, `expiring=False` is the ONLY durable-persisted-token form.
3. [docs/deployment-oidc.md](docs/deployment-oidc.md) — glue contract de-staled: blueprint apply =
   deterministic one-shot playbook step (HD-230b), NOT a persisted provision token.
4. [docs/deployment-secrets.md](docs/deployment-secrets.md) — `authentik-provision_api` tombstone
   (retired 2026-08-22) now carries the identified root cause + recipe pointer.
5. [todo.md](todo.md) — **HD-211 row refocused**: retired-item rotation step dropped;
   `expiring=False` mandatory for any persisted Authentik token in that batch + one-time
   verification of `authentik-api_token`.
6. [docs/services-office.md](docs/services-office.md) — HD-166 final live status (six layers,
   single-secret chain, env-vs-yaml gotcha).

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

## 2. State snapshot

- **main == origin/main** @ `82e3038` at this handoff's write time (HD-216 close-up). The parallel
  session may have merged on top since — re-derive before branching.
- Closed today: **HD-166** (office stack fully live) · **HD-216** (token auto-rotation identified &
  documented everywhere; no live probing was done — verification path = Events filter
  `SECRET_ROTATE`, read-only, if ever needed).
- **In flight elsewhere (expected merged by your start):** the parallel session's small queue — see §3a.
  No other in-flight branches known; both of today's session worktrees were removed after merge.
- **ID registry:** next free = **HD-236** (max(todo)=HD-232, max(changelog)=HD-235 at write time;
  re-derive against changelog top rows when writing — parallel rows may have landed).
- **Coordination:** do NOT touch headplane/headscale (separate lane). Primary checkout owns main.

## 3. Next-session execution order

### 3a. RECONCILE FIRST — parallel session's small queue (probably already finished)

The evening session of 2026-08-24 was finishing these three items. Before touching anything:
`git log --oneline -15` + journal tail + changelog top rows to confirm what landed.

| Item | Area | Expected state |
|------|------|----------------|
| `collaboration.app.insecure` env→schema mapping (7.4 rolling) | opencloud compose | documented TODO / resolution note; secondary, no functional impact |
| csp.yaml restart-on-change behavior | traefik | small diagnostic/fix |
| Surgical-run tag-union gotcha documentation | deployment-manual | docs-only |

If any are still open, finish them in a FRESH worktree per §4; if done, do not redo — just verify
their journal/changelog records exist and move on.

### 3b. Owner-action chase (reminders, not blockers)
- **HD-211 rotation batch** (refocused): placeholder → real values for `openrouter_api`,
  `cohere_api`, `forgejo_api`; plus the original exposure list (onlyoffice_db,
  onlyoffice-rabbitmq_login, opencloud-collab_password — rotating it invalidates ALL OpenCloud
  sessions again, plan a re-login window — DS-generated WOPI keypair). **HD-216 tails:** every
  PERSISTED Authentik API token created/touched here MUST be `expiring=False`
  ([services-authentik.md](docs/services-authentik.md)); include the one-time `expiring=False`
  verification of `authentik-api_token` (sync-authentik-users glue).
- Kopia source wiring (`/backup`) decision + seed; LDAP **HD-132** authoring — remember app
  passwords VANISH at expiry (360-day wizard default): create bind users non-expiring;
  Forgejo `domen/homelab` repo creation (unblocks renovate flip from temporary `domen/test`);
  Phase 1.5 cutover (dnevna/garage swaps + capsman rsc — garage wAP ac declared dead HD-232).

### 3c. Remaining small engineering queue
- Blueprint auto-apply one-shot (`apply-authentik-blueprints.yml`, HD-230b) — IaC wired into
  docker_services main.yml; confirm it fired green on the latest converge.
- Headplane hardening (separate lane — only if its owning session asks).

## 4. Working rules (binding)

- Fresh worktree per session before ANY edit (`../homelab-wt-<date>-<HHMM>`); merge back only
  committed+green; primary checkout owns main; remove own worktree via `git worktree remove`.
- Converges: 9P gate first, surgical `--tags` preferred (traefik dynamic-file changes need the
  `traefik` tag too, e.g. `--tags docker_services,onlyoffice-docs,traefik`). Tag-union gotcha
  documentation may have landed via §3a — follow deployment-manual once it does.
- Secrets: 1Password item.field names only — NEVER values anywhere; `>-` block scalar for ALL
  1P-sourced YAML/compose-env renders. Probes print hashes/lengths/prefixes only.
- **Persisted Authentik API tokens: ALWAYS `expiring=False`** (HD-216) — never store a copy of an
  expiring api-intent token; it will be rotated server-side within minutes.
- Journal append-only; owning doc + changelog row(s) in the same change; English prose; relative links.
- Authentik blueprint: pin array attrs (HD-231). Do not touch headplane/headscale unless asked.
