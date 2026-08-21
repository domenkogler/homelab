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
- **Human input path:** the human does NOT edit this file directly — they paste raw notes into the
  **DATA block of [`prompt-journal.md`](prompt-journal.md)** (standing feed file); the AI session converts
  them into entries per these rules, ticks the plan, closes gates, validates, commits, and clears the feed.

---

## Phase 0 — Bootstrap the Management Laptop

*(no entries yet — runner bootstrap pending)*

## Phase 1 — VPS Public Edge

### 2026-08-18 — Phase 1.0 · VPS purchased & provisioned `[MANUAL]` *(backfilled from repo records)*

- Plan ref: deployment-tasks Phase 1; decisions HD-93/93B (netcup supersedes Contabo); owning doc `docs/services-vps.md`.
- **Ordered + provisioned same day:** netcup **RS 2000 G12** root server — AMD EPYC™ 9645 · 8 dedicated cores · 16 GB DDR5 ECC · 512 GB NVMe · 2,5 GBit/s iface — **263,52 €/12 mo**.
- **Addresses (SSOT: `IaC/ansible/host_vars/vps.kogler.si.yml`):** IPv4 `159.195.111.66` · IPv6 `2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5`.
- **Access model:** `ansible_user: ansible-admin` (sudo NOPASSWD), SSH identity = **1Password SSH agent** + `~/.ssh/config` — no key files on disk.
- **OS plan:** plain Debian + Docker CE (no hypervisor — provider-virtualized root server).
- **Storage add-ons:** netcup Local Block Storage (expandable to 8 TB, bulk candidate); **Hetzner Storage Box live BX11 1 TB** bought same day (3,90 €/mo, connection ref `Hertzner-SB-Data`, CIFS for photos/files).
- **⚠ Backfill gap:** installer image/generation specifics + initial root-password flow were not captured at creation. → At first console/SSH access, record: installed Debian version, partition layout, whether `IaC/host/post_install.sh` has already been applied (expected: NOT yet — first-boot hardening is part of the Phase 1 checklist), SSH host fingerprints vs `known_hosts` TOFU note.
- **Status:** box reachable-ready, service stack NOT deployed — Phase 1 checklist (hardening → docker → docker_services) is the next action.

## Phase 1.5 — Network Redo

*(no entries yet)*

## Phase 2 — NAS

### 2026-08-21 — Phase 2.0 · tank topology locked + Pool-Creation Runbook authored `[MANUAL]` *(decision session — execution pending)*

- Plan ref: HD-206 (runbook authored, preseed serials filled) + HD-207 (execution + redistribution).
- **Decisions made with owner** (rationale recorded in owning docs — not duplicated here):
  - `tank` = **MIRROR (2× 4 TB), raidz1 rejected** despite OpenZFS 2.3+ RAIDZ expansion — mirror wins fast block-copy resilver, per-block self-healing, random I/O at this size. Growth paths: ① `zpool add` a NEW second mirror pair (contributes full size), ② `zpool replace` both disks one-by-one → autoexpand; **never `zpool attach` a larger disk onto the existing pair** (smallest-member cap). Buying rule: CMR only.
  - Docs updated in the same session: `docs/hardware-nas.md` (+ **Pool-Creation Runbook** with the exact planned `zpool create` commands: bulk RAIDZ2 4×3 TB ashift=12 first, legacy pool migrate-off-IronWolf → `bulk/migrate`, then tank mirror), `docs/storage.md` (topology note), `todo.md` (HD-207 refined: redistribution plan — media → `bulk/media`, personal documents → OpenCloud/live Box, interim `/tank/data/users/<name>/` Samba park).
  - `IaC/host/nas/preseed.cfg` real by-ids filled (boot SSD `ata-Crucial_CT525MX300SSD4_173818D02FF0`, USB `usb-Generic_Flash_Disk_C3EB7FE7-0:0`) — closes the HD-201 placeholder class for nas.
- **Execution NOT yet run** — when the runbook executes (pre-reinstall bootstrap), copy the commands **as run** (with real by-id paths + `zpool status` output) into a NEW entry here; the runbook text stays the plan.

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
