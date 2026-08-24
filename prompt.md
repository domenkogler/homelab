# prompt.md — Deployment Execution Handoff #8 — network-redo offline IaC batch (R-1/R-2/tasks 2/4/5/6/8) merged; HD-166 editor PARTIAL (.docx broken); HD-233/235 from prior session intact

> **Role:** Entry point for the next session. This session ran the **network-redo offline IaC + cleanup batch**
> (Option-A home-server reconciliation R-1, DHCP reservations R-2, switch VLAN coverage task 2, backlog cleanup
> task 4, renovate re-enable task 5, migration-inventory refresh task 6, CAPsMAN-modern rsc task 8) all
> **merged to `main`** via branch `cleanup-netredo-20260824-0958`. It ALSO re-verified the ONLYOFFICE editor
> (HD-166) end-to-end with the owner and found it **PARTIAL — `.txt` works, `.docx` is BROKEN** (top next-session
> item). The prior HD-233 (headplane) + HD-235 (secret-hygiene/YAML conventions) work from Handoff #7 is intact.
> **No live playbook was run this session** (other-session-owned); all changes are IaC/doc-only + read-only probes.
> **Linked from:** [README.md](README.md) §2 · journal: [deployment-journal.md](deployment-journal.md)
> (2026-08-24 Phase 1.5 batch: R-1…R-2/task-2/4/5/6/8 + HD-166 editor finding) · changelog rows HD-03 R1…R8 ·
> todo: HD-207 merged, HD-03 rows trimmed · plan dir `plan/20260824-netredo/`.

---

## 0. Mandatory context (read in this order)

1. [deployment-journal.md](deployment-journal.md) — the **2026-08-24 Phase 1.5 batch**: R-1 (Option-A reconcile),
   task 2 (switch VLAN 20/21), task 8 (CAPsMAN modern rsc), task 6 (inventory unknowns → HMIP-HAP resolved), and the
   **HD-166 editor finding** (`.txt` OK / `.docx` broken). Also the HD-233/235 entries from the prior session.
2. [plan/20260824-netredo/](plan/20260824-netredo/) — the orchestrator plan + `t1-report.md` (the .docx fix path).
3. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output-hygiene + secret→YAML block scalar; §4 journal loop; §6 worktree.
4. [docs/deployment-secrets.md](docs/deployment-secrets.md) — secret rendering + rotation/hygiene conventions.
5. [docs/services-authentik.md](docs/services-authentik.md) — blueprint one-shot-apply + pin-array-attrs (HD-231 lesson).
6. [docs/services-office.md](docs/services-office.md) — ONLYOFFICE/WOPI design + the **live .docx finding**.
7. [docs/deployment-renovate.md](docs/deployment-renovate.md) — renovate re-enabled at `domen/test` (temporary).

---

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`, `scripts/ak-shell.sh`).
  NEVER inline commands through wsl.exe.
- ⚠ **9P gate MANDATORY before every playbook run** (HD-212): `git ls-files -z | xargs -0 md5sum --text | md5sum`
  on BOTH sides EQUAL. WORKTREE checkouts need GIT_DIR translation (see Handoff #7 §1).
- Read-only host probes: temp script files + `ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new
  -i ~/.ssh/id_ed25519 ansible-admin@vps.kogler.si` from WSL. sudo via `sudo -n bash -s`.
- ⚠ **Pipe-masking law** & **Secret-output hygiene (HD-235):** never a secret VALUE in stdout/chat/git; probes show
  lengths/prefixes/IDs/hashes only; `>-` block scalar default for secrets in YAML configs.

---

## 2. State snapshot (end of session)

- **main = origin/main** advanced: my `cleanup-netredo-20260824-0958` was **merged to main** (Handoff #8 batch).
  All work committed+pushed; worker branches (task3/task4/pi-parallel-task6) + their worktrees cleaned up/closed.
  The `cleanup-netredo-20260824-0958` branch + worktree are done (safe to archive/delete next session).
- **Live / verified (no mutation this session):** forgejo up · ONLYOFFICE-onlyoffice-docs up + health true ·
  office.kogler.si 200 · **`.txt` editor works, `.docx` BROKEN (see §3b-1 — TOP item)** · headplane (HD-233) +
  headscale live · renovate config file flipped `enabled: true` + `RENOVATE_REPOSITORIES: domen/test`
  (**NOT deployed** — other session runs the playbook) · CAPsMAN rsc authored but **NOT applied** (cutover-gated).
- **IaC added, deploy-gated (cutover):** router DHCP reservations for 11 devices + HMIP-HAP (VLAN-21 reservation; see network-addresses-generated.md) · switch access-port VLAN 20/21 tasks + nas-eno→Home · CAPsMAN modern `wifi-qcom-ac` rsc template ·
  Phase 1.5 firewall verification plan (`t3-firewall-verification.md`).
- **ID registry:** next free HD = **HD-236** (verify against changelog at write time; my batch used working names
  R-1/R-2/task-N, HD-03 sub-rows in changelog, none claimed a new HD number).
- **Coordination:** my worktree `homelab-wt-20260824-0958` + the `task4` worktree are CLOSED. Primary checkout
  `D:/source/domenkogler/homelab` owns `main` and is CLEAN. headplane/headscale work is a SEPARATE lane — do not touch.

---

## 3. Next-session execution order

### 3a. Fresh worktree per §6 before ANY edit (`../homelab-wt-<date>-<HHMM>` from updated main).

### 3b. Open threads (ordered by priority)

1. **🚨 file.kogler.si `.docx` editing is BROKEN (HD-166 tail — TOP of queue).** Owner tested: `.txt`
   preview/edit/save works, but `.docx` → **“No preview available … download instead”** (ONLYOFFICE editor never
   opens office files). `.txt` uses OpenCloud's NATIVE preview — the ONLYOFFICE/WOPI app-provider is NOT authoring
   office MIME. Fix path (from plan/20260824-netredo/t1-report.md): likely the `collaboration` service needs a
   **NATS broker** (`COLLABORATION_STORE=nats-js-kv` but no `nats` container → no registry/store to announce
   office-MIME authoring); verify the OpenCloud 7.4 `collaboration` runtime deps + `frontend.app_handler`; also
   confirm `COLLABORATION_APP_INSECURE` env maps (rendered yaml shows `insecure: true` vs env `false`). The other
   session deploys any IaC change; then re-test `.docx` in file.kogler.si.
2. **Renovate — now LIVE-capable but repo name is a placeholder.** I already flipped `enabled: true` and set
   `RENOVATE_REPOSITORIES: domen/test` (temporary) in the IaC template + deployment-renovate.md. **Other session**
   runs the compose converge. Once owner migrates/creates `domen/homelab` on Forgejo, flip back to
   `domen/homelab` (both template + doc) and re-converge; verify dashboard issue.
3. **CAPsMAN deploy is READY but human-gated at cutover.** `capsman_steady-state.rsc` (modern `wifi-qcom-ac`) is
   authored in IaC; deployment waits on ① dnevna swap (spare hAP ac² → dnevna) + ② garage replacement
   (wifi-qcom-ac-capable). At cutover: validate wifi-qcom-ac field sets LIVE (marked TODO in template), upload rsc,
   then run `t3-firewall-verification.md` tests.

### 3c. Owner-action chase (reminders, not blockers)
- HD-211 rotation batch: grafana contactpoint+datasource, kopia htpasswd+repo password, `authentik-provision_api` SA.
- Kopia source wiring decision (`/backup` volume).
- LDAP HD-132 authoring (authentik-ldap crash-loops BY DESIGN until then).
- Forgejo: create/migrate `domen/homelab` (unblocks renovate repo-name flip).
- **Cutover window** for Phase 1.5 (router rebuild): do dnevna/garage swaps + run the prepared rsc/tests.

### 3d. Small engineering queue
- OpenCloud `COLLABORATION_APP_INSECURE` env→schema map (suspected not taking effect; part of the .docx fix).
- csp.yaml needs explicit opencloud restart on change → candidate restart-on-change task.
- Surgical-run tag gotcha (include tagged docker_services → union, not filter).
- Blueprint auto-apply layer-2 cause (discovery skips `/blueprints/custom/*`) — offline investigation à la HD-216.
- Headplane hardening (HD-233 track): `use_pkce: true`, docker-socket integration (socket proxy) — separate lane.

---

## 4. Working rules (binding)

- New worktree before edits; merge back only committed+green; primary checkout owns `main` — no other active
  worktrees right now, but keep the discipline.
- Converges: 9P gate first (§1 GIT_DIR variant), surgical `--tags` preferred but note the union-tag gotcha.
- Secrets: 1Password item.field names only — **never values in Git/chat/output** (HD-235). `>-` block scalar for
  YAML config secrets. If a live probe will read a config that may contain secrets, **redact** `secret/password/
  token/bind_password` before printing (a probe on this session did leak values once — do not repeat).
- Journal append-only; owning doc + changelog row in the same change; English prose; relative links.
- If you touch an Authentik OIDC provider/blueprint: pin array attrs (grants, property_mappings, redirect_uris) —
  the HD-231 array-wipe bug recurs on any upsert that omits them.
- **Do not touch headplane/headscale** unless the owning lane asks — it's a separate lane.
