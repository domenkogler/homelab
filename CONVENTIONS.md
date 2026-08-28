# Homelab Conventions (Consolidated)

> **Purpose:** one place to *find* every cross-cutting convention in the repo. Each row names the rule and
> points to its authoritative owner — domain-specific detail stays in the owning doc, **this file does not
> duplicate it** (single-SSOT principle). If a rule lives both here and in its owning doc, the owning doc wins;
> update the owning doc and keep this entry to the one-line summary.
>
> **Status:** draft consolidation (2026-08-17) — linked from `README.md` / `docs/index.md` once approved.

---

## 1. Naming

| Convention | Rule | Owning doc |
|-----------|------|-----------|
| DNS namespace | single `kogler.si`, flat subdomains, split-horizon; internal-only hosts unpublished in public DNS | `docs/index.md` (Conventions) |
| Hostnames | canonical list `oldsrv / nas / pi / router / switch / vps` — SSOT table | `docs/index.md` (Conventions, Hosts) |
| Backlog IDs | `HD-<number>` (next free = **max(HD)+1 in [todo.md](todo.md)** — a hand-entered "next free" here went stale within one week; never re-type it), 1 row = 1 outcome, link the owning `docs/*.md` | `todo.md` (§0) |
| Cert issuer | exactly **one** ACME issuer issues the wildcard `*.kogler.si` cert — **the VPS Traefik** (decided HD-178); every other edge (Pi `traefik-ha`, oldsrv internal edge) consumes a **synced cert pair**, never runs its own ACME for this name; the issuer is named in its owning doc and all other docs link to it | [docs/services-traefik.md](docs/services-traefik.md), [docs/services-vps.md](docs/services-vps.md) |
| 1Password items | `<service>_<type>`; `_` only delimiter; `-` allowed inside service; never a field in the name; `field=` mandatory in lookups | [docs/deployment-secrets.md](docs/deployment-secrets.md) (Secret Naming Convention) |
| Vault | one vault `Homelab-ansible`, referenced via `op_vault` var, never a literal | [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Service domains | service → `https://<name>.kogler.si` unless stated (service catalog SSOT) | [docs/services.md](docs/services.md) |
| Service placement | post-HD-135 plane split is a cross-cutting fact: **VPS** = public edge / live-data apps / AI stack / observability backend / GitOps · **oldsrv** = GPU / LAN / storage-bound core · **nas** = ZFS storage (no Docker) · **pi** = HA primary + DNS secondary. A service's plane + exposure is stated in its catalog row, never implied | [docs/services.md](docs/services.md), [docs/services-vps.md](docs/services-vps.md) |

## 2. Values & SSOT (never hardcode)

| Convention | Rule | Owning doc |
|-----------|------|-----------|
| IPs / CIDRs | never hardcode — `network_static_hosts` / `network_ranges` from `group_vars/*` | [docs/deployment-ansible.md](docs/deployment-ansible.md) (Variables & IPs) |
| IP doc | `docs/network-addresses-generated.md` is the SSOT — generated (see Generated docs), **never hand-edit** | [scripts/check_doc_ips.py](scripts/check_doc_ips.py), [docs/deployment-ansible.md](docs/deployment-ansible.md) |
| Service list | `group_vars/<host>.yml` is the deploy loop SSOT; catalog row in `docs/services.md` | [docs/services.md](docs/services.md) |
| Compose path | `/opt/<service>/docker-compose.yml` — architectural constant | [docs/deployment-compose.md](docs/deployment-compose.md) |
| Generated docs | a generated doc is recognized by its `-generated` filename suffix and is **never hand-edited** — canonical rule: §8.2 | [docs/index.md](docs/index.md), §8.2 |
| Counts | doc-stated **counts** (templates, roles, files, services) are **derived, never hand-entered** — quote the validator/dir as the source (`scripts/validate-docker-services.py`, `roles/`, `docker_services/`); a stale number in prose is a defect, not a cosmetic | [docs/index.md](docs/index.md) (Validation), [scripts/validate-all.sh](scripts/validate-all.sh) |
| Pointers / lists | the Counts rule extends to **pointers and enumerated lists**: next-free backlog IDs, 1Password item counts, public-DNS record sets, VLAN maps, AllowedIPs scopes — quote the source ("see todo.md", "see `roles/cloudflare_dns/vars/main.yml`") or render them; re-typed copies drift silently (audit round 2, HD-175/177 — four divergent public-record lists, triple VLAN map) | [docs/index.md](docs/index.md), owning docs |
| Data location | a storage/media **data-location change** (e.g. MinIO retired → live Box CIFS) must update IaC **and** the owning service/storage docs **in the same change** — a data-location claim in prose that contradicts the IaC is a review failure | [docs/services.md](docs/services.md), [docs/storage.md](docs/storage.md), [docs/deployment-compose.md](docs/deployment-compose.md) |
| Secret creation path | every vault item is ONE of: **catalog-generated** (random value — add to `provision-secrets.py` CATALOG, seed via `provision-vault.sh`) · **manual-value** (external source — create in 1P by hand; add catalog/docs row) · **glue-seeded** (`*_oidc` Authentik clients — NEVER hand-create; the egress glue owns them) · **externally-coupled** (rotation breaks live state → `NOT_AUTO_ROTATABLE` with reason) | [docs/deployment-secrets.md](docs/deployment-secrets.md) (Creation & Rotation Workflow), [scripts/provision-secrets.py](scripts/provision-secrets.py) |
| Seed before converge | vault items MUST exist **before** the playbook renders their consumer — 1Password lookups fail loud mid-run; run `check-vault-items.sh` before any deploy and seed gaps first | [scripts/check-vault-items.sh](scripts/check-vault-items.sh), [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Rotation propagation | rotating a vault item reaches live services ONLY via an IaC re-render/converge or an explicit sync task (`db_role_sync`/`db_ro_sync` precedent); if neither exists, the item goes in `NOT_AUTO_ROTATABLE` with a stated reason — no un-managed rotation paths | [docs/deployment-ansible.md](docs/deployment-ansible.md), [scripts/provision-secrets.py](scripts/provision-secrets.py) |
| Item-reference coverage | EVERY group_vars key class that references a vault item must be visible to `check-vault-items.sh` (template lookups AND registry keys like `db_item`/`db_ro_item`) — a new key class lands together with its scanner support in the same change (HD-244 lesson) | [scripts/check-vault-items.sh](scripts/check-vault-items.sh), [deployment-tasks.md](deployment-tasks.md) |

---

## 3. Code / IaC conventions

| Area | Rules | Owning doc |
|------|-------|-----------|
| Ansible roles | 1 entry point (`tasks/main.yml` → `include_tasks:`); assert admin user top; idempotent by default; tag every loop item | [docs/deployment-ansible.md](docs/deployment-ansible.md) (IaC Authoring Conventions) |
| Ansible vars | service/arch values → `group_vars/`, not role defaults | [docs/deployment-ansible.md](docs/deployment-ansible.md) |
| Ansible secrets | `lookup('community.general.onepassword', …, field=…)` only, `op_vault`, no literals | [docs/deployment-ansible.md](docs/deployment-ansible.md), [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Secret output hygiene | **never write a secret VALUE to stdout / chat / git / transcripts** — `op item get` / `ak shell` probes that print a value must print only **lengths, prefixes, item IDs, or hashes**; never run a bare `op item get … --reveal` into a shell that echoes to a session log. Rotation of a shared Authentik client = regenerate in Authentik, persist to the 1P item, re-render consuming services (headscale + headplane), verify | [docs/1password.md](docs/1password.md), [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Secret → YAML rendering | a secret VALUE rendered into a YAML/TOML config file must use the **folded block scalar `>-`** (never inline `"{{ … }}"`) — 1P secrets can contain `:` `"` `'` `@` etc. which break quoted scalars and crash-loop the app (HD-233 live incident: rotated `headscale_api` broke headscale+headplane). Rendered **compose files are still YAML** (`docker compose` parses them at deploy): 1P-sourced compose `env:` values use `>-` too (HD-166); plain non-secret env strings stay quoted. | [docs/deployment-secrets.md](docs/deployment-secrets.md) (Rendering a secret into a YAML config file) |
| Compose location | one dir per service under `templates/docker_services/<service>/` | [docs/deployment-compose.md](docs/deployment-compose.md) (File Location) |
| Compose networks | `external: true` (traefik-public, services-internal, db-internal) created by the role | [docs/deployment-compose.md](docs/deployment-compose.md) (Network Assignment) |
| Compose security | `cap_drop: ALL` + minimal `cap_add`, `read_only`, `tmpfs`; no host ports unless justified; internal services need auth tokens (`<service>-internal_api`) | [docs/deployment-compose.md](docs/deployment-compose.md) (Container Security), [docs/security.md](docs/security.md) (Flaw C/D) |
| Compose versioning | pinned tags (never bare `latest`) + Renovate trail | [docs/deployment-compose.md](docs/deployment-compose.md), [renovate.json](renovate.json) |
| RouterOS | management services bound to Management VLAN; bootstrap `.rsc` + Ansible role both enforce | [docs/network-ops.md](docs/network-ops.md) |
| Two-sided deploy gate | a service/component whose IaC is done **but not live** is ⏳ deploy-gated in `todo.md` **and** its owning doc must carry the same visible status block (**🔴 planned / 🟢 IaC done ⏳ / ✅ live**) — a design-spec doc for a not-live service must say "not yet live — ⏳ deploy-gated", never read as deployed | [todo.md](todo.md) (§0/§3c), [docs/security.md](docs/security.md) (Deploy-gated rows), each owning service doc |

---

## 4. Lifecycle conventions

| Phase | Rule | Owning doc |
|-------|------|-----------|
| Backlog | new work = new `HD-XX` row in `todo.md`; decisions written to owning doc; done → `changelog.md` | [todo.md](todo.md), [docs/index.md](docs/index.md) |
| Post-task housekeeping | **after each completed task, update `todo.md` in the same change** — ONE pattern, two states, no third option: (a) **task fully closed** (nothing left to do) → DELETE the row from `todo.md` in the closing change; the appended `changelog.md` row becomes the only record — a `✅ Done` row with no `⏳` tail must never remain in `todo.md` (2026-08-21: the audit fanout left both patterns; swept + rule made explicit). (b) **IaC done but deploy-gated** → KEEP the row (trim its tail to only the pending `⏳` items) AND append the `Done` row to `changelog.md` — both records exist; the todo row is deleted when the live verify later closes it. **No hand-maintained tally/Status line** — the backlog count is derived from the rows themselves (counts are derived, never hand-entered, §2) | [todo.md](todo.md) (§0 lifecycle), [changelog.md](changelog.md) |
| Decisions | decisions log, date-stamped, closed once per decision (mirror `docs/security.md §7` style); **a resolved decision is written ONCE to `changelog.md` (decision-log SSOT) — do NOT leave a struck duplicate row with the full rationale in `todo.md` §1**; the closing change also **sweeps stale mentions of the superseded thing in other docs** (TileBoard/AnythingLLM/watchtower precedents — a decision that leaves old text standing elsewhere is not closed) | [docs/security.md](docs/security.md) (§7 Decision log), [changelog.md](changelog.md) |
| Onboarding a service | see the 10-step checklist below | — |
| Validation gate | `bash scripts/validate-all.sh` before commit (compose, templates, IPs, docs). **Planned extension (HD-157):** also lint the `docs/index.md` doc-map vs `find docs -name "*.md"` and any doc-claimed role/template count — a docs-claim that drifts is a lint failure, not a cosmetic | [scripts/README.md](scripts/README.md), [docs/index.md](docs/index.md) (Validation) |
| Deploy | first apply human-gated (dry-run → single host); single path = Ansible (Renovate PR → Forgejo Actions deploy button → Ansible) | [docs/deployment.md](docs/deployment.md) |
| Deployment ledger & journal | deploy progress + execution record live in exactly two places (owning docs stay desired-state SSOT — no progress markers, no logs there): (a) **ledger** = `[deployment-tasks.md](deployment-tasks.md)` checkboxes (`- [x]` + date when done; human-only steps prefixed `**[MANUAL]**`) — the plan and what's next; (b) **journal** = `[deployment-journal.md](deployment-journal.md)`, append-only as-built record of every manual action: exact commands run, settings chosen, values captured, verification evidence, deviations (secret VALUES never — item+field names only). (c) **runbook** = `[deployment-manual.md](deployment-manual.md)` — imperative phase-by-phase redeploy procedure (true zero → live): commands, panel settings, per-step evidence; the procedure SSOT carries no progress markers and no execution history. A permanent divergence discovered during execution updates the owning doc/runbook in the same change; the journal entry notes `doc updated: <file>`. **Human feed:** raw notes go into the DATA block of the standing `[prompt-journal.md](prompt-journal.md)` handoff; the AI converts them to entries (validate + commit + clear the feed) | [deployment-tasks.md](deployment-tasks.md), [deployment-journal.md](deployment-journal.md), [prompt-journal.md](prompt-journal.md) |
| Deploy-gated rows | an `HD-XX` row whose IaC is done **but not yet live** stays **open** with a **`⏳ Deploy-gated:`** tail listing the exact pending live steps (provider creation, secret seeding, firewall open, live-verify). It closes only after a live deploy/verify pass — **not** at IaC-completion. A task's ⏳ is a *phase*, never moved to a separate file. Its `Done` record still goes to `changelog.md` at IaC-completion (Post-task housekeeping (b)) | [todo.md](todo.md) (§0 lifecycle, §⏳ checklist), [changelog.md](changelog.md) |
| Session close-out | **Before ending a working session, walk this checklist in order and answer each point explicitly in the final response:** (1) **Any open questions?** (2) **Is all knowledge in the owning docs?** — journal entry written, changelog rows added, todo tails updated, decisions in their specs; (3) **Is `prompt.md` updated** to the new handoff state (next session must be able to start from it alone)? (4) **Is `deployment-manual.md` updated** — every non-Ansible step performed that a future FROM-SCRATCH deployment would need again is written into the runbook as imperative procedure (the journal records history; the manual is where repeatable procedure lives). **If a session performed NO manual/non-Ansible steps (everything automated via IaC/playbook), `deployment-manual.md` stays UNTOUCHED** — diagnostics, root-cause prose, and system mechanics belong in the owning doc + journal, never in the runbook (revert-if-added: runbook is imperative procedure only — commands/settings/evidence, no narrative). (5) **Handoff diff-rule** — the new `prompt.md` handoff is produced by EDITING the previous one, never rewritten from scratch; every prior §2/§3 open item appears or is explicitly resolved (HD-253 lesson: the #17 rewrite silently dropped open items). (6) **Derived-values ban** — computable pointers (next-free HD = max(HD)+1 in todo.md, item counts, record sets) are never typed into prose; quote/re-derive the source instead (§1/§2 reinforcement). (7) **Branch-per-session checkbox** — confirm the session ran on its own `session/<slug>` branch inside its own worktree (never directly on main), merged back green. Only then cleanup: merge the session branch back to main (**green results only**), remove/prune the session worktree, push. | [deployment-manual.md](deployment-manual.md), [prompt.md](prompt.md), [deployment-journal.md](deployment-journal.md) |
| Audit reports | root-level audit / prompt-deliverable reports are **ephemeral**: each actionable finding is folded into its owning doc + an HD row (or explicitly rejected), then the report is deleted in the change that closes its last finding — reports are context, never SSOT (HD-153 precedent; the 2026-08-21 round-2 reports fold per this rule) | [changelog.md](changelog.md) (HD-153), repo root |

> **Decision log format** (`security.md §7`): a dated bullet per decision: `- **Decision statement** — accepted/expected, Date: YYYY-MM-DD, *(evidence: KOPS-xx)*`.

---

## 5. Service-onboarding checklist (10 steps)

A new service must clear this path (each step's owning doc is the anchor; violations are review failures):

1. **Exposure & auth decision** — public / internal / Headscale-only; Forward-Auth vs native OIDC. Write it in the owning service doc.
   - **Native OIDC → Authentik:** declare the provider/application in the **Blueprint** (`ks-oidc.yml`),
     and let the **secret-egress glue** seed its `…_api` item. **Do not** hand-create OIDC providers in
     the Authentik UI. (Forward-Auth services need no provider at all.) [services-authentik.md](docs/services-authentik.md)
2. **Secrets** — create 1Password item(s) `<service>_<type>`; add a catalog row in `docs/deployment-secrets.md` (master list).
3. **Compose template** — `docker_services/<service>/` per `docs/deployment-compose.md` (external networks, pinned tags, no host ports unless justified, `cap_drop: ALL`).
4. **Registry** — add to `group_vars/home_servers.yml` + catalog row in `docs/services.md`.
5. **Edge (if exposed)** — Traefik route + middleware chain (`crowdsec-only`, Forward-Auth) per `docs/services-traefik.md`.
6. **State & backups** — map volumes/data into `db-backup` / Kopia scope.
6.5. **Storage / data location** — state where the service's big data lives (NAS ZFS dataset / VPS NVMe / live Box CIFS / WebDAV / S3) **in the owning doc**, consistent with the storage SSOT (`storage.md`). If a storage decision changes, update IaC + owning doc **in the same change** (data-location rule §2).
7. **Observability** — exporter / scrape target + Grafana dashboard if it's on a watchlist.
8. **Validation** — `bash scripts/validate-all.sh` green (template + group_vars both).
9. **Deploy gate** — first apply is human-gated (dry-run → single host) — no blind `docker compose up -d`.
10. **Docs** — `docs/index.md` map row + family guide (`docs/manual/`) if family-facing.

**Stage tracking:** service-onboarding rows in `todo.md` carry **`Stage: N/10`** in the bold title = current checklist step above. `10/10` = deployed + verified — a row only closes at step 10 (never at step 8 validation / step 9 deploy-gate). The checklist is the ledger in the owning service doc; `Stage: N/10` is a summary pointer, not a second ledger. Non-service tasks (network / IaC fixes / decisions) are not checklist candidates and carry no stage marker.

---

## 6. Cross-cutting rules (short list)

- Language: English (technical), Slovenian (family/manual). Slovenian also covers the family-facing root guide `readme-humans.md`.
- Decision dates are ISO `YYYY-MM-DD`; when touching a dated prose entry, fix year typos in the same change (2025→2026 sweep pending in five docs; changelog rows stay append-only).
- Headers: every doc starts with `> **Role:**` and `> **Linked from:**` — enforced by convention.
- Relative links only — markdown relatives to `docs/*.md`.
- Secrets never in docs — 1Password `Homelab-ansible` vault only.
- **Never print a secret VALUE to stdout / chat / git / transcripts** — probes show **lengths / prefixes / item IDs / hashes** only (rotation + readback precedents, HD-233/HD-234).
- **Secret → YAML config = block scalar `>-` by default** (never inline-quote a 1P secret into a
  YAML/TOML file the app parses) — HD-233 live lesson; see `deployment-secrets.md` Rendering section.
- Generated files use the **`-generated` filename suffix** and are rendered, never hand-edited (§8.2). The legacy **★** marker in `docs/index.md` is a display aid only, **not** the convention.
- **Don't chase cosmetic tweaks** during planning phase (ASCII alignment, spacing); substantive, consistent edits only.
- **Git worktrees (owning rule — CONVENTIONS is SSOT):** **every** session creates its own fresh
  worktree named `../homelab-wt-<date>-<HHMM>` **before touching any file** — single-session work
  included; isolation is the default, not a parallel-sessions special case. Date AND time in the
  name means two sessions started the same day can never collide; apply and validate edits in the
  worktree, merge back only committed, green results, primary checkout untouched.
  **Discipline:** manage ONLY your own session's worktree, always via `git worktree add` /
  `git worktree remove` — never `rm`/move/rename any worktree directory; on `path already exists`,
  abort and pick a new name instead of cleaning up (2026-08-23 incident: an `rm -rf` aimed at a
  colliding path hit another live session's worktree — survived only because a file lock stopped
  it).
  **Mechanical enforcement (HD-253):** this rule is ENFORCED, not prose-only — `scripts/guard-session.sh`
  (pre-edit guard) refuses ANY edit-context while the **primary** checkout (`git-dir == git-common-dir`)
  sits on `main`, and `validate-all.sh` hard-fails when run from primary+main+DIRTY (committing
  primary-resident edits = the violation); a clean-main merge-station validation stays exempt, session
  worktrees and detached-HEAD/CI pass through. Every refusal prints the exact remediation command with a
  live timestamp (`git worktree add ../homelab-wt-YYYYMMDD-HHMM`). **Primary definition:** the primary
  checkout is a **merge station only** — all edits happen on a session branch inside a session worktree;
  main receives only fast-forward merges of committed, green results.
- **Commit signing (HD-265/270):** every commit is signed (`commit.gpgsign=true`, `gpg.format=ssh`,
  `user.signingkey` = the GitHub-sign key from the `Private` vault, served via the SSH agent). A fresh
  shell that reports `Couldn't find key in agent` → load the keys once: `ssh-add ~/.ssh/github_signing
  ~/.ssh/github_auth` (they persist after `git-bootstrap.sh --ssh-auth`). Verify a commit is signed
  with `git log -1 --format='%G?'` (G = good). Only when re-reading the `Private` vault is needed (new
  key pull) does a human `op` sign-in apply. See `scripts/README.md` git-bootstrap row + HD-270 doc.
- **Collapsible `<details>` sections:** human/family-facing browser-rendered docs only (`readme-humans.md`, `docs/manual/*`) and only for optional asides (troubleshooting, FAQ) — **never** in agent-facing docs (owning specs, runbooks incl. `deployment-manual.md`, ledger/journal, todo/changelog): the primary readers are AI agents working on raw text, where folds hurt grep-ability and add noise. Blank lines between the HTML tags and the inner Markdown are mandatory, else fences/tables render as raw text. Precedent: `readme-humans.md` §Za družino troubleshooting fold.

---

## 7. Version-pin hygiene

| Rule | Owning doc |
|------|-----------|
| a `*_version` pin lives in **one** file — `group_vars/all/versions.yml` (HD-156, live 2026-08-19) — **not** spread across `all.yml`; Renovate docker datasource + version review are single-sheet | [docs/deployment-compose.md](docs/deployment-compose.md), [docs/deployment-renovate.md](docs/deployment-renovate.md) |
| a pin is **never bare `latest`** and never a *mutable alias* (`-rocm`, `main-stable`) **unless** the owning doc records an explicit MUST-pin + verified-semver precondition (Tuwunel / OpenClaw / LiteLLM fluid-tag precedents, HD-121/134) | [docs/deployment-compose.md](docs/deployment-compose.md) |
| on a fluid-tag *first* pin, show the registry-verified tag + Renovate tracking **in the same change** | [docs/deployment-compose.md](docs/deployment-compose.md), [docs/deployment-renovate.md](docs/deployment-renovate.md) |
| a `*_version` var carries **no `default()` fallback in templates** — a missing pin aborts the render (fail-loud, same as secrets, HD-65); mutable aliases (`stable`, `release`, `-rocm`) are bare-`latest` equivalents under the same MUST-pin precondition | [docs/deployment-compose.md](docs/deployment-compose.md), HD-121 precedent |

> Strengthens the §3 "Compose versioning" row (pinned tags, never bare `latest` + Renovate trail) — same owner, more explicit.

---

## 8. Docs taxonomy & service triage

> **Purpose:** a repeatable rule for *where a piece of documentation or a service candidate lives*.
> **Two independent axes** (a doc is classified on BOTH):
>  - **Domain (placement)** — which stack / host target the doc's services belong to → `domain:` frontmatter.
>  - **Ownership (cross-cutting)** — who owns the doc's *content*: a single module, or the whole homelab →
>    `cross_cutting: true`.
> These are NOT opposites. A doc is usually a domain AND (optionally) cross-cutting. Deciding one says
> nothing about the other.
> Adopted 2026-08-20 (docs-refactor). The goal is a consistent mental model + URL scheme, not achieved
> purity: both placements and cross-cutting docs have explicit homes and markers (never ambiguous).

### 8.1 Domains & stack index (placement axis)
- **Domain** = a deployable stack: the set of services (plus their docs) that deploy together under one
  owning `domain:` value. A domain has a **primary owning host / host-class** (e.g. `smart-home` →
  Pi/oldsrv, `network` → router/switch, `observability` → VPS backend). Frontmatter: `domain: <stack>`
  + a document `role:`.
- **`role:` values** (the doc's *shape*, not a placement statement): `index` (domain hub linking sub-docs),
  `broad` (overview), `ssot` (single source of truth for a concern), `detail` (a sub-topic), `reference`,
  `design-spec`, `runbook`, `research`, `cross-cutting`. A domain hub is `role: index` (or `broad`).
- **Domain index** links to `<domain>-<sub>.md` detail docs. Canonical pattern: `smart-home.md` →
  `smart-home-{voice,audio,failover}.md`. **Stack / sub-domain docs** group a big domain's catalog into
  `services-<x>.md` — e.g. `services-matrix.md`, and `services-office.md` as the office-workload slice of the
  services stack. All share the owning `domain:` (e.g. `services`).
- **Umbrella domain** — a domain need not have a single service host to be a domain; it may be an
  *ops umbrella* whose children are cross-cutting concerns. Precedent: **`deployment`** — deployment.md
  is the hub; its Document Map/Related seed the cross-cutting children `security.md`, `backup.md`,
  `storage.md` (all `domain: deployment`, `cross_cutting: true`). An umbrella hub is still
  `role: index|broad`; each child keeps `cross_cutting: true` + its own `role:` (detail/ssot).
- **Central service stack index** = `docs/services.md` (catalog + networks + domains). It is the *only*
  pointer from `docs/index.md` for service layout.
- **No doc is both** an index and a dumping ground: when a domain doc grows past ~1 screen of catalog
  table, split the table into a `services-<x>.md` stack doc and link it from the index.

### 8.2 Generated docs — the `-generated` suffix
- **Any file produced by a script/Ansible (not hand-authored) carries a `-generated` suffix** in its
  base name: `<name>-generated.md` (e.g. `network-addresses-generated.md`,
  `services-inventory-generated.md`, `subscriptions-table-generated.md`, `network-rack-generated.md`).
  The suffix appears **in the filename**, never only in a header, so file lists and `git grep` make
  generated sources obvious. Headers still say "do not hand-edit"; the filename is the guarantee, the
  header the hint.
- **Canonical managed-header:** every generated doc opens with `# Ansible managed` — **exactly Ansible's built-in `ansible_managed` default**, so a real Ansible render and the pure-Python `scripts/render_all.py` umbrella stay byte-identical. Do not personalize it (the old `# Ansible managed: file edited by Ansible` and `# auto-gen` variants are retired). HD-163.
- **Renaming a generated file = touching the renderer + every reference** in the same change: the
  render helper itself (`scripts/render_*.py`, `IaC/ansible/playbooks/render-docs.yml`, the
  `docker_services` role), the validators that whitelist/tokenize the name
  (`scripts/check_doc_ips.py`), and the doc map in `docs/index.md`. The doc-map linter
  (`scripts/check_doc_map.py`) fails closed, so a stale reference breaks `validate-all.sh`.

### 8.3 Service triage: `<domain>-review` / `<domain>-rejected` (per-domain)
- **`<domain>-review.md`** = *intake queue* for services heard of but not yet researched. Kept
  **near-empty**: it is a queue, not a backlog. One row = service name + URL + a 3-word "why". Low
  friction is deliberate — a short phrase is enough, a paragraph needs its own `brainstorming/` file.
- **Lifecycle** (checked in this order):
  1. **Before adding** to `-review`, check `<domain>-rejected.md` first (convention: rejected is
     consulted, not auto-blocking). A re-review is allowed **only with an exception note** —
     "re-evaluating Y because X changed".
  2. **Promote** (→ research/backlog): move the row to `todo.md` as an HD-XXX (pointer back to the
     review file), then **delete** it from `-review`. `-review` has no "accepted" state.
  3. **Stale**: if a `-review` entry is untouched for **30 days**, it must be promoted to `todo.md` or
     moved to `-rejected`. (Deliberate anti-`todo.md` guard: review must not become a second backlog.)
- **`<domain>-rejected.md`** = *decision log*. **Append-only** — never edit or reorder an entry, only
  add. Sorted by **service name** (stable key for `git grep` / `git log -S`). Each entry:
  `| <service> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`. When a
  decision changes, the old entry is left unchanged and a new one is appended (do **not** strike the
  old one — mirror the decision-log style in `changelog.md`).
- The **services** domain seeds the pattern: `docs/services-review.md` +
  `docs/services-rejected.md`. Other big domains (network, hardware, smart-home) opt in with their own
  `<domain>-{review,rejected}.md` when they have enough volume.

### 8.4 Cross-cutting docs (ownership axis)
- **Cross-cutting** = the doc's *content* is **owned by no single host/module** — a policy or
  architecture fact spanning the whole homelab (e.g. `security.md`, `backup.md`, `storage.md`,
  `interfaces.md`, `services-office.md`).
- Mark them: frontmatter `cross_cutting: true` + a `**Role:** … (cross-cutting)` header so the taxonomy
  analyzer does not re-litigate them.
- **Orthogonal to `domain:`** — a cross-cutting doc still carries a `domain:` tag, and that tag is its
  *topical home*. Under Option A (the **deployment umbrella**), cross-cutting protection docs are
  tagged `domain: deployment` *and* genuinely seeded from `deployment.md` (added to its Document Map
  / Related). Examples (all `cross_cutting: true`):
  - `security.md` → `domain: deployment` + cross-cutting — hardening policy spans every host.
  - `backup.md` → `domain: deployment` + cross-cutting — spans nas/oldsrv/VPS + cloud Boxes.
  - `storage.md` → `domain: deployment` + cross-cutting — ZFS spans nas (tank/bulk) + oldsrv (nvme).
  - `services-office.md` → `domain: services` + cross-cutting — the office slice; touches oldsrv GPU/VPS/desktop.
  - `interfaces.md` → `domain: services` + cross-cutting — dashboards/management span every host; no single
    deployable home (kept intent-based name, unprefixed).
- **Filenames: prefixed = stack, unprefixed = concern.** A `services-<x>.md` / `<domain>-<x>.md` filename
  signals a *deployable stack* sub-doc. A **strongly cross-cutting** doc keeps an **intent-based unprefixed name**
  (`security.md`, `backup.md`, `storage.md`) — its home lives in frontmatter (`domain: deployment`
  + `cross_cutting: true`), never in a `deployment-` prefix (that prefix is reserved for the deploy toolchain:
  preseed/ansible/compose/secrets/renovate). So: rename a doc to a `services-*` stack *only* when it is a
  real deployable stack slice (e.g. `llm-office.md` → `services-office.md`); do NOT prefix a cross-cutting
  policy doc with its domain.
- **Not all big-stack docs are cross-cutting.** A doc whose services deploy as a **cohesive set with a
  primary home on one host** is a *clean domain* (`cross_cutting: false`). Precedent: `observability.md`
  (Prometheus/Loki/Grafana/n8n backend on the **VPS**; Alloy/nut_exporter/HA-exporters fan out) —
  `domain: observability`, no cross-cutting marker.
- The *decision of what to do with a cross-cutting doc* is a per-task concern, not a standing rule:
  it is a candidate review point whenever a domain doc it overlaps is edited.

### 8.5 SSOT & rendering direction (scripts must not read generated MD)
- **Source of truth for values = IaC** (`group_vars/*.yml`, `host_vars/*.yml`,
  `rack-connections.json`).
- **Scripts consume the SSOT, never a generated `.md`.** Generated markdown is a *render view for
  humans only*; no script parses values out of a generated doc.
- **Drift detection = re-render and `git diff --exit-code`**, NOT a filename allow-list in a linter. If
  a generated file is out of sync with its SSOT, that is a **build failure**, not a docs note.
- Rendering direction is always **IaC → generated MD** (single hand-editing path):
  `group_vars/*.yml` / `rack-connections.json` → `render-docs.yml` / `scripts/render_*.py` →
  `*-generated.md`.

---

*Last review: **2026-08-21** (HD-178–180 decisions recorded; added: single-cert-issuer §1, derived-pointers/lists §2, mention-sweep + audit-report-lifecycle §4, ISO-date hygiene §6, pin-no-default §7; §1 backlog-ID pointer de-hardcoded; **post-task housekeeping §4 made single-pattern** — fully-done rows deleted from todo, deploy-gated rows stay trimmed + changelog Done record — after the audit fanout left both patterns). Owning docs above remain authoritative.*

*Prior review: 2026-08-20 (added: derived-counts, data-location same-change, two-sided deploy gate; placement §1, onboarding storage bullet §5, version-pin hygiene §7, validation-gate extension §4; §8 docs taxonomy & service triage 2026-08-20, refined to a **two-axis model** (domain ≁ placement + cross_cutting ≁ ownership) with observability as the clean-domain precedent and llm-office as a services/office slice; **deployment as the ops-umbrella** seeding cross-cutting security/backup/storage + interfaces (Option A); **filename rule** — prefixed = stack, unprefixed = concern).*