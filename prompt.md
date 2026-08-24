# prompt.md — Deployment Execution Handoff #12 — B-queue small engineering batch CLOSED ✅ (HD-236: collab.insecure false alarm + extras restart guard + --tags union docs); reconcile-with-#11 resolved

> **Role:** Entry point for the next session. This session (2026-08-24, late evening) executed the
> three §3b/§3a small-queue items from handoffs #10/#11 as **parallel isolated worktree workers**,
> merged all three back green, and closed them as **HD-236**. Handoff #11's §3a assumption
> ("parallel session's queue probably already done") was WRONG at its write time — the workers had
> been torn down mid-flight by a tooling fault; this session recovered, re-ran, and landed
> everything. **Linked from:** [README.md](README.md) §2 · journal:
> [deployment-journal.md](deployment-journal.md) HD-236 entry · changelog row HD-236.
> Owning docs touched: [docs/services-office.md](docs/services-office.md),
> [docs/deployment-compose.md](docs/deployment-compose.md), [deployment-manual.md](deployment-manual.md),
> [docs/deployment-ansible.md](docs/deployment-ansible.md).

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output hygiene + secret→YAML `>-` rendering
   (including rendered compose env values), §4 journal loop, §6 worktree discipline.
2. [docs/services-authentik.md](docs/services-authentik.md) — *API-token auto-rotation* section
   (HD-216): ≈5-min sweep rotates expiring api-intent tokens (`SECRET_ROTATE` event);
   `expiring=False` is the ONLY durable-persisted-token form.
3. [docs/deployment-compose.md](docs/deployment-compose.md) — NEW: extras restart-on-change guard
   (bind-mounted configs are invisible to `docker compose up -d`; guarded per-service restart).
4. [docs/deployment-ansible.md](docs/deployment-ansible.md) §Tags & surgical runs +
   [deployment-manual.md](deployment-manual.md) How-to-use — canonical `--tags` invocation tables;
   union semantics; dynamic-include tag gating (service-tag-alone = silent no-op).
5. [docs/services-office.md](docs/services-office.md) — six-layer live status + verified
   `collaboration.app.insecure` resolution bullet.

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

- **main == origin/main** @ this handoff's closing commit (three worker merges `1320e5f`/`224d52c`/
  `ba4fe5d` + closing docs). Working tree clean; all keep/* branches deleted post-merge.
- Closed tonight: **HD-166** (office stack, owner round-trip PASS) · **HD-216** (token auto-rotation
  identified) · **HD-236** (B-queue batch — details below).
- **Deploy-gated residuals (HD-236):** ① first converge must show ZERO spurious restarts on unchanged
  extras and exactly one restart per service whose extra actually changed; ② one-time live probe that
  the EFFECTIVE runtime env of opencloud reads `COLLABORATION_APP_INSECURE=false` (contrasting with
  any stale on-disk yaml snapshot).
- **Flagged latent gap (not fixed):** docker_services' `reload systemd` handler is untagged — under
  filtered runs a notified handler can be silently skipped (see deployment-ansible.md). Candidate for
  the next small batch.
- **ID registry:** next free = **HD-237** (max(changelog)=HD-236 after tonight; re-derive at write time).
- **Coordination:** do NOT touch headplane/headscale (separate lane). Primary checkout owns main.

## 3. Next-session execution order

### 3a. Owner-action chase (reminders, not blockers)
- **HD-211 rotation batch** (refocused per HD-216): placeholder → real values for `openrouter_api`,
  `cohere_api`, `forgejo_api`; plus the original exposure list (onlyoffice_db,
  onlyoffice-rabbitmq_login, opencloud-collab_password — rotating it invalidates ALL OpenCloud
  sessions again, plan a re-login window — DS-generated WOPI keypair). Every PERSISTED Authentik API
  token created/touched here MUST be `expiring=False`
  ([services-authentik.md](docs/services-authentik.md)); include the one-time `expiring=False`
  verification of `authentik-api_token` (sync-authentik-users glue).
- Kopia source wiring (`/backup`) decision + seed; LDAP **HD-132** authoring — remember app
  passwords VANISH at expiry (360-day wizard default): create bind users non-expiring;
  Forgejo `domen/homelab` repo creation (unblocks renovate flip from temporary `domen/test`);
  Phase 1.5 cutover (dnevna/garage swaps + capsman rsc — garage wAP ac declared dead HD-232).

### 3b. Remaining small engineering queue
- Blueprint auto-apply one-shot (`apply-authentik-blueprints.yml`, HD-230b) — IaC wired into
  docker_services main.yml; confirm it fired green on the latest converge.
- Tagged-handler hygiene batch: tag `reload systemd` (+ audit any other notified-but-untagged
  handlers across roles) so filtered runs can't skip notifications (discovered HD-236c).
- Headplane hardening (separate lane — only if its owning session asks).

## 4. Working rules (binding)

- Fresh worktree per session before ANY edit (`../homelab-wt-<date>-<HHMM>`); merge back only
  committed+green; primary checkout owns main; remove own worktree via `git worktree remove`.
- Converges: 9P gate first, surgical `--tags` preferred — follow the canonical tables in
  [deployment-manual.md](deployment-manual.md)/[docs/deployment-ansible.md](docs/deployment-ansible.md)
  now (role+service tags BOTH required; traefik dynamic-file changes need the `traefik` tag too).
- Secrets: 1Password item.field names only — NEVER values anywhere; `>-` block scalar for ALL
  1P-sourced YAML/compose-env renders. Probes print hashes/lengths/prefixes only.
- **Persisted Authentik API tokens: ALWAYS `expiring=False`** (HD-216) — never store a copy of an
  expiring api-intent token; it will be rotated server-side within minutes.
- Journal append-only; owning doc + changelog row(s) in the same change; English prose; relative links.
- Authentik blueprint: pin array attrs (HD-231). Do not touch headplane/headscale unless asked.
