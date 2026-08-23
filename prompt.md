# prompt.md — Deployment Execution Handoff #6 — Phase 1a COMPLETE → Phase 1.5 network redo is THE gate

> **Role:** Entry point for continuing the deployment track. This session closed **Phase 1a
> completely**: the nas OS was installed **FULLY AUTOMATED via preseed** (first hands-off success of
> the track; pools survived untouched; verification green) and all bookkeeping landed in the same
> change. Both homelab hosts are now installed but UNDER HOLD RULE — **no Ansible against
> nas/oldsrv until the Phase 1.5 cutover lands**. Next main event: either **Phase 1.5 network redo**
> (the gate unlocking host onboarding + Phase 2) or the **VPS-track remainder** — owner picks at
> session start (§3b). The Phase-1 VPS Verify-block queue is untouched and rides along.
> **Linked from:** [README.md](README.md) §2 · plan: [deployment-tasks.md](deployment-tasks.md) ·
> as-built log: [deployment-journal.md](deployment-journal.md) · redeploy runbook:
> [deployment-manual.md](deployment-manual.md) · human feed: [prompt-journal.md](prompt-journal.md)

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) §4 (ledger & journal loop is binding) + §6 (worktree convention:
   every session cuts `../homelab-wt-<date>-<HHMM>` before touching files)
2. [deployment-journal.md](deployment-journal.md) §Phase 1a — ALL entries, incl. today's
   nas automated-install entry (and the oldsrv interactive-install entry for contrast)
3. [deployment-manual.md](deployment-manual.md) §Phase 1a — official-path note UPDATED this session:
   preseeded automated = re-proven official path; interactive + catch-up = proven fallback
4. [hardware-nas.md](docs/hardware-nas.md) — current-state banner (installed 2026-08-23), Boot Drive
   chain (Generic stick = permanent GRUB carrier), disk by-id tables, stale `rpool` finding below
5. [todo.md](todo.md) HD-207 (trimmed to redistribution tail only) + [changelog.md](changelog.md)
   HD-206 close-out row

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`); NEVER
  inline commands through wsl.exe (MSYS mangling). Read-only host probes go through script files too.
- ⚠ **Probing nas/oldsrv interactively:** the owner's Windows `.ssh/config` aliases work ONLY through
  `/c/Windows/System32/OpenSSH/ssh.exe` — MSYS git-bash ssh fails on the alias setup
  (`IdentityFile …​.pub` + 1Password agent → `error in libcrypto: unsupported`). Always
  `-o BatchMode=yes`; route `bash -s < script.sh` through ssh.exe.
- ⚠ **9P STALE-CACHE SYNC GATE MANDATORY before every playbook run** (HD-212):
  `git ls-files -z | xargs -0 md5sum --text | md5sum` on BOTH sides must be EQUAL. On mismatch:
  drop_caches → remount drvfs → full `wsl --terminate Debian`; else migrate clone into WSL
  (pre-authorized).

## 2. State snapshot (end of session, 2026-08-23 evening)

- **Session work MERGED to main:** branch `session-nas-osinstall-20260823-1951` merged after green
  validation; its worktree removed per CONVENTIONS §6. Start any new edits in a FRESH
  `../homelab-wt-<date>-<HHMM>` cut from updated main.
- **nas: Debian 13 (trixie) INSTALLED FULLY AUTOMATED 2026-08-23** — Automated grub entry ran
  end-to-end with ZERO interactive questions (early_command resolved the Crucial SSD by-id; GRUB
  landed on the Generic_Flash_Disk permanent carrier via static bootdev pin; keyed late_command
  applied post_install). SanDisk booted explicitly via iLO one-time menu and was pulled pre-reboot;
  Generic carrier STAYS plugged forever (HD-226). Verified: `ansible-admin` key-only SSH OK,
  `domen@nas` REFUSED (AllowUsers), hostname `nas`, both Crucial by-id forms resolve, six data-disk
  ZFS labels intact, sshd hardening drop-in live.
- **Known nas gaps (deferred BY DESIGN, not defects):** `zfsutils-linux` ABSENT on the fresh OS →
  definitive `zpool list`/`zpool import` export-state check folds into the Phase-2 storage role run
  (it installs zfsutils itself); stale whole-disk `zfs_member LABEL="rpool"` signature on the OS SSD
  = optional owner-gated wipefs candidate at Phase-2 first contact; fqdn reads `nas.lan`
  (DHCP-supplied domain) — cosmetic, fixed by Phase 1.5 addressing.
- **Pools installer-ready→reinstall-proven:** `bulk` RAIDZ2 ×4 (legacy payload under `bulk/migrate`,
  ~2.33 T logical, 57 snapshots) + `tank` empty mirror — BOTH still EXPORTED; import-only storage
  role (`allow_create: false`) owns them from Phase 2.
- **oldsrv:** installed 2026-08-23 (interactive), catch-up done, key-only SSH OK. Reachable via the
  owner's temporary Windows `.ssh/config` alias only — address kept OUT of repo docs (SSOT pointer:
  [network-addresses-generated.md](docs/network-addresses-generated.md)).
- **Hold rule (both hosts):** NO Ansible runs until the Phase 1.5 cutover; first contact happens
  with the new VLANs live. Read-only probes over the owner's aliases are fine.
- **VPS queue** — unchanged from Handoff #5: STILL OPEN there = renovate repo-error debug one-shot
  (LOG_LEVEL=debug), onlyoffice-docs first-boot completion check, authentik-ldap outpost-token
  harvest flow, nftables scoped-flush permanent fix, blueprint auto-apply gap; plus owner actions:
  N8N workflow creation, HD-211 rotation batch (incl. two probe-exposed values), stale pairdrop
  CNAME deletion, Hetzner-SB-Backup private-key copy into the 1P item.

## 3. Next-session execution order

### 3a. Fresh worktree (per convention)
Cut `../homelab-wt-<date>-<HHMM>` from current main before any file edit.

### 3b. MAIN DECISION POINT — owner picks the track at session start
- **Track A — Phase 1.5 network redo (THE gate):** router RB4011 + switch CRS328 rebuild per
  [docs/network-vlans.md](docs/network-vlans.md) + ledger §Phase 1.5. Irreversible cutover,
  human-gated steps. AFTER it lands: nas + oldsrv enter the Ansible loop (nas first contact =
  `playbooks/storage.yml` import-first → unlocks Phase 2).
- **Track B — VPS-track remainder:** the Still-open list in §2 last bullet (renovate debug one-shot,
  onlyoffice first-boot check, ldap outpost-token harvest, nftables scoped-flush fix, blueprint
  auto-apply gap) + owner actions. Belongs to a VPS-track session per Handoff #5 §3d.

### 3c. After-any-step bookkeeping (unchanged rules)
Journal entry + ledger tick in the same change; owning-doc updates for permanent divergences +
changelog row same change; validate green before commit.

## 4. Working rules (binding)

- **Use a new worktree before changing any files** — per CONVENTIONS §6: fresh
  `../homelab-wt-<date>-<HHMM>`, edits applied and validated there, merge back only committed green
  results; manage ONLY your own worktree via `git worktree add`/`remove`.
- Validate green → commit; journal append-only; corrections = new entries; feed raw notes via
  [prompt-journal.md](prompt-journal.md) DATA ("read prompt-journal.md" triggers the conversion loop).
- Secrets: 1Password item+field names only — never values, never in Git or chat.
- Temporary host addresses stay out of repo docs (owner's `.ssh/config` aliases are the bridge).
- Decisions made during deploy → owning doc + changelog row in the same change; journal entry notes
  `doc updated: <file>`.
- No cosmetic edits; English technical prose; relative links.
- Live-system debugging stays read-only or goes through IaC — no hand-run SQL against managed
  databases; Authentik data fixes go through `ak-shell.sh` (arg mode) ORM one-shots.
