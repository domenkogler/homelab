# prompt.md — Deployment Execution Handoff #7 — HD-233 headplane live at vpn.kogler.si/admin; HD-235 rotation + secret-output-hygiene + YAML-block-scalar conventions landed; merge clean

> **Role:** Entry point for the next session. The previous session shipped **HD-233** (Headplane
> admin UI for Headscale at `vpn.kogler.si/admin` — deployed, live-verified, merged to main) and
> **HD-235** (rotated the shared `headscale_api` OIDC client secret after a transcript leak, and
> codified TWO new conventions: Secret-output hygiene + Secret→YAML block-scalar rendering).
> The VPS edge is green; a tail queue remains (below). TWO parallel sessions are ACTIVE in their own
> worktrees (`homelab-wt-20260824-0958`, `homelab-wt-task4-20260824`) — coordinate, don't collide.
> **Linked from:** [README.md](README.md) §2 · journal: [deployment-journal.md](deployment-journal.md)
> (2026-08-24 Phase 1 entries: HD-233 deploy saga · HD-235 rotation) · changelog rows HD-233 + HD-235
> in [changelog.md](changelog.md) · todo: HD-233 closed (row removed — see §2)

---

## 0. Mandatory context (read in this order)

1. [deployment-journal.md](deployment-journal.md) — the 2026-08-24 Phase-1 entries: **HD-233 deploy
   saga** (three crash-loop bugs: duplicate `_extra_templates` key → dir-vs-file EISDIR; block-scalar
   indentation; wrong 1P field) and **HD-235 rotation** (secret leak → rotate + scrub).
2. [CONVENTIONS.md](CONVENTIONS.md) — §2 NEW rows: **Secret output hygiene** (never a VALUE in
   stdout/chat/git; probes show lengths/IDs/hashes only) + **Secret → YAML rendering** (folded block
   scalar `>-` by default for 1P secrets in YAML configs). §4 (journal/ledger loop) + §6 (worktree).
3. [docs/deployment-secrets.md](docs/deployment-secrets.md) — NEW subsection *"Rendering a secret into
   a YAML config file — block scalar is the default (HD-233 lesson)"* + TOML escaping analog.
4. [docs/services-authentik.md](docs/services-authentik.md) — blueprint one-shot-apply convention
   (MANDATORY for every custom-blueprint edit) + tokens section.
5. [docs/deployment-renovate.md](docs/deployment-renovate.md) — why renovate is disabled + what
   re-enables it.

---

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`,
  `scripts/ak-shell.sh`). NEVER inline commands through wsl.exe.
- ⚠ **9P gate MANDATORY before every playbook run** (HD-212): `git ls-files -z | xargs -0 md5sum --text | md5sum`
  on BOTH sides must be EQUAL. For WORKTREE checkouts the WSL side needs a GIT_DIR translation:
  `GD=$(sed -n "s|^gitdir: ||p" .git | sed "s|^D:/|/mnt/d|"); export GIT_DIR="$GD"` (worktree `.git`
  files carry Windows-style gitdirs WSL git cannot resolve).
- Read-only host probes: temp script files + `ssh -o BatchMode=yes -i ~/.ssh/id_ed25519 ansible-admin@vps.kogler.si` from WSL (canonical runner key); sudo via `sudo -n bash -s`.
- ⚠ **Pipe-masking law** (process note 2026-08-23): run validators/bare commands, capture `$?`
  FIRST, never gate decisions through pipes/`&&` chains.
- ⚠ **Secret-output hygiene (HD-235, NEW):** never print a 1P secret VALUE to stdout/chat/git.
  Probes print **lengths / prefixes / item IDs / hashes** only. `op item get … --reveal` into an
  echo'd shell is how live client_secrets leak (the HD-235 incident). Block scalar `>-` is the default
  for secrets rendered into YAML configs.

---

## 2. State snapshot (end of session)

- **main = origin/main** at `70928e2` (merge `hd233-headplane → main`). All HD-233/235 work merged &
  pushed. The `hd233-headplane` worktree + branch deleted.
- **Working & verified live:** **Headplane at `vpn.kogler.si/admin`** — owner SSO login works,
  `disable_api_key_login: true`, `/admin/` 302, headplane `Up (healthy)`, connected to Headscale
  0.29.3 · `headscale_api` OIDC client_secret **rotated** (HD-235) + crash-log fragments scrubbed ·
  forgejo native-OIDC · pairdrop+drop PUBLIC · file.kogler.si login · all public routes healthy ·
  db-backup 4/4 · nftables restart survival · renovate container still GONE (disabled) ·
  authentik-ldap still crash-looping BY DESIGN (HD-132 not authored).
- **New conventions live:** Secret output hygiene (CONVENTIONS §2/§6 + 1password.md) + Secret→YAML
  block scalar `>-` default (deployment-secrets.md + CONVENTIONS §2/§6 + swept into headscale/
  headplane/recyclarr/prometheus-web-config/traefik-middlewares/tuwunel templates).
- **ID registry:** next free HD = **HD-236** (233= headplane, 235= rotation+hygiene; 234 unused —
  VERIFY against changelog at write time).
- **Coordination:** TWO parallel worktrees active — `homelab-wt-20260824-0958` (branch
  `cleanup-netredo-20260824-0958`) + `homelab-wt-task4-20260824` (branch `task4-cleanup-20260824`).
  Primary checkout is CLEAN right now (owns `main`), but those sessions may dirty it at any time —
  do not clean/revert their files.

---

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
- Forgejo: migrate `domen/homelab` so the Renovate gate can flip.

### 3d. Small engineering queue
- **Headplane hardening candidates (NEW, tracked in network-vpn.md):** `use_pkce: true`;
  consider docker-socket integration (DNS/tailnet editing from UI) with a socket proxy.
- csp.yaml changes need explicit opencloud restart (bind mount, startup-only parse) → candidate
  deploy-service restart-on-change task.
- Surgical-run tag gotcha: include_tasks is tagged `docker_services`; per-service tags are a union,
  not a filter → add svc tag to the include or accept full-loop runs.
- Blueprint auto-apply layer-2 cause (discovery skips `/blueprints/custom/*`) — offline investigation
  à la HD-216; one-shot apply convention covers it meanwhile.

---

## 4. Working rules (binding)

- New worktree before edits; merge back only committed+green; primary checkout may be owned by the
  PARALLEL sessions — **do not clean/revert their dirty files** (capsman.yml, changelog.md,
  deployment-journal.md, network docs were mid-edit at the last handoff).
- Stale-index artifact pattern: after ref-level merges, primary may show STAGED old versions of
  files you changed elsewhere — fix with `git checkout HEAD -- <path>` ONLY for YOUR files.
- Converges: 9P gate first (see §1 GIT_DIR variant for worktrees), surgical `--tags` preferred
  BUT note union-tag gotcha (include tagged docker_services ⇒ full fleet walk anyway).
- Secrets: 1Password item.field names only — **never values in Git/chat/output** (HD-235: probes show
  length/prefix/id/hash; rotate + scrub logs if one leaks; use `>-` block scalar for YAML configs).
- Journal append-only; owning doc + changelog row in the same change; English prose; relative links.
- **If you touch an Authentik OIDC provider or the blueprint:** re-read services-authentik.md
  blueprint section + pin array attrs (grants, property_mappings, redirect_uris) — the HD-231
  array-wipe bug recurs on any upsert that omits them.