// audit-orchestrator.js — parent workflow for the 2026-08-29 full-repository audit.
// Sibling of agents-workflow.js / audit-workflow.js (those are pinned to a different worktree).
// This orchestrator runs from /home/domen/source/homelab-wt-20260829-152521
// (session/audit-orchestrator-20260829-152521) and launches 5 parallel audit lanes;
// each lane gets its OWN worktree via worktree: true (one writer per worktree).
// After all lanes complete, the parent aggregates the 5 track reports into
// reports/full-audit-2026-08-29.md and .json inside THIS orchestrator worktree.

const ORCHESTRATOR_BRANCH = 'session/audit-orchestrator-20260829-152521';
const ORCHESTRATOR_PATH = '/home/domen/source/homelab-wt-20260829-152521';
const AUDIT_DATE = '2026-08-29';
const AUDIT_COMMIT = 'c9baf09';

// Shared lane-task preamble (every lane gets this + a track-specific tail).
const PREAMBLE = `
You are an audit lane in the Kogler Homelab repo (audit ${AUDIT_DATE}, commit ${AUDIT_COMMIT}).
ENV: debian WSL ext4 · bash · YOU HAVE YOUR OWN WORKTREE (one writer per worktree, audit.md §3b).
You are read-only: do NOT mutate IaC / docs / scripts, do NOT git commit in your own worktree.
You may ONLY write the two audit artifacts listed below into your worktree's reports/ dir.

MANDATORY PRIOR ART (read FIRST, before any new finding):
- reports/audit-analysis.md — AUD-01..13 (all done) — do NOT report these as new findings; tag any
  similar pattern as known-resolved:AUD-XX.
- changelog.md — recent (last 20 entries) — do NOT re-open decided items; the re-decide ban is
  binding (CONVENTIONS §4, audit.md §0).
- brainstorming/audit-prompt.md (the old Qwen audit) — note any items relevant to your track.
- audit.md §0-§2 + your track section — the binding scope; do NOT re-decide settled audit rules.

WRITE EXACTLY ONE ARTIFACT PAIR in YOUR worktree:
  reports/audit-track-<TR>.md    (human-readable findings + verified_ok + questions)
  reports/audit-track-<TR>.json  (structured findings[], verified_ok[], questions[],
                                  false_positives[], deduplication_keys[])

FINDINGS SCHEMA (JSON):
  - id: "AUD-<TR>-<n>"
  - severity: "High|Med|Low"
  - status: "OPEN|OK|OBSOLETE|NOTE|FALSE_POSITIVE"
  - evidence: { type: "grep|journal|live|diff|validator", file, line, command, output_snippet }
  - deduplication_key: "<SSOT_file>:<key>"   # e.g. "group_vars/vps.yml:docker_services.crowdsec.enabled"
  - proposed_fix: "bounded, points to owning doc/SSOT"
  - false_positive_rationale: "..."         # only if status=FALSE_POSITIVE

DRIFT CLASSIFICATION (audit.md §1.5 — binding):
  Use one of: SSOT_Conflict | Liveness_Mismatch | Secret_Reference_Broken |
              Enabled_Not_Converged | Validator_Gap | Orphan_Doc_Script | Cosmetic_Stale_Text

SECRETS: item NAMES / lengths / tails only, NEVER values.
  \`op item get --reveal\` is FORBIDDEN. Use --format=json and extract \`.value | length\` only.
  \`op\` call concurrency budget: ≤6 reads, ≤4-6 writes per minute. The Live lane is read-only.

RETURN: your findings summary as final output (≤3k tokens) — the parent will read the artifact
files in your worktree, not parse your output text.

`;

// Track-specific task tails (concise, lane-distinct, not clones).

const TASK_A = PREAMBLE + `
YOUR TRACK: A — DOCS (Track A from audit.md §2.1).
SCOPE: docs/ + the doc map (docs/index.md) + the manual/ family guide.
SCOPE LIMITS: do NOT touch IaC, scripts, or compose templates.
SOURCE SEAM: docs/index.md (dispatcher) + deployment-journal.md (liveness SSOT) +
             deployment-tasks.md (deploy-gated checklists) + rack-connections.json (IP SSOT).
OWNING DOCS for spot-checks (sample 6+ facts each against the SSOT it cites):
  - docs/deployment-*.md (compose, ansible, oidc, secrets, preseed, renovate, ai-stack-secrets)
  - docs/network-*.md (vlans, dns, vpn, ops)
  - docs/services-*.md (matrix, traefik, authentik, finance, ai, office)
  - docs/observability.md
  - docs/backup.md
  - docs/security.md
  - docs/smart-home*.md
  - docs/hardware-*.md
  - docs/storage.md
CHECKS (audit.md §2.1):
  A.1 Map completeness: every docs/*.md reachable from docs/index.md and vice-versa; status
       banners (🟢 / ⏳ / ✅) cross-checked vs deployment-journal.md + deployment-tasks.md per
       README §2 (banners are hints, not proof). List every banner that says "not live" for
       something the journal shows live (and the reverse).
  A.2 Link integrity: relative .md links resolve; anchors exist; no link to a deleted/moved file
       (\`git log --diff-filter=D --name-only -- 'docs/*.md' | head -50\` for recently removed docs).
  A.3 SSOT discipline: no IP literals outside network-addresses-generated.md / IaC; no secret
       values; no *-generated.md hand-edits (\`git log -p --follow docs/network-addresses-generated.md\`
       — should be renderer-only); no stale "TODO: define service" placeholder language.
  A.4 Docs-vs-IaC parity: for the 8 hottest docs above, spot-check ≥6 concrete facts each
       (service names, subdomains, image versions, ports, hostnames, addresses) against
       group_vars/*.yml, host_vars/*.yml, rack-connections.json. Sample-don't-exhaust.
  A.5 docs/manual/: status fields (\`status: wip\`?), file count vs manual/README.md index,
       language consistent (Slovenian), no technical secrets.
  A.6 Generated-doc accuracy: network-addresses-generated.md IPs match rack-connections.json
       + host_vars/*.yml ansible_host for all 6 hosts (oldsrv/nas/pi/router/switch/vps).
       Spot-check hardware-topology.md and network-topology.md against rack-connections.json.

Drift types to watch: SSOT_Conflict (doc value vs IaC), Liveness_Mismatch (banner vs journal),
Orphan_Doc_Script (file not in map), Cosmetic_Stale_Text (TODO/FIXME placeholders).

`;

const TASK_B = PREAMBLE + `
YOUR TRACK: B — IaC (Ansible) consistency & health (Track B from audit.md §2.2).
SCOPE: IaC/ (Ansible) — inventory, playbooks, roles, group_vars, host_vars, templates.
SCOPE LIMITS: do NOT mutate. Do NOT run \`ansible-playbook\` against live. --check --diff is
              read-only and IS allowed for drift detection (audit.md §3 / B.8).
SOURCE SEAM: IaC/inventory.ini + IaC/group_vars/* + IaC/host_vars/* + IaC/playbooks/*.
OWNING DOCS: docs/deployment-ansible.md, docs/deployment-compose.md, docs/services.md.
CHECKS (audit.md §2.2):
  B.1 Inventory ↔ group_vars ↔ host_vars ↔ playbooks: every host in inventory.ini has a
       host_vars file with an ansible_host; every playbook's host pattern matches the
       inventory groups; no dead/duplicate vars; group_vars/all/ vs per-group precedence sane.
  B.2 Role health: each of the 19 roles — exists under IaC/roles/, referenced by a playbook,
       defaults/ + tasks/ + handlers/ (+ templates/) shaped, no orphan role, no role that a
       playbook references but is missing. requirements.yml collections resolve (they are
       installed in ~/ansible-venv).
  B.3 docker_services registry ↔ templates ↔ vault: every enabled: true entry in
       group_vars/{vps,home_servers}.yml has a template_dir that exists under
       IaC/templates/docker_services/; every template dir has a docker-compose.yml.j2; every
       _template_vault_items / vault[...] reference resolves to a 1P item or a glue-seeded
       item (re-run bash scripts/check-vault-items.sh --strict for the MISSING list; exclude
       documented glue items). Cross-check service list vs docs/services.md catalog +
       docs/network-addresses-generated.md.
  B.4 Compose template rules (docs/deployment-compose.md): external networks, Traefik label
       conventions, no host-net/privileged port binds unless documented, pins (_version
       vars, no bare latest), the \`| replace('$','$$')\` compose-escaping rule (HD-270) applied
       on every vault-value expr, no \`default('')\` anywhere in templates/group_vars
       (fail-loud rule HD-65/HD-91).
       HD-270 Escape Verification: \`grep -rn 'vault\\\\[' IaC/templates/docker_services/ -A1 --include='*.j2'\`
       — every occurrence must have \`| replace('$','$$')\` OR be in a context where escaping
       is not needed (document why in your finding).
  B.5 Playbook tag/surgical hygiene (docs/deployment-ansible.md §Tags & surgical): every
       playbook's role tags declared; docker_services_scope semantics not violated; the rare
       \`base\` tier additive (not a skip-default); nothing renders/updates off-path.
  B.6 IaC ↔ docs parity: the hot IaC values (subdomains, ports, image pins, IPs) match the
       owning docs; where they diverge, one is stale — the audit REPORT says which direction.
  B.7 Convergence verification: for every enabled: true in
       group_vars/{vps,home_servers}.yml, verify:
         - A deployment-journal.md entry exists with "converged"/"verified"/"deployed"
           language for that service.
         - The corresponding deployment-tasks.md phase checklist has the service ticked (✅).
         - If missing → finding AUD-B-<n> High: "Service X enabled but no convergence evidence".
  B.8 Ansible idempotency check: run
         \`ansible-playbook -i IaC/inventory.ini IaC/playbooks/site.yml --check --diff --limit vps\`
       — report any "changed" tasks that should be idempotent. These indicate config drift
       between IaC and live state. Note: ansible-run.sh may need to set ANSIBLE_CONFIG and
       ANSIBLE_ROLES_PATH; the script handles it.

Drift types: SSOT_Conflict (group_vars value vs template), Secret_Reference_Broken
(vault ref points nowhere), Enabled_Not_Converged (no journal+checklist), Validator_Gap.

`;

const TASK_C = PREAMBLE + `
YOUR TRACK: C — Scripts & tooling consistency (Track C from audit.md §2.3).
SCOPE: scripts/ + scripts/README.md (registry) + scripts/validate-all.sh (gate).
SCOPE LIMITS: do NOT mutate. Smoke-tests (\`bash -n\`, \`python3 -m py_compile\`) ARE allowed
              and expected (audit.md §C.1, C.3).
SOURCE SEAM: scripts/README.md (registry) + scripts/validate-all.sh (gate).
OWNING DOCS: CONVENTIONS §4 (Validation gate), §6 (worktree/signing), §8.2 (generated docs).
CHECKS (audit.md §2.3):
  C.1 Registry vs filesystem: every file in scripts/ is in scripts/README.md (and vice-versa,
       cross-check \`git ls-files scripts/\`); portability status table matches reality (each
       script portable per its shebang + a \`bash -n\` / \`python3 -m py_compile\` smoke on the
       worktree). DO NOT MUTATE: smoke-tests read-only, just report failures.
  C.2 Gate exercise: \`bash scripts/validate-all.sh\` from the worktree — must end green; note
       any validator that does NOT actually run (silent skip) or runs but exits 0 while
       reporting an error. Time the gate end-to-end (informational).
  C.3 Validator coverage: do the validators actually catch the classes they claim? Sample: in
       a SCRATCH file under your worktree's reports/_scratch/ (NEVER in templates/group_vars
       itself), introduce a deliberate \`default('')\` or bare \`latest\`, see if the gate fails
       when you run validate-all.sh with that scratch present. Then DELETE the scratch
       (you have a clean worktree to keep). Report coverage gaps.
       Validator Effectiveness Scoring (per validator in validate-all.sh):
         - catches_injected_fault (Y/N)
         - false_positive_rate (0-3)   0=never, 1=rare, 2=occasional, 3=frequent
         - runtime_ms                   (informational)
  C.4 Deploy tooling: provision-secrets.py catalog == docs/deployment-secrets.md generated-
       item list; provision-vault.sh / op-vault-export.py / check-vault-items.sh contracts
       match scripts/README.md; ansible-run.sh / guard-session.sh / git-bootstrap.sh match
       the CONVENTIONS §6/§8 rules; next-hd.sh returns max(HD)+1.
  C.5 Dead/orphan scripts: any script not referenced by the gate/README/owning docs → propose
       retire/move (A3 style: only with a decision, never silent).

Drift types: Orphan_Doc_Script (script not in registry), Validator_Gap (gate misses a class),
Cosmetic_Stale_Text (stale status row in scripts/README).

`;

const TASK_D = PREAMBLE + `
YOUR TRACK: D — Cross-cutting conformance (sample-based) (Track D from audit.md §2.4).
SCOPE: secret hygiene, lifecycle conformance, service-onboarding, decision-log alignment.
SCOPE LIMITS: do NOT mutate. Do NOT read secret VALUES.
SOURCE SEAM: todo.md (open HD rows) + changelog.md (decision log) + CONVENTIONS.md (§5 onboarding).
OWNING DOCS: CONVENTIONS.md, todo.md, changelog.md, deployment-tasks.md.
CHECKS (audit.md §2.4):
  D.1 Secret hygiene: \`bash scripts/check-vault-name.py\` + \`validate-secrets.py\` green on
       the worktree; a human grep for the B5 placeholder tokens + any raw \`password:\` /
       \`token:\` literal in group_vars/templates. Note: secrets live in IaC/, not in repo root.
  D.2 Lifecycle conformance: open HD rows map to owning docs; ⏳ tails exist only where
       deployment-tasks.md has a matching deploy-gated checklist; no fully-done row still
       living in todo (should be changelog-only); no row whose ⏳ is stale vs the journal.
  D.3 Service-onboarding (CONVENTIONS §5): for a sample of 3 enabled services (suggest:
       crowdsec-web-ui (recent on-board), traefik (core), renovate (still-⏳)) — walk the
       10-step checklist and report which steps are done/gapped.
       Onboarding Rubric (per service):
         | Step | Required? | Evidence | Status (✅/⚠️/❌/N/A) |
         | 1. Service catalog entry  | Y/N | file:line | |
         | 2. Vault items created    | Y/N | 1P item name | |
         | 3. Compose template       | Y/N | template dir | |
         | 4. group_vars entry       | Y/N | group_vars file:line | |
         | 5. DNS/TLS configured     | Y/N | zone + cert | |
         | 6. Observability (metrics/logs) | Y/N | dashboard/alert | |
         | 7. Backup policy          | Y/N | borg/restic config | |
         | 8. Deployment journal entry | Y/N | journal date | |
         | 9. deployment-tasks.md checklist | Y/N | phase item | |
         | 10. Doc status banner updated | Y/N | doc file:line | |
  D.4 Decision-log alignment: no open decision in todo.md §1 that changelog.md already
       resolved; no decision re-argued in a doc without a changelog row.
  D.5 False Positive Log: for any finding that LOOKS like drift but is intentional
       (e.g. a service enabled:true but deliberately not converged yet), record:
         AUD-FP-<n> | finding | why it's intentional | owner confirmation needed?

Drift types: SSOT_Conflict (decisions in two places), Validator_Gap, Cosmetic_Stale_Text.

`;

const TASK_E = PREAMBLE + `
YOUR TRACK: E — Live liveness cross-checks (audit.md §3 — Live cross-checks).
SCOPE: read-only probes against the live VPS (\`ssh ansible-admin@vps.kogler.si\`).
SCOPE LIMITS (BINDING): you ARE read-only. NO \`ansible-run.sh\` converge. NO \`op item edit\`.
                     Any env==vault check prints LENGTHS/TAILS only (CONVENTIONS §2
                     secret-output hygiene).
SOURCE SEAM: live VPS state vs IaC group_vars enabled: sets vs docs/services.md.
OWNING DOCS: docs/services.md, docs/services-vps.md, docs/deployment-ansible.md, docs/observability.md.
CHECKS (audit.md §3, sampled):
  E.1 \`docker ps\` (via ssh ansible-admin@vps.kogler.si) — enabled services Up (align with
       group_vars enabled: sets + docs/services.md). One ps -a is enough; report count
       mismatches.
  E.2 \`docker inspect <container> --format '{{.Config.Env}}'\` env LENGTH spot-checks
       (3 services: traefik, authentik, crowdsec). For each, compare env var LENGTHS
       against \`op item get <item> --fields <field> --format=json | jq '.value | length'\`.
       Report length mismatches as High. Never print VALUES.
  E.3 \`headscale policy get\` + \`nodes list\` (tailnet edge role matches docs).
  E.4 \`curl -sI https://<service>.kogler.si\` for 2-4 representative services
       (suggest: kogler.si root, sso.kogler.si, git.kogler.si, logs.kogler.si) — expect
       200/302 per the route tier docs. Note any 404/5xx as Live_Liveness_Mismatch.
  E.5 \`op service-account ratelimit\` — sanity (we are read-only, just confirm budget headroom).
  E.6 Ansible drift detection (read-only): \`bash scripts/ansible-run.sh site.yml --check --diff --limit vps\`
       (or directly \`ansible-playbook -i IaC/inventory.ini IaC/playbooks/site.yml --check --diff --limit vps\`
       with the right env) — report any "changed" tasks. DO NOT APPLY.
  E.7 Certificate expiry: for the 2-4 services from E.4, check
       \`echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | openssl x509 -noout -dates\`.
       Flag < 30 days.
  E.8 DNS/Traefik route parity: for each enabled:true service with a subdomain, verify DNS
       resolves + Traefik router exists (via Traefik API or docker exec traefik). Sample
       2-4 services; do not exhaust.
  E.9 Observability stack health: verify Prometheus targets Up (1-2 samples), Loki ingesting
       (1 stream sample), Grafana dashboards loading (1 dashboard).
  E.10 Backup/restore validation: \`ssh ansible-admin@vps.kogler.si\` — check borg/restic repos
       exist + last backup timestamp < 24h. Test restore of one file (read-only — e.g.
       \`borg extract --dry-run\` or \`restic restore --target /tmp/audit-restore-<n>\`).
  E.11 Hardware health: \`ssh nas.kogler.si\` / \`ssh oldsrv.kogler.si\` / \`ssh pi.kogler.si\`
       (only if provisioned) — \`smartctl -a /dev/sda\` sample, \`sensors\` sample,
       \`apcaccess status\` (UPS).

LIVE_PROBE_HYGIENE: never log VALUES. Print LENGTHS/TAILS/COUNTS. If a probe times out
(ssh, https, dns), report it as a Live_Probe_Unreachable finding and move on.

Drift types: Liveness_Mismatch (live != authored), Secret_Reference_Broken (env length
mismatch), Enabled_Not_Converged (service enabled but container not Up).

`;

const lanes = [
  {
    key: 'audit-docs',
    agent: 'worker',
    task: TASK_A,
    output: 'reports/audit-track-A-docs.md',
    timeoutMs: 1800000,
    worktree: true,
  },
  {
    key: 'audit-iac',
    agent: 'worker',
    task: TASK_B,
    output: 'reports/audit-track-B-iac.md',
    timeoutMs: 1800000,
    worktree: true,
  },
  {
    key: 'audit-scripts',
    agent: 'worker',
    task: TASK_C,
    output: 'reports/audit-track-C-scripts.md',
    timeoutMs: 1800000,
    worktree: true,
  },
  {
    key: 'audit-conformance',
    agent: 'worker',
    task: TASK_D,
    output: 'reports/audit-track-D-conformance.md',
    timeoutMs: 1800000,
    worktree: true,
  },
  {
    key: 'audit-live',
    agent: 'worker',
    task: TASK_E,
    output: 'reports/audit-track-E-live.md',
    timeoutMs: 1800000,
    worktree: true,
  },
];

// Launch all 5 lanes in parallel; each gets its OWN worktree via worktree:true.
// The runner branches each lane's worktree from HEAD (commit ${AUDIT_COMMIT}) on a
// per-lane branch, isolated from this orchestrator's worktree and from the other
// instance's worktree (homelab-wt-2026-08-29-1652).

const results = await runs.all(lanes);
return results.map(r => ({
  key: r.key,
  status: r.status,
  artifactPaths: r.artifactPaths,
  outputReference: r.outputReference,
  runId: r.runId,
}));
