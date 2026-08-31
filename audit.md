# audit.md — Full Repository Audit Prompt (Session: docs / IaC / scripts)

> **Role:** Executable audit prompt for the next session (handoff #33). A self-contained,
> self-driving full-repository audit of `docs/`, `IaC/` (Ansible), and `scripts/` against the
> canonical system and the **live VPS state**. The output is an audit report + a bounded set of
> actionable follow-ups — the session does NOT fix everything; it REOPENS nothing already settled.
> **Linked from:** [prompt.md](prompt.md) (handoff #32) · [README.md](README.md) §2 (live-vs-authored check) · [CONVENTIONS.md](CONVENTIONS.md)

---

## 0. Purpose & scope

Audit the **current** repository (2026-08-29, main `969597d`) — NOT the 2025-08 Qwen audit.
The Qwen audits (61 KOPS findings + architecture audit + low-fruits) were fully reconciled into
the canonical system on 2025-08-16 (`reports/audit-analysis.md`, AUD-01..13 all `(done)`), and the
repo has since: gone live on the VPS (Phase 1), grown to 33 enabled services, 62 docs, 31 scripts,
20 roles, 58 compose templates. This audit measures **drift between authored state and reality** —
the README §2 three-step check is the liveness SSOT (`deployment-tasks.md` ticks + owning-doc ✅ status lines + `git log`; the changelog/journal were frozen → `reports/`, archive-only)
⏳ checklists > doc banners as hints only).

**The session starts by reading (in order):** `README.md` §0-2 → `CONVENTIONS.md` §0-8 →
`docs/index.md` → `todo.md` → `reports/changelog.md` (frozen archive) → `reports/deployment-journal.md` (frozen) → owning docs (live)
tail) → `deployment-tasks.md`. Then it follows the plan below. It does NOT bulk-read or
random-edit; it audits **by checklists drawn from the canonical docs** and reports only genuine
drift, never cosmetic noise.

**Non-negotiables (binding, from `CONVENTIONS.md`):**
- **Session discipline:** fresh worktree `../homelab-wt-<date>-<HHMM>` (branch `session/…`) BEFORE any edit; `scripts/guard-session.sh` refuses primary+main edits; `validate-all.sh` must end green before commit; merge back only green, signed (`ssh-add ~/.ssh/github_signing ~/.ssh/github_auth` if fresh shell).
- **SSOT direction:** values live in IaC (`group_vars/*.yml`, `host_vars/*.yml`, `rack-connections.json`); generated `*-generated.md` are render views — never hand-edit; scripts never parse generated MD.
- **Secrets:** 1Password `Homelab-ansible` item.field refs only, never literal; fail-loud (no `default('')`); never write a secret VALUE to stdout/chat/git/transcripts (lengths/tails/hashes only).
- **Append-only discipline:** decisions/evidence live in the owning docs + `*-rejected.md` logs; the frozen `reports/changelog.md` + `reports/deployment-journal.md` are never rewritten.
- **Derived-values ban:** next-free HD = `bash scripts/next-hd.sh` (from `todo.md` + `docs/**`; changelog archive excluded, + git-history) at write time — never type a literal.
- **Language/links:** English (docs/manual Slovak for family only); relative `.md` links; every doc starts with `> **Role:**` / `> **Linked from:**`.
- **Planning-phase styling:** substantive content-level edits only — no cosmetic/ASCII-alignment/wording-polish passes (park those, don't ship them).

---

## 1.5 Drift Definition (binding for all tracks)

| Drift Type | Example | Severity | Evidence Required |
|------------|---------|----------|-------------------|
| **SSOT Conflict** | `group_vars/vps.yml` port 8080 vs `docs/services.md` port 9090 | High | Both file:line refs |
| **Liveness Mismatch** | Doc banner `⏳ deploy-gated` but owning-doc ✅ + `deployment-tasks.md` tick show `✅ Live since 2026-08-22` | Medium | Owning-doc line + tick date |
| **Secret Reference Broken** | Template `vault[item.field]` but 1P item missing/renamed | High | `check-vault-items.sh --strict` output |
| **Enabled Not Converged** | `enabled: true` in group_vars, no owning-doc ✅ / ledger tick for converge | High | Owning-doc status + `git log` |
| **Validator Gap** | Injected `default('')` not caught by `validate-all.sh` | High | Validator name + injected fault |
| **Orphan Doc/Script** | File exists but not in `docs/index.md` or `scripts/README.md` | Low | `git ls-files` vs registry diff |
| **Cosmetic/Stale Text** | "TODO: define service" in a Live doc | Low | File:line + context |

---

## 1. Audit inputs (read-only ground truth)

| Input | Role | How to read |
|---|---|---|
| `todo.md` | Backlog + open decisions (HD-XX) | Every open row is a **commitment** — the audit must not silently ignore or re-decide it; the audit REPORT may surface a row as stale/needs-update, but must not mutate it without a journal/log decision. |
| `reports/changelog.md` | Frozen decision archive (pre-2026-09-01) | Re-decide ban: historical decisions live here; any claim that contradicts a changelog row is a **re-opened decision** → flag it, don't fix by fiat. |
| `reports/deployment-journal.md` | Frozen liveness/execution archive | Historical "actually live?" evidence — read for context; never edit (archived). |
| `deployment-tasks.md` | Phase-build runbook + deploy-gated checklists | Cross-check every doc status banner against the phase checklists. |
| `docs/index.md` | Document map + dispatcher | The audit verifies every doc is reachable from here (and vice-versa) + every map row resolves. |
| `scripts/README.md` | Script registry | The audit verifies registry accuracy (scripts exist, portability status matches, no orphan/undocumented scripts). |
| `CONVENTIONS.md` | Rule index (§0-8) | The audit samples conformance of docs/IaC/scripts to the rules (naming, secrets, SSOT, lifecycle, onboarding §5). |
| `rack-connections.json` | Physical/topology SSOT | Cross-check for all IP/hostname claims in docs/IaC; source of truth for `network-addresses-generated.md`. |
| LIVE VPS | `ssh ansible-admin@vps.kogler.si` (read-only mostly) | Only for liveness cross-checks (containers Up, watchers, config==vault lengths). No convergent mutations unless a checklist explicitly says so. |

---

## 2. Audit tracks (work each, report per track)

### Track A — Docs consistency & liveness (docs/)
1. **Map completeness** (`scripts/check_doc_map.py` is in the gate; the audit adds a HUMAN pass):
   - Every `docs/*.md` reachable from `docs/index.md` and vice-versa; no orphan doc, no doc the map doesn't dispatch.
   - Every status banner (`🟢 IaC done, not yet live — ⏳ deploy-gated` / `✅ Live since …`) cross-checked against owning-doc ✅ + `deployment-tasks.md` ticks per README §2 (banners are hints, not proof). List every banner that says "not live" for something the owning docs/ticks show live (and the reverse).
2. **Link integrity** beyond the gate: relative `.md` links that resolve; anchors that exist; no link to a deleted/moved file (`git log --diff-filter=D` for recently removed docs).
3. **SSOT discipline**: no IP literals outside `network-addresses-generated.md`/IaC (gate checks); no secret values; no `*-generated.md` hand-edits (git-blame them); no stale "TODO: define service" placeholder language.
4. **Docs-vs-IaC parity**: for the hot owning docs (`deployment-*`, `network-*`, `services-*`, `observability`, `backup`, `security`, `smart-home*`, `hardware-*`, `storage`): each value/fact the doc quotes (service names, subdomains, image versions, ports, hostnames, addresses) must match the SSOT it cites (`group_vars/*.yml`, `host_vars/*.yml`). Sample-don't-exhaust: pick the 8 hottest docs; for each, spot-check ≥6 concrete facts.
5. **Manual/ (family guides)**: `docs/manual/` — status fields (`status: wip`?), file count vs `manual/README.md` index, language consistent with its own spec, no technical secrets.
6. **Generated-doc accuracy**: verify `network-addresses-generated.md` IPs match `rack-connections.json` + `host_vars/*.yml` `ansible_host` for all 6 hosts. Also spot-check `docs/hardware-topology.md` and `docs/network-topology.md` against `rack-connections.json`.

### Track B — IaC (Ansible) consistency & health
1. **Inventory ↔ group_vars ↔ host_vars ↔ playbooks**: every host in `inventory.ini` has a host_vars file with an `ansible_host`; every playbook's host pattern matches the inventory groups; no dead/duplicate vars; `group_vars/all/` vs per-group precedence sane.
2. **Role health**: each of the 20 roles — exists under `roles/`, referenced by a playbook, `defaults/`+`tasks/`+`handlers/`(+`templates/`) shaped, no orphan role, no role that a playbook references but is missing. `requirements.yml` collections resolve (they're installed in `~/ansible-venv`).
3. **docker_services registry ↔ templates ↔ vault**: every `enabled: true` entry in `group_vars/{vps,home_servers}.yml` has a `template_dir` that exists under `templates/docker_services/`; every template dir has a `docker-compose.yml.j2`; every `_template_vault_items` / `vault[...]` reference resolves to a 1P item or a glue-seeded item (re-run `bash scripts/check-vault-items.sh --strict` on the live tree for the MISSING list; exclude the documented glue items). Cross-check service list vs `docs/services.md` catalog + `docs/network-addresses-generated.md`.
4. **Compose template rules** (`docs/deployment-compose.md`): external networks, Traefik label conventions, no host-net/privileged port binds unless documented, pins (`_version` vars, no bare `latest`), the `| replace('$','$$')` compose-escaping rule (HD-270) applied on every vault-value expr, no `default('')` **anywhere in templates/group_vars** (fail-loud rule HD-65/HD-91).
   **HD-270 Escape Verification**: grep for `vault\[` in all `templates/docker_services/**/*.j2` — every occurrence must have `| replace('$','$$')` or be in a context where escaping is not needed (document why).
5. **Playbook tag/surgical hygiene** (`docs/deployment-ansible.md` §Tags & surgical): every playbook's role tags are declared; `docker_services_scope` semantics not violated; the rare `base` tier additive (not a skip-default); nothing renders/updates off-path.
6. **IaC ↔ docs parity**: the hot IaC values (subdomains, ports, image pins, IPs) match the owning docs; where they diverge, one is stale — the audit REPORT says which direction.
7. **Convergence verification**: for every `enabled: true` in `group_vars/{vps,home_servers}.yml`, verify:
   - The owning doc has a ✅ status line / the deployment-tasks.md phase checklist has the service ticked (✅) with "converged"/"verified"/"deployed" evidence.
   - The corresponding `deployment-tasks.md` phase checklist has the service ticked (✅).
   - If missing → finding `AUD-B-<n>` High: "Service X enabled but no convergence evidence".
8. **Ansible idempotency check**: run `ansible-playbook -i inventory.ini site.yml --check --diff --limit vps` (and per-playbook for home_servers when provisioned) — report any "changed" tasks that should be idempotent. These indicate config drift between IaC and live state.

### Track C — Scripts & tooling consistency (scripts/)
1. **Registry vs filesystem**: every file in `scripts/` is in `scripts/README.md` (and vice-versa, cross-check `git ls-files scripts/`); portability status table matches reality (each script portable per its shebang + a `bash -n`/`python3 -m py_compile` smoke on the worktree).
2. **Gate exercise**: `bash scripts/validate-all.sh` from the worktree — must end green; note any validator that does NOT actually run (silent skip) or runs but exits 0 while reporting an error.
3. **Validator coverage**: do the validators actually catch the classes they claim (sample: introduce a deliberate `default('')` or bare `latest` in a scratch template, see if the gate fails)? Report coverage gaps.
   **Validator Effectiveness Scoring**: for each validator in `validate-all.sh`, record:
   - `catches_injected_fault (Y/N)` — test with a deliberate fault in a scratch file
   - `false_positive_rate (0-3)` — 0=never, 1=rare, 2=occasional, 3=frequent
   - `runtime_ms` — execution time
   This builds a validator health dashboard over time.
4. **Deploy tooling**: `provision-secrets.py` catalog == `docs/deployment-secrets.md` generated-item list; `provision-vault.sh`/`op-vault-export.py`/`check-vault-items.sh` contracts match `scripts/README.md`; `ansible-run.sh`/`guard-session.sh`/`git-bootstrap.sh` match the CONVENTIONS §6/§8 rules; `next-hd.sh` returns max(HD)+1 (used for any new HD).
5. **Dead/orphan scripts**: any script not referenced by the gate/README/owning docs (e.g. leftover `collect-*.ps1` siblings, superseded helpers) → propose retire/move (A3 style: only with a decision, never silent).

### Track D — Cross-cutting conformance (sample-based)
1. **Secret hygiene**: `bash scripts/check-vault-name.py` + `validate-secrets.py` green on the worktree; a human grep for the B5 placeholder tokens + any raw `password:`/`token:` literal in group_vars/templates (gate checks; the audit adds a second human layer).
2. **Lifecycle conformance**: open HD rows map to owning docs; `⏳` tails exist only where `deployment-tasks.md` has a matching deploy-gated checklist; no fully-done row still living in todo (should be owning-doc + git-history record); no row whose ⏳ is stale vs the owning-doc ✅ lines.
3. **Service-onboarding (CONVENTIONS §5)**: for a sample of 3 enabled services (e.g. a recent on-board like crowdsec-web-ui, a core like traefik/authentik, and one still-⏳ like renovate) — walk the 10-step checklist and report which steps are done/gapped.
   **Onboarding Rubric** (per service):
   | Step | Required? | Evidence | Status (✅/⚠️/❌/N/A) |
   |------|-----------|----------|------------------------|
   | 1. Service catalog entry | Y/N | file:line | |
   | 2. Vault items created | Y/N | 1P item name | |
   | 3. Compose template | Y/N | template dir | |
   | 4. group_vars entry | Y/N | group_vars file:line | |
   | 5. DNS/TLS configured | Y/N | zone + cert | |
   | 6. Observability (metrics/logs) | Y/N | dashboard/alert | |
   | 7. Backup policy | Y/N | borg/restic config | |
   | 8. Deployment journal entry | Y/N | journal date | |
   | 9. deployment-tasks.md checklist | Y/N | phase item | |
   | 10. Doc status banner updated | Y/N | doc file:line | |
4. **Decision-log alignment**: no open decision in `todo.md` §1 that the owning doc / `*-rejected.md` / frozen changelog already resolved; no decision re-argued in a doc without an owning-doc record.
5. **False Positive Log**: for any finding that *looks* like drift but is intentional (e.g., a service `enabled:true` but deliberately not converged yet), record:
   `AUD-FP-<n> | finding | why it's intentional | owner confirmation needed?`
   This prevents re-flagging known intentional state in future audits.

---

## 3. Live cross-checks (read-only, small)

Sampled against the live VPS (only where a report claim depends on it):
- `docker ps` — enabled services Up (align with `group_vars` `enabled:` sets + `docs/services.md`).
- A couple of `docker inspect` env==vault length/tail spot-checks (secrets policy: lengths/tails only).
- `headscale policy get` + `nodes list` (tailnet edge role matches docs).
- `curl -sI https://<service>.kogler.si` for a representative subset (2-4) — expect 200/302 per the route tier docs.
- `op service-account ratelimit` — sanity (never exceed the ≤6-read / ≤4-6-write concurrency budget when the audit DOES occasionally run a scoped converge).
- **Ansible drift detection (read-only)**: `ansible-playbook -i inventory.ini site.yml --check --diff --limit vps` — report any "changed" tasks. These indicate config drift between IaC and live state. **Do not apply**.
- **Secret value spot-check**: For 3 enabled services (traefik, authentik, crowdsec), compare `docker inspect <container> --format '{{.Config.Env}}'` env var *lengths* against `op item get <item> --fields <field> --format=json | jq '.value | length'`. Report length mismatches as High.
- **Certificate expiry**: `curl -sI https://<service>.kogler.si` → check `expire` date via `openssl s_client -connect <host>:443 -servername <host> < /dev/null 2>/dev/null | openssl x509 -noout -dates`. Flag < 30 days.
- **DNS/Traefik route parity**: for each `enabled:true` service with a subdomain, verify DNS resolves + Traefik router exists + TLS cert valid.
- **Observability stack health**: verify Prometheus targets Up, Loki ingesting, Grafana dashboards loading, Alertmanager routes firing.
- **Backup/restore validation**: verify `borg`/`restic` repos exist, last backup timestamp < 24h, test restore of one file (read-only).
- **Hardware health (SMART, temps, UPS)**: `smartctl -a`, `sensors`, `apcaccess` on `nas`/`oldsrv`/`pi` (if provisioned).
- Report live-vs-authored mismatches as findings, NOT as bootstrapping mutations.

## 3b. Orchestration model (pi-subagents) — run the audit as parallel lanes

This is a **read-only, parallelizable** audit. Run it with the parent as orchestrator and the
tracks as isolated lanes (see `skills/pi-subagents/SKILL.md` + `references/multi-lane-orchestration.md`):

### Lane board (one writer per lane, `worktree:true` spawn isolation, stable keys)

| Lane | Key | Agent | Scope (reports to) | Isolation |
|---|---|---|---|---|
| **A — Docs** | `audit-docs` | worker | Track A (docs map/liveness/parity/manual) → `reports/audit-track-A-docs.md` | own worktree, read-only |
| **B — IaC** | `audit-iac` | worker | Track B (inventory/roles/registry/compose/parity) → `reports/audit-track-B-iac.md` | own worktree, read-only |
| **C — Scripts** | `audit-scripts` | worker | Track C (registry/gate/coverage/dead) → `reports/audit-track-C-scripts.md` | own worktree, read-only |
| **D — Conformance** | `audit-conformance` | worker | Track D (secrets/lifecycle/onboarding/decisions) → `reports/audit-track-D-conformance.md` | own worktree, read-only |
| **Live — liveness** | `audit-live` | worker | §3 live probes (docker ps / env==vault / headscale / curl / ratelimit) → `reports/audit-track-E-live.md` | own worktree, read-only (NO converges) |

### Launch rules (from `pi-subagents` — binding)
- **One top-level async `workflowScript`** with `runs.all([...])` for the five lanes — do NOT launch
  children from separate top-level calls; the workflow aggregates into an ordered array.
- **Reference workflow file**: `agents-workflow.js` (in repo root) — the canonical pi-subagents workflow script for this audit. Use `workflowScriptPath: "agents-workflow.js"` when launching. This file contains the exact lane definitions, task prompts, and output paths.
- **Each lane gets a lane-specific prompt** (not clones): its own track, its own source seam
  (docs/index for A, group_vars/inventory for B, scripts/README for C, CONVENTIONS for D), its
  own evidence file, and the shared contract below. Prefer **fresh-context** lanes so each starts
  from the audit prompt + repo state, not from each other.
- **Read-only lanes share cwd is fine ONLY if they cannot write** — but because each lane writes a
  report artifact into its own worktree, use `worktree:true` per lane (one writer per worktree).
- **No `toolBudget`/`usageBudget` on the lanes** (mutation-capable workers; default is fine).
- **Parent = orchestrator + final decision-maker**: the parent reads the five track files, merges
  them into `reports/full-audit-2026-08-29.md` (§4 sections A–G), and decides which (if any)
  trivially-safe fixes to apply — never a lane.
- **Live lane (`audit-live`) is read-only by construction**: `docker ps`, `curl`, `headscale policy`,
  `op service-account ratelimit` — NO `ansible-run.sh` converge, no `op item edit`. Any
  env==vault check prints LENGTHS/TAILS only (CONVENTIONS §2 secret-output hygiene).
- **Concurrency budget (scripts/README §Parallel-1P):** keep concurrent `op` calls ≤6 reads,
  ≤4–6 when mutating; the audit is read-mostly — the Live lane may call `op` sparingly and only
  for length/tail; never exceed on a live converge.

### Lane task template (shared contract each lane receives)
```
You are an audit lane in the Kogler Homelab repo (audit 2026-08-29).
ENV: debian WSL ext4 · bash · worktree {lane} (clean, no commits) · read-only.
Read: this audit.md (§0-§2 + your track) + the owning docs it cites + the SSOT it cites.
Scope: ONLY {track}. Do NOT fix files; report findings.

MANDATORY PRIOR ART:
- Read `reports/audit-analysis.md` (AUD-01..13 all done) — do NOT report these as new findings.
- Read the frozen `reports/changelog.md` recent rows — do NOT re-open decided items.
- Note any `brainstorming/audit-prompt.md` items relevant to your track.

Write exactly ONE artifact pair in your worktree:
  reports/audit-{track-suffix}.md    (human-readable)
  reports/audit-{track-suffix}.json  (structured: findings[], verified_ok[], questions[], false_positives[], deduplication_keys[])

Findings schema (JSON):
  - id: "AUD-<track>-<n>"
  - severity: "High|Med|Low"
  - status: "OPEN|OK|OBSOLETE|NOTE|FALSE_POSITIVE"
  - evidence: { type: "grep|journal|live|diff|validator", file, line, command, output_snippet }
  - deduplication_key: "<SSOT_file>:<key>"  # e.g. "group_vars/vps.yml:docker_services.crowdsec.enabled"
  - proposed_fix: "bounded, points to owning doc/SSOT"
  - false_positive_rationale: "..."  # if status=FALSE_POSITIVE

Secrets: item NAMES / lengths / tails only, never values. `op item get --reveal` FORBIDDEN. Use `--format=json` and extract `.value | length` only. No git commit.
Return: your findings summary as final output (<=3k tokens).
```

### Resumability & Quick Mode
- **Checkpoint file**: `.audit-state.json` in the parent worktree, updated after each lane completes:
  ```json
  { "tracks_completed": ["A","B"], "live_checks_done": true, "lanes_launched": ["audit-docs","audit-iac"], "started_at": "2026-08-29T10:00:00Z" }
  ```
- **Quick Mode** (`AUDIT_MODE=quick` env var): runs only Track A.1, B.3, C.2, D.2, and §3 live checks for services in `git diff HEAD~5 -- group_vars/`. Document this in `scripts/README.md` under "Audit helpers".

### After the lanes
1. Parent aggregates the five `reports/audit-track-*.md` into `reports/full-audit-2026-08-29.md`
   (§4 sections A–G) — de-duplicate across lanes, reconcile overlapping findings, assign severity.
2. Parent runs `bash scripts/validate-all.sh` in ITS OWN primary/worktree (must be green) then
   applies ONLY the trivially-safe fixes it decides, each as an explicit HD-<next> row or a
   journal+commit (never a lane).
3. New HD rows use `bash scripts/next-hd.sh`; tag `source: full-audit-2026-08-29`; link owning doc.
4. Update `prompt.md` → #33 (diff-edit) with the audit outcome + next task(s).
---


## 4. Deliverables

Produce in the session worktree (do NOT commit findings inside a service config change). The lanes
(§3b) each write one `reports/audit-track-<X>.md`; the parent aggregates them into the report:

1. **`reports/full-audit-2026-08-29.md`** — the consolidated audit report (aggregated from the lane artifacts + parent synthesis), sections:
   - **A. Docs**: findings per track (map, parity, liveness, manual), each = `AUD-<n>` item: `Status: OPEN | OK | OBSOLETE | NOTE`, evidence (file:line/link), severity (High/Med/Low), proposed fix (bounded, points to owning doc/SSOT).
   - **B. IaC**: findings per track (inventory/roles/registry/compose/parity).
   - **C. Scripts**: findings per track (registry/gate/coverage/dead).
   - **D. Conformance**: lifecycle + onboarding + decision-log findings.
   - **E. Live-liveness**: live-vs-authored mismatch table.
   - **F. Consolidated action plan**: High/Med/Low, each tied to a new HD row (use `scripts/next-hd.sh`) or an existing open HD; **do NOT re-decide** — where a fix contradicts an owning-doc/changelog decision, mark it `needs-owner-decision` with the prior decision cited.
   - **G. Open questions** for the owner (only genuine blockers, not resolved ones).

   **Evidence Standard** (for every finding in sections A–E):
   - `evidence_type`: `grep|journal|live|diff|validator`
   - `command_run`: the exact command that produced the evidence
   - `output_snippet`: ≤200 chars, redacted (lengths/tails only for secrets)
   This makes findings verifiable without re-running the audit.

2. **Machine-readable aggregate**: `reports/full-audit-2026-08-29.json` with schema:
   ```json
   {
     "audit_date": "2026-08-29",
     "commit": "969597d",
     "tracks": { "A": {...}, "B": {...}, "C": {...}, "D": {...}, "E": {...} },
     "consolidated_findings": [ { "id": "AUD-001", "track": "B", "severity": "High", "deduplication_key": "group_vars/vps.yml:docker_services.traefik.enabled", ... } ],
     "action_plan": [ { "hd": "HD-XXX", "title": "...", "severity": "High", "owning_doc": "docs/...", "source": "full-audit-2026-08-29" } ],
     "open_questions": [ ... ]
   }
   ```

3. **A bounded set of follow-up rows** — the session may (with green gate + signed commit + journal entry) fix **trivially-safe** items only (broken relative links, a stale banner whose journal evidence is unambiguous, a README/scripts README registry line, an obviously-dead script reference). Everything else lands as a `todo.md` HD row + a note in the report. **Never** mutate a live service config or a changelog decision without a journal/log entry and (if it touches enabled services) a scoped converge + verify.

4. **Handoff update** — after the audit, update `prompt.md` (diff-edit to #33, per the handoff diff-rule) naming the audit outcomes + the concrete next task(s) the report opens.

**Verify (definition of done):**
- `bash scripts/validate-all.sh` green from the worktree.
- The report exists with all sections A–G, every finding has a Status + severity + evidence.
- Every new HD row uses `scripts/next-hd.sh`, links its owning doc, and carries a `source: full-audit-2026-08-29` tag.
- Any live fix performed was journaled + ticked + committed signed; nothing re-decided silently.
- `git status --short` clean in the primary; worktree merged back green + pushed (or the report is committed and the worktree state is explicit in the handoff).
- Both `reports/full-audit-2026-08-29.md` and `reports/full-audit-2026-08-29.json` exist and are consistent.

---

## 5. Severity Calibration Matrix (reference for all lanes)

| Severity | Criteria | Examples |
|----------|----------|----------|
| **High** | Secret exposed; service down but `enabled:true`; SSOT conflict (two sources disagree on same fact); validator gap that permits secret leak; enabled service not converged | `default('')` in template; vault ref broken; `enabled:true` no journal entry |
| **Med** | Banner stale; link broken; doc/IaC parity drift on non-critical fact; orphan script; cert < 30 days; backup > 24h | Doc says ⏳ but journal ✅; dead script in scripts/ |
| **Low** | Cosmetic; naming inconsistency; missing manual guide status; stale TODO placeholder | ASCII alignment; wording polish |

---

## 6. Security / Secret Handling Hardening

- **Rate limiting**: `op` calls in Live lane MUST use `bash scripts/op-rate-limited.sh` (create if missing) that enforces ≤6 reads / ≤4–6 writes per minute with token bucket.
- **No reveal**: `op item get --reveal` FORBIDDEN in all lanes. Use `--format=json` and extract `.value | length` only.
- **Vault path redaction**: In reports, 1P item names may be included but **vault paths** (e.g., `Homelab-ansible/traefik/acme`) must be redacted to `Homelab-ansible/<service>/<purpose>` unless the finding is specifically about vault structure.

---

## 5. Session workflow reminder (from `README.md` / `CONVENTIONS.md`)

1. `read README.md` (intent-routed) → read mandatory context §2 in order (CONVENTIONS → index → IaC README → todo → owning docs).
2. State environment (`platform-env`): debian (WSL ext4) · bash · `/home/domen/source/homelab` primary; `scripts/ansible-run.sh` for playbooks; `ssh ansible-admin@vps.kogler.si` for live.
3. **Step-0 ritual:** `git status` + fresh worktree `../homelab-wt-<date>-<HHMM>` BEFORE any edit (guard-session enforces).
4. Prior-art sweep (`todo.md`/`changelog.md`/`reports/audit-analysis.md` + `brainstorming/audit-prompt.md` — the old Qwen audit) and REPORT prior art before proposing any new HD row.
5. Update `todo.md` (register the audit as HD-<next> via `scripts/next-hd.sh`), implement, validate green, journal, commit signed, merge back.
6. Close-out per CONVENTIONS §7 (open questions, owning docs, prompt.md #33 diff-edit, manual-unchanged rule, branch-per-session).

---

> **Final note to the executor:** this is an AUDIT, not a refactor. The repo is live (Phase 1 VPS
> running 33 services). The highest-value output is an accurate, evidence-backed drift map —
> which the next working sessions then execute via normal HD/plan/worktree flow. Prefer
> *flagging* over *fixing*; where you do fix, do it the repo's way (SSOT → gate → journal → signed commit).
>
> **This audit produces a *drift map*, not a fix list.** Fixes follow normal HD/plan/worktree flow.
>
> **Quick reference for lanes:**
> - Prior Qwen audits: `reports/audit-analysis.md` (AUD-01..13 all done) — tag any similar pattern as `known-resolved:AUD-XX`.
> - Physical topology SSOT: `rack-connections.json` — cross-check for all IP/hostname claims.
> - HD-270 compose escaping: verify `| replace('$','$$')` on *every* vault expr in templates.
> - Convergence evidence: every `enabled:true` must have journal entry + deployment-tasks.md tick.
> - Quick Mode: `AUDIT_MODE=quick` runs only A.1, B.3, C.2, D.2, and §3 live checks for changed services.