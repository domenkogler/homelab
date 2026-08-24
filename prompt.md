# prompt.md — Deployment Execution Handoff #6 — post-HD-230/231 stabilization; VPS track green, small tail queue

> **Role:** Entry point for the next session. The previous session shipped the **HD-230 wave-2
> corrective batch** (pairdrop PUBLIC dual-host · forgejo native OIDC · blueprint one-shot apply
> convention · onlyoffice unblock · db-backup first dumps ever · nftables scoped flush + ExecStop
> override · renovate disable) and then the **HD-231 hotfix chain** (authentik `grant_types` +
> `property_mappings` wipe → opencloud CSP wiring → external-IdP service set), ending with the
> FIRST successful file.kogler.si browser login (owner-confirmed). A parallel session owns the
> NAS/Phase-1a/Phase-1.5-prep work and is ACTIVE in the primary checkout — see §Coordination.
> **Linked from:** [README.md](README.md) §2 · journal: [deployment-journal.md](deployment-journal.md)
> (entries 2026-08-23/24 Phase 1, HD-227→renumbered HD-230 + HD-231 pt.1–pt.7) · changelog rows
> HD-230/231 in [changelog.md](changelog.md) · todo row HD-230 in [todo.md](todo.md)

---

## 0. Mandatory context (read in this order)

1. [deployment-journal.md](deployment-journal.md) — BOTH 2026-08-23/24 Phase-1 entries (HD-230 batch; HD-231 pt.1–pt.7 hotfix chain incl. root causes & lessons)
2. [CONVENTIONS.md](CONVENTIONS.md) §4 (journal/ledger loop) + §6 (worktree convention)
3. [docs/services-authentik.md](docs/services-authentik.md) — blueprint one-shot-apply convention (MANDATORY for every custom-blueprint edit) + tokens section
4. [docs/deployment-renovate.md](docs/deployment-renovate.md) — why renovate is disabled and what re-enables it

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`,
  `scripts/ak-shell.sh`). NEVER inline commands through wsl.exe.
- ⚠ **9P gate MANDATORY before every playbook run** (HD-212): `git ls-files -z | xargs -0 md5sum --text | md5sum`
  on BOTH sides must be EQUAL. For WORKTREE checkouts the WSL side needs a GIT_DIR translation:
  `GD=$(sed -n "s|^gitdir: ||p" .git | sed "s|^D:/|/mnt/d|"); export GIT_DIR="$GD"` (worktree `.git`
  files carry Windows-style gitdirs WSL git cannot resolve).
- Read-only host probes: temp script files + `ssh -o BatchMode=yes -i ~/.ssh/id_ed25519 ansible-admin@vps.kogler.si` from WSL (canonical runner key); sudo via `sudo -n bash -s`.
- ⚠ **Pipe-masking law** (process note 2026-08-23, violated AGAIN this session via `git rebase | tail`):
  run validators/bare commands, capture `$?` FIRST, never gate decisions through pipes/`&&` chains.

## 2. State snapshot (end of session)

- **main = origin/main**, all work merged & pushed (HD-230 as `857cce1..`; HD-231 pt.1–7 as
  `de7c128..b9a5789..143dd74` + pt.7 `HEAD` push of branch `session-close` → main).
- **Working & verified live:** forgejo native-OIDC login (owner connected accounts) · pairdrop +
  drop PUBLIC 200 (crowdsec-only, isolated) · file.kogler.si FULL login + autoprovisioned user ·
  chat/file/vpn/ai/foto/home/stats/sec/pdf/auto/sso routes healthy · db-backup dumping 4/4 DBs with
  checksums (+10 min after boot, 1440-min interval) · nftables restart survival (scoped flush +
  ExecStop override) · renovate container GONE (disabled until repo exists) · authentik-ldap still
  intentionally crash-looping (HD-132 not yet authored).
- **ID registry:** HD-230 = wave-2 batch (ours) · their parallel session took HD-225–229 + HD-232
  (collision resolved by renumber; next free ID ≥ **HD-233** — VERIFY against changelog at write time).

## 3. Next-session execution order

### 3a. Fresh worktree per §6 before ANY edit (`../homelab-wt-<date>-<HHMM>` from updated main).

### 3b. Open thread — finish verification queue (all read-only unless noted)
1. **file.kogler.si editor round-trip (HD-166 tail):** owner opens a docx in the UI; if ONLYOFFICE
   iframe fails, check `/hosting/discovery` (404 known — ds:example RUNNING but route absent in this
   DS build's nginx set; decide: example-based discovery vs direct app URL per OpenCloud collab docs).
2. **Renovate re-enable** once owner migrates `domen/homelab` to Forgejo (`domen/test` exists already;
   homelab repo does NOT): flip `enabled: true` in group_vars/vps.yml, converge, verify dashboard issue.

### 3c. Owner-action chase (reminders, not blockers)
- HD-211 rotation batch: grafana contactpoint + datasource passwords, kopia-server htpasswd +
  repo password (probe-exposed via `.Args`), `authentik-provision_api` SA token.
- Kopia source wiring decision for the `/backup` volume (agent vs server-managed source).
- LDAP HD-132 authoring session: base DN `DC=home,DC=kogler,DC=si`, bind/search mode, TLS cert,
  UID numbers, decouple `authentik-ldap_bind.password` (shared outpost-token/Samba row in
  deployment-secrets.md). Until then authentik-ldap stays crash-looping BY DESIGN.

### 3d. Small engineering queue
- csp.yaml changes need explicit opencloud restart (bind mount, startup-only parse) → candidate
  deploy-service restart-on-change task.
- Surgical-run tag gotcha: include_tasks is tagged `docker_services`; per-service tags are a union,
  not a filter → add svc tag to the include or accept full-loop runs.
- Blueprint auto-apply layer-2 cause (discovery skips `/blueprints/custom/*`) — offline investigation
  à la HD-216; one-shot apply convention covers it meanwhile.

## 4. Working rules (binding)

- New worktree before edits; merge back only committed+green; primary checkout belongs to the
  PARALLEL session right now — **do not clean/revert their dirty files** (capsman.yml, changelog.md,
  deployment-journal.md, network docs were mid-edit at handoff).
- Stale-index artifact pattern: after ref-level merges, primary may show STAGED old versions of
  files you changed elsewhere — fix with `git checkout HEAD -- <path>` ONLY for YOUR files
  (done this session for ks-oidc.yml + ansible.cfg).
- Converges: 9P gate first (see §1 GIT_DIR variant for worktrees), surgical `--tags` preferred
  BUT note union-tag gotcha (include tagged docker_services ⇒ full fleet walk anyway).
- Secrets: 1Password item.field names only — never values in Git/chat/output.
- Journal append-only; owning doc + changelog row in the same change; English prose; relative links.
