# Deployment Journal — As-Built Record

> **Role:** Append-only execution log — the **as-built** counterpart to [`deployment-tasks.md`](deployment-tasks.md)
> (the plan) and the IaC owning docs (desired state). Records what was **actually done**: terminal commands
> as run, settings chosen, values captured, verification evidence, and every deviation from the documented
> procedure. Manual steps end up here even when the outcome later becomes IaC.
> **Linked from:** [deployment-tasks.md](deployment-tasks.md), [docs/deployment.md](docs/deployment.md)

---

## Rules

- **One `###` entry per action or work session**, titled `### YYYY-MM-DD — Phase X.Y · <what>`.
  Newest entries go **at the bottom** of their phase section (chronological reading order).
- **Record exactly:**
  - commands **as run** (fenced blocks, copy-paste fidelity — include the flags you actually used);
  - settings/values chosen where a UI or script asked (panel fields, installer answers, disk by-id paths);
  - secrets by **item + field name only** (`kopia-server-internal_api.credential`) — **never secret values**;
  - verification evidence (short output snippets: `zpool status`, `sshd -T`, HTTP codes …);
  - **deviations** from `deployment-tasks.md` / the owning doc — each with the reason, and whether the
    owning doc was fixed in the same change (`doc updated: <file>`).
- **Append-only** like `changelog.md`: never rewrite an old entry; corrections are a new entry referencing it.
- **Promotion loop:** if a deviation turns out to be permanent/better, fold it into the owning doc or runbook
  in the same change so the SSOT stays true. The journal records the execution; the SSOT records the decision.
- Tick the matching `- [x]` checkbox in `deployment-tasks.md` in the same change.

---

## Phase 0 — Bootstrap the Management Laptop

*(no entries yet — runner bootstrap pending)*

## Phase 1 — VPS Public Edge

### 2026-08-18 — Phase 1.0 · VPS purchased & created `[MANUAL]` *(backfilled from todo/changelog)*

- Ordered **netcup RS 2000 G12** (€263.52/12 mo) — supersedes Contabo (decision HD-93B, purchase HD-93B row).
- Assigned IP: **159.195.111.66** (recorded in `group_vars/vps.yml` + `docs/services-vps.md`).
- ⚠ Not captured at the time (backfill): installed image/generation specifics, initial root password flow.
  → At first console/SSH access, run the Phase 1 checklist and record the actual state below
  (image version, partition layout, whether `post_install.sh` has been run yet).

## Phase 1.5 — Network Redo

*(no entries yet)*

## Phase 2 — NAS

*(no entries yet — zpool/pool-creation runs will be journaled here against the Pool-Creation Runbook in
[`docs/hardware-nas.md`](docs/hardware-nas.md); expected first entry: bulk RAIDZ2 creation with the real
by-id paths from HD-206.)*

## Phase 3 — oldsrv

*(no entries yet)*

## Phase 4 — Pi

*(no entries yet)*

## Phases 5–10

*(no entries yet)*

---

<!--
Entry template (copy per entry):

### YYYY-MM-DD — Phase X.Y · <title>

- Plan ref: [deployment-tasks.md](deployment-tasks.md) §Phase X, step N
- **Commands run:**
  ```bash
  # exact commands, in order, as executed
  ```
- **Settings chosen:**
  - <field>: <value>
- **Secrets touched:** `<item>.<field>` (value → vault only)
- **Verify:** <short output/evidence>
- **Deviations:** none | <what + why> (doc updated: <file>)
-->
