# prompt.md — Deployment Execution Handoff #15 — two lanes closed 2026-08-24: HD-112 Zipline decided + IaC ⏳ · HD-57 finance IaC + HD-238 registered · HD-239 liveness sweep

> **Role:** Entry point for the next session. Two parallel sessions merged the same night — this
> handoff covers BOTH. **Lane A (HD-112):** Zipline v4.7.0 public bin / URL shortener / QR at
> `bin.kogler.si` taken from owner brainstorm to locked architecture to complete IaC (deploy-gated):
> crowdsec-only tier, viewer routes + folder-guest upload API anonymous BY DESIGN, dashboard gated
> by native OIDC (blueprint provider `zipline`, family-group binding), and a **guestbin
> quota-split** — a dedicated Zipline-local user (no Authentik identity) owns the `dropzone`
> folder, so no-login 6h uploads are bounded by ITS quota while global caps stay generous and
> type-blockers stay OFF. Every mechanism source-verified against upstream (an external answer
> with invented env vars/headers was rejected). **Lane B (other worktree):** HD-57 finance stack
> IaC (`actual-budget` stable 26.8.1 + n8n EB bridge, 4 decisions), HD-238 registered (DR
> runbook), HD-239 liveness sweep corrected 8 stale banners. Both lanes: IaC-only, no gear touched.
> **Linked from:** [README.md](README.md) §2 · HD-112 owning doc:
> [docs/services-utilities.md](docs/services-utilities.md) §Zipline + deploy-gate runbook in the
> compose header · changelog rows **HD-112** (decision + Done-IaC), **HD-57**, **HD-239** ·
> journal Phase-1 entries for both lanes.

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output hygiene + secret→YAML `>-` rendering,
   §4 journal loop + post-task housekeeping, §5 service-onboarding checklist (HD-112 and HD-57
   are the newest Stage-9 rows), §6 worktree discipline.
2. [docs/services-utilities.md](docs/services-utilities.md) §Zipline — design record; the
   **deploy-gate checklist lives in the compose header**
   (`IaC/ansible/templates/docker_services/zipline/docker-compose.yml.j2`).
3. [changelog.md](changelog.md) — **HD-112** rows (decision rationale + Done-IaC inventory),
   **HD-57** row, **HD-239** sweep.
4. [docs/deployment-secrets.md](docs/deployment-secrets.md) — new items `zipline_oidc` /
   `zipline_db` / `zipline_password`; remember glue seeds ONLY `_oidc`.
5. [docs/services-authentik.md](docs/services-authentik.md) — *API-token auto-rotation* (HD-216):
   persisted Authentik tokens must be `expiring=False`.

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

- **main == origin/main? verify at close** @ handoff #15 closing commit (worktrees
  `homelab-wt-20260824-2233` [HD-112] and `homelab-wt-2026-08-24-2235` [HD-57 lane] both merged
  back green).
- Closed tonight: **HD-112 decided + IaC authored, Stage 9/10, ⏳ deploy-gated** (validate-all
  green ×2) · **HD-57 Stage 8/10** (IaC + decisions; ⏳ tail = human tokens/EB app, n8n workflows
  at Phase 1, AllowedIPs scope, first deploy at Phase 3) · **HD-239** liveness sweep · **HD-238**
  registered (oldsrv→VPS DR runbook, todo §2.9).
- **Still open at next converge (ride-along checks, no standalone session needed):**
  ① zero spurious restarts on unchanged extras / exactly one per changed extra (HD-236 guard);
  ② direct per-run proof that `apply-authentik-blueprints.yml` fired green (task output shows
  `== applying … ==` + Applied markers; content-side already proven server-side).
- **ID registry:** next free = **HD-240** (max(changelog)=HD-239; re-derive at write time per
  CONVENTIONS §1 — never re-type this pointer).
- **Coordination:** do NOT touch headplane/headscale (separate lane). Primary checkout owns main.

## 3. Next-session execution order

### 3a. Owner-action chase (reminders, not blockers)
- **NEW — Zipline pre-deploy:** create 1Password items `zipline_password` (Password → `CORE_SECRET`)
  and `zipline_db` (Database → username+password); pick the starting guestbin quota (~100 MB
  suggested; runtime-editable later). `zipline_oidc` is glue-seeded — nothing to do there.
- **NEW — after first Zipline converge:** walk the compose-header deploy gate (local admin
  `/auth/setup` → OIDC login verify → flip bypass-local-login in Server Settings → seed `guestbin`
  user w/ small quota + `dropzone` folder `allowUploads=true`) → anonymous upload→short-URL→viewer
  round-trip logged-out → 6h sweep verify → family drop script (folder id = capability secret →
  1Password) + family-guide entry (`docs/manual/`). Then trim the HD-112 ⏳ tail.
- Carried: **HD-211 rotation batch** (placeholder → real values for `openrouter_api`,
  `cohere_api`, `forgejo_api`; exposure list incl. `opencloud-collab_password` re-login window;
  every PERSISTED Authentik token `expiring=False` + one-time verification of `authentik-api_token`);
  Kopia `/backup` source-wiring decision; LDAP **HD-132** authoring (app passwords vanish at
  expiry — non-expiring bind users); Forgejo `domen/homelab` repo creation (renovate flip);
  Phase 1.5 cutover (dnevna/garage swaps + capsman rsc); HD-57 human legs (bank tokens /
  Enable-Banking app).

### 3b. Remaining engineering queue
- **HD-238** oldsrv→VPS DR runbook for non-GPU services (todo §2.9) — laptop-doable authoring task;
  pairs naturally with the next backup.md touch (which now also carries the HD-112 uploads-
  exclusion row).
- **HD-112 deploy-gate rides the NEXT Phase-1 docker_services converge on vps.yml** — plain
  registry entry; no special ordering beyond authentik-precedence already guaranteed by the list
  (OIDC provider + glue fire automatically). Journal the post-up seeding steps as-run.
- Converge ride-along checks (fold into any upcoming docker_services converge): observe residual ①
  (extras restart guard behavior) + confirm blueprint one-shot task output green in the same run;
  journal both, then trim the ⏳ tails via an append-only R-row.
- Phase-2 backlog note: Zipline `/drop` static glue page (Traefik PathPrefix-priority router,
  same-origin) — only if the owner asks; NOT queued.
- Headplane hardening (separate lane — only if its owning session asks).

## 4. Working rules (binding)

- Fresh worktree per session before ANY edit (`../homelab-wt-<date>-<HHMM>`); merge back only
  committed+green; primary checkout owns main; remove own worktree via `git worktree remove`.
- Converges: 9P gate first, surgical `--tags` preferred — canonical tables in
  [deployment-manual.md](deployment-manual.md)/[docs/deployment-ansible.md] (role+service tags BOTH
  required; traefik dynamic-file changes need the `traefik` tag too). Handlers always carry
  `tags: always` (HD-237 invariant).
- Secrets: 1Password item.field names only — NEVER values anywhere; `>-` block scalar for ALL
  1P-sourced YAML/compose-env renders. Probes print hashes/lengths/prefixes only.
- **Persisted Authentik API tokens: ALWAYS `expiring=False`** (HD-216) — never store a copy of an
  expiring api-intent token; rotated server-side within minutes.
- Journal append-only; owning doc + changelog row(s) in the same change; English prose; relative links.
- Authentik blueprint: pin array attrs (HD-231). Do not touch headplane/headscale unless asked.
