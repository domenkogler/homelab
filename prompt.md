# prompt.md — Deployment Execution Handoff #5 — Phase 1a pools DONE → NAS OS install next

> **Role:** Entry point for continuing the **Phase 1a parallel track**. This session executed the
> Pool-Creation Runbook on the nas/gen8 (bulk RAIDZ2 + tank mirror created, legacy payload landed in
> `bulk/migrate`, both pools exported → **installer-ready**), refreshed the nas preseed + install
> media, and closed out docs/journal/ledger. **First task next session: the NAS OS install via iLO**
> (§3b). The Phase-1 VPS Verify-block queue is untouched and rides along unchanged (§3d).
> **Linked from:** [README.md](README.md) §2 · plan: [deployment-tasks.md](deployment-tasks.md) ·
> as-built log: [deployment-journal.md](deployment-journal.md) · redeploy runbook:
> [deployment-manual.md](deployment-manual.md) §Phase 1a · human feed: [prompt-journal.md](prompt-journal.md)

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) §4 (ledger & journal loop is binding) + §6 (worktree convention,
   updated this session: every session cuts `../homelab-wt-<date>-<HHMM>` before touching files;
   own-worktree-only discipline)
2. [deployment-journal.md](deployment-journal.md) §Phase 1a — BOTH entries: oldsrv reinstall
   (2026-08-23 morning session) AND **Pool-Creation Runbook executed** (this session)
3. [deployment-manual.md](deployment-manual.md) **§Phase 1a** — incl. NEW **§1a.0 pool bootstrap**
   (as-executed commands) and §1a.2's **nas two-stick exception**
4. [hardware-nas.md](docs/hardware-nas.md) — disk tables (per-serial SMART hours), runbook banner
   (reality deltas), Boot Drive chain (Generic stick = permanent GRUB carrier)
5. [todo.md](todo.md) HD-207 (trimmed to redistribution tail) + [changelog.md](changelog.md) same ID

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY:
  ```bash
  cmd //c "wsl -d Debian -- bash /mnt/d/source/domenkogler/homelab/scripts/ansible-run.sh playbooks/vps.yml"
  ```
  NEVER inline commands through wsl.exe (MSYS mangling). Read-only host probes go through
  script files too (`ssh -o BatchMode=yes …` inside a temp script; pattern proven two sessions).
  Interactive git-bash ssh can be flaky (1Password agent); key-file paths stay green.
- ⚠ **9P STALE-CACHE SYNC GATE MANDATORY before every playbook run** (HD-212):
  `git ls-files -z | xargs -0 md5sum --text | md5sum` on BOTH sides must be EQUAL. On mismatch:
  drop_caches → remount drvfs → full `wsl --terminate Debian`; else migrate clone into WSL
  (pre-authorized).

## 2. State snapshot (end of session, 2026-08-23 afternoon)

- **⚠ UNMERGED BRANCH:** `session-nas-pools-20260823` (worktree `../homelab-wt-20260823-nas`)
  carries ALL of this session's work — owner has NOT merged yet. Commits: nas preseed refresh ·
  worktree convention (CONVENTIONS §6 SSOT) · HD-207 close-out (journal+ledger+docs+changelog) ·
  manual §1a.0 pool bootstrap · boot-chain decision (Generic stick permanent). **First action next
  session: settle the branch (merge or review) BEFORE any new file edits.**
- **Pools installer-ready on gen8:** `bulk` = RAIDZ2 ×4 enclosure disks (ashift=12, runbook props)
  holding the ENTIRE legacy payload under `bulk/migrate/new-pool` (~2.33 T logical, 57 snapshots);
  `tank` = empty mirror (HGST + ST4000NT001). Both **EXPORTED** — `zpool list` shows nothing until
  the Phase-2 storage role imports them (import-only, `allow_create: false`). Old single-disk pools
  `new-pool` (source, exported→wiped) and `backup` (61.9 G gen8 dumps, owner declared disposable)
  are GONE. SMART: all drives PASS, hours per serial in hardware-nas.md; report archived
  `reports/smart-report-nas-20260823T105831.txt`.
- **Install media READY (SanDisk, currently in the laptop as `E:`):** `preseed/preseed.cfg` = nas
  version (early_command resolves the Crucial SSD at runtime + iwlwifi blacklist; grub-installer/
  bootdev statically pinned to `usb-Generic_Flash_Disk_C3EB7FE7-0:0`) · `preseed/post_install.sh`
  = keyed build reused from the oldsrv media build (verified: 3 keys, guards intact). DVD tree boot
  patches already applied (file= ×5 entries, module_blacklist everywhere).
- **Boot-chain decision (owner):** Generic_Flash_Disk stays PERMANENT GRUB carrier (SSD SATA port
  cannot boot); SanDisk = installer medium only. Two-stick install documented in manual §1a.2.
- **oldsrv:** installed 2026-08-23 (interactive; preseed deferred), catch-up done, key-only SSH OK.
  Reachable via owner's temporary Windows `.ssh/config` alias only — the address is a pre-1.5 DHCP
  artifact deliberately kept OUT of repo docs (SSOT pointer: [network-addresses-generated.md](docs/network-addresses-generated.md)).
  Hold rule: no Ansible against oldsrv/nas until Phase 1.5 cutover.
- **VPS queue UNCHANGED from Handoff #4:** renovate Up-confirm after real `forgejo_api`,
  kopia-server seed (sftp_key + known_hosts), Verify-block evidence capture (crowdsec decisions,
  CIFS round-trip, sshd -T/fail2ban/docker info, NVMe <80%), authentik-ldap + chat health checks,
  HD-211 rotation batch, SMTP port 2525 notes, HD-216 open (offline only), HD-159 ⏳ until 1.5.

## 3. Next-session execution order

### 3a. Settle the session branch (blocking, owner-gated)
Review + merge `session-nas-pools-20260823` into main (all commits validated green); then remove
the worktree via `git worktree remove ../homelab-wt-20260823-nas` and delete the branch. Any new
edits this session happen in a FRESH `../homelab-wt-<date>-<HHMM>` per CONVENTIONS §6.

### 3b. NAS OS install via iLO (main event)
Two-stick setup per manual §1a.2: **SanDisk** (installer medium) + **Generic_Flash_Disk** (permanent
GRUB carrier) BOTH plugged. Boot EXPLICITLY from the SanDisk (iLO one-time menu) — if the old GRUB
menu appears, wrong medium booted. Run an **Automated** entry: early_command resolves the SSD,
grub lands on the Generic stick via the static by-id pin, late_command runs the keyed post_install.
Fallback: *Graphical install* (proven path; pick the small Generic device at the GRUB dialog) +
catch-up script (`gen-media-post-install.sh` → LAN HTTP → run as local user).
✔ Post-install verify: `ssh ansible-admin@<nas>` KEY-ONLY; `domen` REFUSED (AllowUsers); hostname
`nas`; both Crucial by-id forms resolve; pools still exported (import comes later); **no Ansible
runs against nas (hold rule until 1.5)**. Journal + ledger tick in the same change.

### 3c. After-install bookkeeping
Journal entry (manual §1a.4 rules) · ledger checkbox "Reinstall nas" tick · hardware-nas.md
current-state header · if anything deviated permanently → owning doc + changelog same change.

### 3d. Parallel queues (unchanged from Handoff #4)
Phase-1 Verify block evidence, kopia seed, renovate confirm, ldap/chat health, HD-211 batch —
see §2 last bullet; these belong to the VPS-track session, not this one.

## 4. Working rules (binding)

- **Use a new worktree before changing any files** — per the Git-worktrees convention in
  [CONVENTIONS.md](CONVENTIONS.md) §6: fresh worktree named `../homelab-wt-<date>-<HHMM>` for the
  session, all edits applied and validated there, merge back only committed, green results;
  the primary checkout stays untouched.
- Validate green → commit; journal append-only; corrections = new entries; feed raw notes via
  [prompt-journal.md](prompt-journal.md) DATA ("read prompt-journal.md" triggers the conversion loop).
- Secrets: 1Password item+field names only — never values, never in Git or chat.
- Decisions made during deploy → owning doc + changelog row in the same change; permanent divergences
  update the owning doc (`doc updated: <file>` noted in the journal entry).
- No cosmetic edits; English technical prose; relative links.
- Live-system debugging stays read-only or goes through IaC — no hand-run SQL against managed
  databases (2026-08-22 incident precedent). Authentik data fixes go through `ak-shell.sh`
  (arg mode) ORM one-shots.
