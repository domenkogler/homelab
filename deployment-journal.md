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

### 2026-08-21 — Phase 0 · runner state verified — DECISION: wipe + re-bootstrap `[MANUAL]`

- Plan ref: deployment-tasks Phase 0; verification run read-only from the orchestrator (`wsl -d Debian`).
- **Found:** op CLI v2.34.1 installed ✅ · token file `~/.config/op/homelab-sa-token` present ⚠️ but **fails to authenticate** (`unrecognized auth type` — stale/mismatched vs CLI) · `.bashrc` line 116 carries an **inline `OP_SERVICE_ACCOUNT_TOKEN` export** (the exact HD-86 violation; correct `source` line also present at line 118) · **Ansible NOT installed** (login shell + pip both empty) · no `~/.ssh/config` host entries, no agent bridge.
- **Decision (owner, 2026-08-21):** wipe the half-configured WSL Debian and re-run `IaC/bootstrap-ansible-client/bootstrap.sh` from scratch, journaling each step via the prompt-journal feed. Nothing of value lost (no ansible, broken auth).
- **Action items for the redo:** rotate the 1Password Service Account token (old one stale + exposed in session logs) → new token goes ONLY into `~/.config/op/homelab-sa-token` (0600) via the fixed bootstrap flow, never inline in `.bashrc`.

### 2026-08-21 — Phase 0 · VERIFICATION CORRECTION: runner is functional — no wipe

- Corrects the entry above. Re-probe with the REAL environment semantics (interactive shell = venv activated; token loaded via `source`, not `cat`) shows Phase 0 was **already functional**: ansible-playbook core **2.21.1** (`~/ansible-venv`) · collections community.general 13.1.0 / community.docker 5.2.1 / community.routeros 3.21.0 · `op whoami` + vault listing (**35 items**) work through the sanctioned file-sourcing mechanism.
- Root cause of the false alarm: non-interactive probes skip `.bashrc`'s interactive guard (venv) and `cat`-ing the token file yields its `export …` wrapper text, not the value.
- Real findings that DID hold: (1) stale inline `OP_SERVICE_ACCOUNT_TOKEN` export in `.bashrc` line 116 — a DIFFERENT (older) token than the working file one; HD-86 violation + leaked to session logs but inactive ⇒ **deleted in-place** (sed), rotation optional since unused; auth re-verified green after removal. (2) `bootstrap.sh` never neutralized such legacy inline exports ⇒ fixed: it now seds them out idempotently. (3) `bootstrap.sh` installed only 2 collections instead of `-r requirements.yml` (routeros had been added manually) ⇒ fixed: installs from the Renovate-tracked SSOT.
- **Decision revised:** NO wipe, NO re-bootstrap — existing runner stands; WSL local key stays the documented access model (1Password-agent migration remains the separately-tracked end state).

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

### 2026-08-21 — Phase 1.0 · first SSH access verified `[MANUAL]`

- `ssh ansible-admin@vps.kogler.si` succeeds with the 1Password agent key (no password prompt, no fallback offered).
- **Conclusion:** the netcup **Custom Script hook ran at image install** (2026-08-18) with `IaC/host/vps/post_install_with_secrets.sh` — the VPS variant: TWO keys only (`laptop-domen_ssh`, `ansible-admin_ssh`), no `ai-debug`, root login disabled per script.
- Corrects the 2026-08-18 backfill entry above, which assumed "NOT yet applied".
- Still open from that entry's capture checklist (run at the console when convenient): installed Debian version · partition/LVM layout · host-key fingerprints for `known_hosts` pinning · `sshd -T` hardening state pre-Ansible.

### 2026-08-21 — Phase 1.0 · console capture: image/layout/fingerprints + SSHD-SHADOW FINDING `[MANUAL]`

- Plan ref: Phase 1 backfill-gap checklist (this session's earlier entry).
- **Commands run:**
  ```bash
  cat /etc/os-release | head -2; uname -r
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT; df -h /
  id; cut -d: -f1 /etc/passwd | grep -E 'admin|ansible|domen'
  ls -la /root/.ssh/; cat /root/.ssh/authorized_keys | wc -l
  grep -rn "PasswordAuthentication|PermitRootLogin|MaxAuthTries" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
  systemctl is-active ssh; ss -tlnp | grep :22
  for k in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf $k; done
  dpkg -l | grep -cE "docker|fail2ban"; nft list ruleset; free -h; ip -br addr
  cat /etc/debian_version; sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin|maxauthtries'
  ```
- **Findings:**
  - OS: **Debian 13.6 (trixie)**, kernel 6.12.101+deb13-amd64.
  - Layout: `vda` 512 G — `vda1` 243 M vfat EFI · `vda2` 977 M ext4 `/boot` · `vda3` 510.8 G ext4 `/` — **no LVM** (deviation vs the documented "entire + LVM" SCP field choice; doc updated: `docs/deployment-preseed.md`).
  - Users: only `ansible-admin` (uid 1000, NOPASSWD sudo confirmed — `sudo sshd -T` ran clean); `/root/.ssh/authorized_keys` empty (root = password-only, see finding below); no `domen` account (by design).
  - Host keys (for `known_hosts` pinning): ECDSA `SHA256:aPEyZBN0xmIMhqV2SsWSy0OANMRdbmIOYYcYWtgejzI` · ED25519 `SHA256:DfRE+i6EiZUYD2Bot2hanIh+Ey47tTpzv352boxB3fY` · RSA `SHA256:LpwYdCSTDcIZ0fvGUj8mRFJOgLXabbMYU+7VTr+tWIE`.
  - Not yet present: docker, fail2ban, nftables ruleset, swap (0 B — netcup image ships none).
  - Network: `eth0` `159.195.111.66/22` + IPv6 (matches SSOT).
- ⚠ **SSHD-SHADOW FINDING (deploy-blocking priority):** effective config is `passwordauthentication yes` + `permitrootlogin yes` + `maxauthtries 6` (`sshd -T` verified). Cause: netcup's image ships EXPLICIT `PasswordAuthentication yes` / `PermitRootLogin yes` at `sshd_config` lines 124–125; the Homelab hardening block appended at lines 128–129 by the Custom Script **loses to sshd's first-obtained-value-wins semantics**. Root has an SCP-set fallback password ⇒ internet-exposed password login window RIGHT NOW. Mitigation: run `playbooks/vps.yml` promptly — the `vps-hardening` role lineinfile-flips the directives (verified in role tasks). Permanent fix tracked as **HD-208** (drop-in instead of append). (doc updated: `docs/deployment-preseed.md`; todo: HD-208 added)

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
