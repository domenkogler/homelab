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

### 2026-08-22 — Phase 1.0 · VPS re-provision started — HD-208-fixed script pasted `[MANUAL]`

- Plan ref: [deployment-tasks.md](deployment-tasks.md) Phase 1 step 1 sub-step **"Re-provision with the HD-208-fixed script"** (reinstall closes the SSHD-shadow above); owning doc `docs/deployment-preseed.md` §netcup Custom-Script flow.
- **Prep (AI-driven on the WSL runner, same session):**
  - Key-continuity check (prompt.md §3.1, read-only): local WSL `~/.ssh/id_ed25519.pub` = `SHA256:pUUdmN3sVORTqITHHnlhUeH6+As8HkSOIEknI4JtuOg domen@kogler.si` vs vault `ansible-admin_ssh.public_key` = `SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU` — **MISMATCH** ⇒ after the planned runner rebuild (Phase 0, in flight) the canonical private key must be restored from the vault into `~/.ssh/id_ed25519` (1P = source of truth).
  - `cd IaC/host/vps && ./gen-custom-script.sh` — wrote `post_install_with_secrets.sh` (0600, 81 lines, git-ignored); both injected pubkeys fingerprint-verified against the vault (`laptop-domen_ssh` → `SHA256:XTmK3tR59IMnok1HbEW7n3ZK0v4bd7miPS+0r7lSPTA`, `ansible-admin_ssh` → `SHA256:1uKzmwf…7rU`); placeholder self-check + `bash -n` green.
- **Settings chosen (netcup SCP reinstall, fed via prompt-journal):**
  - Official image: **Debian 13.6.0 UEFI amd64** · Installation method: **Minimal**
  - Partitioning: single large OS partition over the full available disk (netcup wording; = plain partitions, no LVM)
  - Hostname: `vps` · Locale: `en_US.UTF-8` · Timezone: `Europe/Vienna`
  - Additional user: **false** (the Custom Script creates `ansible-admin`) · e-mail notification: **true**
  - Custom Script: FULL content of `post_install_with_secrets.sh` (HD-208 drop-in variant, both pubkeys injected)
- **Secrets touched:** public material only — `laptop-domen_ssh.public_key`, `ansible-admin_ssh.public_key` (pubkeys are not secrets); `post_install_with_secrets.sh` deleted immediately after paste.
- **Verify:** ⏳ pending — first boot must show `sshd -T` → `passwordauthentication no` / `permitrootlogin no` / `maxauthtries 3` **from the drop-in alone**; reinstall rotates the host keys ⇒ flush old `known_hosts` entry and capture the new fingerprints for pinning.
- **Deviations:** none vs the documented flow. Three SCP fields were not previously tabulated (installation method, timezone, e-mail notify) — recorded as actually chosen (doc updated: `docs/deployment-preseed.md`).

### 2026-08-22 — Phase 1.0 · reinstall completed — first-boot verification FAILED: injected keys refused `[MANUAL]`

- Plan ref: same step as above — the **Verify** half failed; checkbox stays OPEN pending remediation.
- **Install completed** (netcup report fed via prompt-journal): Debian 13 trixie minimal, hostname `vps`, IPs match SSOT (`159.195.111.66` / `2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5`). New host-key fingerprints (reinstall rotated them; old known_hosts flushed):
  - RSA `SHA256:Eu7MnaeP5u8wG6gyl34CL0/JSjj3AxIuwXnn9vvlA+I` · ECDSA `SHA256:NSAije7AQn/mB7U3nNVOKlqlGj6LzBwjO19tPRbldM4` · ED25519 `SHA256:i1vhb2Su2obdNIqyIw19PLK0PmCZNKl6cBdcUBTky2A` — all three TOFU-verified live via `ssh-keyscan` vs the netcup install report.
- **Verification attempts (from management laptop, Windows OpenSSH + 1Password agent):**
  ```bash
  ssh-keygen -R vps.kogler.si
  ssh-keyscan -4 -t ed25519,ecdsa,rsa vps.kogler.si | ssh-keygen -lf -   # fingerprints match report
  ssh -o BatchMode=yes ansible-admin@vps.kogler.si                        # Permission denied (publickey)
  ssh -o IdentitiesOnly=yes -o IdentityFile=.ssh/laptop-domen_ssh.pub …   # offered SHA256:XTmK3tR… explicit → REFUSED
  ssh -o IdentitiesOnly=yes -o IdentityFile=.ssh/ansible-admin_ssh.pub …  # offered SHA256:1uKzmwf… explicit → REFUSED
  ```
- **Findings / diagnosis:**
  - Both vault identities (the exact two pubkeys injected into the Custom Script) are rejected ⇒ `/home/ansible-admin/.ssh/authorized_keys` absent ⇒ the script **did not reach step 2**.
  - Under `set -euo pipefail` the prime suspect is step 1 (`apt-get update && apt-get install …`) failing during late-install (network/apt not ready).
  - Server offers `publickey` ONLY for `ansible-admin` (verbose capture) — consistent with the **Minimal** image variant shipping password-auth-off defaults rather than proof our drop-in applied; drop-in existence unverified.
  - New deviation candidate: the **Minimal** installation method (first use; 2026-08-18 install method unrecorded — backfill gap) may behave differently around the Custom Script hook.
- **Secrets touched:** root fallback password copied by owner into `netcup-vps_login` — ⚠ open question: owner said "Homelab vault"; plan Table B expects it in the **separate break-glass vault** (SA-invisible, cannot verify — owner to confirm placement).
- **Next:** break-glass diagnostics via netcup SCP console / root fallback; surgical remediation of user+keys (+drop-in if absent); then re-run this verify; root cause decides whether the owning doc needs a Minimal-image warning.

### 2026-08-22 — Phase 1.0 · re-provision VERIFIED after HD-209 console remediation — step closed `[MANUAL]`

- Corrects the FAILED entry above; closes the "Re-provision with the HD-208-fixed script" checkbox.
- **Root cause confirmed** (owner console output): `authorized_keys` lines were `ssh-ed25519 ssh-ed25519 AAAA…` — the template hardcoded the algorithm token while the injected placeholders already carried full keys (HD-209, fixed in `a97783d`). The script itself had run **fully** — user, drop-in and sudoers all present — so both earlier theories (apt failure at step 1; Minimal-image hook difference) are RETRACTED.
- **Remediation (owner, netcup SCP console as root):** `authorized_keys` overwritten with the two correct single-prefix pubkey lines + `chown -R ansible-admin` + `chmod 600`.
- **Verification (this session):**
  ```bash
  ssh -o IdentitiesOnly=yes -i <transient-key> ansible-admin@vps.kogler.si \
    'whoami; hostname; sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin|maxauthtries)"; \
     ls /etc/ssh/sshd_config.d/; sudo cat /etc/sudoers.d/ansible-admin; awk "{print \$NF}" .ssh/authorized_keys'
  ```
  - `ansible-admin@vps` ✓ · **sshd -T = maxauthtries 3 / permitrootlogin no / passwordauthentication no** — the HD-208 no/no/3 requirement, from the drop-in alone ✓
  - drop-in `00-homelab-hardening.conf` present ✓ · sudoers `NOPASSWD:ALL` ✓ · both key comments (`admin@laptop`, `ansible`) present ✓
- **Secrets touched:** `ansible-admin_ssh.private_key` transiently materialized at `%TEMP%\homelab-deploy\vps-verify-key` (0600, written inside WSL via `op read`, **shredded immediately after verification**) — deviation from the no-keys-on-disk posture, forced by the client quirk below.
- **Client quirk recorded (laptop, not server):** Win32 OpenSSH `9.5p2` rejects valid ed25519 `.pub` IdentityFile hints (`Load key … invalid format` while its own `ssh-keygen.exe` parses the same bytes); MSYS git-bash ssh has no agent socket ⇒ plain interactive `ssh` trips `maxauthtries 3` via multi-key agent offering. Interim interactive path = WSL runner (documented model, post-rebuild with canonical key restored); pub-hint Host-entry retry deferred until a Windows OpenSSH update.

### 2026-08-22 — Phase 1.0 · client access model finalized on management laptop `[MANUAL]`

- Owner-finalized `~/.ssh/config` (Windows): two aliases, both `User ansible-admin`, differing only by the presented key (`.pub` hint + `IdentitiesOnly yes`):
  ```ssh-config
  Host vps-ansible   # runner identity (ansible-admin_ssh)
    HostName vps.kogler.si
    User ansible-admin
    IdentityFile ~/.ssh/ansible-admin_ssh.pub
    IdentitiesOnly yes

  Host vps           # personal interactive identity (laptop-domen_ssh)
    HostName vps.kogler.si
    User ansible-admin
    IdentityFile ~/.ssh/laptop-domen_ssh.pub
    IdentitiesOnly yes
  ```
- Both aliases verified live against the VPS post-HD-209 remediation.
- Working prereqs (this session): `Homelab-ansible` allowlisted in 1Password's agent toml + agent-use toggles — without it the agent refuses the keys and `ssh` misreports `invalid format`; offered-key count kept under the server's `maxauthtries 3`. Item names are vault identities, not usernames (no `laptop-domen`/`domen` user exists on the box).
- (doc updated: `docs/1password.md` §Windows-desktop agent notes)

### 2026-08-22 — Phase 0 · runner rebuilt from true zero — VERIFIED `[MANUAL]`

- Owner executed: `wsl --unregister Debian` → `wsl --install -d Debian` (user `domen`) → `IaC/bootstrap-ansible-client/bootstrap.sh`. Repo reused at `/mnt/d/source/domenkogler/homelab` (single working copy, no clone). Supersedes the 2026-08-21 "no wipe" correction per the owner's true-zero documentation decision (prompt.md §3.4).
- Bootstrap output (fed): venv + ansible + collections from `requirements.yml` SSOT; SA token stored 0600 via the prompt flow (`op_api.credential`); sudoers NOPASSWD; throwaway SSH key generated then REPLACED (step 4 below).
- **bootstrap.sh fix (this change):** `chmod 700 ~/.config/op` — the `op` CLI refuses world-accessible config dirs; the script's `mkdir -p` ran before its `umask 077`, so the dir landed 755 and every `op read` aborted (found live on true-zero; the old runner had it fixed by hand at some point).
- **Canonical key restored** per the prompt.md §3.1 continuity plan (the pre-wipe check had found the old local key mismatched): `ansible-admin_ssh.private_key/public_key` → `~/.ssh/id_ed25519[.pub]` via `op read`; fingerprint `SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU` = vault canonical ✓ (stale key `pUUdmN…` ceased to exist with the wipe).
- **Verify:** `ansible-playbook -i IaC/ansible/inventory.ini IaC/ansible/test-1password.yml` → green; `kopia_password` read from vault ✓ (`PLAY RECAP: ok=2 failed=0`). ⚠ required `-e op_vault=Homelab-ansible`: `op_vault` does not resolve for implicit localhost — non-blocking, tracked as HD-210.
- Phase 0 CLOSED — next: Phase 1 main run (`playbooks/vps.yml`).

### 2026-08-22 — Phase 1 · main run `vps.yml` — attempt log, five live defects found + fixed, VPS currently SSH-unreachable (lockout) `[MANUAL]`

- Plan ref: Phase 1 step 2 (`ansible-playbook -i inventory.ini playbooks/vps.yml`), run from the true-zero WSL runner via `%TEMP%\homelab-deploy\vps-run.sh` wrapper (activates venv + sources SA token + exports `ANSIBLE_CONFIG`/`ANSIBLE_ROLES_PATH`). **Every fix below is committed and permanent — a future re-run needs NONE of them again; this list is the record of why they exist.**
- **Attempt 0 (dry-run `--check`)** failed on two setup gaps, both fixed before the real run:
  - ansible.cfg ignored (world-writable /mnt dir) → wrapper exports `ANSIBLE_CONFIG` + `ANSIBLE_ROLES_PATH` explicitly (wrapper-level workaround; NTFS DrvFs mounts always look 0777 — no repo change needed).
  - `group_vars/all.yml` silently shadowed by `group_vars/all/` directory → moved to `all/main.yml`, consumers re-pointed (**HD-210**, closed).
- **Attempt 1** — FAILED at `common`: apt module in check mode needs python3-apt pre-installed (minimal image). Check-mode artifact only → real run auto-installs; no defect.
- **Attempt 2** — FAILED at `docker`: `deb822_repository` needs remote `python3-debian`. Fix (permanent): added `python3-debian` + `python3-apt` to `roles/common/tasks/system.yml` prerequisites.
- **Attempt 3** — FAILED at `docker_services`: the op-CLI fail-closed guard probed the REMOTE host for `op`; lookups resolve on the CONTROL node. Fix: guard task gained `delegate_to: localhost` + `run_once: true` + `become: false`.
- **Attempt 4** — FAILED at `docker_services` network creation: "iptables … No chain/target/match by that name" — loading an nft ruleset that starts with `flush ruleset` DELETES Docker's iptables-nft chains. Fix: `vps-hardening` now restarts Docker immediately after nftables start/reload.
- **⚠ Attempt 5 — SSH LOCKOUT (active):** after hardening applied the default-deny ruleset, new SSH connections time out — **the nftables template had NO `:22` accept rule** (the HD-154 checklist itself omitted SSH while requiring Ansible-managed access; self-contradictory spec, found live). Template fixed to accept `tcp dport 22`; docs swept (deployment-tasks ×2, security.md §8, services-vps.md firewall row).
- **Recovery procedure (owner, netcup SCP console as root):**
  ```bash
  nft flush ruleset        # temporary full-open window (~minutes) until the playbook re-applies
  ```
  then I re-run `vps.yml` from here — it re-applies the corrected ruleset (with :22) and completes the deploy.
- Owner also recorded: WSL user password stored as 1Password item *"Debian Ansible on Laptop P14s"* (personal vault).
- **Re-run recipe from TRUE ZERO (for any future rebuild):** wsl unregister/install → bootstrap.sh (paste `op_api.credential`) → `chmod 700 ~/.config/op` (fixed in script) → canonical key restore (fingerprint `1uKzmwf…`) → test-1password.yml → `vps-run.sh` wrapper. All five attempt-defects above are already fixed in-repo.

### 2026-08-22 — Phase 1 · deploy reached the HD-143 human gate — stack live up to Authentik pre-pass `[MANUAL]`

- Continues the attempt log above (same work session).
- **Attempt 6** — FAILED at HD-143 glue render: bash `${#arr[@]}` contains `{#`, which Jinja parses as a comment opener (`authentik-secret-egress.sh.j2`). Fix: explicit `SEEN_COUNT` counter (⚠ first fix attempt put the sequence into a COMMENT and broke again — lesson: scan the whole template, comments included).
- **Attempt 7** — glue rendered + executed → rc=127 `op: command not found`: the egress script runs ON THE VPS and expects the 1Password CLI installed + authenticated there (it even reads `authentik-provision_api` itself via `op`). This is exactly the **HD-143 deploy-gated human prerequisite** (write-scoped token/item creation is an owner action in the 1P admin console). Playbook halted here BY DESIGN (fail-closed).
- **Live state on vps.kogler.si at halt** (verified over SSH): all four Docker networks present (`traefik-public`, `services-internal`, `db-internal`, `llm-backend`) · CIFS `/mnt/storagebox` MOUNTED (earlier console CIFS timeout self-healed — watch it; if it recurs check cifs role vers/options vs Hetzner SMB3) · hardening active (no/no/3 + nftables with :22) · containers deployed up to the authentik pre-pass.
- ⚠ Minor nit observed: `sudo: unable to resolve host vps` — hostname missing from `/etc/hosts` on the minimal image; candidate small fix for the common role (not blocking).
- **Remaining to finish Phase 1 (owner decisions/actions):**
  1. Create the write-scoped 1Password service account + item per HD-143 (`authentik-provision_api`); decide how the VPS's `op` authenticates (env token file? which vault scope?).
  2. I wire provisioning of op+token onto the VPS (new role task or prepass guard change), then re-run — remaining roles: rest of docker_services (traefik/crowdsec/authentik/apps), monitoring.
  3. Then the Phase 1 Verify block + Deploy-gated verification rows (HD-40A/135/149/143/144/146/166/159).

### 2026-08-22 — Phase 1 · session close — deploy halted at authentik boot; tooling promoted to scripts/ `[MANUAL]`

- Continues the attempt log. **HD-143 unblocked and wired**: owner created the write-scoped SA; token deployed to `/etc/op/provision-token` (0600) out-of-band, then vault-managed via a new `prepass-authentik.yml` copy task (lookup → file, no_log) so rotation = update item + re-run. Provisioner extended with the 8 missing items (create-only; NOT_AUTO_ROTATABLE guard updated) + `stdin=DEVNULL` fix for non-TTY `op item create`; all 8 seeded successfully.
- **Attempts (each fixed in-repo, committed):** postgres services crash-looped under `cap_drop ALL`+read_only (entrypoint chown/setuid denied) → caps + `/var/run/postgresql` tmpfs patched across authentik/db-backup/forgejo/immich-app/pgvector; redis same class → CHOWN/SETUID/SETGID; deploy-service compose validation used nonexistent `compose validate` → `config --quiet`; HD-185 guard inner loop shadowed the outer lazy `item` var → dedicated `loop_var`; authentik labels used mid-template `{% if %}` whose rendered indentation broke YAML → inline ternary.
- **HALT STATE:** glue still cannot reach `127.0.0.1:9000` after fresh containers + 30 retries — authentik-server flapping at halt; first next-session action is its diagnosis (prompt.md §3.1). Everything before it is deployed and verified.
- **Tooling promoted to the repo (owner request):** `scripts/ansible-run.sh` (documented WSL playbook runner replacing ad-hoc %TEMP% wrappers — venv + token + ANSIBLE_CONFIG/ROLES_PATH exports), `scripts/provision-vault.sh`, `scripts/restore-runner-key.sh`, `scripts/check-vault-items.sh`; all documented in scripts/README.md.
- **Registered:** HD-211 (rotate the chat-exposed provision SA token post-deploy; replace placeholder API keys), HD-212 (/mnt/d 9P stale-cache risk — twice served minutes-old files to the runner; migrate to a native WSL clone or add md5 verification before runs). ⚠ Minor: `sudo: unable to resolve host vps` on the box — candidate common-role /etc/hosts nit.

### 2026-08-22 — Phase 1 · corrections at session start: dns.yml test-run backfill + /etc/hosts short-name fix

- **Correction (owner statement):** `playbooks/dns.yml` was already run ONCE during the 2026-08-22 window
  to test `cloudflare_api`, but was not journaled at the time. This entry records that omission
  (append-only; no secret values involved — Cloudflare API token stays in `cloudflare_api.credential`).
- **Decision (owner):** dns.yml is part of the Phase-1 flow per deployment-tasks Phase 1 step 4 and is
  idempotent (Cloudflare record upserts) → re-run this session before the Verify block (`vps` A/AAAA,
  `sso`, then public apps as they land); its evidence will be journaled with that run.
- **Root cause found for the `sudo: unable to resolve host vps` nit** (not blocking, fixed anyway):
  inventory hostnames are FQDNs (`vps.kogler.si`), so the shared `templates/etc_hosts.j2` rendered
  `<ip>  vps.kogler.si.kogler.si vps.kogler.si` — a double-suffixed FQDN and NO `vps` short alias,
  while the system hostname (netcup SCP field) is `vps`; sudo's getaddrinfo on the short name fails.
- **Fix (this change):** `etc_hosts.j2` now renders `<ip>  <fqdn> <short>` (short name = leading label;
  bare-name inventory entries still get `.{{ domain_public }}` appended) — fixes the sudo nit AND the
  latent double-suffix for every managed host; consumed by both the `network` role and `all.yml`.
  Takes effect on the VPS via the next full idempotent `vps.yml` re-run (template task replaces the
  whole file).

### 2026-08-22 — Phase 1 · glue-halt DIAGNOSED: authentik-server image ships no default CMD — `command: server` was never given

- Plan ref: prompt.md §3.1 first diagnostic action (read-only SSH evidence gathering).
- **Live state at pickup:** authentik-postgres / authentik-redis / authentik-worker Up ~9 h
  (worker healthy); authentik-ldap Up-but-unhealthy (its `depends_on` target is down);
  **authentik-server `Restarting (0)`** — crash-loop with EXIT CODE 0 since yesterday's halt;
  port 127.0.0.1:9000 never published.
- **Diagnosis:**
  - Server logs: boot runs clean (config → PostgreSQL OK → bootstrap OK → "Booting authentik
    2026.5.6" → MMDB → app-module imports) … then prints a Django management-command listing and
    exits cleanly — the signature of bare `ak` invoked with NO subcommand (help text → exit 0).
  - `docker inspect authentik-server`: ENTRYPOINT=`["dumb-init","--","ak"]`, **CMD=null** — the
    pinned 2026.5.6 image has no default command. The worker runs only because our compose passes
    `command: worker`; nothing ever told the server to run `server`.
  - Deployed `/opt/authentik/docker-compose.yml` matches the current repo template (NOT 9P
    staleness): neither side defines `command:` for the server service. Rules out both prior
    candidates (redis cascade-abort; migrations exceeding the retry window) — the web server was
    never started at all.
- **Fix (this change):** `templates/docker_services/authentik/docker-compose.yml.j2` gains explicit
  `command: server` + rationale comment (mirrors the worker pattern). Applies via the full
  idempotent `vps.yml` re-run next; expected end-state: server Up, 9000 published, health 200,
  LDAP outpost follows its dependency back to healthy.
- ⚠ **Deviation recorded:** during the deployed-vs-repo comparison I displayed the rendered host-side
  compose file — which carries RESOLVED SECRET VALUES by design — into the session log (same exposure
  class as the HD-211 token paste). Post-green hygiene list EXTENDED: rotate `authentik_db.password`,
  `authentik_password.password` (SECRET_KEY — logs out all sessions, fine pre-production),
  `authentik_login.password` (bootstrap), `authentik-ldap_bind` token alongside HD-211
  (update item → re-run playbook re-renders). No further raw dumps of rendered env blocks.

### 2026-08-22 — Phase 1 · HD-212 sync gate FIRST LIVE RUN: comparator bug found + fixed (`md5sum --text`) — no real staleness

- Plan ref: prompt.md §1 mandatory pre-run sync gate (HD-212, decided today); first execution ever.
- **What happened:** gate reported a mismatch (WIN `ca9851bf…` vs WSL `a74fdf0f…`). Mechanism ①
  `drop_caches` did not change either hash; mechanism ② drvfs remount failed (`target is busy`); a
  full `wsl --terminate Debian` restart changed NOTHING on either side — which disproved staleness:
  a cold VM cannot serve a stale cache. Per-file hash spot-check then showed IDENTICAL digests
  (`.editorconfig` = `868e57b8…` both sides) with different SEPARATORS: MSYS md5sum prints binary-mode
  `<hash> *<path>`, GNU md5sum prints text-mode `<hash>  <path>` — the outer `\| md5sum` hashes those
  different byte streams, so the documented command could NEVER pass across shells (false-positive by
  construction).
- **Fix:** `--text` added to the INNER md5sum on BOTH sides —
  `git ls-files -z \| xargs -0 md5sum --text \| md5sum` — streams become byte-identical when trees
  match. Re-run: WIN = WSL = `a74fdf0f…` → **GATE GREEN, tree in sync, no invalidation needed.**
  Mechanisms ①/②/③ remain valid as staleness invalidation steps; only the comparator was wrong.
  (doc updated: prompt.md §1, deployment-manual.md How-to-use, todo.md HD-212 row;
  changelog HD-212 row left as-is — append-only.)

### 2026-08-22 — Phase 1 · glue halt LAYER 2: /blueprints mount shadowed the image's system blueprints

- Same session, after the `command: server` fix: pre-flight check-vault-items.sh green (43 items cover
  all 30 needed — nothing to provision), sync gate green, FULL idempotent `vps.yml` re-run executed.
  It deployed authentik with the new command and REACHED the HD-143 glue — one layer deeper than ever.
- **New symptom:** authentik-server Up+"healthy" but EVERY route answers 502; router logs
  `dial unix /dev/shm/authentik-core.sock: connect: no such file or directory`; gunicorn master runs,
  no workers bind; raw logs show a ~9 s pre-start loop dying at `[Errno 2] No such file or directory:
  '/blueprints/system/bootstrap.yaml'`.
- **Root cause:** compose volume `- ./blueprints:/blueprints` SHADOWS the image's entire /blueprints
  tree (`system/ default/ example/ migrations/ testing/ schema.json` — verified against the pristine
  image via `docker run --rm --entrypoint sh …`). The server's migrate pre-start hard-requires
  `/blueprints/system/bootstrap.yaml`; missing it, core workers never finish booting → no unix socket
  → router 502s everything. This also explains why the container still passes its `ak healthcheck`
  (process-level, not route-level).
- **Fix (this change):** custom blueprints now mount at `/blueprints/custom` — on BOTH authentik-server
  AND authentik-worker (file-based blueprint discovery also runs worker-side; recursive discovery is
  proven by the image shipping system/ as its own subdir). Host-side layout unchanged
  (/opt/authentik/blueprints/ks-oidc.yml).
- Next: sync gate → full `vps.yml` re-run → expect health 200 + glue completing all providers.

### 2026-08-22 — Phase 1 · layers 3–4: glue API path wrong + provision token dead + blueprint entries lacked required `identifiers`

- Same session, after the `/blueprints/custom` mount fix: full re-run reached the glue again; server
  healthy (core socket bound, `/-/health/live|ready/` = 200 — note: bare `/-/health/` from prompt.md
  §3.1 is NOT an authentik route; it 404s by design).
- **Layer 3 — glue API path:** script called `/api/v3/core/providers/oauth2/` → **404**. Authentik
  serves OAuth2 providers under **`/api/v3/providers/oauth2/`** (`core/*` is users/groups/apps;
  verified live: old path 404 unauthenticated, new path 403). Fixed in `authentik-secret-egress.sh.j2`
  (commit 62913f1) + ks-oidc.yml header comment updated here.
- **Layer 4a — provision token dead:** with the right path the API answered **403**, then
  `/api/v3/core/users/me/` returned "Token invalid/expired": the vault item
  `authentik-provision_api.credential` holds no valid Authentik token — in fact NO provision token
  exists in this authentik instance at all (only tokens: the LDAP outpost service-account one).
  Root cause of the original value is unknown (pre-reprovision artifact); resolution below.
- **Layer 4b — blueprint never applied (root blocker for the glue):** zero OAuth2Provider objects,
  zero BlueprintInstance for ks-oidc.yml. Manual `ak apply_blueprint /blueprints/custom/ks-oidc.yml`
  rejected EVERY entry: **"No or invalid identifiers"** — the Blueprint-v1 spec
  (docs.goauthentik.io/customize/blueprints/v1/structure) requires non-empty `identifiers` on every
  entry; our file kept name/slug in attrs only.
- **Fixes (this change):**
  - ks-oidc.yml: all 16 entries gained proper `identifiers:` (providers ← `name`, applications ←
    `slug`; moved out of attrs per spec — identifiers merge into attrs on create, updates only apply
    attrs so auto-generated client_id/secret are preserved); header notes updated.
  - Provision token: created via `ak shell` (`Token.objects.create(user=akadmin, intent="api")`) and
    written into the vault item ON THE VPS through its write-scoped op SA (value never displayed;
    journal records names only).
- Note for future sessions: authentik 2026.5.x has NO `is_superuser` on User (FieldError) — admin
  capability lives in Group.is_superuser ("authentik Admins" contains akadmin); `ak shell -c` works,
  stdin-piped REPL does not; wrap python in base64 to survive ssh quoting.

### 2026-08-22 — Phase 1 · layer 5: token-architecture conflation resolved; blueprint APPLIED (8 providers live); one owner input pending

- **Blueprint applied GREEN** after the identifier/serializer fixes: manual
  `ak apply_blueprint /blueprints/custom/ks-oidc.yml` → all **8 OAuth2 providers + 8 applications**
  exist (forgejo, headscale, immich, matrix, metabase, openclaw, opencloud, openwebui). Iterated
  against the image's own `/blueprints/schema.json`: `redirect_uris` items are objects
  `{url, matching_mode}`; `invalidation_flow` required; openclaw needs a placeholder URI until HD-104.
- **Provision (Authentik) token minted**: `Token.objects.create(user=akadmin, intent="api",
  identifier="provision-glue")` → stored into vault item `authentik-provision_api.credential` via the
  runner-side op (VPS-side `op item edit` hangs: its `~/.config/op` was never initialized as root;
  template-edit from WSL worked). Verified end-to-end: readback 60 chars → Bearer GET
  `/api/v3/providers/oauth2/` = **200**, provider query resolves.
- **ROOT CONFLATION found (explains yesterday's halt too):** `prepass-authentik.yml` copies item
  `authentik-provision_api.credential` → `/etc/op/provision-token`, and the glue exports that file AS
  `OP_SERVICE_ACCOUNT_TOKEN` (a 1PASSWORD SA token) while ALSO reading the same item as the
  AUTHENTIK Bearer. One value cannot be both systems' secret. Yesterday "worked" only because the
  file held an out-of-band 1P SA while the item ALSO wrongly held it → every glue API call failed
  with "Token invalid/expired". The catalog (deployment-secrets.md) always said the item is an
  AUTHENTIK-ISSUED token — yesterday's session mis-filed the 1P SA into it because Authentik wasn't
  up to issue the real one yet.
- **Incident within the fix:** my ak-shell token write REPLACED the mis-filed 850-char 1P write-SA
  value in the item (intended per catalog semantics, but that SA secret now lives only in 1Password
  item history / the admin console). The 12:49→12:59 playbook pre-pass then copied my Authentik
  token into `/etc/op/provision-token` → host-op parse failure (61-byte file, expected under the new
  architecture to hold a `ops_…` SA).
- **Permanent architecture (docs updated this change):** TWO distinct secrets —
  `authentik-provision_api` = Authentik-ISSUED API token (glue Bearer; DONE ✓);
  `vps-op-write_api` = 1Password write-scoped service-account token (host-op; prepass copy task
  REPOINTED here). Owning docs: services-authentik.md (live-deploy findings section + canonical
  pattern corrected + tokens section), deployment-secrets.md rows, prompt.md health-path fix.
- ⏳ **HUMAN INPUT NEEDED (only blocker left):** create item `vps-op-write_api` in `Homelab-ansible`
  with the write-scoped 1P service-account token — either restore the previous version of
  `authentik-provision_api` (1P UI → item history) and copy its credential over, or re-issue a fresh
  token for the same service account in the 1P admin console. Then re-run vps.yml from the pre-pass:
  glue harvests all providers → remaining services deploy.
- Also observed ~13:00–13:06: interactive Windows `ssh vps` hung post-kex (agent returns identities,
  signature requests stall) while WSL key-file SSH stayed green throughout — likely locked/wedged
  1Password app on the laptop; deployment traffic unaffected (WSL path only).

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
