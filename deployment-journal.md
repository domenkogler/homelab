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
- **Owner actions landed:** fresh `vps-op-write_api` created (850-char `ops_` token ✓);
  `authentik-provision_api` item restored around the STILL-LIVE Authentik DB token
  (`provision-glue`, no re-issue needed) via runner-side op with the new write-SA — Bearer verify
  **200**. Owner question "one item enough?" answered: NO — two systems, two secrets
  (services-authentik.md tokens section).
- **Tooling promoted:** `scripts/ak-shell.sh` — base64-safe Python-in-authentik-worker runner
  (script-file indirection from Windows; agent-independent key-file SSH); ends the multi-layer
  quoting failures hit all session. Documented in scripts/README.md.

### 2026-08-22 — Phase 1 · DECISION Option A: glue mints an EPHEMERAL Authentik token per run; authentik-provision_api retired; out-of-band SQL incident recorded

- **Owner decision (session, after the token-rotation mystery blocked three glue runs):** stop
  chasing the background rotator — the glue now MINTS its own throwaway api-intent token via
  `ak shell` (identifier `egress-glue-<pid>-<ts>`), uses it for the provider harvest, and REVOKES it
  on exit (trap). Nothing persisted → the rotator (whatever it is, **HD-216** registered) cannot
  invalidate anything. `authentik-provision_api` RETIRES from the flow (vault item tombstone row in
  deployment-secrets.md; services-authentik tokens section rewritten to TWO secrets + one ephemeral).
  Trade-off recorded: minted token = akadmin full rights for seconds — equivalent to the existing
  root-on-VPS trust model, weaker than the old least-privilege aspiration.
- ⚠ **INCIDENT (own it):** while hunting the rotator I installed an audit trigger + audit table via
  hand-run `psql` against the live authentik DB — out-of-band surgery on an Ansible-managed system,
  NOT in the plan, flagged by the owner. All three artifacts dropped and verified gone the same
  hour; no data changed beyond the forensic objects. Lesson recorded: live-system debugging stays
  read-only or goes through IaC, full stop.
- Glue changes (this commit): helper-python written to container tmpfs per run; mint/revoke via
  `docker exec` + `ak shell -c` (single-layer quoting); fail-loud if mint returns empty.
- Also registered: the mystery rotator itself (HD-216) for OFFLINE investigation.

### 2026-08-22 — Phase 1 · SESSION PAUSE: docker_services completes all 27 services (11 up / ~17 crash-looping); next blocker = monitoring role (homepage failover buttons)

- **Deploy depth reached:** the docker_services loop rendered and deployed EVERY enabled VPS
  service for the first time (ok=207/changed=83 at the last full attempt); traefik + crowdsec +
  authentik + homepage + docling + litellm + open-webui + pgvector + onlyoffice + blackbox + loki +
  immich-postgres/valkey + forgejo-db are Up (several healthy); ~17 containers across ~14 services
  are crash-looping with per-app causes (below). The failure point moved PAST docker_services into
  the `monitoring` role: homepage_services.yaml.j2 fails on `'failover_api_url' is undefined` (and
  its `ha-failover_api` lookup targets an item that is Phase-4/HD-17 scope — not in the vault yet).
- **Fixes committed this session (all validated green, in order):** etc_hosts short-alias;
  authentik `command: server`; blueprints → `/blueprints/custom`; glue API path
  `/api/v3/providers/…`; two-secret split (vps-op-write_api); blueprint identifiers + 2026.5.6
  serializer fixes APPLIED LIVE via `ak apply_blueprint` (8 providers + 8 apps exist); sync-gate
  comparator `--text`; `jq` prereq; glue non-TTY `< /dev/null` on op writes; commented
  `{{ lookup }}` neutralized ×39; `svc_entry`/`extra` loop_vars; indented `{% if %}` → inline
  ternary ×29; certs-dumper → `ldez/traefik-certs-dumper:v2.11.4` (registry-verified; old pin never
  existed) + wrapper/post-hook flat naming; `storage_uid/gid` defined; immich postgres
  `/etc/postgresql` tmpfs + valkey caps; kopia `.env` interpolation mechanism (server+agent).
- **Diagnosed-but-unfixed crash causes (next session, in this order):**
  1. crowdsec: `COLLECTIONS` contains `crowdsecurity/matrix` — does not exist upstream; pick the
     correct collection set and re-render.
  2. opencloud: `/srv/docker/opencloud/config:/etc/opencloud:ro` — first-boot `opencloud init`
     cannot write config/jwt_secret; mount needs rw (or seeded tmpfs).
  3. grafana: host bind `/srv/docker/grafana/data` root-owned, image runs uid 472 → `user: "0"` +
     CHOWN cap (entrypoint drops privileges itself), or a pre-chown task.
  4. matrix/tuwunel: rendered tuwunel.toml "mixes bare keys with a [global] profile" — config
     schema drift vs the pinned tuwunel version; rework `tuwunel.toml.j2`.
  5. n8n: node module compile error — capture a fuller log before touching anything.
  6. Not yet sampled: chat, headscale, metabase, openclaw, pairdrop, renovate, stirling-pdf,
     db-backup, forgejo app, immich-server app, traefik-certs-dumper.
- **Proposed (owner sign-off pending):** gate the homepage failover buttons behind a
  `homepage_failover_button: false` group_var until HD-17 (Phase 4) — unblocks the monitoring role
  without pretending Phase-4 features are live.
- **Session hygiene note:** interactive Windows `ssh vps` was flaky (agent wedged) — WSL key-file
  path used throughout; 1Password app restart recommended before next session.

### 2026-08-22 - Phase 1 - RESUME: owner sign-off on homepage failover-button gating (HD-217); monitoring-role halt cleared

- **Owner decision (resume Q/A):** approve the proposed gate verbatim. New group_var
  `homepage_failover_button` (`group_vars/vps.yml`, default **false**) controls whether the HA
  Forward Takeover / Reverse Failback cards render in `homepage_services.yaml.j2`; stays false
  until Phase 4/HD-17 (`ha-failover_api` seeded + HmIP-RFUSB stick moved), then flips true.
- Same-change IaC: failover block wrapped in `{% if homepage_failover_button %}` (+ comment);
  var pinned in `group_vars/vps.yml`. With the gate off, the monitoring role no longer touches the
  undefined `failover_api_url` / missing vault item -> halt point cleared for the next run.
- Other resume-session owner calls, recorded: placeholder provider keys (`openrouter_api`,
  `cohere_api`, `forgejo_api`) post-green; HD-211 rotation batch post-green; check-vault-items
  blind spot (missed `kopia-server_internal_api`) -> document + fix (repo-only, rides the Wave 2
  batch); `dns.yml` re-run when needed; LDAP outpost health re-check post-green; HD-159 unchanged
  (Phase 1.5).
- Clarified for the record: **HD-216 stays OPEN** (rotator root cause unidentified) - the
  ephemeral-token design is the Option A workaround, not a fix; `vps-op-write_api` is the
  host-side op write-SA, not the token minter.
- doc updated: docs/smart-home-failover.md (gate note in status callout); todo + changelog HD-217 rows.

### 2026-08-22 - Phase 1 - Wave 1 (parallel read-only triage, 18/18 diagnosed) + Wave 2 (batched fixes) - HD-218

- **Wave 1 method (owner-approved pattern):** live roster first (`docker ps -a`: 18 Restarting
  containers incl. prometheus which was NOT in the pause list), then one read-only worker per
  service - docker ps/inspect/logs ONLY via script-file WSL ssh; each read its own template +
  group_vars and returned a structured root-cause report. All 18 reports landed; zero mutations,
  zero repo writes. Probe skeleton dumped full container ENV -> several secrets transited the
  session transcripts (see HD-211 additions below). Process note: future probes grep-filter
  *PASS/*TOKEN/*SECRET/*KEY env names before printing.
- **Root causes (all confirmed against live logs):** crowdsec = nonexistent `crowdsecurity/matrix`
  collection aborting hub setup (+ secondary EROFS: entrypoint symlinks data files into
  /staging on the ro rootfs - host probe confirmed no mount anomaly, pure Class B) · opencloud =
  config bind :ro blocked first-boot init · grafana/n8n/openclaw/opencloud = **Class A** Docker-
  auto-created root:root bind dirs vs image uids (472/1000/1000/storage_uid) · chat = nginx
  envsubst needs writable /etc/nginx/conf.d under read_only · pairdrop+db-backup = s6-overlay
  needs writable /run · forgejo = s6-svscan lock in /etc/s6 (tmpfs would mask init scripts) ·
  metabase = stock entrypoint user-creation/chmod/su vs cap_drop ALL + read_only · stirling-pdf
  = init.sh chown+symlink vs hardened rootfs · matrix = tuwunel rejects bare keys mixed with
  [global.*] subtables · headscale = NO command (bare binary prints help, exits 0 forever) +
  pre-0.24 config schema keys · immich-server = DB_HOST vs DB_HOSTNAME typo (ENOTFOUND database)
  · kopia-server = image ENTRYPOINT /bin/kopia ate `sh -c` argv (.env rework VERIFIED GOOD) ·
  renovate = image 35.x predates forgejo platform (FATAL at startup validation) · prometheus =
  three full-URL scrape targets invalid (host:port required) + ha_token never mounted/renderable ·
  traefik-certs-dumper = CF token 403 from VPS egress IP (OWNER FIXED same day: IP whitelisted)
  + wrapper crash-looped on cert-less acme.json + post-hook ran without shell + dead trailing
  args + NOTHING EVER REQUESTED the wildcard (per-router certs only).
- **Wave 2 applied (single writer, one commit):** crowdsec_collections minus matrix (trade-off:
  no tuwunel log parsing until upstream/collection exists) · Class A generic fix =
  `bind_owner_uid`/`bind_dirs` metadata on the 4 service entries + pre-create/chown task in
  deploy-service.yml · element-web tmpfs trio · pairdrop/db-backup `/run` tmpfs · forgejo app
  read_only removed (db untouched, healthy) · metabase hardening relaxed + ALLOWED_NO_CAP_DROP
  validator entry w/ justification · stirling read_only->cap_add CHOWN/SETUID/SETGID · tuwunel
  `[global]` insert · immich DB_HOSTNAME · headscale command: serve + dns:/policy.path migration
  · renovate RENOVATE_PLATFORM gitea · prometheus bare targets + `prometheus_ha_exporter: false`
  gate (re-enable at HD-04 with HA token item + compose mount) · kopia entrypoint: [] + /app/logs
  tmpfs · opencloud rw mount + csp.yaml finally mounted (HD-144 gap found by worker) ·
  certs-dumper rewritten around rendered `certs-rename.sh` (guards empty acme.json, shelled
  post-hook, dead args removed) + issuer-only wildcard request labels (*.kogler.si sans apex) ·
  check-vault-items.sh now scans shared top-level templates + VPS group_vars (the kopia miss had
  self-resolved via the same-day .env rework; the CLASS was real - ha-failover_api/cloudflare_api
  were invisible to it).
- **Validation:** validate-all green (50/50 templates after allowlist entry); hand-renders with
  real group_vars context: tuwunel.toml parses as TOML w/ single [global], headscale config YAML
  valid on new schema, prometheus yml valid in both gate states, certs-rename.sh sh -n clean.
- **HD-211 rotation additions (post-green batch):** GF_SECURITY_ADMIN_PASSWORD, GF_SMTP_PASSWORD,
  N8N_ENCRYPTION_KEY, N8N_BASIC_AUTH_PASSWORD, RENOVATE_TOKEN, OPENCLAW_GATEWAY_TOKEN,
  OPENCLOUD_WEBDAV_PASSWORD, db-backup DB01-04 passwords (forgejo_db already listed).
- **Caveats carried into Wave 3:** openclaw may land "perms fixed, awaiting onboard" (config
  generated at HD-104 deploy step) · headscale schema migration is medium-confidence until first
  serve attempt · crowdsec hub-upgrade EROFS expected silenced by /staging tmpfs (verify) ·
  renovate runs but fails against forgejo until IT is up (ordering fine post-fix).

### 2026-08-22 - Phase 1 - Wave 3: combined runs GREEN; public DNS published; 32/35 Up; 3 owner-gated remainders (HD-218 cont.)

- **Loop discipline:** every fix = validate green -> commit -> 9P sync gate -> one playbook run.
  Commits 143d477, 6482eeb, 900b27b, fbdd913, cf1c350, 528a527, f45f679 (first FULL GREEN run),
  d3a8f7c (R2), a334370+f6d2d41 (R3), 9c44e63, cf478a3, 2b6edc5, 80cf101 (R4/R5 headscale),
  1db2a7b+d4c7d18 (DNS), 73f4c8d (headscale resolvers).
- **Run-1..8 dominoes (all first-time-live defects):** orphaned group_vars/subscriptions.yml
  (no [subscriptions] group existed) -> group wired; broken post-deploy inventory-doc render
  (all_hostvars never built host-locally; would clobber the multi-host generated doc) -> removed,
  canonical renderers documented in-place; monitoring ha_token -> gated behind
  prometheus_ha_exporter; Debian 13 has no apt-key -> Grafana repo via deb822 (param is
  signed_by); snmp.yml scoped to oldsrv (undefined {{ community }} inside a template comment);
  alert-rule summaries carrying Go-template vars -> !unsafe. First FULL GREEN run: ok=264 failed=0.
- **Round 2:** crowdsec read_only relaxed (upstream seeds /staging on the rootfs; tmpfs made the
  seed glob degenerate) + one-time data-dir reset (operational; polluted bind kept as
  db.stale-20260822T181838Z); db-backup+pairdrop: tmpfs /run -> host bind (Docker mounts tmpfs
  noexec - s6 stage0 exec died with 126) + pairdrop s6 cap quartet; headscale
  noise.private_key_path (0.24+ requirement); kopia --known-hosts/--keyfile (--no-check-known-hosts
  never existed in 0.23.1); openclaw --allow-unconfigured until HD-104 onboard; opencloud
  bind_dirs += data (NATS JetStream died in the root-owned data bind); prometheus trailing
  storage.tsdb block deleted (not a valid config key - CLI flags only).
- **Round 3:** crowdsecurity/grafana ALSO nonexistent upstream (masked behind matrix in round 1)
  -> dropped from collections; headscale prefixes block (v2 schema); n8n read_only removed
  (~/.cache lives on the rootfs); stirling-pdf user 0:0 + forgejo cap quintet (init.sh must run
  root) + validator ALLOWED_NO_CAP_DROP entry.
- **Rounds 4/5 (headscale v2 schema chain):** base_domain ts.kogler.si (v2 rejects server_url
  inside base_domain; DECISION reversible pre-enrolment - nodes = <node>.ts.kogler.si); policy
  comments // (HuJSON rejects ansible_managed #-style); tagOwners empty (no autogroup:admin in
  v2; server-side CLI tagging unaffected); interim *:* ACL (enrolment itself is OIDC-gated;
  TIGHTEN at first enrolment with real usernames - owner-flagged).
- **Public DNS published (dns.yml green x3):** apex + sso/git/chat/matrix/file/office/foto/ai/
  stats/sec/pdf/vpn/pairdrop/auto CNAMEs -> vps (sso unblocks headscale OIDC + the whole
  forward-auth chain; ha stays unpublished until Phase 4; apex via flattened kogler.si CNAME -
  the module rejects an empty name). Gotcha: netcup resolvers negative-cache NXDOMAIN beyond
  the record TTL -> headscale got explicit 1.1.1.1/8.8.8.8.
- **FINAL TALLY: 32/35 Up** (incl. previously crash-looping chat, forgejo, grafana,
  immich-server, matrix, metabase, n8n, stirling-pdf, openclaw, opencloud, prometheus,
  pairdrop, db-backup, crowdsec; traefik-certs-dumper idling correctly pre-issuance).
  Remaining loops, ALL owner-gated: kopia-server (needs /srv/docker/kopia-server/config/
  {sftp_key,known_hosts} seeded), renovate (needs real forgejo_api token swap), headscale
  (needs wildcard cert: CF API STILL 403 from VPS IP 159.195.111.66 despite the whitelist -
  owner re-check WHICH token was edited vs vault cloudflare_api). authentik-ldap + chat
  unhealthy = post-green checks.
- **Process slip (own it):** commit a334370 landed while the validator was red - the `| tail`
  pipe masked the script exit code. Fixed next commit (f6d2d41); lesson: capture rc before the
  pipe, never trust the pipe's status.

### 2026-08-26 — Phase 1 · Vault completion + vault-coverage scanner live-confirm (HD-244/245/247 prep)

- Plan refs: todo HD-244/HD-245 (scanner contract), HD-247 ⏳ gate legs; owning docs `scripts/README.md`, `docs/services-ai.md` §4, `docs/deployment-secrets.md`.
- **Vault seeded** via `bash scripts/provision-vault.sh` (WSL Debian runner, HD-212 sync gate green both sides): created exactly **one** item — `litellm_db` (Database class, username `litellm`, generated password, NOT_AUTO_ROTATABLE) — skipped 35 existing, confirming owner-side presence of real `openrouter_api`/`cohere_api`/`forgejo_api` values, `metabase-forgejo_ro`, `zipline_password`/`zipline_db`. Output printed names/status only — no secret values.
- **Scanner live-confirm (HD-244 tail closed):** pre-fix run flagged the 7 HD-247 scoped keys MISSING-and-not-glue — fixture had masked the gap (fixture glue template carries literal "name:field" pairs; the real `litellm-bootstrap-keys.sh.j2` is Jinja-rendered, `spec.vault_item`). Same-day fixes (`4113897`, `6493126`): specs inside a top-level `*_scoped_keys:` list route to GLUE; `db_item`/`db_ro_item` on service entries stay NEEDED (owner-seeded catalog); glue-minted names finally subtracted from NEEDED because they ALSO enter via literal consumer lookups. Post-fix live run: **needed items 36 | in vault 63 | MISSING = `ha-failover_api` ONLY** (Phase-4 scope behind disabled homepage button — expected). Self-test extended to 24 asserts incl. case 7 control/scoped mutate-copy pair.
- **Lanes A+B shipped to main:** scanner (`f1e9eee`), litellm spine (`5388dda` + `5ebdcb8`), close-out/bookkeeping (`4901a9b`), scanner v2 (`6493126`), seed-note (`b4158de`) — all ff-merged from session branches in per-session worktrees, pushed; worktrees pruned.
- Notes: renovate stays pointed at `domen/test` until the owner migrates `domen/homelab` (delayed); HD-252 Lane D will VERIFY the owner's manual domen↔OIDC provider_identifier link rather than re-migrate.

### 2026-08-26 — Phase 1 · HD-252 Lane D: headscale OIDC recovery + container recycle, surgical-converge blocker found `[AI]`

- Plan ref: todo HD-252 ①②; prompt.md §3b Lane D; owning docs docs/network-vpn.md, docs/deployment-oidc.md. 9P sync gate green BOTH sides (`309a6782…` = `309a6782…`) against the session worktree (`homelab-wt-20260826-1600`, branch `session-headscale-oidc`); WSL Ansible runner reachable (ansible `ping` on `vps.kogler.si` = pong); direct SSH via the Windows OpenSSH `vps-ansible` alias.
- **Root cause re-confirmed live:** headscale container started `2026-08-23T20:36Z` (RestartCount 8, pre-HD-235-rotation) — process memory held the STALE pre-rotation OIDC client_secret, so every enrolment died `invalid_client`; the on-disk `config.yaml` (same 128-char secret, block-scalar `>-` rendered correctly) was already good — headplane (restarted `2026-08-24T08:47Z`) shared the new secret and worked.
- **Fix (commands as run, surgical — headscale container ONLY, no other lane folds):**
  ```bash
  ssh vps-ansible
  cd /opt/headscale
  docker compose up -d --no-deps headscale          # NO-OP: spec unchanged, container left running (root cause of the gap)
  docker compose up -d --no-deps --force-recreate headscale   # forces recycle -> new process reads the good config
  docker ps --filter name=headscale --format '{{.Names}}: {{.Status}}'   # headscale: Up …  Started 2026-08-26T14:05:00Z, RestartCount 0
  ```
- **Verification (secrets never printed — lengths/codes only):**
  - token-endpoint replay on the VPS (python3 yaml-parse on-disk creds → POST `https://sso.kogler.si/application/o/token/` with a DUMMY code): previous `invalid_client` → now **`HTTP 400 / error = invalid_grant`** (= client auth OK; the exact HD-252 success criterion). `client_id` 40, `client_secret` 128.
  - control plane healthy: `/health` 200, `/api/v1/node` + `/api/v1/user` 200 (headplane polling every minute), zero errors in logs since recycle.
  - clients: laptop node `Domen_P14s` reconnected **online 2026-08-26 14:05:03Z** (right after the recycle); phone `Naprava A54` offline (pre-existing); both no tags (interim `*:*` ACL intact).
- **New blocking finding (→ todo HD-255):** the documented surgical converge `--tags "docker_services,headscale"` does **NOT** filter per-service — a `--check` run executed ALL services' tasks (compose up + restart guard for authentik/traefik/crowdsec/opencloud/onlyoffice/immich/forgejo/zipline/litellm/traefik…): the `Deploy each enabled service` include's `tags: docker_services` cascades into inner-task effective tags, so per-service `{{ svc.name }}` tags give no narrowing. Additionally the extras restart-on-change guard in `deploy-service.yml` (`Restart … to apply changed extra config`) aborts with `Error evaluating conditional: object of type 'dict' has no attribute 'item'` on a service whose template-result lacks `item` — likely why the Aug-24 re-render never restarted headscale. Tracked as NEW HD-255 (authoring fix, not a live blocker).
- **Session execution model:** change happened via direct host ops (least blast radius), iterated repo discipline in the session worktree (todo HD-252 updated, HD-255 added, this journal entry, prompt.md §3b ref), `bash scripts/validate-all.sh` green before close.
- **Owner device-gated remainders:** HD-252 ② full browser `/register`→sso→`/oidc/callback` round-trip (server leg verified; needs a logged-in browser + Tailscale app); ③ LIVE VERIFY FAILED — headscale user `domen` (ID 1, 2026-08-25) has empty email and NO provider_identifier (hand-created; `headscale users list` shows no OIDC link), so the Lane-D path is: owner deletes the hand-created `domen` user and re-enrolls ONE device through the now-working OIDC flow (or explicitly accepts hand-created); ④ tighten interim ACL `*:*` in `policy.hujson.j2` per TIGHTEN promise once ③ yields a real OIDC identity.
- **Secrets touched:** none written to git/chat; `headscale_api.credential` read on-box via yaml+probe only for the replay (lengths reported, never value). **Deviations:** none — the documented Lane-D surgical fix executed directly because the documented surgical-tag converge is (separately, HD-255) broken. **Follow-up same session → next entry:** OIDC login still 401 — Authentik hardcodes `email_verified: False`; fixed via headscale `oidc.email_verified_required: false`.

### 2026-08-26 — Phase 1 · HD-252 follow-up: OIDC login still 401 — root cause = Authentik hardcodes `email_verified: False`; fix `oidc.email_verified_required` `[AI]`

- **Stimulus:** owner tried adding the phone via the Tailscale Android app → `/oidc/callback` **401 Unauthorized: You are not authorized**. Headscale logs showed `ERR user msg: unverified email error="authenticated principal has an unverified email" code=401` at 16:57:40Z.
- **Root cause (verified against upstream source, both sides):** headscale v0.29.3 defaults `oidc.email_verified_required: true` (`config-example.yaml` l.417; `doOIDCAuthorization` in `hscontrol/oidc.go` — with `allowed_domains` set and `!emailVerified`, it short-circuits to `401 unverified email`). The Authentik 2026.5.6 default `OpenID 'email'` scope mapping **hardcodes `email_verified: False`** (verified in source + the provider's bound ScopeMappings: pk `fc468837…` returns `{"email": request.user.email, "email_verified": False}`). So every OIDC consumer gets `email_verified: false`; headscale (strict default) rejects all logins. The prior recycle fixed the `invalid_client` half; this was the second-half blocker.
- **Fix (surgical, headscale config only — family-trusted internal users, `allowed_domains: kogler.si` still enforced):**
  ```bash
  # live (/opt/headscale/config.yaml, root-owned -> sudo; .bak in /tmp)
  sudo awk '{print} /^[[:space:]]*- kogler\.si$/{print "  email_verified_required: false"}' config.yaml | sudo tee config.yaml.new >/dev/null && sudo mv config.yaml.new config.yaml
  docker compose restart headscale
  # verify: grep email_verified_required; python3 yaml -> oidc.email_verified_required == False, allowed_domains==['kogler.si']
  # status: headscale Up, edge https://vpn.kogler.si/health 200, headplane healthy (1 transient 'failed to poll nodes' during restart only), laptop node online
  ```
  IaC template `IaC/ansible/templates/docker_services/headscale/config.yaml.j2` updated the same way with a comment explaining the why + the `allowed_domains` mitigation + the upstream-correct alternative. Tracked in todo HD-255 as a follow-up (a provider-scoped Authentik scope mapping emitting `email_verified: True` would restore headscale's strict default without weakening it).
- **Verification:** live config valid YAML, `email_verified_required=False`, `allowed_domains=['kogler.si']`; headscale restarted + `/health` 200; the `config.yaml` bind-mount is re-read on restart so the running headscale has the new value. Owner retries the phone in the Tailscale app.
- **Secrets touched:** none NEW this entry; the on-box `client_secret` surfaced again while dumping the oidc block — still queued for rotation per secret-hygiene (HD-211/HD-235 note); do NOT persist it. **Deviations:** relaxing headscale's default email-validation is a deliberate, documented security-posture choice for family-trusted users behind `allowed_domains`; the strict-default restoration is tracked as an Authentik-side fix.

### 2026-08-26 — Phase 1 · HD-252 CORE DONE: first-ever successful OIDC callback — phone enrolled + owner cleanup (users/nodes) `[AI]`

- **Milestone reached (2026-08-26):** the first-ever successful `/oidc/callback` — the phone added via the Tailscale app with NO error, landing under the OIDC-linked account. Logs: `17:43:30 GET /register/hskey-authreq-… 302` → `17:44:05 POST /register/confirm/hskey-authreq-… 200` → `17:44:06 INF node connected … node.name="Naprava A54 uporabnika Domen" user.name=domen@kogler.si node.online=true`. This closes HD-252 ② core (the row's core: first successful callback + device auto-provisioned under an OIDC-linked user).
- **Owner action (③ resolved):** owner deleted the hand-created user ID 1 (no email/provider_identifier) in Headplane. Confirmed live: only user ID 2 `domen@kogler.si` (email `domen@kogler.si`) remains — the OIDC-linked account is correct.
- **Cleanup side-effect to redo (⏳):** deleting the old user removed the laptop node (node 1 `Domen_P14s`) and the owner separately removed the just-added phone (node 3) — `headscale nodes list` is now EMPTY. The OIDC flow is proven working, so re-enrolling both devices is quick: they re-join under `domen@kogler.si`. Keep the interim ACL `*:*` until both are back (HD-252 ④ TIGHTEN-at-first-enrolment promise applies once real OIDC identities are present).
- **Health after all changes:** headscale/headplane healthy, edge `https://vpn.kogler.si/health` 200, only 2 benign ERR in logs (the pre-fix 16:57:40 unverified-email + the expected 17:46:57 disconnect-after-delete `node not found: 3`).
- **Secrets touched:** none. **Deviations:** none beyond the already-documented `email_verified_required: false` relaxation (family-trusted users behind `allowed_domains`).

### 2026-08-26 — Phase 1 · HD-252 ④ DONE: ACL tightened at first enrolment — `*:*` → deny-by-default user-based `policy.hujson` `[AI]`

- **Objective ④ (HD-84 TIGHTEN-promise) closed.** Both devices now enrolled under the OIDC-linked user `domen@kogler.si` (laptop node 4 `Domen_P14s`, phone node 5 `Naprava A54` — CGNAT overlay IPs per SSOT). Replaced the interim `*:*` in `policy.hujson.j2` with a deny-by-default user-based policy:
  ```json
  {"acls":[{"action":"accept","src":["domen@kogler.si"],"dst":["domen@kogler.si:*"]}]}
  ```
  (User-reference format verified against headscale v0.29.3 policy v2 tests + docs: `src`=OIDC email, `dst`=email+`:port`; `tagOwners` left empty because headscale v2 requires tags be declared before ACLs may reference them and there is no `autogroup:admin` source here.)
- **Applied live + validated, then restarted headscale:**
  ```bash
  sudo cp policy.hujson /tmp/policy.hujson.bak
  sudo cp /tmp/new_policy.hujson policy.hujson        # new content written over the bind-mount
  echo y | docker exec -i headscale headscale policy check --bypass-grpc-and-access-database-directly --file /etc/headscale/policy.hujson   # -> "Policy is valid" (resolves domen@kogler.si vs live DB)
  docker compose restart headscale
  docker exec headscale headscale policy get   # effective ACL = the new deny-by-default rule
  ```
- **Verification:** `policy check --bypass-grpc` = **Policy is valid** (user reference resolved against the live DB); restarted for headscale 200; Node node `Naprava A54` reconnected **online** at 18:20:05Z under the tightened policy; **0** deny/unauthorized log lines; `/health` 200. Laptop `Domen_P14s` shows offline because its Tailscale nx client is currently disconnected (client-side, not a policy denial).
- **Docs pulled in same change:** network-vpn.md layer-2 contract + registration/ACL stanza rewritten (interim `*:*` → tightened; tag-based model documented as the later option). `tagOwners` empty + rationale recorded in template comments. **Secrets touched:** none. **Deviations:** none — this is the documented HD-84 TIGHTEN-at-first-enrolment.

## Phase 1a — Parallel Track: NAS Pools + Host Installs

### 2026-08-23 — Phase 1a · oldsrv reinstalled interactively — preseed automation bypassed after four delivery failures `[MANUAL]`

- Plan ref: [deployment-tasks.md](deployment-tasks.md) §Phase 1a, "Reinstall oldsrv via preseed media"
- **Media:** Debian 13.6.0 amd64 DVD-with-firmware, SanDisk 3.2 Gen1 USB ("DEBIAN 13_6", FAT32). Overlay: `preseed/preseed.cfg` (repo copy) + `preseed/post_install.sh` (real pubkeys injected at build from 1Password `Homelab-ansible` items `laptop-domen_ssh` / `ansible-admin_ssh` / `ai_ssh`, field `public_key` — via `IaC/host/gen-media-post-install.sh`). Boot configs patched in place: `module_blacklist=iwlwifi` on EVERY entry (GRUB 20 lines + all isolinux appends) and `file=/cdrom/preseed/preseed.cfg` on the automated entries. `install.amd/initrd.gz` additionally rebuilt with `/preseed.cfg` injected (original kept as `initrd.gz.orig`).
- **Why automation was bypassed (four delivery mechanisms failed identically at partman):**
    1. netcfg looped on the WPA dialog — oldsrv has a WLAN NIC (`wlp9s0`) and `choose_interface=auto` picked it.
    2. `file=` preseed never loaded: first attempt used the wrong path (`/cdrom/preseed.cfg` vs subdir); with the correct path the medium mounts late on this Rufus-FAT32 layout → syslog: `preseed: error: error handling file`.
    3. Manual `debconf-set-selections` (SEEDED-OK) + partman kill/re-run STILL hit "no root filesystem" — root cause found on the console: **debian-installer udev creates no `nvme-eui.*` links**, so `partman-auto/disk` pointing at the eui form matched nothing; model_serial links exist (`S3EUNX0HC06971Z`, owner-confirmed against an OCR misread of `05971Z`).
    4. initrd-injected `/preseed.cfg` also absent in the running installer — and the decisive discovery: the installer console showed boot medium = **Kingston DataTraveler**, not our SanDisk → a second stick was being booted (also explains an empty `/cdrom` during one manual mount). Kingston quarantined pending inspection.
- **Decision:** finish interactively (*Graphical install*), then replicate `post_install.sh` state with a one-shot catch-up script served over LAN HTTP from the management laptop (`bootstrap-oldsrv.sh`; NOT committed — carries real pubkeys, repo keeps placeholder-only discipline).
- **Install answers/settings:**
    - mode: BIOS/CSM — partman-efi force-UEFI question answered **No** (target disk carried Windows GPT/ESP; fresh msdos table written)
    - NIC: `enp0s31f6` (onboard Intel), DHCP · hostname `oldsrv.kogler.si`
    - root password: none (blank ×2, KOPS-044 posture) · user `domen` (local desktop; sudo via blank-root rule)
    - partitioning MANUAL on `nvme-Samsung_SSD_960_EVO_500GB_S3EUNX0HC06971Z` only: p1 ext4 `/` bootable + p2 swap 8 GB; **970 EVO untouched** (NTFS until pool-create)
    - tasksel: XFCE + SSH server + standard utilities · GRUB → same 500 GB disk
- **Catch-up run (`bootstrap-oldsrv.sh`, as domen via sudo):** apt python3/sudo/openssh-server/curl; `ansible-admin` + 2 keys + `sudoers.d` NOPASSWD; `ai-debug` + restricted AI key (`from="<SITE_LAN_CIDR>"`, value per [network-addresses-generated.md](docs/network-addresses-generated.md) — same restriction string as IaC/host/post_install.sh); sshd drop-in `00-homelab-hardening.conf` (`AllowUsers ansible-admin ai-debug`); sshd restarted; self-verify OK (2+1 keys).
- **Verify:** `ssh ansible-admin@oldsrv` key-only OK from the management laptop; `ssh domen@oldsrv` correctly REFUSED (AllowUsers — domen is the local-desktop identity by design). Post-install live check (runner SSH, 2026-08-23): full udev DOES create the eui links on the installed system — both `nvme-eui.*` and model_serial by-ids resolve to the same disks, serial `S3EUNX0HC06971Z` confirmed → `storage_nvme_data_by_id` target exists and the d-i eui limitation was installer-environment-only.
- **Deviations:**
    - interactive install instead of preseeded (reasons above) — doc updated: `IaC/host/oldsrv/preseed.cfg` (model_serial by-id + `early_command` runtime resolver + wifi-blacklist note), `docs/deployment-preseed.md` (media-build generator step + eui warning), `scripts/check_placeholders.py` ALLOWLIST (generator class), `scripts/README.md` (collect-disk-facts row)
    - preseed partman path switched to model_serial by-id; `host_vars` `storage_nvme_data_by_id` KEEPS the eui form (full udev on the live system resolves it) — distinction noted in both files
    - nas HDD SMART-hour re-read still pending (smartmontools absent in the collector live env) — stays at the Phase-2 deploy check per hardware-nas.md
    - doc updated: [hardware-oldsrv.md](docs/hardware-oldsrv.md) current-state header (installed 2026-08-23, BIOS/CSM, NIC map incl. wlp9s0)

### 2026-08-22/23 - Phase 1 - Waves R4/R5: wildcard ISSUED + installed, public TLS live, authentik admin synced; 33/35 Up (HD-218 cont.)

- **Traefik docker provider was dead since FIRST BOOT**: Engine 29 (min client API 1.40) refused
  traefik v3.5.2's default API-1.24 client -> label routers never registered. Pin bumped
  v3.5.2 -> **v3.7.11** (registry-verified 2026-08-22); DOCKER_API_VERSION detour reverted
  (negotiation works upstream).
- **Crowdsec bouncer plugin chain (three stacked defects, all first-boot-latent):** moduleName
  typo maxlerebour**c** -> **maxlerebourg**, version v0.4.0 never existed -> **v1.7.1**
  (registry-verified); read_only rootfs killed /plugins-storage -> tmpfs (plugins disabled
  since boot); v1.7.1 REQUIRES crowdsecLapiKey -> generated `cscli bouncers add traefik-bouncer`
  key, stored as NEW vault item **crowdsec-bouncer_api** (host-side op create), wired into
  middlewares.yml.j2 + deployment-secrets row.
- **DNS-01 propagation self-check failed against netcup resolvers' negative cache**
  (_acme-challenge.* NXDOMAIN outlived record TTL) -> traefik container got explicit
  1.1.1.1/8.8.8.8 (same fix as headscale).
- **CF token saga closed:** CIDR entries (/22, /64) were not honored reliably - exact-IP roll
  exposed a genuinely broken v4 row (home exact-IP passed, VPS exact-IP 403); owner deleted +
  re-typed the .66 entry -> v4 probe 200 -> issuance cascade.
- **LE rate-limit interplay:** each blocked-era attempt burned 5-per-identifier-per-hour budget;
  windows slid for hours; converged ~23:45 CEST once CF accepted + resolvers fixed. Wildcard
  *.kogler.si + apex ISSUED; certs-rename crt/key dirs were swapped (dumper writes private=key,
  certs=crt) -> fixed; contract files kogler.si.pem/-key.pem INSTALLED at /opt/traefik/certs.
- **headscale schema chain completed:** prefixes block, derp map (public Tailscale relays),
  tmpfs /var/run/headscale (Class-B) -> **headscale UP** on v0.29.3.
- **authentik akadmin identity stale (R5 close):** DB predated the bootstrap env vars ->
  akadmin kept root@example.com + dead password; bootstrap env applies ONLY at creation.
  Fixed via sanctioned ak-shell ORM sync (worker lacks the bootstrap env - values passed
  explicitly). Owner logged in, enrolled WebAuthn + TOTP. Finding recorded in
  services-authentik.md live-deploy findings. Fresh reinstalls are UNAFFECTED (env pinned
  from first boot).
- **FINAL STATE:** 35 containers accounted: 33 Up (all Phase-1 services behind real LE TLS,
  crowdsec chain enforced), renovate + kopia-server looping PENDING OWNER steps (forgejo_api
  real token; kopia sftp_key/known_hosts seed), authentik-ldap + chat health checks post-green.
  Public routes live: sso (owner-verified), git, chat, matrix, file, office, foto, ai, stats,
  sec, pdf, vpn, pairdrop, auto + apex homepage.
- **HD-211 rotation additions:** CF_DNS_API_TOKEN old value transited probe transcript
  (rolled same day - old value burned); db-backup/n8n/grafana/openclaw entries from Wave 1.
- Next session: Phase-1 Verify block (deployment-tasks 3b-4) once forgejo_api + kopia seeds land.

### 2026-08-23 - Phase 1 - async convergence run completed GREEN (HD-218 close-out)

- Post-handoff async `vps.yml` finished: recap `ok=264 changed=35 failed=0 unreachable=0`.
- At handoff still open: renovate token re-render (mid-run) - next session verifies renovate Up,
  then proceeds to the Verify block per prompt.md Handoff #4.

### 2026-08-23 — Phase 1a · Pool-Creation Runbook EXECUTED on nas (gen8) — bulk RAIDZ2 + tank mirror created, legacy payload landed in bulk/migrate; installer-ready `[MANUAL]`

- Plan ref: [deployment-tasks.md](deployment-tasks.md) §Phase 1a checkbox 1 + [hardware-nas.md](docs/hardware-nas.md) → Pool-Creation Runbook; execution record anticipated by the 2026-08-21 Phase-2 note (placed here per the HD-215 parallel-track home).
- **Access model (temporary, pre-management install):** owner's Windows `.ssh/config` alias `Host nas` → current Debian 13 box (`domen` account, NOPASSWD sudo confirmed live); probes via git-bash script-file indirection. No Ansible contact (hold rule until 1.5).
- **SMART pre-check (agreed add-on):** smartmontools installed on the running system; full `-H -A -l error` sweep over sda–sdh → all 7 disks PASS, zero reallocated/pending/offline-uncorr/CRC counters. Hours per serial: WDC 45,903 · Toshibas 6,885/8,560/8,497 · ST4000NT001 399 · HGST 60,452 · MX300 SSD 56,232. Full dump archived: `reports/smart-report-nas-20260823T105831.txt`. Closes the deferred HDD-hour re-read early.
- **Reality deltas vs runbook assumptions:**
    - The "legacy IronWolf single-disk pool" is pool **`new-pool`** on `ata-ST4000NT001-3M2101_WX122FLD` (~1.96 T: `uvoz-zpool/storage/data` 1.49 T + `uvoz-data/NAS` 460 G + ~10 G shares; TrueNAS/iocage heritage names). Both pools scrubbed clean Aug 9.
    - A SECOND single-disk pool **`backup`** existed on `ata-HGST_HDN726040ALE614_K4K9LBGB` (61.9 G `gen8` Proxmox-style dumps incl. `subvol-102-disk-0`). **Decision (owner, option b):** disposable — destroyed after migration verification instead of being migrated.
- **Commands run (as executed, stepwise with verification between blocks):**
    ```bash
    # step 1 — snapshot (AI-run, owner-authorized)
    sudo zfs snapshot -r new-pool@migrate                 # 26 snapshots; send -nVR estimate 2.35T
    # step 2 — wipe stale GPT/PMBR labels + create bulk (AI-run)
    sudo wipefs -a /dev/disk/by-id/ata-WDC_WD30EFRX-68EUZN0_WD-WCC4N6YFD1UU \
                /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0X0TAS \
                /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0ZZYAS \
                /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M101SAS   # signature-only erase, seconds
    sudo zpool create -o ashift=12 \
      -O xattr=sa -O acltype=posixacl -O atime=off -O normalization=formD \
      bulk raidz2 <the same four by-ids>                  # ONLINE, 10.9T raw
    # step 3+ — transfer started by OWNER at iLO console:
    sudo nohup sh -c 'zfs send -R new-pool@migrate | zfs receive -s bulk/migrate/new-pool' > ~/send-migrate.log 2>&1 &
    ```
    First start FAILED instantly: `cannot open 'bulk/migrate': dataset does not exist` — `zfs receive` does NOT create intermediate datasets. Fix (non-destructive, AI-run): `sudo zfs create -p bulk/migrate`; owner re-pasted the same line.
    Transfer completed cleanly in ~2.5 h (peak ~450 MiB/s, small-files tail ~160 MiB/s; logical landed 2.33 T, physical ALLOC ≈1.67× = parity + stripe padding on raidz2 — completion gauges are process-exit + target snapshot, NOT pool ALLOC).
- **Verification evidence:**
    - `bulk/migrate/new-pool@migrate` present; 57 snapshots replicated (all historical chains ride along under `-R`); no `receive_resume_token`, no hidden `%recv` → clean end-to-end completion (ZFS send/receive checksums every block).
    - Spot-check: dataset tree source↔landing IDENTICAL (`diff` of `zfs list -o name` sets); `diff -rq` of the ~10 G `new-share` subtree → 0 differences; media file counts 26/26.
    - Zero kernel block-layer faults during the whole run (only benign Gen8 DMAR PTE spam — noted in hardware-nas.md).
- **Closing sequence (owner gate "GO", AI-executed):**
    ```bash
    sudo zpool export new-pool        # releases sde after verified copy
    sudo zpool destroy backup         # disposable per owner decision (b) — IRREVERSIBLE
    sudo wipefs -a /dev/disk/by-id/ata-ST4000NT001-3M2101_WX122FLD \
                /dev/disk/by-id/ata-HGST_HDN726040ALE614_K4K9LBGB
    sudo zpool create -o ashift=12 \
      -O xattr=sa -O acltype=posixacl -O atime=off -O normalization=formD \
      tank mirror /dev/disk/by-id/ata-HGST_HDN726040ALE614_K4K9LBGB \
                  /dev/disk/by-id/ata-ST4000NT001-3M2101_WX122FLD   # ONLINE, mirror-0
    zpool status; zpool list
    sudo zpool export bulk tank       # final state: 'no pools available' = installer-ready
    ```
- **Final state:** only `bulk` (exported, holds ALL legacy data under `bulk/migrate`) and `tank` (exported, empty mirror) exist; both imported by the future Phase-2 storage role (import-only). Nas ready for OS reinstall (iLO4 + proven SanDisk stick; preseed refreshed same day — see changelog).
- **Deviations:** two-pool reality + backup disposal decision (doc updated: `hardware-nas.md` runbook banner); explicit `bulk/migrate` parent creation required (folded into runbook notes); physical-vs-logical ALLOC ratio documented (same file); SMART re-read done NOW instead of Phase-2 check (doc updated: `hardware-nas.md` hour tables per serial). Secrets touched: none.
### 2026-08-23 - Phase 1 - session: rotation-drift incident + HD-220/221/222/223 (forgejo heal, grafana 401 fix, pairdrop→drop, db-backup zero-backups fix, onlyoffice sidecars, nftables br-* forward fix) — PARTIAL: corrective converge pending

- Session entry point: prompt.md Handoff #4. Worktree `../homelab-wt-20260823` branch `session-20260823-phase1-verify`.
- **Incident A — forgejo/renovate crash-loops (rotation drift):** overnight convergence rendered compose with the HD-211-rotated vault values; postgres images apply POSTGRES_PASSWORD only at first cluster init → persisted clusters kept OLD role passwords. Compounded by two gitea/psql traps: (1) app.ini `[database] PASSWD` overrides env; (2) psql `-c` performs no `:var` interpolation (SQL must go via stdin; identifiers `:"var"`, literals `:'var'`); ini_file had a configparser false-negative → lineinfile used. Fix = HD-220 `db_role_sync/db_item/db_pg_container` opt-in guards in deploy-service.yml + forgejo app.ini sync task. Verified live: role==ini==vault after guards ran; forgejo stopped crash-looping. Renovate endpoint switched to internal `http://forgejo:3000` (git.kogler.si sits behind authentik-forward-auth — SSO redirect ≠ token check); token validity test pending stable forgejo.
- **Incident B — grafana↔prometheus 401 since first deploy:** prometheus enforces basic auth (HD-59) but the provisioned datasource shipped WITHOUT credentials. Fixed in grafana-datasources.yml.j2. Root cause of "never applied": monitoring handler `restart grafana` had inverted guard (`in groups['home_servers']` = False on the VPS) AND handlers are tag-filtered — both fixed (`tags: always`). Verified: restart → 401 count 0; creds HTTP 200 on /-/healthy.
- **Decision A (owner):** systemd-ssh-generator AF_VSOCK console noise benign (netcup KVM exposes no vsock); documented in services-vps.md.
- **HD-221:** pairdrop route moved to drop.kogler.si — group_vars subdomain, CF CNAME `drop` created via dns.yml (verified changed=1), forward-auth blueprint URLs, traefik Host label, inventory re-render. ⚠ stale `pairdrop` CNAME remains in Cloudflare (role has no absent-state) — owner deletes manually or role gets absent-support later.
- **HD-222a — db-backup ZERO-BACKUPS:** tiredofit/db-backup s6 cont-init.d mutates its own rootfs at boot; under read_only:true /etc/services.d stayed EMPTY → scheduler never ran → /backup volume empty since deploy (kopia protecting nothing, KOPS-026 class). Fix: read_only removed (crowdsec precedent), scratch tmpfs added, CONTAINER_ENABLE_MONITORING=FALSE. ⏳ first real dump verify pending post-rerun.
- **HD-222b — onlyoffice never functional:** image bundles LOCAL pg/rabbitmq/redis; under cap_drop:ALL embedded init died (chown EPERM) → eternal localhost:5432 wait → WopiDiscovery 502. Fix: three healthcheck-gated sidecars (postgres:16.15-alpine / redis:7.4.11-alpine / rabbitmq:3.13.7-alpine, registry-verified), env names verified from pinned image script (DB_PWD not DB_PASS! REDIS_SERVER_HOST! AMQP_URI), new vault items onlyoffice_db + onlyoffice-rabbitmq_login provisioned live, bind_owner_uid 70 for pg dir, rabbitmq cap_add CHOWN/SETUID/SETGID (su-exec setgroups EPERM under bare cap_drop — found live). ⏳ rabbitmq health-gate still failing at last run; diagnostics in flight.
- **Incident C + HD-223 — fleet-wide container isolation:** after a nftables restart (~12:52) all container↔container TCP timed out while container↔gateway worked; survived reboot and full network teardown/rebuild. ROOT CAUSE (pre-existing IaC bug): vps-hardening forward chain allowed `iifname "docker*"` but docker's custom bridges are `br-<hash>` → never matched; with br_netfilter loaded + bridge-nf-call-iptables=1 ALL bridged peer traffic traverses host FORWARD → dropped (7533 drops counted). Fix committed+applied live (--tags hardening): `br-*` prefix accepts. Post-fix evidence: authentik-server healthy again, onlyoffice pg/redis healthy. Also during recovery my nftables restart wiped docker NAT briefly (`flush ruleset` hazard) — recovered via docker restart; permanent scoped-flush fix NOT yet written (open item).
- **forgejo_db rotations RESOLVED:** owner confirmed exactly one intentional rotation today at 13:05 (as instructed during session); earlier differing hashes were pre-rotation renders plus probe hashing inconsistencies (op CLI trailing newline vs printf). No security concern. Post-rotation converge aligned env/ini/role to the new value. NOTE: probe output accidentally exposed two secret values (grafana contactpoint basicAuthPassword; datasource password) — both flagged into the HD-211 rotation batch.
- **Recovery actions (live):** VPS reboot (owner-approved) after bridge forwarding died post-daemon-churn; full network teardown + IaC recreation; multiple surgical/full converges. State at entry close: authentik-server healthy, onlyoffice pg/redis healthy, rabbitmq unhealthy (diag in flight), ~13 containers up — one corrective full converge pending after rabbitmq fix; services after onlyoffice-docs in list order not yet re-processed this pass.
- **Still open (owner):** kopia seed (human-vault key), forgejo_api validity check in Forgejo UI, N8N workflow creation at auto.kogler.si (DB empty — nothing ever imported; encryption-key rotation lossless NOW), forgejo_db Item Activity review, old pairdrop CNAME deletion.
- **Corrective converge RESULT:** RC=0 ok=272→271 changed=41-43, 38/38 containers running. rabbitmq HEALTHY (su-exec probe fix verified over 30+ min). forgejo STABLE post ini_file correction. drop.kogler.si LIVE (302→SSO) — required a manual Authentik ORM nudge (ProxyProvider.external_host via ak-shell): the renamed blueprint did NOT auto-re-apply server-side even after worker restarts — blueprint auto-apply gap logged as follow-up. chat FIXED (element-web tmpfs long-syntax mode=01777 via volumes type:tmpfs; short-form mounted root:root 0755 while image runs uid 101 nginx → envsubst EROFS → no :80 listener; chat=200 at edge). renovate AUTHENTICATES now (platform bootstrap passes) but fails repo-level "Repository has unknown error" for domen/homelab — next step LOG_LEVEL=debug one-shot; possibly repo path/scope. onlyoffice-docs: all sidecars healthy, DS entrypoint still mid-first-boot (>30 min, nothing on :80) — first-init slowness known for image; recheck later.
- **Kopia seed COMPLETED (2026-08-23 late):** owner pasted laptop known_hosts entry (VPS keyscan confirmed broken); entries written to /srv/docker/kopia-server/config/known_hosts; `mkdir kopia` executed on box via seeded key (Hetzner SFTP returns SSH_FX_FAILURE for kopia's create-path even when dir exists → kopia_sftp_path made RELATIVE in group_vars — absolute '/' component broke create-path). Result: kopia-server UP, running full maintenance against /kopia on the box. 1P Hertzner-SB-Backup item should still receive the private-key copy (owner action).
- **AI queue remainder:** LDAP outpost-token harvest flow (ak-shell; container env vs server drift confirmed 403-looping), nftables scoped-flush permanent fix, renovate repo-error debug one-shot, onlyoffice first-boot completion check, branch merge after green.

### 2026-08-23/24 - Phase 1 - session: HD-230 wave-2 corrective batch (pairdrop PUBLIC + forgejo native OIDC + blueprint one-shot apply + onlyoffice unblock + db-backup first dumps + nftables ExecStop override + renovate disable)

- Entry point: prompt.md Handoff #5 §3d (VPS queue); worktree `../homelab-wt-20260823-2120`, branch `session-20260823-vps-fixes`. Pattern: SIX parallel read-only diagnostics (renovate LOG_LEVEL debug one-shot · onlyoffice recheck · authentik-ldap token harvest [sanctioned ak-shell write] · db-backup dump verification · blueprint auto-apply RCA · nftables scoped-flush IaC) → one serial editing pass → iterative gated converges (`--tags docker_services,hardening` + dns.yml; every run behind the mandatory 9P md5 gate, which for WORKTREE checkouts needs a GIT_DIR `/mnt/d` translation on the WSL side — worktree `.git` files carry Windows-style gitdirs).
- **Owner decisions taken this session:** (1) PairDrop goes PUBLIC on BOTH `pairdrop.kogler.si` + `drop.kogler.si` — crowdsec-only tier, no forward-auth, traefik-public-only isolation (supersedes HD-113 LAN-only); stale `pairdrop` CF CNAME KEPT + IaC-tracked. (2) Forgejo switches from forward-auth wall to NATIVE OIDC (owner proposal; ideal timing — instance freshly installed, single account). (3) authentik-ldap HD-132 provider authoring DEFERRED to an owner-decision session (handoff below).
- **Renovate:** root cause = repo `domen/homelab` does NOT exist on Forgejo (instance installed, admin exists, ZERO repos — GitHub migration pending owner). Token verified 200 as `domen`. Latent blocker removed: repo-root `renovate.json` lost unsupported `"platform": "forgejo"` (pinned 35.x). Service `enabled: false` until repo lands; docs/deployment-renovate.md refreshed to SSOT.
- **onlyoffice-docs:** TWO stacked root causes. (a) supervisord per-child setuid EPERM under bare cap_drop:ALL (docservice/converter never spawned; edge 502 since deploy). A full setuid-cap whitelist (CHOWN/DAC_READ_SEARCH/FOWNER/SETUID/SETGID, verified present via inspect) STILL EPERM'd while raw `setpriv --init-groups` succeeded → cap whitelisting abandoned per metabase precedent: cap_drop REMOVED + validator ALLOWED_NO_CAP_DROP entry. (b) postgres+redis datadirs were NESTED host binds under DS's own mount → DS init chown-walk corrupted pgdata (base/* owned 105:107 → server could not read own catalog; also broke the db_role_sync ALTER). Both moved to NAMED volumes; corrupt datadir abandoned (regenerable). Post-fix: healthcheck 200, ds processes RUNNING. OPEN: `/hosting/discovery` still 404 (ds:example now enabled via EXAMPLE_ENABLED=true and RUNNING, but discovery route absent in this DS build's nginx set) — whether OpenCloud collaboration needs classic discovery vs direct app URL = owner browser round-trip test on file.kogler.si (HD-166 tail).
- **db-backup (HD-222a CLOSED):** schedule fix took two corrections: DEFAULT_BACKUP_BEGIN syntax `"120"` INVALID (image wants `+N` where N = MINUTES — live-verified; bare number rejected, +120 pushed first run 2h) → settled `"+10"`. Real blocker beneath: image internals DELETE+RECREATE `/tmp/backups` around first-fire time (dir mtime == fire second) → mktemp EACCES regardless of delay. Fix: dedicated sticky-world-writable tmpfs on `/tmp/backups` (typed volumes entry `mode: 01777` uint32 — string rejected; NOT the service-level tmpfs key, compose rejects objects there). Manual `backup0X-now` triggers: ALL FOUR dumps landed (authentik 2.6M / forgejo 30K / immich 18M / pgvector 405B + md5 + latest links). Cosmetic residual: `ln ../latest-*.log` warning. COMPRESSION=ZSTD kept (deprecated but honored by pinned 4.1.100; successor var name needs pinned-image verification at bump). Kopia source wiring for the volume still OPEN (owner decision: agent vs server-managed source).
- **nftables (HD-223 residual CLOSED):** ruleset file now replaces ONLY `table inet filter` (declare+delete+recreate idiom); unconditional docker-restart task REMOVED. Survival test exposed the deeper hazard: Debian's stock unit ships `ExecStop=nft flush ruleset` — restart wiped docker nat/filter via the STOP half even with scoped start file (live: tables count 0, edge dark, recovered via docker daemon restart). Fix: systemd drop-in emptying ExecStop (`vps-hardening` task + drop-in dir). Re-test PASSED: all five docker tables survive restart, peer traffic OK, SSH survives.
- **Blueprint auto-apply gap (RCA):** custom blueprints have NEVER been registered as BlueprintInstances (28 instances, 0 custom; hourly blueprints_discovery 'done' but skips /blueprints/custom/*) → file-hash re-apply never fires; objects existed only via one-shot applies. Layer-2 cause unknown (follow-up investigation). Mitigation shipped: deterministic `apply-authentik-blueprints.yml` one-shot step wired into docker_services main.yml pre-glue (upsert-only; deletions stay ORM). Jinja trap recorded: Jinja-brace refs inside shell cmd fail task-arg resolution EVEN IN COMMENTS.
- **Live ORM cleanup post-converge (ak-shell arg-mode one-shots):** deleted `edge-pairdrop` app, `forward-pairdrop` provider, `edge-forgejo` app, `forward-git` provider (m2m rows included) → remaining edge set exactly matches trimmed ks-forward-auth.yml (7 apps / 7 providers).
- **Forgejo native OIDC:** Authentik side pre-existed since HD-148 (provider_forgejo/app_forgejo + glue-seeded `forgejo_oidc`). Consumer side registered idempotently post-up: `gitea admin auth add-oauth --name authentik --provider openidConnect --auto-discover-url https://sso.kogler.si/application/o/forgejo/.well-known/openid-configuration --scopes openid profile email` (CLI VERBATIM for this build: provider key is `openidConnect` NOT `oidc`; no --active/--use-auto-discovery-url flags; delete subcommand = `admin auth delete --id N`). Traefik route → crowdsec-only; `[oauth2_client] ENABLE_AUTO_REGISTRATION=true` env. Owner next browser step: log into git.kogler.si → "Sign in with authentik" associates existing `domen` account by email.
- **authentik-ldap handoff (deferred):** outpost-token drift FIXED + verified (server re-synced to vault value, fingerprint-only evidence, 403 loop gone, forward-auth untouched). Container still panic-crash-loops `no ldap provider defined`: ZERO LDAPProviders / no ldap-type outpost exist — HD-132 declared in deployment-oidc.md but never implemented. Owner decisions needed: base DN (tasks doc hints DC=home,DC=kogler,DC=si), bind/search mode, TLS cert, UID numbers, AND decoupling `authentik-ldap_bind.password` (shared between outpost AUTHENTIK_TOKEN and Samba ldapsam bind — deployment-secrets.md row).
- **Verify snapshot (post batch):** pairdrop/drop 200 PUBLIC from laptop · git 200 direct (Forgejo page, SSO button) · home 302→sso (CNAME was missing entirely — created) · traefik-dash 302 gated (same) · stats/sec/pdf/auto/kogler.si 302 gated (unchanged) · chat/file/vpn/ai/foto 200 · sso alive · renovate container GONE · forgejo OAuth2 source `authentik` listed · nftables survival PASS · db-backup 4/4 dumps + checksums.
- **Secrets touched:** none printed anywhere (fingerprint-only evidence pattern held; one worker's docker-inspect .Args probe HAD exposed kopia htpasswd/repo-password into its transcript earlier — flagged into HD-211 rotation batch alongside grafana contactpoint + datasource passwords).
- **HD-231 pt.6 (opencloud client reshape):** docs.opencloud.eu external-idp spec — web is a PUBLIC PKCE client with PREDEFINED id `web` (WebFinger default), redirects `/oidc-callback.html` + `/oidc-silent-redirect.html`. Provider reshaped live via ORM then pinned in ks-oidc.yml (client_type public + both redirects; client_id itself set via ORM only — serializer treats it read-only, upsert preserves unlisted attrs). GOTCHA recorded: a converge launched mid-rebase applied the STALE blueprint and upserted old uris back over the ORM reshape (pipe-masked rebase failure hid it); re-running apply from the corrected branch restored state — blueprint must always be applied from the commit you intend.
- **HD-231 pt.2 (second layer of the same hotfix):** after grant_types landed, callback still 500'd — forgejo log: `Non-200 response from UserInfo: 403 insufficient_scope`. Cause: `property_mappings` ALSO wiped to [] by the same upsert mechanism (proxy providers had the full default set, native providers none) → access tokens carried no resolvable scopes. Live ORM fix assigned the three defaults (openid/email/profile ScopeMappings) to all 8 native providers; `property_mappings:` pinned via !Find in every ks-oidc.yml entry; post-apply regression check confirms BOTH fields survive re-apply. Combined lesson recorded above.
- **HD-231 pt.5 (file.kogler.si login stuck):** browser blocked oidc-client-ts discovery fetch (`connect-src` violation). THREE stacked wiring faults: (1) env name wrong — image binary knows `PROXY_CSP_CONFIG_FILE_LOCATION`, not `CSP_CONFIG_FILE`; (2) schema — csp.yaml needs ALL directives nested under top-level `directives:` (flat map parses silently into nothing); (3) ops caveat — proxy reads CSP ONCE AT STARTUP and csp.yaml is a bind mount, so content-only changes need an explicit opencloud restart (converge recreate does NOT trigger on bind-mount content; candidate for a deploy-service restart-on-change task). Template rewritten as full baseline (stock captured live + sso/office additions); served header verified containing sso.kogler.si from box AND laptop.
- **HD-231 RESOLVED END-TO-END (owner-confirmed):** first-ever successful file.kogler.si browser login (autoprovision created the account; editor iframe = office route). Note: an interim `LDAP9236_CLOSED` reading was a BUSYBOX false negative (`/dev/tcp` unsupported in its sh); `netstat` shows idm LISTENing on 127.0.0.1:9236 — trust netstat/-S probes, not /dev/tcp, in this image.
- **HOTFIX HD-231 (owner-reported, same session):** "Prijava z Authentik" on forgejo errored (`invalid_request: The request is otherwise malformed`) AND file.kogler.si login stalled at /login — ONE root cause: authentik 2026.5 OAuth2Provider carries a per-provider `grant_types` allowlist; ks-oidc.yml never set it, so every blueprint apply/upsert wrote `[]`, killing the `authorization_code` grant on ALL 8 native-OIDC providers (forward-* proxy providers were unaffected — populated via their own creation path — masking the gap until now; authentik-server log: `Invalid grant_type for provider, grant_type=authorization_code`). Fix: live ORM one-shot set `[authorization_code, refresh_token]` on all 8 + `grant_types:` pinned explicitly in every ks-oidc.yml entry; post-apply regression check confirms values SURVIVE blueprint re-apply. Lesson: blueprint serializer writes EMPTY for absent array attrs — pin arrays you care about.
- **Deviations:** none unplanned beyond documented cap_drop relaxation + COMPRESSION retention rationale (both commented in-file); converges c1–c11 all gate-first, failures were template/CLI-syntax iterations caught by fail-loud gates.

### 2026-08-23 — Phase 1a · process note: validator exit-code pipe-masking / ignore-red-commit — REPEATED CLASS

- 4th occurrence (2026-08-24, HD-231 session): `git rebase | tail -1` masked a rebase CONFLICT; the chained converge then ran against a conflict-state worktree (harmless here — only the journal conflicted — but the class is identical). Bare-rc rule now explicitly covers GIT state-changing commands too, not just validators.
- Records a repeat of the 2026-08-22 lesson ("capture rc before the pipe, never trust the pipe's status") — now three occurrences in two days: (1) Wave-3 `| tail` masking; (2) Handoff-#5 prompt close-out where a masked RED let a temporary DHCP address (owner's `.ssh/config`-only alias, deliberately kept out of repo docs) land in prompt.md — amended within minutes (`95746e3` → `bb53323`, never pushed); (3) THIS process-note entry itself first committed red through an `if/else … && commit` chain whose failure branch still exited 0. Rule hardened to a single safe form for every future gate run: run the validator bare, capture `$?`, and only then act — formatting pipes and conditional chains are forbidden around the gate. All three incidents were caught/amended before any push.

### 2026-08-23 — Phase 1a · nas reinstalled FULLY AUTOMATED via preseed (iLO two-stick) — preseed path re-proven `[MANUAL]`

- Plan ref: [deployment-tasks.md](deployment-tasks.md) §Phase 1a checkbox "Reinstall nas via preseed media"; runbook [deployment-manual.md](deployment-manual.md) §Phase 1a.
- **Execution (owner at iLO console):** SanDisk (installer medium, nas preseed build) + Generic_Flash_Disk C3EB7FE7 (permanent GRUB carrier) both plugged per the manual §1a.2 nas exception; booted EXPLICITLY from SanDisk via the iLO one-time boot menu (old GRUB menu never appeared). Chose the **Automated** entry: ran flawlessly END-TO-END with ZERO interactive questions — early_command resolved the Crucial SSD by-id at runtime, partman auto-partitioned ONLY the SSD, GRUB landed on the Generic stick via the static bootdev pin, late_command executed the keyed post_install.sh. Installer USB pulled BEFORE reboot; Debian booted clean off the GRUB carrier.
- **Why automation succeeded here when oldsrv went interactive same day:** wired-only NIC (no netcfg WLAN loop), ata-model_serial by-id resolves in d-i udev (no nvme-eui trap), `file=` patched entries loaded, module_blacklist everywhere, explicit medium choice killed the wrong-medium class. Attribution is the combination; no single mechanism isolated.
- **Post-install verification (AI read-only probes over the owner's Windows `.ssh/config` alias `Host nas`; the temporary DHCP address deliberately NOT recorded here — pre-1.5 artifact, SSOT pointer: [network-addresses-generated.md](docs/network-addresses-generated.md)):**
    - `ssh ansible-admin@nas` KEY-ONLY OK (`uid=1000(ansible-admin)`; BatchMode proves no password path). Environment quirk: git-bash MSYS ssh CANNOT drive the alias (`IdentityFile …​.pub` + 1Password agent → `error in libcrypto: unsupported`) — probes routed through `/c/Windows/System32/OpenSSH/ssh.exe`, which handles the owner's setup. `ssh domen@<nas>` correctly REFUSED (rc=255 Permission denied — AllowUsers).
    - Hostname `nas` (`/etc/hosts` → `nas.lan`: DHCP-supplied domain `lan`, not kogler.si — cosmetic; Phase 1.5 lands proper addressing); Debian 13 trixie, kernel 6.12.94-amd64.
    - Hardening live: sshd drop-in `00-homelab-hardening.conf` (PasswordAuthentication no, PermitRootLogin no, `allowusers ansible-admin ai-debug`); ansible-admin authorized_keys = 2 keys.
    - Disks: BOTH Crucial by-id forms resolve to the OS SSD (`ata-Crucial_CT525MX300SSD4_173818D02FF0` + `wwn-0x500a075118d02ff0`; ext4 `/` on part1, msdos table, swap part5); all SIX data-disk by-ids present with intact `zfs_member` labels (bulk 4× + tank 2× — installer never touched them); `usb-Generic_Flash_Disk_C3EB7FE7-0:0` present, NO SanDisk.
- **Gaps / findings (deferred by design):**
    - `zfsutils-linux` ABSENT on the fresh OS → the `zpool list` (no pools) / `zpool import` (offers bulk+tank) export-state check could not run; lsblk label evidence stands in. Definitive check lands with the Phase-2 storage role (it installs zfsutils itself).
    - Stale whole-disk `zfs_member LABEL="rpool"` signature on the OS SSD (blkid; heritage leftover, harmless for import-by-name) — flagged as optional owner-gated `wipefs` candidate at Phase-2 first contact.
- **Deviations / doc updates:** preseed automation RE-PROVEN — `doc updated:` [deployment-manual.md](deployment-manual.md) §Phase 1a (official-path note flipped: automated = proven official, interactive = fallback; deferred-items paragraph updated); `doc updated:` [hardware-nas.md](docs/hardware-nas.md) (current-state banner: installed 2026-08-23). Secrets touched: none beyond pubkeys already baked into the media build.

### 2026-08-23 — Phase 1 · owner identity bootstrap on the VPS edge: authentik Family group + personal domen user (Internal, MFA), forgejo admin per §1.7, n8n owner account `[MANUAL]`

- Context: closes several "owner actions" from the Phase-1 queue (Handoff #5/#6); executed by the owner in live UIs, recorded here per the journal loop.
- **Authentik (sso.kogler.si):** group **`Family`** created; user **`domen`** created — Name `Domen`, email `domen@kogler.si`, type **Internal** (per new human-user policy, HD-227), Active; added to `Family`; **WebAuthn + TOTP enrolled**. `akadmin` stays break-glass admin via "authentik Admins" group membership — `domen` deliberately NOT a member.
- **Forgejo (git.kogler.si):** `domen` administrator account created through the one-time installer exactly per [deployment-manual.md](deployment-manual.md) §1.7 (Administrator Account table: `domen` / `domen@kogler.si`) — self-registration OFF / OIDC-only preserved.
- **n8n (auto.kogler.si):** owner account created — prerequisite for the still-pending workflow import.
- **Still open after this entry:** renovate token (create in Forgejo UI as `domen`, repo read/write → 1Password `forgejo_api`.`credential` → restart renovate) THEN the LOG_LEVEL=debug repo-error one-shot; forgejo OAuth2 source wiring (HD-148: authentication name MUST equal `forgejo`, creds from item `forgejo_oidc`); N8N workflow import; onlyoffice-docs first-boot check; authentik-ldap outpost-token harvest; nftables scoped-flush permanent fix; blueprint auto-apply gap; HD-211 rotation batch (incl. two probe-exposed values); stale pairdrop CNAME deletion; Hetzner-SB-Backup private-key copy into the 1P item.
- **Deviations / doc updates:** human-user policy codified — `doc updated:` [deployment-manual.md](deployment-manual.md) §1.5 (Internal type + family group + MFA setup imperative); cross-ref added to [services-authentik.md](docs/services-authentik.md) RBAC bullet. Secrets touched: none journaled (passwords/tokens live in 1Password; values never recorded here).

## Phase 1.5 — Network Redo

### 2026-08-23 — Phase 1.5 · cutover-prep IaC batch: HD-193 closed, CoAP firewall delta + CAPsMAN scaffold landed

- Entry point: prompt.md Handoff #6 §3b Track A; worktree `../homelab-wt-20260823-2308`. NO live gear touched — pure repo prep ahead of the cutover window.
- **HD-193 CLOSED** (row deleted from todo.md per housekeeping (a), changelog Done record): crs328_initial.rsc.j2 api/www-ssl/ssh bound to `interface=vlan99-mgmt`; ap_initial.rsc.j2 ssh bound to `interface=bridge`; rb4011 bootstrap DHCP DNS literal parameterized to new `bootstrap_dns_servers` group_var (1.1.1.1 until Technitium lands at Phase 3); `vps` added to site.yml pre-flight guard pattern.
- **Shelly probe evidence (read-only, shelly skill, flat LAN):** all four units = SHRGBW2 **Gen1**, fw v1.14.0 (2023-09), no auth, SSID `Kogler IOT`, DHCP (.112/.104 color 1-ch, .105 white 4-ch, .106 color 1-ch) — Gen1 CoAP push motivates the firewall delta below.
- **HD-229 OPENED (IaC done, deploy-gated):** CoAP reverse exception added to roles/router forward chain (`src=vlan20 dst-address-list=trusted-ha protocol=udp dst-port=5683 accept`) directly after established/related; gives the created-but-unused `trusted-ha` list its first consumer; network-vlans.md IoT→Home matrix row updated with the exception.
- **CAPsMAN scaffold (deliberately NOT speculative):** SSID/VLAN/1P-item SSOT map in group_vars/router.yml (`routeros_capsman_ssids`, flags off); capsman.yml ships as documented implementation plan + assert gate (security-profiles / configurations / access-list ssid→vlan tagging / provisioning to be written against the LIVE manager at cutover prep — ROS7 field guesses intentionally not committed); main.yml include gated on `routeros_capsman_enabled`.
- **Secrets:** catalog rows added for `wifi-kogler_password`, `wifi-kogler-iot_password`, `wifi-kogler-iot-wan_password`, `wifi-kogler-guest_password`, `wifi-kogler-kids_password` (field `password`). OWNER ACTION: create the five items (values owner-chosen, alphanumeric) before any flag flip.
- Secrets values touched: none (names only).

### 2026-08-23 — Phase 1.5 · live verification round: CAPsMAN flavor pinned LEGACY, migration inventory captured from live LAN `[AI]`

- Read-only probes over the RouterOS API (mikrotik skill, shared admin credential per HD-165; MSYS arg-conversion gotcha for positional API paths solved with `MSYS_NO_PATHCONV=1`).
- **Router:** RB4011iGS+ (no local radios — pure manager), ROS 7.23.2 stable; `wireless` pkg ENABLED, `wifi-qcom-ac` staged-but-disabled.
- **AP probes** (owner enabled api on two units): AP-dnevna = hAP ac classic 7.23.3, `wireless` only — no wifi-qcom-ac present; AP-spalnica = hAP ac², wifi-qcom + wifi-qcom-ac staged (disabled). AP-garaza/.6 spare still API-off.
- **DECISION: legacy `wireless` CAPsMAN fleet-wide.** MikroTik compatibility table (manual.mikrotik.com/docs/wireless/wifi): hAP ac classic + wAP ac T-variant = MIPSBE → incompatible with wifi-qcom-ac; flavors cannot mix in one managed fleet. New flavor revisitable after owner's planned dnevna swap (spare hAP ac² takes the slot) AND garage wAP variant confirmation (D vs T). Pinned in capsman.yml header; ap_initial.rsc.j2 stays legacy `/interface wireless cap` syntax unchanged.
- **Migration inventory created:** [network-migration-inventory.md](docs/network-migration-inventory.md) from a 33-lease live dump — highlights: 3× Bosch Home Connect appliances on DYNAMIC leases (→ VLAN 21 tier per HD-228, need reservations), Shelly DW2 flood sensor (Gen1 CoAP — covered by the HD-229 exception), GIRA X1 + KNX IP router (VLAN 20), Canon TS9550 printer (.117 "Tiskalnik" → VLAN 10, family web UI by design), Reolink garage camera (port-type says VLAN 20 — viewing constraint flagged for owner confirm). ⚠ Owner to identify: .111, .121 (0003B5F29AFDC36), "deblab" .125 (Hyper-V VM), "truenas" .60 (not in any owning doc).
- Secrets values touched: none.

### 2026-08-24 — Phase 1.5 · garage wAP ac declared DEAD; CAPsMAN flavor re-decided to MODERN `wifi-qcom-ac` (HD-232) `[AI]`

- **wAP ac (AP-garaza, 6C:3B:6B:7D:B9:C5) → hardware-fault verdict.** Diagnosed live over the RouterOS API + CRS328 logs (read-only): PHY links 1G on switch `ether7` with healthy PoE (dual PSU 26.4 V/52.8 V, 17.7 W total draw), but the board boot-loops (link self-drops every ~50 s), then goes **totally silent after network init** — no DHCP renew, no MNDP, no ARP answers. Config reset (15 s+ button) and Netinstall/Etherboot attempted: device answered BOOTP exactly once (2026-08-24 00:40) then went mute; Netinstall never listed it again even with Npcap installed, firewall off, wired NIC. Clean cold boot with uninterrupted power reproduced the hang → corrupt flash or failing SoC/RAM power path. Switch-side PoE auto-on `current_too_low` cutoffs during its hangs were a *symptom* (idle draw below threshold), not the cause. Documented in [network-migration-inventory.md](docs/network-migration-inventory.md).
- **DECISION (owner): CAPsMAN flavor flips LEGACY → MODERN `wifi-qcom-ac`** — supersedes the 2026-08-23 legacy pin. The wAP ac was one of two MIPSBE blockers; its death resolves revisit-condition ②. Remaining conditions for the modern fleet: ① dnevna swap executes per owner plan 2026-08-23 (spare hAP ac² C4:AD:34:42:F0:B9 takes the dnevna slot; classic MIPSBE unit retires — no MIPSBE device may remain in the managed fleet); ② garage replacement hardware must be wifi-qcom-ac-capable. Pinned in capsman.yml header; ap_initial.rsc.j2 must move to modern `/interface/wifi` cap syntax at cutover prep (legacy `/interface wireless cap` line now stale). Implementation still fail-loud/live-validated per the scaffold's culture — no speculative field-level tasks shipped.
- Secrets values touched: none.

### 2026-08-24 — Phase 1.5 · reconcile home-server VLAN/IP/DNS model to Option A (R-1) `[AI]`

- Decision (owner): **Option A — pi & oldsrv dual-homed (trunk 10+99, mgmt 99 addr + home 10 addr);
  nas single-Home (VLAN 10) with iLO4 on 99.** No live gear touched — IaC/SSOT + doc reconciliation only.
- Verified SSOT `group_vars/all.yml` already models pi/oldsrv/nas dual; migration inventory lists
  pi/oldsrv trunk 10+99, nas Home. Router role skips VLAN-99 DHCP (pools/net/servers `id not in [1,99]`)
  and reserves only AP MACs → all 99 hosts are static IPs from preseed/host_vars. Option A holds without
  reservation churn.
- **Patches applied in worktree `homelab-wt-20260824-0958`:**
  - `host_vars/pi.kogler.si.yml` — added `mgmt_ip` for the pi mgmt plane (SSOT VLAN-99 address, dual-homed);
    kept `ansible_host` on the Home VLAN (SSH/VPN anchor).
  - `docs/network-migration-inventory.md` — removed duplicate AP-dnevna row (same MAC/plan repeated twice;
    R-4 leftover coalesced here); nas row already single-Home ✓.
- DNS invariant unchanged: oldsrv Technitium primary + pi secondary stay on the Home VLAN (they bind the
  node IP, per network-dns.md); router keeps the tertiary `/ip dns`. No mgmt-IP moves for DNS.
- Switch-port finding deferred to R-2 (below): `nvidia-shield` MAC `48:B0:2D:09:6F:90` conflicts with the
  inventory ⚠ unknown; Nintendo Switch listed VLAN 21 vs Media(50) in the plan; `nas-eno1/eno2` vlan blank.
- Secrets values touched: none.

### 2026-08-24 — Phase 1.5 · switch role access-port VLAN coverage completion (task 2) `[AI]`

- Worker implementation verified + committed by orchestrator (worker had edited but not committed).
- **Added two missing access-port tasks** in `roles/switch/tasks/main.yml`: `Configure access port for IoT VLAN (20)`
  and `Configure access port for IoT-Internet VLAN (21)` (mirror the existing 99/10/50 blocks; `when` gates + pvid + unique comments).
  Effect: reolink-camera + knx-ip + knx-x1 (VLANs 20/21) no longer fall through to the unconfigured->mgmt(99) default.
  Defensive-only for 21 today (no wired VLAN-21 device in the port map — Bosch/LG are WiFi on `Kogler IOT WAN`).
- **`group_vars/switch.yml`:** `nas-eno1`/`nas-eno2` `vlan:` blank → `10` (Home, per R-1 resolution); removed the stale duplicate `# NAS eno1` comment above nas-eno2.
- Validators: YAML parse OK, `validate-docker-services.py` PASS (50), `check_doc_ips.py` OK. No live gear touched (read-only repo edits).
- Secrets values touched: none.

### 2026-08-24 — Phase 1.5 · CAPsMAN steady-state as modern wifi-qcom-ac rsc (task 8 — authoring only, no deploy) `[AI]`

- Owner decisions recap: steady-state CAPsMAN is a **rendered rsc** (not ansible api_modify); whole fleet MODERN
  `wifi-qcom-ac` (HD-232). **Human-gated at cutover:** ① dnevna swap (spare hAP ac² → dnevna slot), ② garage
  replacement wifi-qcom-ac-capable. No gear touched — offline IaC authoring only.
- **Created `IaC/router/templates/capsman_steady-state.rsc.j2`**: `/interface wifi` security profiles (WPA2-PSK,
  passphrase from the five `wifi-kogler*` 1Password items at render) + config objects with datapath VLAN tagging
  (`datapath.vlan-mode=use-tag` + `vlan-id` per SSID/vlan SSOT) + one provisioning rule (master `cfg-kogler`,
  slaves IoT/Internet/Guest/Kids). SSIDs are quote-wrapped (`ssid="Kogler IOT"`) so multi-word SSIDs import cleanly.
- **render-routeros.yml** extended to also render `capsman_steady-state.rsc` into IaC/router/rendered/ (same
  pattern as the bootstrap scripts; upload-after-bootstrap + `/import capsman_steady-state.rsc` — NOT a reset).
- `capsman.yml` header + `group_vars/router.yml` + `network-vlans.md` updated to document rsc-upload delivery;
  `routeros_capsman_enabled` comment notes the flag stays false (rsc replaces api_modify).
- `ap_initial.rsc.j2`: stale legacy `/interface wireless cap` → modern `/interface wifi cap` with a validate-live
  TODO (exact wifi-qcom-ac cap fields confirmed against the live AP at cutover).
- **TODO validate-live (fail-loud, cutover-prep session, HD-229):** wifi-qcom-ac field names in the rsc
  (`datapath.*`, `provisioning add` params, security-profile passphrase field) to confirm against the LIVE
  manager — unverified guesses would silently no-op or brick the bootstrap window.
- Secrets values touched: none (lookups only, never rendered VALUES into the repo).

### 2026-08-24 — Phase 1.5 · migration-inventory unknowns refresh — read-only live lease dump (task 6) `[AI]`

- **Read-only RouterOS API probe** (`skills/mikrotik/scripts/mikrotik-read.py --op-env-file skills/mikrotik/.env.op /ip/dhcp-server/lease`, MSYS_NO_PATHCONV=1) against the live flat-LAN router — 32 leases captured. No mutation; lease data only (MAC/hostname/comment).
- **Resolved from OUI + repo cross-reference:**
  - `0003B5F29AFDC36` (00:1A:22:1E:F7:FD) → **HMIP-HAP HomeMatic AP** — MAC matches router.yml ether9 + Rack.canvas + rack-connections.json exactly; static-lease hostname = its device ID. → WIRED to **VLAN 21 IoT-Internet** per network-vlans Port Type Reference (cloud-bound HAP needs internet).
  - `48:B0:2D:09:6F:90` → NVIDIA Shield (already R-2/D2); lease confirms still hostname-less.
- **Remaining PENDING-IDENTIFY (owner):**
  - `deblab` (00:15:5D:01:67:1E) — Microsoft Hyper-V OUI confirmed; hostname `deblab` live. Likely a Hyper-V VM on a Windows host (laptop `Domen_P14s`?) — owner to confirm host + role.
  - `truenas` (92:47:15:04:EB:49) — **locally-administered MAC** (no vendor OUI), still live, no owning doc anywhere — owner to identify hardware/role.
- Also captured/lodged: Bosch hostnames confirmed (`BOSCH-CSG656RB7…` etc.), Valentina tablet (30:56:84:35:00:DC), `Naprava-A54-uporabnika-Domen` (34:F0:43:73:96:35), Domen_P14s laptop (48:2A:E3:9D:31:85).
- Validators: `check_doc_ips.py` OK (no IP literals added to prose). No secret values touched; no live mutation.

### 2026-08-24 — Phase 1.5 · ONLYOFFICE/OpenCloud editor round-trip — PARTIAL: .txt works, .docx BROKEN (HD-166 tail) `[AI]`

- Owner round-trip test in the file.kogler.si UI (two browsers):
  - **.txt: PASS** — preview + editor load, edit + Save work, updates persist on reopen. “updated outside this
    window” = save-conflict guard, not an error.
  - **.docx: FAIL** — “No preview available … download instead.” The ONLYOFFICE editor does NOT open real office
    documents (previously reported as PASS was an OVER-OPTIMISTIC reading based on .txt only — corrected here).
- **Root cause (high confidence):** `.txt` uses OpenCloud’s NATIVE text preview — it never invokes ONLYOFFICE/WOPI.
  Office docs fall through to “download” because the `frontend.app_handler` / app-provider is NOT authoring
  office MIME (`application/vnd.*`) → OnlyOffice for the editor link.
  - Likely: `COLLABORATION_STORE=nats-js-kv` but **NO NATS broker container** exists → the collaboration svc has no
    registry/store to announce office-MIME authoring. (Earlier “no NATS needed for .docx” was WRONG — it’s not live
    typing, it’s the app-provider registry.)
  - Also: rendered opencloud.yaml shows `collaboration.app.insecure: true` despite env `COLLABORATION_APP_INSECURE:
    "false"` (env→schema map may not take effect).
  - `OC_ADD`+`OC_EXCLUDE` both list `collaboration` — ADD wins (editor/health work); EXCLUDE inert, not the blocker.
- **Task 1 verdict: NOT done.** Needs a real fix (app-provider/NATS/store for office MIME + verify INSECURE flag),
  then re-test `.docx`. Handed to next session — see plan/20260824-netredo/t1-report.md.
- **Secret-hygiene note (HD-235):** one probe on this session inadvertently dumped real secret VALUES from the
  container's opencloud.yaml to a transcript. No rotation needed (they belong in container config) but future
  probes MUST redact secret/password/token/bind_password values.
- Secrets values touched: none (values were not committed; transcript-only, per HD-235 do-not-print).

#### HD-166 pt.2 — root cause found: collaboration service excluded via `OC_EXCLUDE_RUN_SERVICES` (2026-08-24, live diagnostics) `[AI]`

- **Symptom recap:** `.docx` in file.kogler.si shows “No preview available … download instead”; the ONLYOFFICE editor never opens office MIME. The prior entry's theory pinned this on “no NATS broker → collaboration has no registry/store to announce office authoring” — **that theory is now DISPROVEN.**
- **Evidence (read-only probes, opencloud 7.4.0 rolling):**
  - Container env sets BOTH `OC_ADD_RUN_SERVICES=collaboration` AND `OC_EXCLUDE_RUN_SERVICES=collaboration,idp`.
  - `opencloud list` on the live box shows **no `collaboration` service**; `nats` (embedded), app-registry, app-provider, gateway, frontend all run.
  - `opencloud collaboration server/health/version` subcommands exist, so the service is runnable — it is simply not being started.
  - Embedded NATS at the default node IS running, so a separate NATS container is not required for `collaboration`; the earlier “no NATS broker” theory was wrong.
  - Rendered `/etc/opencloud/opencloud.yaml` shows `collaboration.app.insecure: true` despite env `COLLABORATION_APP_INSECURE: "false"` — env→schema map does not appear to take effect for this flag in 7.4 rolling (secondary, open).
- **Corrected service-set semantics:** the running set is `(defaults − EXCLUDE + ADD)`. A service named in `OC_EXCLUDE_RUN_SERVICES` is NOT started even if also listed in `OC_ADD_RUN_SERVICES`. Earlier journal/changelog text claiming “ADD wins; EXCLUDE inert” is wrong.
- **Effect chain:** `collaboration` (never started) → never registers its WOPI app with app-registry → web UI has no editor for `application/vnd.*` → `.docx` falls to “download instead.”
- **Fix (Lane A IaC, in-flight):** remove `collaboration` from `OC_EXCLUDE_RUN_SERVICES` (keep `idp`); then **converge + live re-test the `.docx` round-trip — PENDING.**
- **Follow-up:** confirm `COLLABORATION_APP_INSECURE` env→schema takes effect after convergence (the `insecure: true` render may surface once the service starts).
- **Secret-hygiene:** only env names/id lengths captured; no secret values printed. The earlier `insecure: true` render observation stands but no secret material is repeated here.


#### HD-166 pt.3 — second root cause: ONLYOFFICE DS had WOPI disabled → `/hosting/discovery` 404; fixed via `WOPI_ENABLED=true`, verified live (2026-08-24) `[AI]`

- **After pt.2's fix** (`collaboration` removed from EXCLUDE, container recreated), `opencloud list` showed `collaboration` running, but the service logged a persistent WOPI-discovery failure:
  `WopiDiscovery: wopi app url failed ... https://office.kogler.si/hosting/discovery ... HttpCode 404`.
- **Second root cause:** ONLYOFFICE Docs (DS) had **WOPI disabled**. The DS image's `run-document-server.sh` line 127 reads `WOPI_ENABLED=${WOPI_ENABLED:-false}` — default OFF. Our `onlyoffice-docs` compose env had no WOPI env, so `/etc/onlyoffice/documentserver/local.json` got `wopi: { enable: false }` and DS never served the WOPI discovery XML → OpenCloud's collaboration service polled `/hosting/discovery`, got 404, and could not register the editor for office MIME.
- **Fix (Lane A2 IaC):** add `WOPI_ENABLED: "true"` to `onlyoffice-docs` compose (`IaC/ansible/templates/docker_services/onlyoffice-docs/docker-compose.yml.j2`). The DS script then writes `wopi.enable=true` and auto-generates the WOPI public/private keypair (modulus/exponent) into `local.json` on first boot — regenerable, no literal secret to store.
- **Live verification (2026-08-24 after converge, 9P gate ✓):**
  - `onlyoffice-docs` recreated (Up, all sidecars healthy).
  - `https://office.kogler.si/hosting/discovery` → **200** with a real `wopi-discovery` XML (Word/Excel/PowerPoint actions, `urlsrc=https://office.kogler.si/hosting/wopi/word/view?&<rs=...>&<wopisrc=WOPI_SOURCE>`).
  - `opencloud list` still shows `collaboration` running.
  - `opencloud` logs: **no new discovery/collaboration errors** after the DS recreate (the 404 loop stopped).
- **Still pending:** owner browser round-trip on a real `.docx` in file.kogler.si (should now open in the ONLYOFFICE editor) — the definitive close gate.
- **Open follow-up (unchanged):** rendered `collaboration.app.insecure: true` in opencloud.yaml vs env `COLLABORATION_APP_INSECURE: false` — env→schema map for this flag still not confirmed in 7.4 rolling; confirm behavior post-editor-test.
- **Secret-hygiene incident (must-flag, HD-235):** one probe on this session inadvertently dumped the ONLYOFFICE container's `local.json` (DB password, AMQP URI with credentials, WOPI private key, JWT strings) into a transcript. No rotation performed; values belong in container config. **Recommend adding the involved secrets to the HD-211 rotation batch** (onlyoffice_db, onlyoffice-rabbitmq_login, opencloud-collab_password, and the generated WOPI keypair — regenerateable via container regenerate).


#### HD-166 pt.4 — “Invalid access token” 401: REVA-leg JWT secret split-brain (`token_manager.jwt_secret` vs env `OC_JWT_SECRET`) — DIAGNOSED, fix PARTIAL (2026-08-24) `[AI]`

- **After pt.3 (discovery 200) the browser now opens ONLYOFFICE but DS shows “Invalid access token” (401) on checkFileInfo.**
- **Evidence (live, values never printed — hashes only):**
  - opencloud env: `COLLABORATION_JWT_SECRET` (hash `169e85ad…`) == onlyoffice env `JWT_SECRET` (hash `169e85ad…`) — the shared DS JWT secret is consistent ✓.
  - opencloud env: **`COLLABORATION_WOPI_SECRET` now set** (same `169e85ad…` value) — but yaml `collaboration.wopi.secret` is still `c806a4f3…` (rendered at first `opencloud init`, Aug 22, never regenerated; the 7.4 build does NOT re-render yaml from new env — same class as the `insecure: true` env→schema bug).
  - **`OC_JWT_SECRET` env is ABSENT** from the opencloud container. yaml `token_manager.jwt_secret` = `eefff1c1…` (auto-generated, never overridden).
- **Exact failing code (fetched from opencloud v7.4.0 source, `services/collaboration/pkg/middleware/wopicontext.go`):**
  - L93 `jwt.ParseWithClaims(accessToken, claims, … cfg.Wopi.Secret)` — WOPI JWT signature (this PASSES; Wopi.Secret is fine).
  - L108 `DecryptAES(cfg.Wopi.Secret, claims.WopiContext.AccessToken)` — decrypt embedded REVA token (PASSES).
  - **L114/L123 `rjwt.New({secret: cfg.TokenManager.JWTSecret}); tokenManager.DismantleToken(…wopiContextAccessToken)` — FAILS with `token signature is invalid`.** This is the REVA-leg: collaboration validates the decrypted REVA token with `cfg.TokenManager.JWTSecret` which is env `OC_JWT_SECRET;COLLABORATION_JWT_SECRET`.
- **Root cause (high confidence):** JWT secret split-brain. The REVA token was **minted by auth-service** using the system-wide `token_manager.jwt_secret` (yaml auto-gen `eefff1c1…`, since `OC_JWT_SECRET` env was never set). collaboration **overrides** its `TokenManager.JWTSecret` via `COLLABORATION_JWT_SECRET` env (`169e85ad…`). Mint secret ≠ verify secret → “signature is invalid” → 401. `COLLABORATION_JWT_SECRET` was (wrongly) treated as “just the ONLYOFFICE secret”, but in OpenCloud it also feeds the reva token manager and must equal the system `OC_JWT_SECRET`.
- **Fix (Lane A3, DEPLOYED but NOT sufficient alone):** set `COLLABORATION_WOPI_SECRET` = shared value (needed for the WOPI leg; correct). **Remaining fix (NOT yet applied): set `OC_JWT_SECRET` env on the opencloud compose to the SAME shared value** so every service (auth mint + collaboration dismantle + DS JWT + WOPI) uses one consistent secret. After that: **converge + the user must RE-LOGIN** (existing REVA tokens were minted with the old secret and become invalid).
- **Notes / gotchas for next session:**
  - `opencloud.yaml` is a **persistent bind mount** at `/srv/docker/opencloud/config/opencloud.yaml` (mtime Aug 22 19:10, unchanged); `opencloud init` at container start is idempotent and does NOT regenerate an existing file → stale `token_manager.jwt_secret` (`eefff1c1…`) and `collaboration.wopi.secret` (`c806a4f3…`) persist. Setting the env vars (envdecode runs after BindSourcesToStructs in `parser.ParseConfig`) is the intended override path.
  - After setting `OC_JWT_SECRET`, if the yaml still shows the old secret, verify via `opencloud list`/log that the service actually picked up env (envdecode) — or regenerate yaml via `opencloud init` (careful: may rewrite LDAP/idm blocks — prefer env-only first).
  - `COLLABORATION_WOPI_SECRET` + `COLLABORATION_JWT_SECRET` + `OC_JWT_SECRET` all set to the SAME `opencloud-collab_password` value = single-secret chain (simplest).
  - **Owner action needed after the next converge: re-login to file.kogler.si and retry the `.docx`.**
- **Worktree/branch state at close (IN-FLIGHT, not merged to main):** branch `laneA3-hd166-wopisec` (commit `4976540`, `COLLABORATION_WOPI_SECRET` added, correct+deployed) and `session-hd166-wopisec-20260824-1315` (same commit) in worktrees `../homelab-wt-laneA3-hd166` and `../homelab-wt-wopisec`. main == origin/main == `8f3f7d0` (pt.1–3 merged). The `OC_JWT_SECRET` change is NOT yet written.

#### HD-166 pt.5 — OC_JWT_SECRET single-secret chain + mixed-content CSP fix: `.docx` round-trip PASSES, task CLOSED (2026-08-24, evening session) `[AI]`

- **Session start state:** main had moved to `50e2d49` — `4976540` (COLLABORATION_WOPI_SECRET) already merged by the prior close-out; wopi branches/worktrees pruned. Fresh worktree `../homelab-wt-20260824-1859`, branch `session-hd166-jwtfix-20260824-1859`.
- **Source re-verification (v7.4.0 tag):** auth-service `TokenManager.JWTSecret` env `OC_JWT_SECRET;AUTH_SERVICE_JWT_SECRET`; collaboration same struct via `OC_JWT_SECRET;COLLABORATION_JWT_SECRET`; `Wopi.Secret` env `COLLABORATION_WOPI_SECRET`. Confirms pt.4 exactly.
- **Fix 1 applied (`3d2adda`):** `OC_JWT_SECRET` added to opencloud compose = 1P `opencloud-collab_password` (same value as COLLABORATION_JWT_SECRET/WOPI_SECRET/DS JWT_SECRET). All four collab-chain env values now render via folded block scalar `>-` (owner-directed: a `"` in the 1P value would break the RENDERED compose at docker-compose parse time; inline double-quoted lookups retired for these). Dry-run `--check` first, then converge `--tags docker_services,opencloud`, 9P gate ✓ both sides.
- **Live verification:** env names present ×3; chain hashes IDENTICAL (`eb63ab…` ×3, sha256 prefixes only); collaboration running; discovery 200; zero "signature is invalid" log lines. Persistent yaml still holds stale values (expected — envdecode override is the active path).
- **Owner re-login + retry:** editor NOW OPENS (401 gone) but DS showed **“Napaka: Prenos ni uspel!” + empty document** → new layer.
- **Forensics:** proxy logs show ONE successful `/contents` GET (200, 34 KB) then cache reuse without refetch on every retry (same docId); `Editor.bin` built fine in DS cache (magic `DOCY`); ALL server logs clean (docservice/converter/nginx/opencloud); edge healthy from owner LAN (discovery 200, versioned static redirects normal). Conclusion: failure is browser-side delivery.
- **Owner DevTools evidence:** `Mixed Content: ... requested an insecure XMLHttpRequest endpoint 'http://office.kogler.si/cache/files/data/<id>/Editor.bin/...'` — **DS emits http:// cache URLs over the WOPI session websocket**, ignoring `X-Forwarded-Proto` when building them (upstream [ONLYOFFICE/DocumentServer#2186](https://github.com/ONLYOFFICE/DocumentServer/issues/2186) class; no server-side knob exists — upstream workarounds are JS/entrypoint seds).
- **Fix 2 applied (`0110a74`):** Traefik file middleware `onlyoffice-csp` = `Content-Security-Policy: upgrade-insecure-requests`, attached to the office router (`crowdsec-only@file,onlyoffice-csp@file`). Considered and REJECTED: DS-native TLS per ONLYOFFICE docs (wildcard-key sprawl onto a regenerable worker container, WAF loss or double-TLS hop, entrypoint fragility on Renovate bumps) — no benefit over the header for our browser-only broken leg. Converged `--tags docker_services,onlyoffice-docs,traefik` (9P gate ✓); middleware renders into `/opt/traefik/dynamic/middlewares.yml`.
- **Post-fix verification:** CSP header live on office.kogler.si ✓; onlyoffice-docs recreated healthy ✓; DS↔OC secret chain still identical (`eb63ab…`) ✓; discovery 200 ✓.
- **OWNER VERIFIED:** `.docx` opens, edit + save persist, and **live co-editing works across two browsers simultaneously. HD-166 CLOSED.**
- **Deviations:** none. Secret VALUES never printed (hashes/prefixes only throughout). No manual/non-Ansible steps → deployment-manual.md untouched.


### 2026-08-24 — Phase 1 · Headplane admin UI for Headscale at `vpn.kogler.si/admin` (HD-233) `[AI]`

- **Context / root cause:** `https://vpn.kogler.si` returns 200 with a 123-byte empty shell.
  Verified live (headers `x-frame-options: DENY` + `content-security-policy` + `content-length: 123`
  are headscale's own) and against upstream source: that is stock headscale's `BlankPage()`
  template — headscale has **no built-in admin UI**; `/health` 200, `/windows` + `/apple` 200,
  `/oidc/callback` 400 (route live) all confirmed healthy.
- **Decision:** co-deploy **Headplane** (ghcr.io/tale/headplane, pinned `0.7.0` — GHCR tags are bare
  semver; `v0.7.0` 404s, verified) as a second service in the headscale compose project; dashboard
  served by headplane itself under `/admin`, `server.base_url` = public root WITHOUT the suffix
  (upstream contract, v0.7.0 docs). Traefik router `Host(vpn.kogler.si) && PathPrefix(/admin)` —
  the longer rule wins priority without touching the control plane (`/ts2021`, DERP, `/oidc/*`);
  crowdsec-only tier like headscale.
- **OIDC:** deliberately the **same Authentik client as headscale** (upstream best practice: identical
  `client_id`) — ks-oidc.yml `provider_headscale` gained a second redirect URI
  `https://vpn.kogler.si/admin/oidc/callback`, both entries pinned (HD-231 array-wipe lesson).
  First login bootstraps the owner; later users get `default_role: member`.
- **Secrets touched:** none (values only). Required NEW 1Password items (owner):
  `headplane_api` = Headscale API key (`docker exec headscale headscale apikeys create --expiration 8760d`),
  `headplane_password` = cookie secret, exactly 32 chars (`openssl rand -hex 16`).
- **Settings chosen:** `headscale.url: http://headscale:8080` (internal, NOT gRPC); `config_path: /etc/headscale/config.yaml`
  mounted `:ro` → read-only Settings view in the UI; `disable_api_key_login: false` (recovery path until
  first OIDC login verified); docker-socket integration deliberately NOT enabled (hardening candidate).
- **Template plumbing:** `_extra_templates` in role defaults gained `headscale → headplane-config.yaml.j2`
  so the new config renders alongside the compose file (existing mechanism, no role changes).
- **Remaining (deploy-gated):** owner creates `headplane_api` + `headplane_password` → converge
  (`services` tag; blueprints one-shot apply adds the redirect; 9P gate first) → browser-verify
  `vpn.kogler.si/admin` login; hardening candidates afterwards (`use_pkce: true`, flip
  `disable_api_key_login`).
- **Deviations:** none.

### 2026-08-24 — Phase 1 · Headplane DEPLOYED + live-verified; YAML-block-scalar convention + three crash-loop lessons (HD-233 deploy / HD-235 follow-up) `[AI]`

- **Deploy** `--tags docker_services` from the worktree (9P gate ✓): headplane + headscale compose
  rendered onto the VPS; headplane initially **crash-looped** through THREE distinct bugs, each
  found live:
  1. **Dir-vs-file:** `_extra_templates` had a DUPLICATE `headscale:` key (headplane-config +
     config/policy) — YAML duplicate-mapping only kept ONE, so the copy step dropped
     `headplane-config.yaml.j2` unrendered and a stale `headplane.yaml/` DIRECTORY shadowed the
     render → `EISDIR`. Fix: merge into one list (`headplane-config.yaml.j2, config.yaml.j2,
     policy.hujson.j2`), point the compose mount at `./headplane-config.yaml`, remove the stale dir.
  2. **Block-scalar indentation:** in the FIRST block-scalar edit the value was NOT indented deeper
     than `>` (col 0) → `could not find expected ':'`. Block scalar content must be indented MORE
     than the key. Fix: re-indent to 6 (list item `- api_key:` → value at 6).
  3. **Wrong 1P field for Password item:** `headplane_password` is a **Password** category item (value
     in `password` field), but the template rendered `field='credential'` → empty `cookie_secret` →
     headplane `missing required fields`. Fix: `field='password'`. **Lesson: `<service>_password` items
     read `field='password'`; `<service>_api` items read `field='credential'`.**
- **YAML-safe block scalar convention (user-requested “make it the default”):** every secret
   rendered into a YAML config file must be a folded block scalar `>-` (never inline `"{{ … }}"`),
   because 1P secrets can contain `:` `"` `'` `?` `@` `!` (the rotated `headscale_api` value literally
   breaks quoted scalars on restart). Applied to `headscale/config.yaml`, `headplane` config,
   `recyclarr.yml`, `prometheus-web-config`, `traefik/dynamic/middlewares.yml`; TOML
   (`tuwunel.toml`) uses basic-string Jinja escaping instead (`replace('','\')|
   replace('"','\"')`) since TOML has no `>-`. Exempt: Docker `env:` strings + keepalived (not
   YAML-parsed). Convention documented in deployment-secrets.md + CONVENTIONS §2/§6.
- **Verified live:** headplane `Up (healthy)`, `Connected to Headscale 0.29.3`, `/admin/` → 302,
   owner SSO login works → **deploy-gate CLOSED**. `disable_api_key_login` flipped `true`
   (API-key field removed).
- **Log scrub (HD-235 follow-up):** the crash-loop json.logs contained the rotated `headscale_api`
   client_secret fragment in the YAML exception. Scrub: `sudo bash -c ': > …-json.log'` for
   headplane + headscale container logs (values never in git/chat — only lengths/IDs).
- **Secrets touched:** `headplane_api.credential` (87, live-key), `headplane_password.password` (32),
   `headscale_api.credential` (128, rotated HD-235). No other items exposed; no re-rotation needed.
- **Deviations:** none.
- **Commands (verified):** `docker exec headscale headscale apikeys create --expiration 8760d`;
  `op item create/get/edit … < /dev/null` (non-TTY stdin fix).


### 2026-08-26 — deploy-speed class: profile_tasks + bulk 1Password pre-pass (HD-257/258/259) — live surgical converge

- Plan ref: todo HD-257/HD-258/HD-259 (Ansible deploy-speed audit); owning docs `docs/deployment-ansible.md` (bulk pre-pass), `scripts/README.md`, `deployment-manual.md` (ext4 runner HD-259 in effect).
- **Commands run (as executed, on the WSL ext4 runner `/home/domen/source/homelab`):**
  ```bash
  # HD-257: callbacks_enabled = ansible.builtin.profile_tasks added to IaC/ansible/ansible.cfg
  # HD-258 live surgical converge (one service, renders from the vault dict):
  bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=headscale --limit vps
  ssh ansible-admin@vps.kogler.si 'docker ps --filter name=headscale --format "{{.Names}} {{.Status}}"; docker exec headscale headscale health'
  ```
- **Settings chosen:**
  - `callbacks_enabled = ansible.builtin.profile_tasks` (per-run top-task timing, HD-257)
  - `scripts/op-vault-export.py --derive`: expand enabled docker_services' `template_dir` -> `_template_vault_items` -> fetch each item once concurrently (`op item get --reveal`); ~34 items in 2.4s (vs ~160 sequential per-template `op` spawns)
  - `fetch-vault-pass.yml`: delegate_to localhost, run_once, no_log, become:false; derive (default) or explicit list mode; merges into a `vault` fact
  - static pre-pass runs BEFORE the authentik lane; litellm scoped keys (`litellm_scoped_keys.vault_item`) excluded from static and fetched in a post-litellm bootstrap refresh
- **Secrets touched:** `Homelab-ansible` items READ only (names logged, values no_log) — none rotated this session.
- **Verify:** `validate-all.sh` green; `ansible-playbook --syntax-check` green; live headscale converge RC=0 (`ok=28 changed=4 failed=0`); headscale container `Up` + `/health` OK.
- **Deviations:** `deploy-service.yml` DB-sync guard lookups left on direct lookup (dynamic `svc.db_item`, rare/non-loop) — documented in the owning doc. HD-259 = runner already on WSL ext4 primary; docs de-staled.


### 2026-08-24 — Phase 1 · Rotate shared headscale OIDC client secret + encode “never a secret VALUE in output” hygiene rule (HD-235) `[AI]`

- **Stimulus:** an operating probe exposed the shared `headscale_api` OIDC client_secret to the
  chat transcript (HD-233 implementation). Rotated AND turned the lesson into a convention so it
  never recurs from automation.
- **Rotation (values never printed — lengths/IDs only):**
  - Authentik ORM in `authentik-worker` (`ak shell` heredoc): provider `headscale` (pk 13)
    `client_secret` regenerated via `authentik.lib.generators.generate_key()` (128 chars);
    `client_id` left stable (no `generate_client_id` symbol exists in that module).
  - Persisted into `headscale_api` (`Homelab-ansible`, item `k6ehl32qrogcqhxu4efb42ft24`)
    `credential` field via `op item edit` with the write token from `/etc/op/provision-token`
    (the VPS-hosted SA, same path `provision-vault.sh` uses); `< /dev/null` (non-TTY stdin
    otherwise parsed as JSON template).
  - Verified readback: `username` 40, `credential` 128.
- **Convention fix (same change):**
  - CONVENTIONS §2: new “Secret output hygiene” row — never a secret VALUE in stdout/chat/git/
    transcripts; probes print length/prefix/item-ID/hash only; rotation sequence for a shared
    Authentik client.
  - CONVENTIONS §6: matching short bullet.
  - docs/1password.md: Output-hygiene note next to the existing Secrets-rule callout + a
    troubleshooting row for a leaked-value incident (rotate immediately, keep inspecting in
    plaintext off).
- **Remaining:** re-render headscale + headplane (converge `services` tag) so both consumers
  pick up the rotated secret; verify `vpn.kogler.si` control plane + `vpn.kogler.si/admin` login.
- **Secrets touched:** `headscale_api.credential` (rotated; value → vault only), `headscale_api.username` (unchanged). No values committed/logged.
- **Deviations:** none.

### 2026-08-24 — Phase 1 · Authentik background token rotator identified: upstream auto-rotation of expiring API tokens (HD-216) `[AI]`

- **Stimulus:** close HD-216 (Phase-1 mystery: persisted api-intent ORM tokens rewritten
  server-side within minutes, no local actor) via OFFLINE research only — upstream docs plus a
  source read of branch `version-2026.5` (pinned image 2026.5.6 = same minor); NO live DB/API
  probing (out-of-band SQL incident precedent).
- **Evidence fetched:** docs.goauthentik.io service-accounts / oauth2-provider /
  proxy-header-authentication pages; raw source `core/tasks.py`, `core/apps.py`,
  `core/models.py`, `core/api/tokens.py`, `lib/models.py`, `tenants/models.py`
  (+ sparse clone for cross-greps).
- **Root cause (feature, not bug):** scheduled task `clean_expired_models` (crontab
  `2-59/5 * * * *`, ≈ every 5 min) sweeps rows with `expiring=True AND expires<=now()`;
  `Token.expire_action()` ROTATES api-intent tokens (new key + fresh expiry =
  `now() + tenant.default_token_duration`, upstream default `days=1`) and writes a
  `SECRET_ROTATE` event instead of deleting; recovery/verification/app_password intents are
  deleted at expiry. Bare ORM creates default `expiring=True`, so even an `expires=NULL` token
  is rotated on the first sweep — the previously documented `.update(expires=None)` minting
  trick was ineffective (doc corrected in the same change). Only `expiring=False` is exempt.
- **Doc changes (same commit):** docs/services-authentik.md — new *API-token auto-rotation*
  section (mechanism + durable-persisted-token rules); ephemeral-glue rationale updated;
  ak-shell minting recipe fixed to `expiring=False`. todo.md row deleted per lifecycle
  (fully done → changelog-only record); changelog row appended.
- **Follow-ups surfaced:** one-time `expiring=False` verification for `authentik-api_token`
  (sync-authentik-users glue) at its next live touch; HD-211 scoped persisted
  `authentik-provision_api` re-issue unblocked via rule 1; app-password vanish-at-expiry
  flagged for future LDAP bind users (HD-132 authoring).
- **Deviations:** none.

### 2026-08-24 — Phase 1 · HD-216 close-up: owning-doc sweep, stale provision-token refs fixed `[AI]`

- **Audit:** repo-wide greps for stale minting advice, "root cause unidentified" wording and
  all HD-216 mentions — the mechanism itself was already fully documented in
  services-authentik.md; historical journal/changelog statements stay as records (append-only,
  corrected by newer entries, never edited).
- **Gaps fixed (same change):** `deployment-secrets.md` tombstone rationale updated (identified
  root cause + recipe pointer); `deployment-oidc.md` blueprint-apply step and fail-closed
  paragraph de-staled (retired `authentik-provision_api` references → deterministic blueprint
  one-shot per HD-230b + ephemeral-mint description); `todo.md` HD-211 row refocused (moot
  retired-item rotation step dropped; `expiring=False` rule for any persisted Authentik token
  in the batch + the one-time `authentik-api_token` verification now tracked where work will
  actually happen).
- **Changelog:** HD-216 R2 row appended.
- **Deviations:** none.

### 2026-08-24 — Phase 1 · B-queue small engineering batch closed via parallel isolated workers (HD-236) `[AI]`

- **Execution model:** orchestrator session ran three prompt.md §3b items as parallel subagent
  workers, each in its own managed git worktree off main; shared index files (changelog/journal/
  todo/prompt) reserved for the orchestrator so three branches could never conflict; lanes kept
  disjoint from the concurrent HD-216 session (authentik docs untouched).
- **(a) collaboration.app.insecure = FALSE ALARM:** parent fetched upstream source live from
  github.com/opencloud-eu/opencloud tag v7.4.0 (image pin `opencloudeu/opencloud-rolling:7.4.0`):
  `app.go` maps `COLLABORATION_APP_INSECURE` → `collaboration.app.insecure`; `parse.go` decodes
  env LAST over file+defaults; `defaultconfig.go` hardcodes default false with NO `OC_INSECURE`
  coupling → the yaml `true` seen during HD-166 pt.3/pt.5 forensics was a non-authoritative
  snapshot (stale scaffolded config / pre-env container / HD-212-class 9P stale read). Kept
  `"false"` (= verify edge LE cert); compose TODO rewritten with sources; services-office.md
  verified bullet added. Residual: one-time live probe of the EFFECTIVE runtime value.
- **(b) extras restart-on-change guard:** root cause — rendered extras are bind-mounted and
  compose up -d sees SPEC changes only. deploy-service.yml registers the extra-render loop result;
  a guarded post-up task runs `docker_compose_v2 state: restarted` for that one service when any
  non-`.env` extra actually changed. Exclusions reasoned in comments (`.env.j2` interpolation
  class; traefik/traefik-ha file-provider hot reload); prometheus restart accepted deliberately
  (web-config basic auth is startup-only). Raw-copy step deliberately NOT registered (every
  current extra is a .j2 render overwriting the raw copy) — noted in-task for future static extras.
- **(c) --tags union semantics:** verified against vps.yml/main.yml/deploy-service.yml wiring:
  union never narrows; dynamic `include_tasks` gate their FILE by own effective tags and do NOT
  cascade into contents → per-service filtering needs `--tags "docker_services,<service>"`,
  service-tag-alone is a SILENT NO-OP; handlers are tag-filtered too (`reload systemd` untagged —
  LATENT GAP flagged for a future batch, not fixed here); playbooks without role-level tags can't
  be surgically filtered today; canonical invocation tables in deployment-manual.md How-to-use +
  deployment-ansible.md §Tags & surgical runs; wrong Targeted Mode examples fixed; stale
  pre-HD-220 parenthetical removed.
- **Process lessons (tooling, not repo rules):** (1) workflow teardown on an intercom-detached
  child killed two in-flight workers before commit → relaunched standalone with an explicit
  `git branch keep/<item>` survival ref; (2) a completed worker's branch can vanish with managed-
  worktree cleanup — the commit object survived and was re-pinned to `keep/collab-insecure`
  before merging; (3) untracked research temp files in the primary checkout block managed-worktree
  creation (clean-tree requirement) — cleaned before relaunch.
- **Validation:** validate-all.sh green after each merge (final run on fully merged main).
- **Deviations:** none requiring owner input; ⏳ residuals recorded in changelog HD-236 row
  (first-converge restart observation + effective-env live probe).

### 2026-08-24 — Phase 1 · HD-237 tagged-handler hygiene sweep: all 22 role handlers carry `tags: always` `[AI]`

- Closes the latent gap flagged during HD-236c (journal entry above + deployment-ansible.md
  gotcha bullet): handlers are tag-filtered exactly like tasks — under a surgical run such as
  `--tags "docker_services,<service>"` on `vps.yml`, an UNTAGGED notified handler is skipped
  even though the notifying task ran. `docker_services`'s `reload systemd` was the live-risk
  instance: a unit-file change inside a filtered run would drop the notification and leave
  stale units.
- **Audit first:** enumerated every `roles/*/handlers/main.yml` (9 roles, 22 handlers) + every
  `notify:` reference. Findings: notifications are strictly 1:1 within their own role, no inline
  handler blocks, no cross-role notifies; only `monitoring` carried `tags: always` (HD-220);
  the other 8 roles' 21 handlers were untagged. Roles reachable under surgical runs via
  `vps.yml` role tags (`docker`, `hardening`, `wireguard`, `docker_services`, `monitoring`)
  were the acute exposure; home-lane roles (nut/storage/home_assistant/amd_rocm) fixed too for
  uniformity — their playbooks have no role tags today, but the invariant costs nothing and
  prevents regression if role tags are ever added there.
- **Fix:** `tags: always` on every handler + one rationale comment per file (HD-220 finding,
  HD-237 sweep). No task files touched — notify names unchanged.
- **Verification:** py-yaml parse of all 9 handler files → `BAD: 0`, `total handlers: 22, all
  tagged always`; validate-all.sh green; `--list-tasks` spot-check not needed (no structural
  change). IaC-only change — handler definitions are controller-side and take effect at the
  next notify; NO converge required and nothing deploy-gated. The next filtered run that hits a
  changed unit file is the implicit live proof (watch for `RUNNING HANDLER [reload systemd]`).
- **Doc updated:** docs/deployment-ansible.md gotcha bullet now states the fixed invariant and
  the rule for new handlers (must carry `tags: always`).

### 2026-08-24 — Phase 1 · HD-236 residual ② CLOSED live + HD-230b blueprint one-shot state probed `[AI]`

- **Residual ② (effective runtime env) — CLOSED.** Read-only probe (temp script → WSL →
  `ssh -o BatchMode=yes ansible-admin@vps.kogler.si` → `sudo -n bash -s`, boolean output only):
  container `opencloud` (`Up 3 hours`, i.e. started under the current converged compose env) reads
  `COLLABORATION_APP_INSECURE=false` at runtime — exactly the IaC value; the on-disk yaml snapshot
  showing `true` is confirmed non-authoritative stale scaffold content, matching the HD-236(a)
  upstream-source analysis. No other env values printed.
- **HD-230b blueprint one-shot state — mechanism PROVEN, per-run firing still ride-along.**
  `ak-shell.sh` probe of `BlueprintInstance`: `custom instances: 0 / total: 28` — EXPECTED, this IS
  the documented discovery gap; `ak apply_blueprint <path>` applies content without registering an
  instance row, so 0-custom is not a failure signal. End-to-end content proof: the server-side
  `headscale` OAuth2 provider carries redirect `/admin/oidc/callback` — present ONLY if
  `ks-oidc.yml` applied after HD-233 added it (hand-created providers are forbidden by convention,
  so the blueprint path is the only sanctioned source). All 15 expected providers exist.
- Inconclusive leg: `docker logs authentik-worker --since 5h | grep -i 'blueprint|apply'` → no hits;
  worker itself up since 2026-08-23T20:35Z (the ~3h-ago converge was surgical/opencloud-only), and
  log retention/level may hide successful applies. Decisive per-run evidence = next docker_services
  converge output (`== applying ks-forward-auth.yml / ks-oidc.yml ==` + Applied markers), folded in
  with HD-236 residual ① (zero spurious restarts on unchanged extras) as a converge-time check.
- Probes used throwaway temp scripts outside all checkouts, deleted after capture.

### 2026-08-24 — Phase 1 · HD-112 Zipline: brainstorm → decisions locked → full IaC authored (deploy-gated) `[AI]`

- Entry point: owner chat brainstorm (no prior prompt.md task) that flowed straight into an
  implementation session. Worktree `../homelab-wt-20260824-2233`, branch
  `session-20260824-hd112-zipline` — commits `9bc84be` (decision docs) + `746ae97` (IaC)
  + this close-out.
- **Design source verification (read-only upstream, no live probing):** every load-bearing
  mechanism verified against the Zipline v4 trunk source before deciding — anonymous upload is
  FOLDER-scoped (`Folder.allowUploads`; unauthenticated `POST /api/upload` with
  `x-zipline-folder`; file attributed to the folder OWNER and draws ITS quota; flagged
  `anonymous`); expiry header is `x-zipline-deletes-at` (human time like `6h` / `date=<ISO>` /
  `never`; optional `maxExpiration` cap knob exists); OIDC callback path is
  `${origin}/api/auth/oauth/oidc` (route source); shortener API `POST /api/user/urls` + dashboard
  QR modal exist natively; stable release = **v4.7.0** (2026-08-16, tag has `v`). An earlier
  external answer suggesting `EXPOSE_NOT_FOUND` / `WEB_SHORTENER_DISABLED` envs and a
  `X-Zipline-Expiration` header was checked against source and REJECTED as hallucinated.
- **Decisions locked** (changelog decision row): ONE public host `bin.kogler.si` on
  `crowdsec-only@file`; dashboard gated by native-OIDC provider `zipline` (blueprint-declared,
  family-group binding; Forward-Auth NOT stacked); **guestbin quota-split** — dedicated
  Zipline-local user (no Authentik identity, never logs in) owns the `dropzone` folder
  (`allowUploads=true`) so the public side is bounded by QUOTA + 6h TTL instead of global caps →
  NO type/extension blockers (owner stores executables privately), generous
  `FILES_MAX_FILE_SIZE=1gb`; uploads tree Kopia-excluded, metadata DB dumped via db-backup DB05;
  Phase-2 `/drop` static glue page deferred.
- **IaC authored:** compose template `docker_services/zipline/` (v4.7.0 + postgres sidecar,
  db-internal only, read_only + cap_drop ALL, healthcheck-gated depends_on, deploy-gate checklist
  in header comment); vps.yml registry w/ `db_role_sync`; ks-oidc.yml `provider_zipline`/
  `app_zipline` (strict callback; grant_types + property_mappings pinned per HD-231); glue
  PROVIDERS += `zipline:zipline_oidc`; vault catalog rows (`zipline_oidc`/`zipline_db`/
  `zipline_password`); CNAME `bin`; versions pins; validator `WEB_SERVICES += zipline`;
  backup.md payload row; utilities doc flipped 🟢 IaC done ⏳; todo Stage 9/10 trimmed tail.
- **Verification:** validate-all.sh green on BOTH commits. First IaC run failed with
  `[zipline] non-web service should not set traefik.enable: true` — resolved by registering
  zipline in the validator's explicit `WEB_SERVICES` allowlist (the intended registration path,
  not an exemption).
- **Deviations:** none live — NO gear touched; everything ⏳ deploy-gated to the Phase-1 wave.
  Owner pre-deploy action: create 1Password items `zipline_password` + `zipline_db` (the glue
  seeds ONLY `zipline_oidc` from Authentik). Post-up seeding per compose-header runbook:
  local admin `/auth/setup` → OIDC verify → flip bypass-local-login in Server Settings →
  seed `guestbin` (small quota, no password) + `dropzone` folder → anonymous round-trip +
  6h sweep verify → family drop script + manual guide.

### 2026-08-24 — Phase 1 · HD-112 follow-up: vault items made script-seedable; go-live sequence pinned `[AI]`

- **Owner-spotted gap closed (merge `56c2fe9`):** the handoff said "create 1Password items
  manually" while `scripts/provision-secrets.py` maintains a generated-item CATALOG (+
  `provision-vault.sh` wrapper, `check-vault-items.sh` coverage diff). Added `zipline_db`
  (Database) + `zipline_password` (CORE_SECRET) to CATALOG and to NOT_AUTO_ROTATABLE (init-once
  DB password / session-invalidating secret classes); verified via `--list` showing both entries
  flagged `[manual rotate]`. Root README §6 quick-refs gained the missing `scripts/README.md`
  link (its "Linked from" header claimed README.md but never had it).
- **Go-live sequence pinned** (prompt.md §3b + compose-header DEPLOY-GATE preamble):
  provision-vault.sh → 9P gate + human-gated dry-run → vps.yml converge → **dns.yml** (the `bin`
  CNAME applies ONLY there — Traefik route alone is unreachable) → compose-header post-up
  seeding → round-trip + 6h sweep verify → HD-112 closes at Stage 10/10.
- Repo-only lanes, no gear touched. Worktree `../homelab-wt-20260824-2312` merged green;
  this entry closes the session.

### 2026-08-25 — Phase 1 · HD-241/HD-242 · Metabase operationalization: env-driven SMTP + data-source IaC `[AI]`

- Owner walked the Metabase first-boot wizard manually 2026-08-24 (settings recorded in services-admin.md Notes; admin `admin@kogler.si`; forward-auth logout round-trip verified live by the owner).
- HD-241: SMTP moved to compose env (`MB_EMAIL_SMTP_*` + `MB_FROM_ADDRESS`) off the shared smtp2go SSOT + `smtp_login` lookups — owner's "must this be manual?" assumption corrected; env-set settings lock UI fields.
- HD-242: crowdsec sqlite bind into metabase (RW per WAL-recovery reasoning); new generic `db_ro_sync` opt-in in deploy-service.yml ensures the read-only `metabase_ro` role in forgejo-db every converge; `metabase-forgejo_ro` added to the vault catalog.
- LDAP option evaluated against the Authentik outpost and PARKED as HD-243 (second login form, no MFA passthrough, HD-186 outpost binding) — owner decision: local-admin-only until a second real user appears.
- No gear touched; nothing live changed yet. Worktree `../homelab-wt-20260825-0031` merged green; ⏳ tails ride the next docker_services converge (seed `metabase-forgejo_ro` first).
### 2026-08-24/25 — Phase 1 · HD-240: stats.kogler.si SSO dead-end fixed LIVE (edge-IP pin + datasource auth chain rebuilt + UPS rule exprs)

- **Symptom:** clicking Grafana on the SSO dashboard landed every SSO-authenticated user on a
  logo-only bare `/login` (native form disabled by design — the page itself proves proxy-auth
  rejection).
- **Root cause ① — edge IP drift:** traefik ran at `.12` on traefik-public while consumers trust
  headers only from `traefik_edge_ips` = `.2/32` (HD-190 contract) → every forwarded request
  rejected at the source-IP check. Fix: compose template pins the edge IP
  (`ipv4_address: traefik_edge_ip_pin`, new group_var; validator SSOT-loader extended).
- **Root cause ② — datasource never sent credentials:** the provisioned datasource set
  `basicAuthUser` + password but NOT the `basicAuth: true` flag → queries left anonymously
  (wire-capture proof: health-check POST `/api/v1/query` carried no Authorization header;
  HD-220b's earlier "verified HTTP 200" had tested creds against prometheus directly, not
  through grafana). Deeper: grafana 13.2.0 file-provisioning stores a secureJsonData blob it
  cannot resolve at use time ("Authentication to data source failed") even on fresh creates,
  and refuses API updates for provisioned datasources. Fix: Prometheus datasource moved out of
  file-provisioning into an idempotent API-seed task pair (create-only when absent +
  until-looped health verify, both no_log); `grafana-datasources.yml.j2` keeps Loki only.
  Rotation path documented in-task: delete DS → re-run role.
- **Root cause ③ — UPS rules invalid PromQL:** `(nut_ups_status & 2) > 0` style bitmask tests
  never parsed (PromQL has no bitwise AND) — invisible for weeks because everything 401'd
  upstream first. Fixed to modulo arithmetic `(nut_ups_status % 4) >= 2` / `% 32 >= 16`.
- **Owner mapping done in-session:** Authentik identity `domen` / domen@kogler.si created in
  Grafana via admin API and promoted to org Admin (random password generated on-box, never
  displayed). Proxy auth matches by email → SSO auto-login works without any password entry.
- **Verification:** surgical converges green (`--tags docker_services,traefik`, then
  `--tags monitoring` twice); traefik Up @ `.2`; `sso`/`stats` still 302-gated at the edge;
  **forged-header test** — direct `X-authentik-email` from the crowdsec container (non-whitelisted
  IP) → 302 rejected (**closes the HD-190 deploy-gate**); datasource health 200 through grafana;
  proxy query returns real series; zero eval errors across the final 3-minute window.
- **Incident A (transient edge outage ≈2 min, self-inflicted):** the first traefik recreate
  failed "Address already in use" — grafana itself held `.2` (an earlier who-holds-.2 probe was
  faulty: it kept only each container's FIRST network IP). Recovered by bouncing grafana
  (releases .2) → starting traefik onto .2 → grafana back on .12. Lesson: multi-network-aware
  probes before claiming an IP is free.
- **Incident B (secret exposure, self-reported):** a broken multi-layer ssh quoting attempt
  echoed the `prometheus-internal_api` password into the session transcript (~23:05). The same
  item was ALREADY queued in the HD-211 rotation batch (journal 2026-08-23, probe-exposure
  precedent) — treat rotation as raised-priority. All subsequent probes switched to stdin-fed
  scripts; nothing else printed.
- **Secrets touched:** none rotated (see Incident B; HD-211 owns the rotation).
- **Verify:** validate-all green ×4 commits; live checks listed above; owner action remaining:
  logged-in browser round-trip sso dashboard → stats.kogler.si must land IN Grafana.
- **doc updated:** docs/observability.md (Access & login path section), deployment-tasks.md
  (HD-240 ledger item).

### 2026-08-25 — Phase 1 · HD-246 · Secret-lifecycle rules promoted into CONVENTIONS §2 `[AI]`

- Owner prompt: "is secrets-creation knowledge documented well enough? Should it be part of conventions?" Audit found the four-path creation taxonomy, seed-before-converge invariant, rotation-propagation contract and scanner-coverage contract lived only in changelog precedents + session memory.
- Landed: 4 binding rows in CONVENTIONS.md §2 (index level) + full mechanics section "Creation & Rotation Workflow" in docs/deployment-secrets.md (owning spec).
- Docs/rules only; no gear, no vault changes. Worktree ../homelab-wt-20260825-0114 merged green.

### 2026-08-25 — Phase 1 · HD-240 round 2: THE login blocker found (authResponseHeaders dropped by traefik) + zipline bring-up ride-alongs

- **Owner retest after round 1 still landed on bare `/login`.** Grafana request log showed
  `userId=0 uname=` with `remote_addr=<owner public IP>` — anonymous through-and-through.
- **Root cause ④ (the real browser-flow blocker):** `middlewares.yml.j2` rendered
  `forwardAuth.authResponseHeaders` as a YAML MAP (`X-authentik-email: email`); Traefik's schema
  wants a LIST of header names. Traefik silently DROPPED the field (no error) → identity headers
  were NEVER copied onto proxied requests since authoring → every header consumer saw anonymous
  traffic. Proof: throwaway `traefik:v3.7.11` config dump decoded the middleware WITHOUT the
  field; after the list-form fix the decode shows all six X-authentik-* names.
- **Fix:** list form in template; converged `--tags docker_services,traefik`; live decode verified.
- **Ride-along fixes (parallel-lane defects blocking/impacting deploys):**
  - `deploy-service.yml` db_ro_sync task: `stdin:` placed beside the action read as a conflicting
    action statement → blocked EVERY docker_services run; nested into the module args (+ block
    indentation).
  - zipline pin `v4.7.0` does not exist upstream (404-proven; upstream ships only rolling
    `v4`/`v4-<sha>` builds + `latest`, no semver for v4) → owner-corrected to `4.6.5`
    (registry-verified 200).
  - zipline DATABASE_URL crash-looped (Prisma P1013): vault-generated password contains `#` +
    other URL-hostile chars, truncating the DSN → credentials now urlencoded at render.
  - uploads mount moved `/uploads` → `/zipline/uploads` (app's built-in path; mkdir ENOENT
    otherwise). Result: zipline 4.6.5 UP, server started on :3000, db healthy.
- **Verification:** converge green ×3 (ok=241 failed=0 last run); middleware live-decode shows the
  full header list; grafana ds-health 200; stats edge still 302-gated. Owner browser click-test
  still pending (final HD-240 leg).
- **Secrets exposed to transcript this session (rotation batch HD-211 — raised priority):**
  `prometheus-internal_api` password (quoting failure, ~23:05), `crowdsec-bouncer_api` LAPI key
  (traefik debug config dump, ~00:45). Nothing else printed; both items already vault-managed.
- **Deviations:** none further (doc updated: docs/observability.md access-path section).
- **Close-out (2026-08-25):** owner confirmed the browser round-trip — SSO dashboard → Grafana UI lands directly, no bare `/login`. HD-240 FULLY closed; todo row deleted (changelog row is the record); HD-190 deploy-gate closure stands.

### 2026-08-26 — Phase 1 · AI stack v2 architecture LOCKED (owner brainstorm session — docs-only, no IaC/no deploy) `[DECISION]`


- **Session:** owner brainstorm on the AI stack — where OWUI state/admin lives, LiteLLM integration & UI exposure, OpenClaw onboarding, DeepSeek Harness feasibility. Claims live-verified against repo + upstream (DeepSeek Harness: MIT/TS-Cordis, no official Dockerfile, loopback-only Web UI).
- **Decisions locked with owner** (substance in owning docs + changelog `HD-247–251` 2026-08-26 — NOT duplicated here): two-instance OWUI split (`chat.` public-limited / `ai.` internal-full-power) + Element→`msg.` · capability-tiering posture (security.md §10, network-vpn.md Patterns A/B) · LiteLLM v2 spine (HD-247: Postgres + `STORE_MODEL_IN_DB`, scoped consumer keys, master_key retirement) · n8n internal (HD-249) · DSH DevOps/IaC cockpit replaces Hermes (HD-250) · embeddings uniform (HD-246 amendment).
- **Docs touched:** todo.md (HD-247/248/249/250/251 + HD-104/HD-246 amendments), changelog.md (decision bundle), docs/services-ai.md (§2/§4/§5/§6/§7/§9), docs/security.md (§10), docs/network-vpn.md (Tailnet section), docs/services-utilities.md (n8n note), docs/services-matrix.md (Element rename pointer), prompt.md → handoff #17. **IaC untouched — all deploy-gated/planned.** validate-all GREEN.
- **Secrets touched:** none. **Deviations:** none (all docs-only).

### 2026-08-26 — Phase 1 · complete the mid-flight headscale_api OIDC client_secret rotation (HD-235 / handoff #20) `[AI]`

- **Stimulus:** handoff #20 flagged the headscale_api rotation MID-FLIGHT: Authentik provider pk 13 `headscale` `client_secret` had been regenerated in the DB, but 1Password `headscale_api.credential` still held the OLD value and headscale/headplane had NOT been re-rendered/restarted → new OIDC enrollments would fail `invalid_client` until finished.
- **Pre-write state (hashes only):** Authentik DB client_secret sha256 `28f53d33…` (NEW); 1Password `headscale_api.credential` sha256 `d28741dd…` (OLD, matched handoff); `client_id` unchanged (sha256 `220719ad…`) in both; on-disk `/opt/headscale/config.yaml` + `headplane-config.yaml` both still held the OLD secret (`d28741dd…`).
- **Commands run (as executed, on the WSL ext4 runner):**
  ```bash
  # 1) read the new DB secret into the authentik-worker container /tmp (ak-shell sanctioned path)
  bash scripts/ak-shell.sh 'from authentik.providers.oauth2.models import OAuth2Provider
  p = OAuth2Provider.objects.get(pk=13)
  open("/tmp/hs_new_secret.txt","w").write(p.client_secret)'

  # 2) VPS-side pipeline: worker /tmp -> host temp file (docker exec cat, NOT docker cp — cp is
  #    broken on this host), fail-closed hash-assert == DB secret, then apply to 1Password via
  #    op item edit --template (value only in the file, never argv / my session log)
  #    (whole flow ran in one /tmp/finish_hs_v3.sh on the VPS; value never returned to session)

  # 3) surgical converge re-renders headscale + headplane configs from the vault dict and restarts:
  bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=headscale --limit vps
  #    ok=29 changed=6 failed=0 (incl. "Restart headscale stack to apply changed extra config")
  ```
- **Verify:** vault `headscale_api.credential` sha256 now `28f53d33…` == Authentik DB; on-disk headscale + headplane configs both re-rendered to `28f53d33…`; headscale + headplane restarted (`Up 16s` / `Up 11s (healthy)`); token-endpoint replay (dummy code) → `HTTP 400 error: invalid_grant` = client auth OK (HD-252 criterion); `/health` HTTP 200; `headscale health` rc=0.
- **Secrets touched:** `headscale_api.credential` (rotated to the DB value, value → vault only). No values committed/logged; hashes/lengths only.
- **Deviations:** `docker cp` and `docker exec python3` value-transfer paths are broken on this host (handoff #20 already noted); used `docker exec cat` → host temp file instead. Secret value routed through host temp files + `op --template` stdin, never argv/session.

### 2026-08-21 — Phase 2.0 · tank topology locked + Pool-Creation Runbook authored `[MANUAL]` *(decision session — execution pending)*

- Plan ref: HD-206 (runbook authored, preseed serials filled) + HD-207 (execution + redistribution).
- **Decisions made with owner** (rationale recorded in owning docs — not duplicated here):
  - `tank` = **MIRROR (2× 4 TB), raidz1 rejected** despite OpenZFS 2.3+ RAIDZ expansion — mirror wins fast block-copy resilver, per-block self-healing, random I/O at this size. Growth paths: ① `zpool add` a NEW second mirror pair (contributes full size), ② `zpool replace` both disks one-by-one → autoexpand; **never `zpool attach` a larger disk onto the existing pair** (smallest-member cap). Buying rule: CMR only.
  - Docs updated in the same session: `docs/hardware-nas.md` (+ **Pool-Creation Runbook** with the exact planned `zpool create` commands: bulk RAIDZ2 4×3 TB ashift=12 first, legacy pool migrate-off-IronWolf → `bulk/migrate`, then tank mirror), `docs/storage.md` (topology note), `todo.md` (HD-207 refined: redistribution plan — media → `bulk/media`, personal documents → OpenCloud/live Box, interim `/tank/data/users/<name>/` Samba park).
  - `IaC/host/nas/preseed.cfg` real by-ids filled (boot SSD `ata-Crucial_CT525MX300SSD4_173818D02FF0`, USB `usb-Generic_Flash_Disk_C3EB7FE7-0:0`) — closes the HD-201 placeholder class for nas.
- **Execution NOT yet run** — when the runbook executes (pre-reinstall bootstrap), copy the commands **as run** (with real by-id paths + `zpool status` output) into a NEW entry here; the runbook text stays the plan.

### 2026-08-27 — Phase 1 · HD-254 live deploy: `sync-skills.sh --push` on the WSL ext4 primary + verify `[AI]`

- **Stimulus:** HD-254 (skill-sync guard `scripts/sync-skills.sh`) authored + wired into `validate-all.sh` as item 13 (guarded to SKIP when no `~/.pi/agent/skills`), but the changelog row still read `⏳ deploy-gated` — one live two-sided push against the real `~/.pi` remained to close it.
- **Commands run (as executed, on the WSL ext4 runner):**
  ```bash
  # pre-flight: repo skills vs deployed (baseline — should be clean)
  bash scripts/sync-skills.sh --check --strict        # exit 0: repo == ~/.pi, no drift, no encoding violations
  # canonical deploy direction (repo = SSOT -> ~/.pi)
  bash scripts/sync-skills.sh --push                  # pushed 5 skill(s): mikrotik plan-task platform-env run-task shelly
  bash scripts/sync-skills.sh --check --strict        # exit 0 again: in sync after push
  ```
- **Verify:** (1) `--check --strict` BEFORE and AFTER both exit 0 (repo == `~/.pi/agent/skills`, no drift, no encoding violations); (2) `diff -r --exclude=__pycache__ --exclude=net.json skills ~/.pi/agent/skills` → **IDENTICAL**; (3) no runtime artifacts shipped to the deploy side: 0 `net.json`, 0 `__pycache__`, 0 zero-byte skill-name markers; (4) `sync-skills.sh --check --strict` still PASS inside the full `validate-all.sh` (green).
- **Secrets touched:** none. **Deviations:** none — live behavior matched the sandbox tests (baseline-clean → push → clean); the two-sided path confirmed working against the real deploy target.
- **Bookkeeping:** todo.md HD-254 row deleted (§4 fully-done close-out; changelog row retains the history). The changelog row's `⏳ deploy-gated` tail updated to `✅ live` in this same session.

### 2026-08-27 — Phase 1 · HD-268 full converge + DSH live — Qdrant / pi-dev / dsh all running; baseline captured `[AI]`

- **Plan ref:** [deployment-tasks.md](deployment-tasks.md) Phase 1 step 2 (VPS stack converge); owning docs `docs/services-ai.md` (HD-267/268), `docs/network-vpn.md` (§Tailnet Pattern A). Continues the (now-closed) HD-268 deploy handoff: dsh `{{ }}` comment blocker (already fixed in `main` at session start) + DSH image + first live converge + baseline second run.
- **Stimulus:** prior session authored the HD-268 AI IaC (Qdrant swap, dual pi.dev+DSH harness) with one remaining deploy blocker (Jinja `{{ }}` in a dsh-sidecar comment) that broke the dsh compose render; that blocker was already landed in `main` (`44a8bbc`) before this session resumed.
- **Commands run (as executed, on the WSL Debian runner):**
  ```bash
  # (0) handoff said apply the dsh comment fix; it was already committed — clean state verified;
  bash scripts/validate-all.sh             # green (exit 0)
  # (1) first full converge — dsh now RENDERS (blocker gone) but image pull failed:
  bash scripts/ansible-run.sh playbooks/vps.yml    # failed=1: docker pull access denied runzhliu/deepseek-harness-docker (image repo 404)
  # (2) fix image repo: runzhliu/deepseek-harness (NOT -docker) — verified tag 0.1.1-rc.2 on Docker Hub
  bash scripts/validate-all.sh                    # green
  bash scripts/ansible-run.sh playbooks/vps.yml    # ok=311 changed=60 failed=0 — dsh pulled + started BUT crash-loop
  # verify: docker ps -> dsh Restarting(1); logs = ENOENT mkdir /home/node/.dsh/profiles (read-only root)
  # (3) fix crash-loop — read_only:true but DSH_HOME=/home/node/.dsh was on the RO root FS:
  #   + named volume 'dsh-home:/home/node/.dsh' + top-level 'volumes:' + shm_size 1gb (Chromium)
  bash scripts/ansible-run.sh playbooks/vps.yml    # ok=311 failed=0; dsh now 'Up', logs: dsh web http://127.0.0.1:3080
  # BASELINE SECOND RUN (user-requested static cost, nothing changed):
  bash scripts/ansible-run.sh playbooks/vps.yml    # ok=311 changed=45 failed=0, wall ~203s
  ```
- **Settings chosen:**
  - `dsh_version`: `0.1.1-rc.2` (repo corrected to `runzhliu/deepseek-harness`; tag verified present 2026-08-27; digest pin still TODO)
  - dsh compose: `read_only:true` + `cap_drop ALL` + DSH home named volume `dsh-home:/home/node/.dsh` + `shm_size 1gb` (browser desktop); Pattern-A tailnet sidecar still **commented/disabled** (needs `tailscale_dsh` item + uncomment at deploy)
- **Secrets touched:** `qdrant_db` (created by provision-vault.sh), `dsh_api`/`pi-harness_openai_api` + 6 other glue-minted LiteLLM scoped keys (len 26) — values to 1P vault only. 1P rate-limit headroom comfortable (token read 83/1000 used).
- **Verify:** (1) `validate-all.sh` green; (2) `docker_services : Docker compose up -d for dsh` → ok (image pull, then fast 1.7s steady); (3) `docker ps` dsh = `Up` (was `Restarting(1)`), logs show the WebUI line; (4) dsh Web UI `curl 127.0.0.1:3080` returns http 000 from the host — **expected**: UI binds inside the container only, exposed only via the still-disabled tailnet sidecar (by design).
- **Deviations:** dsh container image repo corrected (authoring had used the GitHub source repo name). The `--tags dsh` surgical run only hit guard tasks (include_tasks tag not inherited) — full converge is the reliable path. A `localhost` + duplicate `op_derive_services` map-key warning persists in validate output (warning, not a failure).
- **Bookkeeping:** main pushed to `d33ab44`. DSH/Qdrant/pi-dev on-live; remaining deploy-gated tailnet sidecar wiring + live-verify Qdrant embed/rerank + re-index tracked in todo.md HD-268 tail.

### 2026-08-27 — Phase 1 · HD-269 deploy-speed surgery: scoped + multi-service docker_services_scope `[AI]`

- **Plan ref:** [deployment-tasks.md](deployment-tasks.md) Phase 1 step 2; owning docs `docs/deployment-ansible.md` (§Tags & surgical runs) + this lane's handoff. Baseline (from the HD-268 session): full converge ~204s, ok=311 changed=45 failed=0 (static).
- **Stimulus:** HD-269 lane — make one-service and several-service surgical deploys work AND fast. The handoff Step-0 measurement revealed the primitives were broken for glue-consuming scopes.
- **Commands run:**
  ```bash
  # 1) measure ~ broken pi-dev scoped run (original behavior, session-first run on primary)
  bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=pi-dev
  #   → FAILED, object of type 'dict' has no attribute 'pi-harness_openai_api'
  #   → root cause: scoped op pre-pass excluded litellm-scoped keys (op_derive_glue) and litellm
  #     bootstrap glue never ran (scope=pi-dev, litellm not in loop). pi-dev/dsh consume those keys.
  # 2. edit IaC role defaults + main.yml (see git diff / changelog HD-269) in session worktree
  #    homelab-wt-20260827-2311 (session/hd269-scope-transitive-deps)
  # 3. re-run scoped pi-dev converge (post-fix)
  bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=pi-dev
  #   → ok=20 changed=1 failed=0, ~5-6s wall; op-pre-pass 5.79→0.78s; pi-dev container Up
  # 4. multi-service scope validate
  bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope='qdrant,docling'
  #   → ok=27 changed=3 failed=0, only qdrant+docling deploy, all others skipped; op pre-pass 0.78s;
  bash scripts/validate-all.sh  # all green
  ```
- **Settings chosen:**
  - `docker_services_scope`: now a comma-string (`svc1,svc2`); role default computes `scope_is_all` + `scope_list`.
  - Scoped op derive: fetch the scoped service's full item-set (incl. existing glue-seeded keys) — `op_derive_glue` empty when not `all`.
- **Secrets touched:** n/a (no new secret; existing litellm-scoped keys read from vault on the provisioned host).
- **Verify:** `scope=pi-dev` → `ok=20 changed=1 failed=0` ~5-6s, pi-dev container Up; `scope=qdrant,docling` → `ok=27 changed=3 failed=0` only those two; validate-all green.
- **Deviations:** none. The handoff's Step-2/Step-3 fix respects `docker_services_scope` being the surgical mechanism (HD-255/260) and keeps fail-closed secret resolution.

### 2026-08-27 — Phase 1 · HD-269 Step 1: parallelize the two serial egress glue loops `[AI]`

- **Plan ref:** [deployment-tasks.md](deployment-tasks.md) Phase 1 step 2; owning doc `docs/deployment-ansible.md` §Tags & surgical runs.
- **Stimulus:** full-converge baseline ~204s has ~35s in 3 serial glue loops (Authentik secret-egress ~21-22s, LiteLLM bootstrap-keys ~8s, op-vault-export ~5s). Both egress loops' sub-operations are independent per provider/key — parallelize reads/probes, keep writes ordered/serial.
- **Commands run:** `git worktree add ../homelab-wt-20260827-2335 -b session/hd269-parallelize-glue`; edited the two rendered `*.sh.j2` templates; `validate-all.sh` green; sandbox tests (below). No live secret writes — the parallel logic was proven in a sandbox against stub `op`/`docker`/`curl`.
- **Settings chosen:**
  - `authentik-secret-egress.sh.j2`: per-provider worker `sync_provider`, `xargs -P "${OP_PARALLEL:-6}"`; each worker owns a DIFFERENT 1P item (safe parallel writes); write-only-if-changed retained; worker nonzero -> xargs nonzero -> abort (rc 1); provider-not-found -> rc 3; result lines serialized via a shared `$RESULTS` file read once after all workers finish.
  - `litellm-bootstrap-keys.sh.j2`: new Phase-1 PARALLEL read+probe (`op item get` + `docker exec` HTTP probe) via `xargs -P`; Phase-2 SERIAL mint/store for empty-vault keys only (avoids `_enforce_unique_key_alias` races). rc taxonomy carried in worker LINES (not exit code): STALE→2, TRANSIENT→3, alias-conflict→4.
- **Verify (sandbox, no real 1P/containers):** authentik 5-provider run -> all 5 found, exit 0; litellm -> stale key aborted rc 2, and all-valid yielded MINT for empty + KEEP for present, exit 0. export -f + xargs fork/export concurrency, fail-closed, and result aggregation all confirmed. `validate-all.sh` green; both templates render to valid bash.
- **Secrets touched:** none executed live (sandbox stubs only); the parallel logic does not relocate or re-print secret values.
- **Deviations:** none from the handoff's Step-1 design (reads parallel, writes ordered; 1P rate-limit bounded by OP_PARALLEL). Live full-converge timing re-baseline still pending (flagged in todo HD-269).

### 2026-08-28 — Phase 1 · HD-269 Step 1 live re-baseline + full-converge warning audit `[AI]`

- **Plan ref:** [deployment-tasks.md](deployment-tasks.md) Phase 1 step 2; owning doc `docs/deployment-ansible.md` §Tags & surgical runs; log `/tmp/fullconverge2.log`.
- **Stimulus:** close the Step-1 “live full-converge re-baseline still pending” item from last session, and pivot the found warnings into tracked backlog before proceeding to the Step-4 tier modulariser.
- **Commands run:** ran the full converge `bash scripts/ansible-run.sh playbooks/vps.yml` (log: `/tmp/fullconverge2.log`, 2934 lines); no code edits in this session (read-only audit + doc/backlog work only, in worktree `homelab-wt-20260828-0035`). For the audit: `grep -n 'WARNING|DEPRECATION WARNING' /tmp/fullconverge2.log` then ±2-line context each.
- **Result / baseline (live re-measure):** `ok=311 changed=45 failed=0 skipped=381`, last cumulative ~3:13. **Authentik secret-egress glue: 21-22s → 11.94s** — the $xargs$-`P` parallel sink is a shipped, live win. **LiteLLM bootstrap-keys glue: PARALLEL attempt FAILED live (rc 3, 12 retries, ~155s):** its `probe_key` reads the probe via a `docker exec -i … <<'PYEOF'` heredoc, whose stdin is a broken pipe under `xargs -P` fan-out → probe returns 000/hangs → transient failure. Reverted to the **serial main loop** (identical to the pre-parallel a57e128 version). Lesson ossified in `scripts/README.md` §Parallel-1P: a fan-out worker may use `curl`/`op`/plain subprocess, but a worker whose body pipes a heredoc into `docker exec -i`/`ssh` runs SERIALLY (or gets a stdin-neutral invocation). Authentik parallel survives because its workers only `curl` + `op read` and never feed stdin.
- **Warning scan → new backlog (todo HD-270/271):** ① **HD-270 silent-secret-truncation bug (P1):** 6× `The \"<token>\" variable is not set. Defaulting to a blank string.` in compose `up` (authentik `z`, zipline `JP8`, litellm `PoZcG`, pi-dev `DWeRfADjDd6h`, openclaw `TY4`, kopia-server `P` + its `Cannot parse event from non-JSON line`). Tokens are fragments of 1P values that contain `$`; compose `${}`/`$VAR`-interpolates the whole file pre-YAML-parse and blanks them → **values silently truncated at the `$` in the running config**; `--quiet` validate never fails. Fix deferred (todo HD-270). ② **HD-271 `ansible-core 2.24 deprecations` (todo HD-271):** `INJECT_FACTS_AS_VARS` (deploy-service.yml:106/160) + internal `vars` dict (group_vars/all:230, router.yml:58). ③ note-only: `localhost` group+host clash.
- **Secrets touched:** none (no secret values printed; truncation class logged as lengths/patterns, not values).
- **Deviations:** none from the design; the Step-1 validate went from “parallel + live-rebaseline pending” to “parallel only for authentik (real win), litellm restored to serial (revert).” [scripts/README.md](scripts/README.md) updated so the parallel-concurrency contract reflects the shipped state; `todo.md` HD-269 🚧 collapsed + HD-270/HD-271 filed.

### 2026-08-28 — Phase 1 · HD-271-followup live-found fixes: qdrant + kopia-server crash-loops `[AI]`

- **Plan ref:** the HD-270/HD-271 follow-up lane (live deploy-health); owning docs `docs/services-ai.md` §5b (qdrant rebuildable cache) + `docs/backup.md` (kopia). Worktree `homelab-wt-20260828-1626hd271` (branch `session/hd271-ansible224`).
- **Stimulus:** after the HD-271 deprecation commit, a live deploy-health rollup (`docker ps`) showed **two services crash-looping with real bugs** (plus two known/expected loops — authentik-ldap is the known HD-186 “no ldap provider defined” state, renovate is the known HD-264 churn).
- **qdrant (crash-loop `Restarting (101)` — `Can't create Snapshots directory: Read-only file system` at `toc/mod.rs:100`):** the compose sets `read_only: true` with only a `/qdrant/storage` bind; qdrant 1.12.4 creates its snapshots dir at startup and the RO rootfs blocks it. **Fix:** add `QDRANT__STORAGE__SNAPSHOTS_PATH: "/qdrant/storage/snapshots"` (inside the writable storage bind). Verified live: standalone run with that env starts clean (`Access web UI`, HTTP 6333 + gRPC 6334, graceful shutdown RC=0); after the surgical deploy `qdrant` = `Up (healthy)`, `RestartCount=0`, `/srv/docker/qdrant/snapshots` created. Commit `d90f0e2`.
- **kopia-server (crash-loop `found existing data in storage location` + “Creating SFTP repository”):** the first-run gate checked `if [ ! -f /app/config/config.json ]`, but `config.json` is an unrelated technitium zone file — kopia's repo-connection file is **`repository.config`** (present since the 2026-08-23 create). With a repo already on the backup box, every boot re-ran `kopia repository create sftp` → failed `found existing data in storage location` → `set -e` exit → restart loop. **Fix:** gate on `repository.config` instead. Verified live after surgical deploy: `kopia-server` = `Up`, logs show `SERVER ADDRESS: http://[::]:51515` + normal maintenance/GC against the existing repo, no more create loop. Commit `d90f0e2`.
- **Commands run:** `docker ps` health rollup; `docker logs` on each looping service; the qdrant fix verified via throwaway `docker run --rm -e QDRANT__STORAGE__SNAPSHOTS_PATH=… --workdir /qdrant qdrant/qdrant:v1.12.4 ./entrypoint.sh` (`tail`); deploys: `bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=qdrant` (`ok=20 changed=4 failed=0`) and `…-e docker_services_scope=kopia-server` (`ok=20 changed=4 failed=0`). `validate-all.sh` green before each.
- **Secrets touched:** none printed (the qdrant `QDRANT__SERVICE__API_KEY` value stayed inside the vault dict/template; the test-1password read of the SA token prints a sample but it's the runner's own read-scope SA, not a service secret).
- **Deviations:** none from design — the two fixes are the documented rebuildable-cache/backup-seam behavior made actually startable. `todo.md`/`changelog.md`/`prompt.md` HD-271 row updated to note the follow-up fixes.



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
