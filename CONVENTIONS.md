# Homelab Conventions (Consolidated)

> **Purpose:** one place to *find* every cross-cutting convention in the repo. Each row names the rule and
> points to its authoritative owner — domain-specific detail stays in the owning doc, **this file does not
> duplicate it** (single-SSOT principle). If a rule lives both here and in its owning doc, the owning doc wins;
> update the owning doc and keep this entry to the one-line summary.
>
> **Status:** in force — linked from `README.md` and `docs/index.md`; the rules here are binding.

---

## 1. Naming

| Convention | Rule | Owning doc |
|-----------|------|-----------|
| DNS namespace | single `kogler.si`, flat subdomains, split-horizon; internal-only hosts unpublished in public DNS | `docs/index.md` (Conventions) |
| Hostnames | canonical list `oldsrv / nas / pi / router / switch / vps` — SSOT table | `docs/index.md` (Conventions, Hosts) |
| Backlog IDs | `HD-<number>` (next free = **max(HD)+1 in [todo.md](todo.md)** — a hand-entered "next free" here went stale within one week; never re-type it), 1 row = 1 outcome, link the owning `docs/*.md`. **The `9000–9999` block is reserved for tool-fixture tokens, never for a row** — a classifier has to mint ids that look real, and the wide mint scan reads those tokens as evidence, so the exclusion is a range (`RESERVED_RANGES` in `scripts/next-hd.sh`), not a list of ids; both directions are held by `scripts/gate/check_hd_mint_space.py` | `todo.md` (§0) |
| Cert issuer | exactly **one** ACME issuer issues the wildcard `*.kogler.si` cert — **the VPS Traefik**; every other edge (Pi `traefik-ha`, oldsrv internal edge) consumes a **synced cert pair**, never runs its own ACME for this name; the issuer is named in its owning doc and all other docs link to it | [docs/services-traefik.md](docs/services-traefik.md), [docs/services-vps.md](docs/services-vps.md) |
| 1Password items | `<service>_<type>`; `_` only delimiter; `-` allowed inside service; never a field in the name; `field=` mandatory in lookups | [docs/deployment-secrets.md](docs/deployment-secrets.md) (Secret Naming Convention) |
| Vault | one vault `Homelab-ansible`, referenced via `op_vault` var, never a literal | [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Service domains | service → `https://<name>.kogler.si` unless stated (service catalog SSOT) | [docs/services.md](docs/services.md) |
| Service placement | the plane split is a cross-cutting fact: **VPS** = public edge / live-data apps / AI stack / observability backend / GitOps · **oldsrv** = GPU / LAN / storage-bound core · **nas** = ZFS storage (no Docker) · **pi** = HA primary + DNS secondary. A service's plane + exposure is stated in its catalog row, never implied | [docs/services.md](docs/services.md), [docs/services-vps.md](docs/services-vps.md) |

## 2. Values & SSOT (never hardcode)

| Convention | Rule | Owning doc |
|-----------|------|-----------|
| IPs / CIDRs | never hardcode — `network_static_hosts` / `network_ranges` from `group_vars/*` | [docs/deployment-ansible.md](docs/deployment-ansible.md) (Variables & IPs) |
| IP doc | `docs/network-addresses-generated.md` is the SSOT — generated (see Generated docs), **never hand-edit** | [scripts/gate/check_doc_ips.py](scripts/gate/check_doc_ips.py), [docs/deployment-ansible.md](docs/deployment-ansible.md) |
| Service list | `group_vars/<host>.yml` is the deploy loop SSOT; catalog row in `docs/services.md` | [docs/services.md](docs/services.md) |
| Compose path | `/opt/<service>/docker-compose.yml` — architectural constant | [docs/deployment-compose.md](docs/deployment-compose.md) |
| Generated docs | a generated doc is recognized by its `-generated` filename suffix and is **never hand-edited** — canonical rule: §8.2 | [docs/index.md](docs/index.md), §8.2 |
| Counts | doc-stated **counts** (templates, roles, files, services) are **derived, never hand-entered** — quote the validator/dir as the source (`scripts/gate/validate-docker-services.py`, `roles/`, `docker_services/`); a stale number in prose is a defect, not a cosmetic | [docs/index.md](docs/index.md) (Validation), [scripts/validate-all.sh](scripts/validate-all.sh) |
| Pointers / lists | the Counts rule extends to **pointers and enumerated lists**: next-free backlog IDs, 1Password item counts, public-DNS record sets, VLAN maps, AllowedIPs scopes — quote the source ("see todo.md", "see `roles/cloudflare_dns/vars/main.yml`") or render them; re-typed copies drift silently — this tree has carried four divergent public-record lists and a triple VLAN map at once | [docs/index.md](docs/index.md), owning docs |
| Data location | a storage/media **data-location change** (e.g. MinIO retired → live Box CIFS) must update IaC **and** the owning service/storage docs **in the same change** — a data-location claim in prose that contradicts the IaC is a review failure | [docs/services.md](docs/services.md), [docs/storage.md](docs/storage.md), [docs/deployment-compose.md](docs/deployment-compose.md) |
| Secret creation path | every vault item is ONE of: **catalog-generated** (random value — add to `provision-secrets.py` CATALOG, seed via `provision-vault.sh`) · **manual-value** (external source — create in 1P by hand; add catalog/docs row) · **glue-seeded** (`*_oidc` Authentik clients — NEVER hand-create; the egress glue owns them) · **externally-coupled** (rotation breaks live state → `NOT_AUTO_ROTATABLE` with reason) | [docs/deployment-secrets.md](docs/deployment-secrets.md) (Creation & Rotation Workflow), [scripts/secrets/provision-secrets.py](scripts/secrets/provision-secrets.py) |
| Seed before converge | vault items MUST exist **before** the playbook renders their consumer — 1Password lookups fail loud mid-run; run `check-vault-items.sh` before any deploy and seed gaps first | [scripts/gate/check-vault-items.sh](scripts/gate/check-vault-items.sh), [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Rotation propagation | rotating a vault item reaches live services ONLY via an IaC re-render/converge or an explicit sync task (`db_role_sync`/`db_ro_sync` precedent); if neither exists, the item goes in `NOT_AUTO_ROTATABLE` with a stated reason — no un-managed rotation paths | [docs/deployment-ansible.md](docs/deployment-ansible.md), [scripts/secrets/provision-secrets.py](scripts/secrets/provision-secrets.py) |
| Item-reference coverage | EVERY group_vars key class that references a vault item must be visible to `check-vault-items.sh` (template lookups AND registry keys like `db_item`/`db_ro_item`) — a new key class lands together with its scanner support in the same change | [scripts/gate/check-vault-items.sh](scripts/gate/check-vault-items.sh), [deployment-tasks.md](deployment-tasks.md) |

---

## 3. Code / IaC conventions

| Area | Rules | Owning doc |
|------|-------|-----------|
| Ansible roles | 1 entry point (`tasks/main.yml` → `include_tasks:`); assert admin user top; idempotent by default; tag every loop item | [docs/deployment-ansible.md](docs/deployment-ansible.md) (IaC Authoring Conventions) |
| Ansible vars | service/arch values → `group_vars/`, not role defaults | [docs/deployment-ansible.md](docs/deployment-ansible.md) |
| Ansible secrets | `lookup('community.general.onepassword', …, field=…)` only, `op_vault`, no literals | [docs/deployment-ansible.md](docs/deployment-ansible.md), [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Secret output hygiene | **never write a secret VALUE to stdout / chat / git / transcripts** — `op item get` / `ak shell` probes that print a value must print only **lengths, prefixes, item IDs, or hashes**; never run a bare `op item get … --reveal` into a shell that echoes to a session log. **Redact by VALUE, never by the `=` operator:** a filter that masks `KEY=value` leaves the rendered-config form `KEY: "value"` in the clear, and `check_secrets.py` reads the tree, not transcripts, so nothing gates that shape. Rotation of a shared Authentik client = regenerate in Authentik, persist to the 1P item, re-render consuming services (headscale + headplane), verify | [docs/1password.md](docs/1password.md), [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Secret → YAML rendering | a secret VALUE rendered into a YAML/TOML config file must use the **folded block scalar `>-`** (never inline `"{{ … }}"`) — 1P secrets can contain `:` `"` `'` `@` etc. which break quoted scalars and crash-loop the app — and a rotation is exactly the moment it bites. Rendered **compose files are still YAML** (`docker compose` parses them at deploy): 1P-sourced compose `env:` values use `>-` too; plain non-secret env strings stay quoted. | [docs/deployment-secrets.md](docs/deployment-secrets.md) (Rendering a secret into a YAML config file) |
| Compose location | one dir per service under `templates/docker_services/<service>/` | [docs/deployment-compose.md](docs/deployment-compose.md) (File Location) |
| Compose networks | `external: true` (traefik-public, services-internal, db-internal) created by the role | [docs/deployment-compose.md](docs/deployment-compose.md) (Network Assignment) |
| Compose security | `cap_drop: ALL` + minimal `cap_add`, `read_only`, `tmpfs`; no host ports unless justified; internal services need auth tokens (`<service>-internal_api`) | [docs/deployment-compose.md](docs/deployment-compose.md) (Container Security), [docs/security.md](docs/security.md) (Flaw C/D) |
| Compose versioning | pinned tags (never bare `latest`) + Renovate trail | [docs/deployment-compose.md](docs/deployment-compose.md), [renovate.json](renovate.json) |
| RouterOS | management services bound to Management VLAN; bootstrap `.rsc` + Ansible role both enforce | [docs/network-ops.md](docs/network-ops.md) |
| Two-sided deploy gate | a service/component whose IaC is done **but not live** is ⏳ deploy-gated in `todo.md` **and** its owning doc must carry the same visible status block (**🔴 planned / 🟢 IaC done ⏳ / ✅ live**) — a design-spec doc for a not-live service must say "not yet live — ⏳ deploy-gated", never read as deployed | [todo.md](todo.md) (§0/§3c), [docs/security.md](docs/security.md) (Deploy-gated rows), each owning service doc |
| **Comment hygiene** | **an `IaC/` comment states an invariant and its consequence — never a history.** No changelog narrative ("previously / retired / superseded / as of / we found"), **no ticket ids** (`HD-<n>`, `KOPS-<n>`, review tags), **no dates that are not real state**. Durable knowledge that belongs to a doc goes to the owning `docs/*.md` as state prose (present tense) with a `→ docs/<file>.md §<Heading>` pointer **only when that heading exists**; a comment that only records what changed belongs to no file at all, because **git history is the only changelog** | §6 (Docs are state-only), each owning doc |

---

## 4. Lifecycle conventions

| Phase | Rule | Owning doc |
|-------|------|-----------|
| Backlog | new work = new `HD-XX` row in `todo.md`; decisions written to owning doc (and the `<domain>-rejected.md` log where it applies); done → closing update in the owning doc + the git commit (frozen `reports/changelog.md` is archive-only). **An `HD` id is not stable prose** — rows are renumbered when they collide, so any brief that lists ids **re-derives them from `todo.md` at its own commit** and never copies a list from another doc or plan; a copied list silently turns into a false pointer. **`docs/*.md` name no HD ids at all** (state-only rule §6) — the id belongs to the queue, the fact belongs to the doc | [todo.md](todo.md), [docs/index.md](docs/index.md) |
| Work package | a run spanning **more than one session or more than ten HD rows** may carry its execution state in one `tasks-<slug>.md` — orchestrator is its only writer, it names rows that already exist in `todo.md` and never a second backlog, it closes a task only on evidence, and it dies with the last row | [docs/orchestration.md](docs/orchestration.md) §4 |
| Post-task housekeeping | **a `todo.md` row is a work queue, not a changelog**: it states **what is still missing** and may carry **clues for doing it** (the exact command, the probe that does not lie, the trap that cost an hour). It never carries durable knowledge — findings, measurements, root-cause prose, mechanism explanations, ✅ retrospectives — because that belongs in the owning `docs/*.md`, which the row links. When a row's ⏳ list empties, the row is deleted; when a finding is written, the doc is edited and the row shrinks. Test: a row that only describes *history* is a row that should be shorter. **after each completed task, update `todo.md` in the same change** — ONE pattern, two states, no third option: (a) **task fully closed** (nothing left to do) → DELETE the row from `todo.md` in the closing change; the close-out record lives in the owning doc (`docs/*.md` ✅ line) + the commit message + git history — a `✅ Done` row with no `⏳` tail must never remain in `todo.md`. (b) **IaC done but deploy-gated** → KEEP the row (trim its tail to only the pending `⏳` items); the todo row is deleted when a later live verify closes it. **No hand-maintained tally/Status line** — the backlog count is derived from the rows themselves (counts are derived, never hand-entered, §2) | [todo.md](todo.md) (§0 lifecycle), owning docs |
| Decisions | one decision, recorded once, closed once; **a resolved decision is written ONCE to its owning `docs/*.md` (+ the `<domain>-rejected.md` decision log where it applies) — do NOT leave a struck duplicate row with the full rationale in `todo.md` §1**; a `-rejected` row states the decision as a fact — no date, no rationale prose (§8.3); the closing change also **sweeps stale mentions of the superseded thing in other docs** (TileBoard/AnythingLLM/watchtower precedents — a decision that leaves old text standing elsewhere is not closed). Historical decisions live in the frozen `reports/changelog.md` (archive-only) | [docs/security.md](docs/security.md) (§7 Decision log), `<domain>-rejected.md` docs |
| Onboarding a service | see the 10-step checklist below | — |
| Validation gate | `bash scripts/validate-all.sh` before commit (compose, templates, IPs, docs). The `docs/index.md` doc-map vs `find docs -name "*.md"` is linted by `scripts/gate/check_doc_map.py`; **planned extension:** also lint any doc-claimed role/template count — a docs-claim that drifts is a lint failure, not a cosmetic | [scripts/README.md](scripts/README.md), [docs/index.md](docs/index.md) (Validation) |
| Deploy | first apply human-gated (dry-run → single host); single path = Ansible (Renovate PR → merge → Ansible from the control node — no deploy button exists on either git surface) | [docs/deployment.md](docs/deployment.md) |
| Deployment ledger & journal | deploy progress + execution record live in exactly two places (owning docs stay desired-state SSOT — no progress markers, no logs there): (a) **ledger** = `[deployment-tasks.md](deployment-tasks.md)` checkboxes (`- [x]` + date when done; human-only steps prefixed `**[MANUAL]**`) — the plan and what's next; (b) **as-built evidence** = the owning doc ✅ status lines + the git commit message of the change that did the work (commands/evidence in the commit; secret VALUES never — item+field names only). (c) **runbook** = `[deployment-manual.md](deployment-manual.md)` — imperative phase-by-phase redeploy procedure (true zero → live): commands, panel settings, per-step evidence; the procedure SSOT carries no progress markers, no execution history and no knowledge (specs/designs/root causes stay in the owning doc, linked from the step that needs them). Its phase numbering **follows the ledger** (spark = Phase 4b in both); Ansible commands belong there because they are the deploy procedure until the ledger's Phase 5 deploy button exists. A permanent divergence discovered during execution updates the owning doc/runbook in the same change (noted in the commit). The frozen `reports/deployment-journal.md` is archive-only. **Human feed:** there is no standing `prompt-journal.md` DATA feed — raw notes go straight into the owning-doc edit + ledger tick + commit | [deployment-tasks.md](deployment-tasks.md), [deployment-manual.md](deployment-manual.md) |
| Deploy-gated rows | an `HD-XX` row whose IaC is done **but not yet live** stays **open** with a **`⏳ Deploy-gated:`** tail listing the exact pending live steps (provider creation, secret seeding, firewall open, live-verify). It closes only after a live deploy/verify pass — **not** at IaC-completion. A task's ⏳ is a *phase*, never moved to a separate file. Its close-out record at IaC-completion lives in the owning doc (Post-task housekeeping (b)) | [todo.md](todo.md) (§0 lifecycle, §⏳ checklist), owning docs |
| Session close-out | **Before ending a working session, walk this checklist in order and answer each point explicitly in the final response:** (1) **Any open questions?** (2) **Is all knowledge in the owning docs?** — owning-doc status lines updated, todo tails updated, decisions in their specs (+ `<domain>-rejected.md` where applicable); the close-out record is the owning-doc edit + the commit (frozen changelog/journal are archive-only). (3) **Is `prompt.md` updated** to the new handoff state (next session must be able to start from it alone)? (4) **Is `deployment-manual.md` updated** — every non-Ansible step performed that a future FROM-SCRATCH deployment would need again is written into the runbook as imperative procedure (commits record history; the manual is where repeatable procedure lives). **If a session performed NO manual/non-Ansible steps (everything automated via IaC/playbook), `deployment-manual.md` stays UNTOUCHED** — diagnostics, root-cause prose, and system mechanics belong in the owning doc + commit, never in the runbook (revert-if-added: runbook is imperative procedure only — commands/settings/evidence, no narrative). (5) **Handoff diff-rule** — the new `prompt.md` handoff is produced by EDITING the previous one, never rewritten from scratch; every prior §2 open item is then either **still listed with its pointer** or **gone**, its destination named in at most one clause ("ruled in its owning doc", "row **HD-nnn**", "dropped — no row was owed"). **A resolved item LEAVES the file** — its ✅/⏸ resolution narrative never stays behind as proof that it appeared, because the record is the owning doc + the commit, and an accreted proof-log is exactly how a pointer index becomes a changelog. Mechanically bounded by the handoff gate wired into `scripts/validate-all.sh` and listed in [`scripts/README.md`](scripts/README.md): this history shape and the ban in (6) below, which are findings, and a size line that only reminds (§6.4); its baseline is re-sealed by the parent at the merge station, never inside a lane (`prompt.md` has no §3 — the live lane waves are [todo-table.md](todo-table.md) §B0). (6) **Derived-values ban** — computable pointers (next-free HD = max(HD)+1 in todo.md, item counts, record sets) are never typed into prose; quote/re-derive the source instead (§1/§2 reinforcement). (7) **Branch-per-session checkbox** — confirm the session ran on its own `session/<slug>` branch inside its own worktree (never directly on main), merged back green. Only then cleanup: merge the session branch back to main (**green results only**), remove/prune the session worktree, push. | [deployment-manual.md](deployment-manual.md), [prompt.md](prompt.md), owning docs |
| Path citations | **a path a doc or an IaC comment cites must exist in the tree.** Invented-but-plausible paths do ship: a lane brief cited `scripts/llm_serving_bench.py` as its bench harness and that tool does not exist in this repository, and the first sweep found 47 stale citations (moved files, deleted lane briefs, links written as if the author's directory were the repo root). Proved offline by `scripts/gate/check_doc_path_refs.py`, wired into `validate-all.sh`. Either fix the citation or delete the claim; when a path is genuinely pending, WRITE that it is pending ("`x.sh` does not exist yet") — that is the difference between a tracked gap and a false promise | [scripts/gate/check_doc_path_refs.py](scripts/gate/check_doc_path_refs.py) |
| Audit reports | root-level audit / prompt-deliverable reports are **ephemeral**: each actionable finding is folded into its owning doc + an HD row (or explicitly rejected), then the report is deleted in the change that closes its last finding — reports are context, never SSOT (precedent recorded in the frozen `reports/changelog.md`) | repo root, frozen `reports/changelog.md` |

> **Decision log formats differ per file, and both are mandatory.** `docs/security.md §7` keeps **one bullet per decision, stated as a fact** — no `Date:` field, no evidence ids: `- **Decision statement** — what the system does, and the owning doc that implements it`. Every `<domain>-rejected.md` is a **table**, append-only, per §8.3: `| <service> | <rejected|dropped|superseded> | <why, ≤ ~12 words> |` — **no dates, no evidence links, no rationale prose**: the row is the fact that the alternative was rejected; the trail of how it was decided is git + the owning doc. A file's own preamble wins over this footnote either way. Historical changelog decisions live in the frozen `reports/changelog.md`.

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
- Decision dates are ISO `YYYY-MM-DD`; when touching a dated prose entry, fix year typos in the same change (2025→2026 sweep pending in five docs; the frozen `reports/changelog.md` / `reports/deployment-journal.md` are untouched archive).
- Headers: every doc starts with `> **Role:**` and `> **Linked from:**` — enforced by convention.
- **Docs state facts; commits state what changed (owning-doc rule):** an owning `docs/*.md` says what is
  true now — configuration, invariants, interfaces, live status — and nothing else. A sentence that reports
  an **event** (what a session did, found, measured, fixed, moved, ruled, renamed) belongs to the commit
  message and `git log`, exactly as an `IaC/` comment does (§3 Comment hygiene): **git is the only changelog
  this repo keeps.** A superseded value, placement or pin is a value that no longer exists, and git keeps it
  (§2). The rule binds the root tool map `scripts/README.md` (§3 registry rows), the runbook (§4 ledger) and
  the backlog surfaces (§4 housekeeping) by the same argument — different files, one rule.
  - **Ticket ids, with one exception:** an `HD-<n>` / `KOPS-<n>` token may sit in a doc **only while its
    `todo.md` row still exists** — the pointer is honest while the work is unfinished. When the row closes it
    is deleted (§4(a)), and a doc still naming it points at nothing, so the mention leaves **in the same
    change** as the row. An id is not stable prose (rows renumber, §4 Backlog); the fact outlives it.
  - **A date is legal; a dated event is not.** Dates that ARE state stay and are never findings: expiry,
    `valid_until`, a renewal, a firmware build date, and a **`live-verified` / as-built marker — there the
    date IS the information** (it answers "how fresh is this claim?"). What is not state is a past-tense
    **evidence verb anchored to a date** (`measured …`, `ruled …`, `fixed …` + `YYYY-MM-DD`): the verb marks
    the sentence as history, the date only points at it. The closed verb list lives in
    `scripts/gate/check_backlog_prose.py` and is **never re-typed here** (§2).
  - **The finding is the sentence; the token is only the tell.** Clearing means rewriting the sentence as a
    fact or cutting it — never deleting a date and keeping the story, because a stripped "measured X" is
    still a story. **State Test:** after the next re-render and the next live verify, is this sentence still
    true, and does anything read it? A sentence whose only purpose is to prove that someone checked is
    changelog.
  - **What blocks, and what only reminds** (§6.4): no **size** finding blocks. Every size bound in this
    repo prints with a pointer to §6 / §6.4 and exits green, because bytes are a proxy and a file that grew
    with honest content is allowed to grow. Blocking is reserved for what the tree can prove — a dangling
    ticket id, a stale citation, a secret literal, generated-view or SSOT drift, and a **sealed narrative
    count that grew**, which is a diff against recorded state rather than an opinion about prose. Judgement
    about prose shape stays a reminder (`check_docs_pure.py`'s warned half).
  - **Gate ownership:** `check_docs_pure.py` (`docs/**/*.md` + root `README.md`), `check_doc_size.py`
    (corpus size, reminder), `check_registry_prose.py` (`scripts/README.md`), `check_runbook_purity.py`
    (runbook), `check_backlog_prose.py` (`todo.md`, briefs), `check_iac_identifiers.py` (`IaC/`),
    `check_handoff_size.py` (`prompt.md`).
- Relative links only — markdown relatives to `docs/*.md`.
- Secrets never in docs — 1Password `Homelab-ansible` vault only.
- **Never print a secret VALUE to stdout / chat / git / transcripts** — probes show **lengths / prefixes / item IDs / hashes** only (rotation + readback precedents).
- **Secret → YAML config = block scalar `>-` by default** (never inline-quote a 1P secret into a
  YAML/TOML file the app parses) — see the Rendering section of `deployment-secrets.md`.
- Generated files use the **`-generated` filename suffix** and are rendered, never hand-edited (§8.2). The legacy **★** marker in `docs/index.md` is a display aid only, **not** the convention.
- **A script that runs `ssh` must give it `-n` (or `</dev/null`)** — for the duration of that ssh, stdin is whatever the parent was reading, so the run silently truncates and exits with whatever the last executed line returned — a fully working setup whose acceptance never executed can still exit `0`. The exit code alone never tells you which of the two you are looking at. **Two shapes, one trap:** (a) a script piped into `bash -s` over ssh — stdin IS the rest of the script; (b) a `while read` loop fed by a process substitution/here-string with an `ssh` in the body — the ssh eats the **loop's own list**, the loop ends cleanly, and the run reports success having done the first item — it can print `IN SYNC` after **1 of 8** items ran. So: read loop input on a private FD (`while read -u 3 …; done 3< <(…)`), or `-n` every inner command, and **never let "items processed" be assumed equal to "items declared"** — count both and fail on a mismatch.
- **A script is run by its own interpreter, never by the one that happens to be in the shell:** `python3 scripts/gate/<name>.py` (the gate's own launcher spells it `$PY` so the venv guard applies), `bash scripts/<name>.sh`. `bash scripts/gate/<name>.py` is not a syntax error — it is a HANG with a plausible face: bash parses the Python as shell, a `"""` docstring line becomes a quoted string whose quoting swallows the lines after it, and the words inside are then word-expanded into a COMMAND, so argv can end up holding source text (`ps` showing `import os` at 0.0 % CPU is this bug). The process reads the inherited stdin and blocks forever — harmless to data, invisible to `bash -n`, which parses without executing, and it survives `rm` of its own script because an executable is held by inode, not path. When the interpreter or the path arrives from a variable, QUOTE both (`"$PY" "$script"`): an unquoted expansion re-splits a path containing spaces and hands the interpreter the wrong argv.
- **Don't chase cosmetic tweaks** during planning phase (ASCII alignment, spacing); substantive, consistent edits only.
- **Git worktrees (owning rule — CONVENTIONS is SSOT):** **every** session creates its own fresh
  worktree named `../homelab-wt-<date>-<HHMM>` **before touching any file** — single-session work
  included; isolation is the default, not a parallel-sessions special case. Date AND time in the
  name means two sessions started the same day can never collide; apply and validate edits in the
  worktree, merge back only committed, green results, primary checkout untouched.
  **Discipline:** manage ONLY your own session's worktree, always via `git worktree add` /
  `git worktree remove` — never `rm`/move/rename any worktree directory; on `path already exists`,
  abort and pick a new name instead of cleaning up — an `rm -rf` aimed at a colliding path
  destroys whichever worktree really lives there.
  **Mechanical enforcement:** this rule is ENFORCED, not prose-only — `scripts/gate/guard-session.sh`
  (pre-edit guard) refuses ANY edit-context while the **primary** checkout (`git-dir == git-common-dir`)
  sits on `main`, and `validate-all.sh` hard-fails when run from primary+main+DIRTY (committing
  primary-resident edits = the violation); a clean-main merge-station validation stays exempt, session
  worktrees and detached-HEAD/CI pass through. Every refusal prints the exact remediation command with a
  live timestamp (`git worktree add ../homelab-wt-YYYYMMDD-HHMM`). **Primary definition:** the primary
  checkout is a **merge station only** — all edits happen on a session branch inside a session worktree;
  main receives only fast-forward merges of committed, green results.
- **A lane brief (`prompt-<domain>.md`) is named for its domain and host, never for an HD id** — an id records
  which row happened to be minted first in the lane, not the context the session is entering. A brief names the
  rows it carries **as of its own worktree's commit** and **re-derives** those ids from `todo.md` at that commit —
  it never copies an id list from another doc or plan (§4 Backlog). It **links** the lane-session rules
  ([docs/orchestration.md](docs/orchestration.md) §4, the overrides O1–O11) instead of restating them, and it dies
  with its rows, deleted by the orchestrator in the cleanup commit (O7).
- **Subagent children: inherit the model, stay at two, wait out a compaction.** A child launch never names a
  `model:` — builtins inherit the session model and a seat's rendered model set carries one serving provider, so
  an override names a provider that does not exist here; the ceiling is a setting (`subagents.modelScope`,
  `allow: ["inherit"]`) in `pi-agent/settings-ssot.json`, not a habit. **≤2 children run concurrently**, because
  the engine's `max_num_seqs` minus the parent minus the always-on consumers is 2 (`docs/harness-pi-engines.md` §6) —
  a third preempts a live prefix rather than queueing. And **a silent child is not a hung child**: a local engine
  compacts for minutes at a time, so a stall is waited out, and the run deadline is per child, not per parent.
  Numbers, reasoning, and which file sets each: `docs/orchestration.md` §4 (O10–O11).
- **Commit signing is OFF: `commit.gpgsign=false`, and a plain
  `git commit` is the correct command.** ⚠ **Do not reach for `git commit -s`** — in git, `-s`/`--signoff`
  adds a `Signed-off-by:` **trailer and signs nothing**; a session that mistakes it for signing leaves a
  trailer no other commit in this history carries. Why it is off: no SSH signing key is registered on
  GitHub, so `commit.gpgsign=true` is not a policy but a **hang** — git waits on an
  agent for a key that can never validate, in the shells nobody watches (cron, a converge, a pi bash call).
  **`git log -1 --format='%G?'` returning `N` is the expected value on every commit now and is not a
  failure** — there is nothing to verify; `gpg.ssh.allowedSignersFile` stays only so the signed history
  still verifies. The mechanism (the `GitHub auth` SSH_KEY item in `Homelab-ansible` — `GitHub sign` is DELETED, the
  key-**file-path** vs `key::<pub>` form and why the file path was chosen, the
  `ssh-add ~/.ssh/github_signing ~/.ssh/github_auth` recovery for a shell that still has a key to find) is
  documented in [docs/deployment-secrets.md](docs/deployment-secrets.md) §6 (the seat
  test), [docs/1password.md](docs/1password.md) (the key-file vs `key::<pub>` measurement),
  [docs/deployment-rejected.md](docs/deployment-rejected.md) (the rejected form) and the `git-bootstrap.sh`
  row of [`scripts/README.md`](scripts/README.md) (the `--ssh-auth` plumbing and the `~/.bashrc`
  re-add block) — kept as history and as the rebuild path, so **if the owner ever re-registers a key, those
  and the seat template [`scripts/git/gitconfig-nightly`](scripts/git/gitconfig-nightly) are where it
  changes, not this bullet.**
- **A gate that cannot see the file cannot fail either — prove the probe, not the platform.** Four validator shapes are
  silently blind on a Git-Bash/Windows seat: MSYS opens files in **text mode**, so a
  plain `LC_ALL=C grep $'\r'` never sees the CR of a CRLF pair (`grep -U` is mandatory in every encoding guard; `cmp`/`diff`
  are binary-safe and were fine); a self-test fixture with a hardcoded `/usr/bin:/bin` PATH dies `git: command not found`
  because Git-Bash keeps `git` in `/mingw64/bin`; a `^={7}$` anchor never matches a `=======\r`; and a case whose last step is
  a load probe counted "no tmux here" as a broken invariant. Each of these reports **green or a misleading red**, so the rule
  for any host-dependent guard: assert the probe detects the canary **on the host it will run on**, and make an environment
  boundary print `SKIP`, never a pass.
  **The same trap has a second half, found 2026-10-10 while removing forks from an encoding guard:** a **command
  substitution** applies that text-mode translation too. `printf 'a\r\n' > t`, then `s=$(<t)` and `case "$s" in
  *$'\r'*)` reports NO CR, while `IFS= read -r line < t` keeps it (`od` shows the byte either way) — so the fork-free
  rewrite of a guard that had used `grep -U` went blind on Windows again and its own CRLF canary was the only thing that
  said so. Rule of thumb for a Windows seat: `read`/`case`/`cmp` are byte-truthful, `$( )` is not; and any rewrite of a
  probe needs the canary to run in the script that depends on it (`sync-skills.sh` still keeps the exec-based body for
  exactly that reason — it has no self-test to prove a new one with).
- **A test that cannot fail is not evidence.** Before claiming a fix, write the input that
  differs *only* under the fix and run it; if the check would print the same thing either way,
  it proves nothing. The shape to refuse is a commit that describes a
  scanner fix it does not contain, backed by a "proof" that prints a vocabulary looking
  identical either way because those tags also exist at top level. Prefer gates that carry
  their own `self_test()` plus a canary (drop a role that restarts `sshd` and
  `scripts/gate/check_self_converge_guard.py` goes red) over prose that asserts coverage. Same rule
  for live claims: prove the thing you are about to rely on (`ssh-keygen -F`, one read-only
  converge, a fresh auth) rather than reasoning that it probably works.
- **A duplicate YAML mapping key is a silent no-op — ansible keeps the LAST one and only warns.** Same
  silent-failure class, cheaper to introduce than to notice: a second `tags:` on a task **strips a tag**
  (surgical `--tags` runs then skip it forever), a second `no_log:` **prints a secret**, a second `when:`
  silently re-gates the task, and `--syntax-check` + the converge both stay green. The gate is
  `scripts/gate/check_yaml_dup_keys.py` (validate-all item 30,
  with ansible's own stderr as the second witness); when you fix one, **prove the fix is a no-op** — the
  render matrix byte-identical before/after, not "the values looked the same".
  Precedent: [docs/deployment-ansible.md](docs/deployment-ansible.md) §Three ways a converge lies to you.
- **A string two files shipped byte-equal may not be renamed on one side**, so a deliberate rename changes every side in one commit; the enforcer is `scripts/gate/check_string_twins.py`, and its blind spots (payload block scalars, heredocs, rendered Jinja, twin families that never agreed at the pinned baseline) are stated with it in [scripts/README.md](scripts/README.md) §Validation gate.
- **Collapsible `<details>` sections:** human/family-facing browser-rendered docs only (`readme-humans.md`, `docs/manual/*`) and only for optional asides (troubleshooting, FAQ) — **never** in agent-facing docs (owning specs, runbooks incl. `deployment-manual.md`, ledger, todo, or the frozen `reports/*` archives): the primary readers are AI agents working on raw text, where folds hurt grep-ability and add noise. Blank lines between the HTML tags and the inner Markdown are mandatory, else fences/tables render as raw text. Precedent: `readme-humans.md` §Za družino troubleshooting fold.

### 6.4 Why the doc gates exist, why they remind, and what they are NOT

- **Motivation, recorded once:** these gates were not built over long files or over formatting. They exist
  because **the docs, the script registry, the runbook and the backlog were used as a changelog** — preserved
  history, dated "as of" narration, session accounts of what was measured, and references to `HD-` rows that
  had already been deleted. That text is a second copy of git that nothing re-renders: it goes false the
  moment reality moves, and it buries the fact a reader came for.
- **The rule is semantic; size is a proxy for it, never the rule.** A long doc made of facts is a *placement*
  problem, and the fix is §8.1 — split a catalog out of an index — not a size finding. A changelog-shaped doc
  is the defect at any length.
- **A size bound is a reminder wherever it exists; the prose is the rule.** Bytes and lines are never the
  verdict on a hand-authored surface: a row, brief or handoff that grew because it carries more honest
  content is allowed to grow, and the next re-seal books that size. So the size halves of
  `check_doc_size.py`, `check_handoff_size.py` and `check_backlog_prose.py` **print and exit green**, while
  their changelog halves — dangling ids, history-shaped entries, typed counts, narrative growth — are what
  reddens. A size line is an instruction to read the file, not a reason to shave it; and a reminder that
  cannot print is a silent cap, which is why each of these gates carries a self-test arm proving its size
  half fires on a canary while the run stays green.
- **Reminder semantics (ruled 2026-10-26):** the prose-shape and doc-size checks run in every validation,
  print their findings **with a pointer to §6 / §6.4**, and **exit green** — they inform the next edit and
  never veto one. Two consequences are binding. A reminder must **re-derive its finding on every run**: a
  frozen per-file baseline would rot into permanent yellow nobody clears, because yellow never blocks a
  merge — that is why the doc-size seal (`gate/doc_size_baseline.txt`) was retired rather than widened, and
  why the size bound is derived at run time from the new-doc reference. And a reminder must stay **cheap to
  clear in the same change**: one sentence rewritten, not a project. Findings nobody clears over weeks are
  evidence the wording or the threshold is wrong, and are re-tuned rather than promoted to a blocker.
  Every seat is the merge station, so nothing here waits on a special place or a special person.
- **What stays a blocker:** a **dangling ticket id** (a doc naming an `HD-`/`KOPS-` row that no longer
  exists — §6), a false statement the tree can disprove (secret literals and value disclosure, doc-map /
  path / anchor citations, generated-view purity and SSOT drift, duplicate YAML keys, duplicate todo ids,
  the session-worktree guard), and anything that would render a lie.
- **Drain, do not sweep:** the reminder drains the corpus by touch — each doc's history leaves when a session
  edits that doc. No purge wave is run for prose shape, because a wave of rewrites is what turned these files
  into changelogs in the first place.
- **What a reminder does not license:** accreting history "for context", citing a closed `HD` id as
  provenance, or treating a printed reminder as debt someone else owes. The session that wrote the sentence
  clears it.

---

## 7. Version-pin hygiene

| Rule | Owning doc |
|------|-----------|
| a `*_version` pin lives in **one** file — `group_vars/all/versions.yml` — **not** spread across `all.yml`; Renovate docker datasource + version review are single-sheet | [docs/deployment-compose.md](docs/deployment-compose.md), [docs/deployment-renovate.md](docs/deployment-renovate.md) |
| a pin is **never bare `latest`** and never a *mutable alias* (`-rocm`, `main-stable`) **unless** the owning doc records an explicit MUST-pin + verified-semver precondition (Tuwunel / OpenClaw / LiteLLM fluid-tag precedents) | [docs/deployment-compose.md](docs/deployment-compose.md) |
| on a fluid-tag *first* pin, show the registry-verified tag + Renovate tracking **in the same change** | [docs/deployment-compose.md](docs/deployment-compose.md), [docs/deployment-renovate.md](docs/deployment-renovate.md) |
| a `*_version` var carries **no `default()` fallback in templates** — a missing pin aborts the render (fail-loud, same as secrets); mutable aliases (`stable`, `release`, `-rocm`) are bare-`latest` equivalents under the same MUST-pin precondition | [docs/deployment-compose.md](docs/deployment-compose.md) |
| a pinned **host package** (APT, not a container image) is **held in IaC** — `apt-mark hold`, asserted back with `apt-mark showhold` — so `apt upgrade` cannot move it; its version changes only when `versions.yml` changes, as a deliberate Renovate → converge event, and there is **no automated upgrade phase** anywhere in the fleet | [docs/deployment-ansible.md](docs/deployment-ansible.md) |

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
> The goal is a consistent mental model + URL scheme, not achieved
> purity: both placements and cross-cutting docs have explicit homes and markers (never ambiguous).

### 8.1 Domains & stack index (placement axis)
- **Domain** = a deployable stack: the set of services (plus their docs) that deploy together under one
  owning `domain:` value. A domain has a **primary owning host / host-class** (e.g. `smart-home` →
  Pi/oldsrv, `network` → router/switch, `observability` → VPS backend, `harness` → the operator seats).
  Frontmatter: `domain: <stack>` + a document `role:`.
- **`role:` values** (the doc's *shape*, not a placement statement): `index` (domain hub linking sub-docs),
  `broad` (overview), `ssot` (single source of truth for a concern), `detail` (a sub-topic), `reference`,
  `design-spec`, `runbook`, `research`, `cross-cutting` — plus the four shapes the tree already carried and
  this list omitted: `log` (a `-rejected` decision log), `queue` (a `-review` intake queue), `evidence` (a
  captured bench run), `incident-log`. A domain hub is `role: index` (or `broad`). Membership is gated by
  [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py), so a typo'd role cannot silently
  drop a doc out of every other rule in this section.
- **The hub floor, and where it does NOT apply** (gated by the same checker): a domain owes a
  `role: index|broad` hub only when it has **≥2 non-pair docs**. A domain whose whole body is ONE doc **is**
  its entry point whatever its role — an `ssot` body or a `reference` one — so the floor never invents a
  file for a one-doc domain. Two `index|broad` docs in one domain is a defect: two hubs are two opinions
  about where to start. The domain **set** is DERIVED from the `domain:` frontmatter over `docs/**/*.md`
  and is written down nowhere, which is why adding or retagging a domain is a frontmatter edit.
- **A `-review` / `-rejected` pair cannot create a domain** (§8.3): a pair's `domain:` must also appear on a
  doc **body**, because a pair is a decision log dispatched from a hub. Precedent: **`storage` is not a
  domain** — ZFS spans nas + oldsrv with no primary owning host (the test above), and `storage.md` already
  lives under the `deployment` umbrella (§8.4) — so `docs/storage-review.md` + `docs/storage-rejected.md`
  carry `domain: deployment` instead of opening a domain nothing can dispatch from.
- **Domain index** links to `<domain>-<sub>.md` detail docs. Canonical pattern: `smart-home.md` →
  `smart-home-{voice,audio,failover}.md`. **Stack / sub-domain docs** group a big domain's catalog into
  `services-<x>.md` — e.g. `services-matrix.md`, and `services-office.md` as the office-workload slice of the
  services stack. All share the owning `domain:` (e.g. `services`).
- **Umbrella domain** — a domain need not have a single service host to be a domain; it may be an
  *ops umbrella* whose children are cross-cutting concerns. Precedent: **`deployment`** — deployment.md
  is the hub; its Document Map/Related seed the cross-cutting children `security.md`, `backup.md`,
  `storage.md` (all `domain: deployment`, `cross_cutting: true`). An umbrella hub is still
  `role: index|broad`; each child keeps `cross_cutting: true` + its own `role:` (detail/ssot).
- **Seat-class domain** — the host-class of a domain may be the **operator seats** instead of a fleet
  machine, and such a domain is still a clean domain (not cross-cutting). Precedent: **`harness`** —
  `harness.md` is the hub for the coding-agent harness on the seats, and what deploys together there is a
  **plane** set (`scripts/lib/seat-planes.yml`, fanned out by `scripts/harness/pi-seat-sync.sh`) rather
  than a `docker_services` catalog. Harness docs are therefore **not** `domain: services`: a coding
  harness is not a service — it consumes the engine directly — so its config, seat and terminal subjects
  belong to the seat-class domain even though the model contract it writes is about an AI engine.
- **Central service stack index** = `docs/services.md` (catalog + networks + domains). It is the *only*
  pointer from `docs/index.md` for service layout.
- **No doc is both** an index and a dumping ground: a doc that mixes a pointer list with a catalog table
  reads as a dumping ground whatever its length — split the table into a `services-<x>.md` stack doc and link
  it from the index. Placement follows content shape, not line count (§6.4).

### 8.2 Generated docs — the `-generated` suffix
- **Any file produced by a script/Ansible (not hand-authored) carries a `-generated` suffix** in its
  base name: `<name>-generated.md` (e.g. `network-addresses-generated.md`,
  `services-inventory-generated.md`, `subscriptions-table-generated.md`, `network-rack-generated.md`).
  The suffix appears **in the filename**, never only in a header, so file lists and `git grep` make
  generated sources obvious. Headers still say "do not hand-edit"; the filename is the guarantee, the
  header the hint.
- **Canonical managed-header:** every generated doc opens with `# Ansible managed` — **exactly Ansible's built-in `ansible_managed` default**, so a real Ansible render and the pure-Python `scripts/render_all.py` umbrella stay byte-identical. Do not personalize it: `# Ansible managed` is the only accepted header (`# Ansible managed: file edited by Ansible` and `# auto-gen` are not accepted).
- **Renaming a generated file = touching the renderer + every reference** in the same change: the
  render helper itself (`scripts/render_*.py`, `IaC/ansible/playbooks/render-docs.yml`, the
  `docker_services` role), the validators that whitelist/tokenize the name
  (`scripts/gate/check_doc_ips.py`), and the doc map in `docs/index.md`. The doc-map linter
  (`scripts/gate/check_doc_map.py`) fails closed, so a stale reference breaks `validate-all.sh`.

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
- **`<domain>-rejected.md`** = *decision-log SSOT* (per domain, replaces the frozen changelog
  decision log). **Append-only in content** — never rewrite or delete an entry's text; adding a row
  is the only content change. The table is kept in **one sorted sequence by subject**, using the
  canonical key: lowercase, non-alphanumerics dropped (so `` `--foo` `` sorts as `foo`, `/health …`
  as `health`, `WSL `mirrored`` as `wslmirrored`). Appending and then re-sorting is expected — a
  re-sort moves lines and changes no text, so it is not an edit (stable key for `git grep` /
  `git log -S`). Each entry:
  `| <service> | <rejected|dropped|superseded> | <why, ≤ ~12 words> |` — a short fact: **no date, no
  evidence link, no prose paragraph** (the reasoning trail is git and the owning doc). When a
  decision changes, the old entry is left unchanged and a new one is appended (do **not** strike the
  old one).
- **An open question is an `Options` section in its OWNING doc, keyed by its `OQ-<n>` id** — the counterpart
  of the log above, and its open half. Shape, all of it mechanically checkable: a heading at level 2 or 3 whose
  text begins `Options` and names the id (`### Options (OQ-<n>): <the question as asked>`), carrying a table
  with the header exactly `| Option | For | Against | Cost | Cheap test |`, **two or more** option rows, every
  `Cheap test` cell non-empty — the cheapest experiment that would settle it, which is what makes the section
  cheaper to answer than to argue — and **no recommend/decided/decision wording inside it**: an option is never
  a recommendation dressed as a decision. The recommendation is the owner's act, and when it lands it lands as
  state prose elsewhere in the doc.
  - **Inventory:** `rg -n '^#{2,3} Options' docs/` is the whole list of open questions — that fixed heading
    shape is exactly what a prose heading like "Open questions" cannot give, since the same phrase also appears
    in prose.
  - **An answered question leaves no `Options` section behind.** The answer becomes state in the doc, plus a
    `<domain>-rejected.md` row where the outcome is a rejection. A section whose question is answered is a
    changelog wearing a table.
  - **`<domain>-rejected.md` keeps NO `open` status.** The log is one row per subject and append-only, so an
    open→decided pair on one subject would break the subject-keyed sort that makes it greppable — the row is
    the fact that an alternative was rejected, and a row that is still waiting says nothing about any
    alternative. The doc's `Options` section IS the open state, the log is the decided state; one subject is
    therefore in one of the two, never in both.
  - **`OQ-<n>` ids are derived, never typed** — the next id is max+1 over every `OQ-<n>` already in the tracked
    `*.md` (`git grep -hoE 'OQ-[0-9]+' -- '*.md' | sed 's/OQ-//' | sort -n | tail -1`), the same argument as the
    backlog ids (§2): a hand-typed number goes stale the moment two docs grow at once.
  - **The citation direction is row→doc, never doc→row** (§6 state-only): a `todo.md` row may name the `OQ` id
    and its doc section; the doc names no row. A doc that cites a queue row has made a standing question depend
    on a line that moves.
- The **services** domain seeds the pattern: `docs/services-review.md` +
  `docs/services-rejected.md`. Other big domains (network, hardware, smart-home) opt in with their own
  `<domain>-{review,rejected}.md` when they have enough volume. A domain **cut out of an existing one**
  opens its log with **seed pointers** to the logs that already hold its history rather than migrating
  rows — the moved domain's log is then append-only from the split onward (`harness-rejected.md`, seeded
  from `services-rejected.md` + `services-ai-rejected.md`).

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
- **A rendered file's bytes are a pure function of its SSOT — no wall clock may enter a render
  context.** A stamped "generated at" is the one diff that re-rendering can never clear: it makes the
  drift check above permanently red, so "when was this generated?" stays out of the compared bytes and
  in git, which already keeps it (`git log -1 --format=%ci -- <generated file>`).

### 8.6 Data-sensitivity class (`sensitivity:`)

> **Why this exists:** the external-model rule ([README.md](README.md) §3) decides where a run's *context* may
> go, and the shape scanners (`scripts/gate/check_secrets.py`, `scripts/gate/check_secret_leak.py`) prove that
> no credential **text** ships. Neither can say what a document is **about**, which is the fact a run needs
> before it decides where its read list may be sent. The class is that fact, declared where the run can read it.

- **Three classes, one per hand-authored doc:**
  - `infra` — **the default.** Build, topology, service mechanics: how a thing is deployed and how it fails.
  - `secret-bearing` — the doc enumerates vault **item/field names** or credential mechanics: the secrets
    master list, the 1Password notes, the OIDC glue, the AI-stack secret catalog. Names are not values, so
    these docs are safe to read; they are not neutral to hand over.
  - `personal` — the doc's subject is a **person**: the family plane `docs/manual/**`, the household-finance
    stack.
- **Highest class wins** where subjects overlap — a doc that documents someone's accounts *and* their vault
  items is `personal`. It has to be a `max`, not a judgement call, or the class is an opinion about privacy
  rather than a field.
- **Field placement:** `sensitivity:` is a key in the doc's **leading `---` frontmatter block**, sitting
  **after `status:`**, holding exactly one bare lowercase slug — `sensitivity: secret-bearing`, no quotes, not
  a list. The slot is fixed because the field is read mechanically, by a run deciding where its context may
  go: a key that may sit anywhere is a key a scanner has to guess at, and a second spelling of the same value
  is a second source.
- **A `-generated.md` render view inherits its source doc's class and declares nothing** — the canonical
  managed header (§8.2) is line 1 of a generated file, so there is no frontmatter block to put the field in,
  and a second declaration would be a second source. Therefore **a renderer that would emit a personal value
  into a render view is a defect at the source, not a filter at the output** — that argument already lives in
  §8.5 and adds nothing here; fix the renderer or the SSOT it reads.
- **The egress rule, stated once in this repo:** a run whose read list names a `personal` or a
  `secret-bearing` doc is **not** an external-lane run, whatever the owner's general preference. The read list
  is the promise, not the prompt — quoting one field into an external session is the same egress with extra
  steps. What an external lane may be, and that switching is the owner's call, stays [README.md](README.md) §3's.
- **Which doc sits at which floor is the field's own content — derive it, never re-type it** (§2): a list of
  filenames in prose is exactly the copy that drifts when a doc is retagged. Read the declarations instead,
  e.g. `rg -l '^sensitivity: personal' docs/` and the same for `secret-bearing`; what matches neither is
  `infra`. A doc carrying no `sensitivity:` line is therefore `infra` — unprotected rather than protected by
  accident, which is why a missing field is a gap to close and never a silent exemption.

---

*This file states current conventions only — its own change history is `git log`. The owning docs above remain authoritative.*
