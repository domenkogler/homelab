# deployment-manual.md — Redeployment Runbook (True Zero → Live)

> **Role:** Imperative, phase-by-phase **procedure** for redeploying the homelab from true zero —
> exact commands, panel settings, and the verification evidence each step must produce before the
> next step runs. Deliberately free of progress markers and fix history: progress checkboxes live in
> [deployment-tasks.md](deployment-tasks.md) (ledger), as-built evidence in the owning-doc ✅ lines
> + the git commit of the change. If reality diverges permanently, fix the procedure here (or the
> owning spec) in the same change and record it in the owning doc/commit.
> **Linked from:** [docs/index.md](docs/index.md), [docs/deployment.md](docs/deployment.md),
> [deployment-tasks.md](deployment-tasks.md), [CONVENTIONS.md](CONVENTIONS.md) §4

---

## How to use

- Execute phases in order. Every step ends with a ✔-evidence check — do not proceed past red.
- Binding working rules: `bash scripts/validate-all.sh` green before every commit; secrets by
  1Password item+field name only (never values); every executed action gets an owning-doc
  ✅ note + a commit.
- Shells: repo ops + validators from **git-bash** (Windows laptop); Ansible runs ONLY on the
  **WSL Debian runner** through [scripts/ansible-run.sh](scripts/README.md) — never pass inline
  commands to wsl.exe.
- **Ansible-run semantics** (sync gate, `--tags` surgical runs, venv interpreter): see
  [scripts/README.md](scripts/README.md) + [docs/deployment-ansible.md](docs/deployment-ansible.md) §Tags & surgical runs.

---

## Phase 0 — Management runner (WSL Debian) from true zero

> Rebuilds the Ansible control node on the management laptop. Owning specs:
> [docs/1password.md](docs/1password.md) (runner auth + agent), [scripts/README.md](scripts/README.md)
> (runner tooling).
> **Prerequisites (vault `Homelab-ansible`):** items `op_api` (field `credential`),
> `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `kopia_password` exist.

### 0.1 (Re-)install the WSL Debian distro `[MANUAL]`

```powershell
wsl --unregister Debian    # destructive — wipes the current runner; deliberate rebuilds only
wsl --install -d Debian
```

Create the local user `domen`, then set its password (`passwd`) and store it as item
`laptop-domen-wsl-debian_login` (field `password`) in the **Homelab** 1Password vault.
The repo is **reused** from the WSL ext4 primary checkout at
`/home/domen/source/homelab` (single working copy — the Debian ext4 primary, per HD-259;
`scripts/git-bootstrap.sh` sets this up and its session worktrees live as
siblings `../homelab-wt-*`. No second clone; the old `/mnt/d` drvfs path is retired).

✔ `wsl -l -v` lists Debian; inside WSL `whoami` → `domen`.

### 0.2 Bootstrap tooling, service-account token, sudo

```bash
cd /home/domen/source/homelab && bash scripts/bootstrap-runner.sh
source ~/.bashrc
```

When prompted, paste the 1Password Service Account token = item `op_api.credential`. The idempotent
script installs system prerequisites + the `op` CLI, creates the `~/ansible-venv` virtualenv with
ansible + collections from `requirements.yml`, stores the token at `~/.config/op/homelab-sa-token`
(0600), grants passwordless sudo, and generates a throwaway SSH key.

✔ Script prints `FULL BOOTSTRAP COMPLETED SUCCESSFULLY`; `ansible --version` and `op --version` respond.

### 0.3 Canonical runner identity + 1Password/Ansible connectivity check

```bash
cd /home/domen/source/homelab && bash scripts/restore-runner-key.sh
bash scripts/ansible-run.sh IaC/ansible/test-1password.yml
```

`restore-runner-key.sh` pulls `ansible-admin_ssh.private_key` / `public_key` from the vault into
`~/.ssh/id_ed25519[.pub]` (bootstrap's throwaway key is discarded — the vault is the source of
truth); `test-1password.yml` then proves the lookup path end-to-end.

✔ `restore-runner-key.sh` prints `pair-consistent: yes` with the fingerprint matching the canonical
one it prints · `test-1password.yml` ends `PLAY RECAP: ok=2 failed=0` (reads `kopia_password`).

### 0.3.5 Skill sync: repo `skills/` → pi agent `~/.pi/agent/skills` (repo = SSOT)

```bash
bash scripts/sync-skills.sh --push            # deploy repo skills/ -> ~/.pi/agent/skills (canonical)
bash scripts/sync-skills.sh --check --strict  # confirm no drift / no encoding violations
```

`sync-skills.sh` (HD-254) deploys from the repo (single source of truth) to `~/.pi/agent/skills` and prunes
runtime artifacts (`net.json`, `__pycache__/**`, zero-byte skill-name markers). `--check --strict` exits
nonzero on any drift and is wired into `validate-all.sh` as a gate (SKIPs when `~/.pi` is absent, so
a bare CI / non-pi laptop never breaks validation). A UTF-8-BOM/CRLF encoding violation blocks `--push`.
To capture a post-session self-learn back into the repo (copy-only, never auto-commits), use `--pull` then
commit per CONVENTIONS §6.

Prerequisite: pi must already be installed — on this host `scripts/install-pi-wsl.sh` installs pi + the
other SSOT content (`pi-agent/`, packages); once pi is present, `sync-skills.sh` keeps only the skills tree
in drift-free sync. On a TRUE-ZERO runner without pi, `sync-skills.sh --check` SKIPs and `--push` populates
`~/.pi/agent/skills` for the first time.


### 0.4 Windows-side interactive SSH *(one-time, recommended — not required by the runner)*

> Nothing automated depends on this step: the Ansible runner (WSL) presents the canonical
> `ansible-admin_ssh` key directly, and interactive debugging also works from WSL
> (`ssh ansible-admin@vps.kogler.si`, full sudo). Recommended anyway — `ssh vps` from the laptop is
> the standing debug path (deployment-handoff diagnostics) and stays available while the WSL runner
> itself is down or being rebuilt.

1. 1Password desktop app running, with the `Homelab-ansible` vault allowlisted in the SSH-agent
   config — without it the agent refuses the keys and `ssh` misreports `invalid format`.
2. `%USERPROFILE%\.ssh\config` gets two aliases differing only by presented key:

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

The `.pub` files are hints for the 1Password agent, not key copies. Item names are vault identities —
there is no `domen` account on managed hosts.

✔ Once a provisioned host exists (Phase 0.5): `ssh vps whoami` and `ssh vps-ansible whoami` both
return `ansible-admin` with no password prompt.

### 0.4b Windows-side GitHub SSH auth + commit signing *(one-time; HD-265 win companion)*

> Handled by [scripts/git-bootstrap-win11.sh](scripts/git-bootstrap-win11.sh) (`--ssh-auth`, idempotent). The
> Windows desktop laptop differs from the WSL runner: the **1Password desktop app** owns the GitHub
> SSH keys (`GitHub auth` + `GitHub sign` items) and serves them over the Windows named pipe
> `\\.\\pipe\\openssh-ssh-agent`. There is **no `~/.ssh/config` `Host github.com` block and no
> `~/.1password/agent.sock`** on Windows — the CLI-only `op` key-pull path is Linux/WSL-only.
>
> What this does (idempotent):
> 1. Points git at **Windows OpenSSH** — `core.sshCommand = C:/Windows/System32/OpenSSH/ssh.exe` in
>    `.gitconfig-windows` — so git reaches the named-pipe agent automatically. Removing the bogus
>    `-I …/op-ssh-sign.dll` and a dead `IdentityAgent ~/.1password/agent.sock` is part of it (that DLL
>    path does not exist on this laptop; the real signer is
>    `~/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe`).
> 2. Ensures `.gitconfig-windows` has `gpg.ssh.program` set to that desktop signer.
> 3. Flips `origin` HTTPS→SSH so the `.gitconfig-github` includeIf (`gpg.format=ssh` /
>    `commit.gpgsign` / `user.signingkey`) fires.
>

---

## Phase 0.5 — VPS (re-)provisioning (netcup SCP)

> Maps to [deployment-tasks.md](deployment-tasks.md) Phase 1 step 1. Authoring spec for the install
> scripts/media: [docs/deployment-preseed.md](docs/deployment-preseed.md).
> **Prerequisites:** Phase 0 green; vault fields `laptop-domen_ssh.public_key` +
> `ansible-admin_ssh.public_key` readable by the runner.

### 0.5.1 Generate the Custom Script

On the WSL runner (working `op` session):

```bash
bash scripts/gen-custom-script.sh
```

Builds the git-ignored `post_install_with_secrets.sh` (0600): injects both real public keys into a
copy of `post_install.sh`, then self-checks placeholders replaced, no doubled algorithm prefix
(HD-209 guard), `bash -n` syntax.

✔ `✔ post_install_with_secrets.sh written (0600, placeholders injected, syntax OK).`

### 0.5.2 netcup SCP — reinstall settings `[MANUAL]`

In the netcup SCP, open the server's image-delivery / reinstall dialog and set exactly:

| netcup SCP field | Value |
|---|---|
| Official image | **Debian 13.6.0 UEFI amd64** (current Debian 13 UEFI amd64 at reinstall time) |
| Installation method | **Minimal** — Minimal image |
| Partitioning | one large OS partition using **all available disk space** (plain partitions, no LVM) |
| Hostname | `vps` |
| Locale | `en_US.UTF-8` (`sl_SI.UTF-8` is set by the Ansible `common` role on first run) |
| Timezone | `Europe/Vienna` |
| Create additional user | **false** — the Custom Script creates `ansible-admin` |
| Send e-mail to me | **true** — the finish notification carries the host-key report used below |
| Custom Script | **full content** of the generated `post_install_with_secrets.sh` |
| Root password (fallback) | set — break-glass console recovery only |

After pasting: **delete** the generated file — `rm -- post_install_with_secrets.sh` (never commit it;
committed `post_install.sh` stays placeholder-only, keys never in Git).

### 0.5.3 First-boot verification

Reinstall rotates the host keys — capture them fresh and pin against the netcup install report (TOFU):

```bash
ssh-keygen -R vps.kogler.si
ssh-keyscan -4 -t ed25519,ecdsa,rsa vps.kogler.si | ssh-keygen -lf -
# compare the three fingerprints with the install-report e-mail, then:
ssh vps whoami && ssh vps hostname
ssh vps 'sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin|maxauthtries)"'
ssh vps 'ls /etc/ssh/sshd_config.d/'
ssh vps 'sudo cat /etc/sudoers.d/ansible-admin'
ssh vps 'awk "{print \$NF}" ~/.ssh/authorized_keys'
```

✔ Evidence: three fingerprints match the report · `ansible-admin` / `vps` ·
`passwordauthentication no` + `permitrootlogin no` + `maxauthtries 3` (from the hardening drop-in
alone) · `00-homelab-hardening.conf` present · `NOPASSWD:ALL` sudoers · exactly two authorized keys
(comments `admin@laptop` and `ansible`).

> **Break-glass:** locked out → netcup SCP **console** as root; the fallback password is item
> `netcup-vps_login` (owner's personal Homelab vault — invisible to the automation service account).
> Reusable recovery patterns from past incidents: authorized_keys repair (owning docs + git
> history, HD-209) and `nft flush ruleset` for a deploy-induced firewall lockout.

---

## Phase 1a — Homelab host installs (oldsrv / nas)

> **Official path: preseeded AUTOMATED install** (Automated entry, ZERO interactive questions
> end-to-end incl. the keyed late_command; success factors: wired-only NIC, ata-model_serial
> by-id resolves in d-i udev, `file=` patched entries, explicit medium choice via the iLO
> one-time boot menu). **INTERACTIVE + catch-up script remains the proven fallback.**
> Execution record: [deployment-tasks.md §Phase 1a](deployment-tasks.md) (ledger + commit evidence).
>
> **Prerequisites:** owning hardware doc ([hardware-oldsrv.md](docs/hardware-oldsrv.md) /
> [hardware-nas.md](docs/hardware-nas.md)) at hand · working `op` session on the laptop ·
> **exactly ONE USB stick** plugged into the target (two-sticks = wrong-medium boots).

### 1a.0 NAS ZFS pool bootstrap (one-time, BEFORE the nas installer boots) `[MANUAL]`

> As executed on 2026-08-23 (the data-migration leg is NOT part of a redeploy —
> execution record: [deployment-tasks.md §Phase 1a](deployment-tasks.md) (ledger + commit); hardware spec +
> by-id tables: [hardware-nas.md](docs/hardware-nas.md)). Pools are created EMPTY here; the
> Ansible `storage` role is import-only (`allow_create: false`) and owns every dataset beyond
> `bulk/migrate`. Gate: destructive — human approval per wipefs/pool-create block.

```bash
sudo apt update && sudo apt install -y zfsutils-linux

# -- stale-label wipe (signature-only erase, seconds; enclosure disks carry old GPT/PMBR) ------
sudo wipefs -a \
  /dev/disk/by-id/ata-WDC_WD30EFRX-68EUZN0_WD-WCC4N6YFD1UU \
  /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0X0TAS \
  /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0ZZYAS \
  /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M101SAS

# -- bulk RAIDZ2 (external SilverStone miniSAS enclosure, 4× 3 TB) ----------------------------
sudo zpool create -o ashift=12 \
  -O xattr=sa -O acltype=posixacl -O atime=off -O normalization=formD \
  bulk raidz2 \
    /dev/disk/by-id/ata-WDC_WD30EFRX-68EUZN0_WD-WCC4N6YFD1UU \
    /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0X0TAS \
    /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0ZZYAS \
    /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M101SAS

# -- landing-zone parent — ONLY if legacy data will be received into bulk/migrate -------------
#    (zfs receive does NOT create intermediate datasets)
sudo zfs create -p bulk/migrate

# -- tank mirror (2× 4 TB internal) -----------------------------------------------------------
sudo wipefs -a /dev/disk/by-id/ata-HGST_HDN726040ALE614_K4K9LBGB \
                /dev/disk/by-id/ata-ST4000NT001-3M2101_WX122FLD
sudo zpool create -o ashift=12 \
  -O xattr=sa -O acltype=posixacl -O atime=off -O normalization=formD \
  tank mirror \
    /dev/disk/by-id/ata-HGST_HDN726040ALE614_K4K9LBGB \
    /dev/disk/by-id/ata-ST4000NT001-3M2101_WX122FLD

# -- verify both ONLINE with zero errors, then export BOTH before booting the installer -------
zpool status; zpool list
sudo zpool export bulk tank
```

✔ Evidence: two `zpool status` blocks ONLINE / `errors: No known data errors`; after export,
`zpool list` shows no pools. Notes: physical ALLOC on raidz2 runs ≈1.67× logical bytes written
(parity + stripe padding) — do not mistake it for runaway growth; compression stays OFF at pool
level (runbook props; dataset props come later from the storage role SSOT).

### 1a.1 Build / verify media `[MANUAL]`

1. Base: Debian amd64 **DVD-with-firmware** image on a FAT32 stick (Rufus-style extracted layout is what was proven).
2. Recommended overlay (already applied to the proven SanDisk media): patch every boot entry (`boot/grub/grub.cfg`, `isolinux/*.cfg`) with `module_blacklist=iwlwifi` — kills the wireless-loop class of failures.
3. ✔ Boot the stick on the target → the Debian installer menu appears.

### 1a.2 Single-stick identity check `[MANUAL]`

At the installer console (**Ctrl+Alt+F2**):
```sh
ls /dev/disk/by-id/ | grep usb
```
✔ Exactly ONE `usb-*` entry and it is YOUR stick model. If anything else appears — shut down and remove the stranger first.

> **nas exception (two-stick install):** the nas installs with TWO USB
> sticks by design — the **SanDisk** = installer medium you boot from, and the **Generic_Flash_Disk
> (C3EB7FE7)** = permanent GRUB carrier that must be plugged so the preseed's `bootdev` by-id pin
> resolves. Boot EXPLICITLY from the SanDisk (iLO one-time boot menu); if the old Generic stick's
> bootloader comes up instead, the wrong medium booted — reboot and reselect. Verify at the console:
> exactly these two `usb-*` entries, nothing else.

### 1a.3 Interactive install `[MANUAL]` (*Graphical install*)

1. Network: choose the **wired** NIC only; skip any wireless prompt.
2. Hostname `<host>` (e.g. `oldsrv`), domain `kogler.si`.
3. Root password: **leave blank twice** (KOPS-044 posture; the local user gets sudo automatically).
4. Local user: real name + username + password (e.g. `domen`) — this is the LOCAL desktop/sudo identity, never a remote one.
5. Partitioning → **Manual**: identify the OS disk BY MODEL AND SIZE from the hardware doc (never by `sdX`; data disks must not appear in any step). New empty **msdos** table → swap ~8 GB primary → ext4 `/` primary + **bootable flag** → finish & write.
    - If asked *"Force UEFI installation?"* → **No** (keeps BIOS/CSM + MGR-in-MBR consistent with prior installs; record the answer in the commit/owning doc each time).
6. Mirror: `deb.debian.org`, defaults, no proxy.
7. Software selection: oldsrv = **XFCE desktop + SSH server + standard system utilities**; headless hosts = **SSH server + standard system utilities**.
8. GRUB → install to the OS disk entry matching the size above.
9. Reboot; **pull the stick**. ✔ Log in locally as the local user; `hostname -I` prints an address.
   - **VT map on oldsrv:** the XFCE desktop (lightdm) runs on **Ctrl+Alt+F7**; `F1`–`F6` are all text consoles.

### 1a.4 Catch-up: automation identity + keys + hardening `[MANUAL]`

The interactive path skips the preseed's `post_install.sh`, so reproduce its effect:

1. Laptop: build the keyed script — `bash scripts/gen-media-post-install.sh` (writes git-ignored `post_install_with_secrets.sh`, three pubkeys from 1Password).
2. Serve it: `py -3 -m http.server 8000 --directory <dir>` from the folder containing the script (first inbound connection triggers a Windows firewall prompt → Allow; or pre-open with elevated
   `netsh advfirewall firewall add rule name="preseed-http-8000" dir=in action=allow protocol=TCP localport=8000`).
3. Target (as the local user):
   ```sh
   sudo useradd -m -s /bin/bash ansible-admin
   wget -O pi.sh http://<LAPTOP_IP>:8000/post_install_with_secrets.sh
   sudo bash pi.sh
   rm pi.sh
   ```
   (`post_install.sh` installs python3/ssh, injects the two admin keys + restricted AI key, writes the sshd drop-in, restarts sshd.)
4. Delete the secrets file on the laptop: `rm IaC/host/post_install_with_secrets.sh`.
5. ✔ From the laptop: `ssh ansible-admin@<host>` logs in KEY-ONLY (no password prompt).
6. ✔ Expected refusal: `ssh <localuser>@<host>` is rejected by `AllowUsers` — the local user is desktop-only **by design**.
7. Ledger tick (deployment-tasks.md) + owning-doc evidence in the same change.

> **Proven chain:** the full hands-off preseed path works on the FAT32-extracted DVD layout (`file=`
> patched entries loaded, early_command runtime by-id resolution, static bootdev pin, keyed
> late_command). Still unproven: the initrd-injection route (initrd.gz rebuild works mechanically
> but was never needed). Single-stick discipline vs the nas two-stick exception stands (§1a.2);
> preseed disk paths use model_serial by-id (never eui — d-i udev lacks those links).

---

## Phase 2 — NAS runbook (`nas.kogler.si`): provision + UPS master

> **Depends on:** preinstall (Phase 1a), network cutover (Phase 1.5), the ZFS pools already
> created + exported (hardware-nas.md Pool-Creation Runbook / HD-207 — the storage role is
> import-only). Ledger: deployment-tasks.md §Phase 2.

1. **DHCP client-id = MAC (one-time, host pre-Ansible):** a fresh Debian install sends an
   RFC4361 DUID client-id that does NOT match the RouterOS MAC reservation → the host takes a
   dynamic pool address instead of its reserved static. The `network` role sets this via
   dhcpcd (`clientid mac`) / NM (`ipv4.dhcp-client-id=mac`) **on the first playbook run**, but
   until then the ansible_host (the reserved static) is unreachable. So before the first run,
   fix it by hand on the host (or run against the transient lease address):
   ```sh
   # dhcpcd (nas): comment out `duid`, add `clientid mac`
   sudo sed -i '/^duid/d' /etc/dhcpcd.conf && echo 'clientid mac' | sudo tee -a /etc/dhcpcd.conf
   sudo pkill -HUP dhcpcd        # re-request → binds the MAC reservation
   # verify: ip -br addr (should show the SSOT reserved Home IP)
   ```
   (oldsrv uses NetworkManager: `nmcli con mod "Wired connection 1" ipv4.dhcp-client-id mac`.)

2. **Ansible provision:**
   ```bash
   bash scripts/ansible-run.sh playbooks/storage.yml --check   # dry-run first
   bash scripts/ansible-run.sh playbooks/storage.yml
   ```
   Roles: `common` → `ai_diag` → `network` (netd units: untagged Home + tagged-99) → `storage`
   (import tank/bulk, datasets+props, NFS exports, sanoid/syncoid, Samba, exporters) → `nut`
   (master) → `cockpit`.

3. **ZFS kernel module (trixie):** the stock Debian kernel has no `zfs` module until `zfs-dkms`
   builds it — and DKMS needs the RUNNING kernel's headers. The role installs both, but if
   `modprobe zfs` fails first run: `apt-get install -y linux-headers-$(uname -r)` then
   `dkms autoinstall` (the meta `linux-headers-amd64` only gives the NEWEST kernel, not the
   booted one).

4. **UPS USB permissions (NUT):** the PowerWalker USB (Phoenixtec `06da:ffff`) node must be
   readable by the `nut` group. If `nut-driver@powerwalker.service` fails with "Access denied
   (insufficient permissions)": `sudo udevadm control --reload-rules && sudo udevadm trigger
   --subsystem-match=usb --subsystem-match=usb_device` (the stock NUT rules then set
   `root:nut 664`). Also: `retrycount` is NOT valid for `usbhid-ups` (NUT 2.8.1) — the role's
   ups.conf.j2 no longer emits it.

5. **Verify:** `zpool status` (tank mirror + bulk raidz2 ONLINE), `upsc powerwalker@localhost`
   (battery %/runtime), `exportfs` shows the 3 shares → oldsrv, `ss -tlnp | grep 9199`
   (nut_exporter), cockpit at cockpit-nas.kogler.si.

---

## Phase 1 — Deploy the VPS service stack

> Stack went live 2026-08-22 (33/35 Up). This section captures the settled initialization path —
> what a redeployer runs beyond the playbook itself.

### 1.1 Preconditions

- Phase 0 runner ready (`op` token readable; canonical key); Phase 0.5 VPS reachable as
  `ansible-admin@vps.kogler.si`.
- **Sync gate before EVERY run** (HD-212): whole-tree md5 compare Windows↔WSL must match.
- Vault coverage: `bash scripts/check-vault-items.sh` → seed gaps via
  `scripts/provision-vault.sh --create --yes` or manually. Placeholders that stay manual:
  `forgejo_api` (created post-install, step 1.7), provider keys (`openrouter_api`,
  `cohere_api`) post-green swaps.

### 1.2 First deploy

```bash
cmd //c "wsl -d Debian -- bash /home/domen/source/homelab/scripts/ansible-run.sh playbooks/vps.yml"
```

Anchor until green (`failed=0`).

### 1.3 Publish public DNS

```bash
cmd //c "wsl -d Debian -- bash /home/domen/source/homelab/scripts/ansible-run.sh playbooks/dns.yml"
```

Runs from home egress (token IP filter). Records: `vps` A/AAAA + apex/app CNAMEs
(SSOT: `roles/cloudflare_dns/vars/main.yml`; `ha` withheld until Phase 4).
Note: netcup resolvers negative-cache NXDOMAIN past record TTL — fresh records may take
minutes to resolve locally while authoritative answers are immediate.

### 1.4 Wildcard certificate

Traefik requests `*.kogler.si` + apex via DNS-01 automatically once the Cloudflare token is
valid from the VPS. Evidence of success:

- `traefik-certs-dumper` logs `certs-rename: installed kogler.si.pem + kogler.si-key.pem`
- `/opt/traefik/certs/kogler.si{,-key}.pem` exist (consumer pull contract)

If issuance loops: read traefik logs. `403 · 9109` = token IP filter (use EXACT IPs, never
CIDR — see [deployment-secrets.md](docs/deployment-secrets.md) `cloudflare_api`).
`429` from Let's Encrypt = 5 failed authorizations/identifier/hour — stop restarting, let the
window slide, then one clean restart. DNS-01 propagation checks query the CONTAINER's
resolvers — netcup negative cache requires the pinned `dns: [1.1.1.1, 8.8.8.8]` (already in
traefik + headscale services).

### 1.4b Tailnet dashboard edge (HD-135b follow-up) — tailnet-only admin dashboards

Converged by Ansible like every other compose service (`docker_services` row `traefik-tailnet`
in `group_vars/vps.yml`, enabled). Imperative facts a from-scratch deploy needs:

1. **Seed the tailscale auth key BEFORE the first converge** (fail-loud render if absent):
   `Homelab-ansible` item `tailscale-sidecar_api`, field `credential` = a headscale preauth key
   scoped to `tag:sidecar` — mint on the VPS:
   ```bash
   docker exec headscale headscale preauthkeys create --user 2 --tags tag:sidecar --reusable --expiration 8760h -o json
   ```
2. **`tailnet_sidecar_ip`** (`group_vars/vps.yml`) must hold the sidecar node's tailnet IPv4
   (read from `headscale nodes list` after the first join — value per SSOT/`tailnet_sidecar_ip`). Empty →
   headscale renders no `extra_records` (dashboards won't resolve on the tailnet).
3. **Certificate pairs:** the issuer requests `*.kogler.si` AND `*.ts.kogler.si`
   (Traefik dash router `tls.domains[0]/[1]`); `certs-rename.sh` copies both pairs to
   `/opt/traefik/certs/` (`kogler.si.pem` + `ts.kogler.si.pem`). The tailnet edge serves both
   from the DEFAULT store — no per-edge ACME.
4. **Serve passthrough:** the sidecar's `TS_SERVE_CONFIG` (`serve.json`) runs
   `tailscale serve --tcp=443 → 127.0.0.1:443`; the edge shares traefik-tailnet's netns
   (`network_mode: service:traefik-tailnet`) — recreate the PROJECT together (compose
   down+up) if the netns goes stale, then re-apply the serve config.

Verify from a tailnet device: `https://stats.kogler.si` (forward-auth → SSO) and
`https://stats.ts.kogler.si` (ACL-gated, tailnet-only).

### 1.5 Authentik first login

- `akadmin` / `authentik_login` password — works FIRST TRY on a fresh install (bootstrap env
  is pinned in compose and applies at user creation).
- Enrol WebAuthn + TOTP when prompted. Optional: personal named admin for daily use.
- **Human-user policy:** every new HUMAN user is created as **Internal
  type** — never External (federated sources) or Service account (machine/API identities). Full
  setup per user: real name + real email · Active ON · membership in the **`family` group** (the
  NAS user-sync glue reads exactly this group, D5/HD-131) · WebAuthn + TOTP enrolled at first
  login. Admin capability stays group-based (`authentik Admins`, where break-glass `akadmin`
  lives) — daily-driver users NEVER join it.
- Blueprint sanity: application count = 8 OIDC (`ks-oidc`) + 9 edge (`ks-forward-auth`);
  outpost “authentik Embedded Outpost” lists all 9 edge providers.

### 1.6 Forward-auth routes

Unauthenticated requests to protected hosts redirect to `sso.kogler.si`. Protected set +
exclusions are declared by router labels (source of truth) and mirrored in
`ks-forward-auth.yml` — add a proxy provider there when a new service joins the tier.

### 1.7 Forgejo one-time wizard

Browse to `git.kogler.si` → authentik login → installer:

| Field | Value |
|---|---|
| Database Type | PostgreSQL |
| Host | `forgejo-db:5432` |
| Name / Username | `forgejo` / `forgejo` |
| Password | 1Password `forgejo_db` → `password` |
| SSL Mode | Disable |
| Server Domain | `git.kogler.si` (pre-filled via env) |
| Disable self-registration | ON |
| Allow registration only via external services | ON (OIDC JIT provisioning) |
| Administrator Account | expand + set personal admin |

**Mail section** (leave empty; SMTP added post-green via app.ini — SMTP2Go port **2525**, netcup blocks 587):

| Field | Value |
|---|---|
| SMTP Host / SMTP Port / Send email as / SMTP Username / SMTP Password | *(empty)* |
| Require email confirmation for registration | false |
| Enable email notifications | false |

**Server & third-party settings:**

| Field | Value |
|---|---|
| Disable third-party | ON |
| Gravatar avatar sources | OFF |
| Libravatar federated lookup | OFF |
| Enable OpenID user login | ON |
| Allow registration only via external services | **ON** ← OIDC JIT provisioning (HD-148); local signup hidden anyway |
| Enable OpenID-based self-registration | ON |
| Require CAPTCHA for user registration | OFF |
| Require sign-in to view pages | OFF (edge forward-auth already gates every request) |
| Default hide email addresses | false (optional: ON for privacy) |
| Default allow organization creation | ON |
| Default enable time tracking | ON |
| Hidden email domain | `noreply.localhost` |
| Password hashing algorithm | `pbkdf2_hi` |

**Administrator account:**

| Field | Value |
|---|---|
| Administrator username | `domen` |
| Email | `domen@kogler.si` |
| Password + Confirm | personal password (stored in 1Password) |

⚠ The installer form does NOT read the `FORGEJO__*` env overlay — type DB values manually.
After install: Forgejo Admin → Applications → create API token (repo read/write) → paste into
1Password `forgejo_api` → `docker compose up -d renovate` (in `/opt/renovate`) or next run.

### 1.8 Kopia server seed *(fresh volumes only)*

If `/srv/docker/kopia-server/config/` is empty:

```bash
# 1) sftp_key — backup-box PRIVATE key (Hetzner-SB-Backup 1P item), unencrypted:
sudo nano /srv/docker/kopia-server/config/sftp_key && sudo chmod 600 /srv/docker/kopia-server/config/sftp_key

# 2) known_hosts — ssh-keyscan FROM THE VPS HANGS SILENTLY on box:23 (netcup egress quirk).
#    Take the entry from the LAPTOP's known_hosts instead:
#    laptop: ssh-keygen -F "[u653424.your-storagebox.de]:23"  -> copy the matching lines
#    into /srv/docker/kopia-server/config/known_hosts (mode 644).

# 3) Pre-create the repo dir ON THE BOX — Hetzner SFTP returns generic SSH_FX_FAILURE for
#    kopia's create-path even when the dir pre-exists (kopia_sftp_path is RELATIVE in IaC):
sudo ssh -i /srv/docker/kopia-server/config/sftp_key -p 23 \
  -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/srv/docker/kopia-server/config/known_hosts \
  u653424@u653424.your-storagebox.de "mkdir kopia"

# 4) Restart and verify (expect repository-creation lines, no SSH_FX_FAILURE):
sudo docker restart kopia-server && sleep 30 && sudo docker logs --tail 10 kopia-server
```

`kopia_sftp_path` stays RELATIVE (`kopia`) — absolute paths break create-path on Hetzner.
If the crowdsec volume is also fresh: regenerate the bouncer key (`sudo docker exec crowdsec
cscli bouncers add traefik-bouncer -o raw`) and update 1Password item `crowdsec-bouncer_api`
→ re-run vps.yml (re-renders middleware).

### 1.9 Verification

Full checklist: [deployment-tasks.md](deployment-tasks.md) Phase 1 Verify block. Quick spot
set: all forward-auth routes return 302→sso; vpn + ai return 200; wildcard cert served on
every host; `docker ps` shows no Restarting except documented owner-gated stragglers;
nvme usage <80%.

First-boot notes:
- **onlyoffice-docs** may sit at edge-502 for >30 min while its entrypoint initializes
  (nothing listens on :80 until done) — check `docker exec onlyoffice-docs wget -qO-
  http://localhost/healthcheck` before assuming failure.
- **db-backup**: trigger + verify the first dump manually —
  `docker exec db-backup backup01-now`, then confirm `/backup` fills inside the container.

### 1.10 Manual recovery patterns (non-Ansible)

- **nftables restart wipes docker NAT** (`flush ruleset` at top of ruleset): any manual
  `systemctl restart nftables` deletes docker's NAT programming → edge dark until docker
  re-programs. Recovery order:
  ```bash
  systemctl restart nftables && sleep 2 && systemctl restart docker   # live-restore keeps containers
  # verify: nft list tables | grep inet filter ; nft list table ip nat | grep -c dnat
  ```
  A plain docker restart does NOT wipe the inet filter table.
- **VPS reboot checklist** (~2 min): `docker ps` roster complete; inet filter present with
  input policy drop; ip nat has dnat entries; sso/git return 302.
- **Renovate repo-error diagnosis** (FATAL summary hides cause):
  `docker compose -f /opt/renovate/docker-compose.yml run --rm -e LOG_LEVEL=debug renovate`
- **Stale compose env:** container env older than rendered file (compose sees no change):
  `docker compose -f /opt/<svc>/docker-compose.yml up -d --force-recreate`.
## Phase 1.5 — Network redo cutover (MikroTik RB4011 / CRS328 / APs) `[MANUAL]`

> **Scope:** the post-Phase-1 home network redo. The 4 .rsc files below are
> **rendered once** (per change) from `IaC/router/templates/*.rsc.j2`; the router role takes
> over from there. Pre-flight: the two WireGuard S2S keys are **distinct per side** (HD-285 fix)
> — router `wg_password` (pub `wg_s2s_router_public_key`), VPS `wg_password_vps` (pub
> `wg_s2s_vps_public_key`, NEW item) — verify both 1P items hold `wg genkey`-format 44-char
> values; all 5 `wifi-kogler*` 1P items seeded; and the RB4011 flat backup saved
> (`rb4011_flat_backup.rsc` exported from Files before the reset).
> Backups: owner confirms each device has a current `.backup` file before starting.

### 1.5.1 Render the 4 bootstrap scripts + materialize the 2 .pub files (laptop, from the worktree)

> **Flash-persistence rule (HD-304):** on the **switch and APs**, the `.pub` files
> MUST live in the **`flash/` folder** — files placed in the device **root** are
> **wiped on reboot**, and the `/user ssh-keys import` in the bootstrap runs
> post-reset from `flash/`. The **RB4011 boots off flash and is immune** — its
> `.pub` files stay in root. The rendered `crs328_initial.rsc` / `ap_initial.rsc`
> import `public-key-file=flash/admin.pub` / `flash/ansible.pub`; `rb4011_initial.rsc`
> imports the bare names.

```bash
# 1) render the 4 secrets-injected .rsc files into the gitignored rendered/ dir
bash scripts/ansible-run.sh playbooks/render-routeros.yml -i inventory.ini
# 2) materialize the two SSH public keys the .rsc files import on each device
bash scripts/get-bootstrap-keys.sh
ls -la IaC/router/rendered/   # expect 6 files: 4 .rsc (4–5KB) + 2 .pub (~80B)
# 3) when uploading to the switch/APs, put the 2 .pub files in the device's
#    flash/ folder (root files are wiped on reboot); RB4011 root is fine.
```

✔-evidence: 6 files in the gitignored `IaC/router/rendered/`; the 4 .rsc files match the
expected byte sizes (rb4011 4173 B, crs328 4877 B, ap 3249 B, capsman 5110 B), and the 2
.pub files carry the expected fingerprints (asserted inside the script — `admin.pub` =
`SHA256:XTmK3tR59IMnok1HbEW7n3ZK0v4bd7miPS+0r7lSPTA`, `ansible.pub` =
`SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU`). The script reads from the
1Password vault `Homelab-ansible` (items `laptop-domen_ssh` + `ansible-admin_ssh`) and
exits non-zero on fingerprint drift — re-anchor the expected fingerprints in the script
if the vault rotates. Re-render the .rsc files if any lookup fails (fail-loud).

### 1.5.2 Upload + run-after-reset on each device `[MANUAL]`

Order matters: **RB4011 first**, then **CRS328**, then the **APs** (APs need the router DHCP
server for their mgmt lease). For each device: open WinBox → Files → drag-drop the matching
`.rsc` (into root) + the 2 `.pub` files into the device's **flash/ folder** on switch/APs (RB4011:
root is fine) → in the terminal:

```text
/system reset-configuration no-defaults=yes run-after-reset=<file>
```

Per device:

- **RB4011** — upload `rb4011_initial.rsc` + the 2 pubkeys. Reset triggers the script. Wait
  ~60 s; the router reappears as `router.kogler.si` on the management VLAN (SSOT gateway IP
  in [network-addresses-generated.md](docs/network-addresses-generated.md)) with services
  bound to `vlan99-mgmt`. PPPoE comes up automatically. ✔-evidence: ping the mgmt-VLAN
  router IP from the laptop (now on the same mgmt VLAN via the bootstrap access port).
- **CRS328** — upload `crs328_initial.rsc` (root) + the 2 pubkeys into `flash/`. Reset triggers
  the script. ✔-evidence: ping the mgmt-VLAN switch IP from the laptop; the CRS328 is
  reachable as `switch.kogler.si`.
- **APs** (hAP/wAP, one at a time) — upload the per-AP `ap_initial-<name>.rsc` (root; rendered
  per-AP since 2026-09-02 so the identity is `ap-spalnica`/`ap-dnevna`/`ap-spare`) + the 2 pubkeys
  into `flash/`. Each AP comes up on `bridge`, joins as a CAP (manager: radio config
  `configuration.manager=capsman`, `slaves-static=yes`), and gets its static-reserved `10.10.99.x`
  from the router's DHCP server. (Flash-persistence: root `.pub` files were being wiped on the AP
  reboot — the bug this phase fixed, HD-304.) ✔-evidence: on the router, `/ip dhcp-server lease
  print` shows the AP's expected MAC at its reserved `10.10.99.x` (dnevna =
  `C4:AD:34:42:F0:B9` after the Phase 1.5 prep swap; ap-garage retired); `:put
  [/system identity get name]` on the AP returns `ap-<name>`.

### 1.5.3 Hand over to the Ansible `router` role (the take-over)

From the **management laptop** (or the WSL runner — the role is the same). **Runner note:**
`community.routeros` 3.x requires `librouteros` in the
interpreter Ansible uses for modules. `inventory.ini` pins
`ansible_python_interpreter=/usr/bin/python3` (system), which does NOT have `librouteros` —
the venv (`~/ansible-venv`) does. The `scripts/ansible-run.sh` wrapper hardcodes `REPO` to the
PRIMARY checkout, so run from a **fresh session worktree** and force the venv interpreter.

**Laptop runner is Home-only → use the Pi-99 hop wrapper (2026-09-02, HD-285):** the WSL
runner sits on VLAN 10; its direct connection to `routeros_api_host` on the Mgmt VLAN loses
at both lockdown layers (forward `Default deny inter-VLAN` + `/ip service available-from =
mgmt`). The Pi (`eth0.99` tagged Mgmt) is the only real mgmt client. Use
[`scripts/ansible-network-hop.sh`](scripts/ansible-network-hop.sh) — it SSH-local-forwards
the device API through `pi` (traffic originates mgmt-sourced, passes both gates with zero
firewall surface) and execs `ansible-run.sh` with the loopback host/port + venv interpreter:

```bash
# from the session worktree (NOT the primary checkout):
bash scripts/ansible-network-hop.sh router playbooks/router.yml --check --diff   # dry-run first
bash scripts/ansible-network-hop.sh switch playbooks/switch.yml --check --diff
bash scripts/ansible-network-hop.sh router playbooks/router.yml                  # real
bash scripts/ansible-network-hop.sh switch playbooks/switch.yml
```

**Manual mgmt from the laptop — `~/.ssh/config` aliases (2026-09-02):** for direct WinBox/SSH/
RouterOS to switch + APs from the Home-only laptop, the same Pi-99 hop works through SSH port
forwards/ProxyJump. Preconfigured aliases (all via ProxyJump `pi`, same `id_ed25519`):

```bash
# verify (RouterOS answers `:put`):
ssh switch '':put OK''            # CRS328 .99.2
ssh ap-spalnica '':put OK''       # hAP ac² .99.4
ssh ap-dnevna '':put OK''         # hAP ac² .99.5
# WinBox on the laptop -> localhost:8291 (device .99.2):
#   ssh -N -L 8291:<switch .99.2>:8291 switch   (then WinBox Address=127.0.0.1:8291)
#   ssh -N -L 8291:<ap-dnevna .99.5>:8291 ap-dnevna
# aliases live in ~/.ssh/config:  pi99 .99.20, router99 .99.1, switch .99.2,
# ap-spalnica .99.4, ap-dnevna .99.5, ap-spare .99.6, nas99 .99.10 (nas offline → Phase 2)
# .99.x IPs = network-addresses-generated.md SSOT; aliases keep Windows off tagged-99 (laptop stays untagged Home-only).
```

> The aliases keep Windows off tagged-99 (the laptop stays untagged Home-only); the Pi `eth0.99`
> leg is the only mgmt client. `nas99`/`ap-spare` may report 'No route to host' until those devices
> are powered/provisioned (spare AP + Phase-2 NAS).

> **2026-09-02 (maintenance window):** this hop unblocked the live re-converge — router
> `ok=34 changed=5 failed=0`, switch `ok=23 changed=4 failed=0`, both through the Pi hop.
> It also surfaced + fixed live switch-role bugs: `poe-out: on` (→ `auto-on`, the CRS328
> rejects `on`), `poe-priority: high` (invalid value), INPUT firewall `dst-port` without
> `protocol: tcp` (RouterOS requires it). And a router-role `router_port_map` dict2items
> bug (`item.port` → `item.value.port`).

✔-evidence: `ok`/`changed` counts in the play recap are sensible (expect 1–2 changed per
device on a re-run; expect a larger changed count on a fresh-bootstrap run because VLANs
and firewall are built from scratch). The role's first task is an **identity assert**
(HD-161) — a wrong-target aborts the run before any `api_modify`. The `vlan-filtering` enable
on `bridge-lan` is the **last** task (line ~811) so a half-applied run can never blackhole
the bridge.

#### 1.5.3b Converge-.rsc escape

If the Ansible role take-over stalls on live-found `api_modify` bugs (partial state left on
the device), the pragmatic cutover path is a **generated full-steady-state `.rsc` import** —
the same mechanism as the bootstrap. Render + import:

```bash
# from a session worktree, venv interpreter:
ansible-playbook -i inventory.ini playbooks/render-converge.yml \
  -e ansible_python_interpreter=~/ansible-venv/bin/python3
# outputs IaC/router/rendered/rb4011_converge.rsc + crs328_converge.rsc (gitignored)
```

Then on each device: upload the matching `.rsc` + the `.pub` keys (rb4011: root
`admin.pub`/`ansible.pub`; crs328: `flash/` per HD-304), `/import` in a WinBox terminal
(or `run-after-reset=` on a clean device — the converge is self-sufficient: PPPoE + INPUT
floor are included). **Order: crs328 first, then rb4011.** The converge is idempotent-ish
(`/set` safe; `/add` on duplicates reports "already have" and continues).

Live lessons baked into the templates: (a) **quote EVERY non-literal value** — the WG
pubkey contains `+/=` and the admin/pppoe passwords contain `!`, all of which the RouterOS
script parser mangles UNQUOTED (the operator hit the WG pubkey on import); (b) the crs328
converge enables `vlan-filtering` as the LAST command (enabling it at bridge create severs
the switch's own mgmt path — the recurring re-lock); (c) no forced `poe-out=on` (CRS328
rejects it — `syntax error col 41`; the default `auto-on` powers APs/camera).

⚠ **Secret hygiene for the converge path:** the rendered `.rsc` files contain LIVE secrets
(admin password, PPPoE login). Never commit/push them (`IaC/router/rendered/` is
gitignored), never cat/grep their values to a terminal/chat/transcript, and delete the
folder or re-render after any secret rotation. CONVENTIONS §2.

### 1.5.4 Apply the CAPsMAN steady-state (the `wifi-qcom-ac` package, HD-232)

After §1.5.3 settles and the role is green, push WiFi back up. This is **NOT a reset** —
the RB4011 already has the bridge/VLANs/DHCP/firewall; the import only adds the
wifi/security/provisioning objects.

```text
# in WinBox Files on the RB4011
/import capsman_steady-state.rsc
```

> **1.5.3c Delta-rsc apply path (HD-308 Shield L2 trunk fix / HD-309) — ssh-import; full procedure in [network-ops.md](docs/network-ops.md) §Apply workflow.** Render the transient delta, SCP to the device root, `/import` over SSH (ansible identity, pinned hostkey). **Automated:** `bash scripts/routeros-apply-delta.sh <router-ip> <delta-file>` (op read → key load-verify → host-key pin → SCP → `/import`). Manual equivalent:
> ```bash
> ssh-keyscan -T5 -t ed25519,rsa <router> > /tmp/router_hostkeys.txt
> scp -i <ansible-key> IaC/router/rendered/rb4011_<name>_delta.rsc ansible@<router>:/rb4011_<name>_delta.rsc
> ssh ansible@<router> '/import rb4011_<name>_delta.rsc'   # 'loaded and executed successfully'
> ```
> The `apply-converge.yml` playbook (Ansible path) SCP-uploads + verifies the key (`ssh-keygen -y` load-verify, HD-309) but its final API `/import` step needs `librouteros` in the runner interpreter — if that is missing, use the SSH-import path above (`routeros-apply-delta.sh`).

✔-evidence on the RB4011:

```text
/interface wifi configuration print        ; expect the ENABLED cfg-kogler* rows (currently 2: cfg-kogler + cfg-kogler-iot)
/interface wifi capsman print              ; 'enabled: yes' (was the missing piece — APs never provisioned)
/interface wifi security print             ; expect sec-kogler* profiles (currently 2)
/interface wifi registration-table print   ; clients appear per SSID as they re-join
/interface wifi provisioning print         ; dynamic CAP entries created for each AP
```

> **2026-09-02/03 live fix recap (the 'APs not functioning' bug):**
> 1. The rendered rsc **never enabled the manager** — `/interface wifi capsman set enabled=yes` is now
>    the first line (configs existed but the manager sat `enabled=no`, so no AP ever provisioned).
> 2. wifi-qcom-ac CAPs **cannot honor datapath vlan-id** — configs now use a named datapath `DP_AC`
>    (bridge-lan, NO vlan-id); per-SSID VLAN rides the CAP's **bridge** (pvid per provisioned slave
>    interface + tagged uplink `ether1`).
> 3. AP radios need `configuration.manager=capsman` + `disabled=no` + CAP `slaves-static=yes`
>    (ap_initial.rsc.j2 carries this; a plain `cap set enabled=yes` alone left them locally-configured
>    masters that never joined — the `MBX` state).
> 4. AP identities are now descriptive (`ap-spalnica`, `ap-dnevna`, `ap-spare`) via per-AP rendered
>    `ap_initial-<name>.rsc`.
> 5. Enabled SSIDs = **Kogler + Kogler IOT + Kogler guest** (HD-312 3-SSID, owner decision 2026-09-03).
>    **Kogler IOT is 2.4GHz-only; Kogler guest is 5GHz-only** (band-split provisioning by SSID `band:`
>    in `routeros_capsman_ssids` SSOT: 2.4GHz = Kogler+IOT, 5GHz = Kogler+guest). IOT-WAN + Kids SSIDs
>    were **deleted** 2026-09-03 (configs + security profiles removed; kids-control → firewall
>    MAC-list per HD-312).
> 6. **Switch AP ports must carry the wifi VLANs tagged** (2026-09-03 — the 'phone disconnects'
>    cause): AP ports ether11/12 on the CRS328 need tagged membership of the wifi VLANs (10+20,
>    and 30 since guest went live) not just the untagged 99 access, or the AP's per-SSID tagged
>    frames get dropped at switch ingress and clients associate but never DHCP. Encoded in
>    `wifi_ports` (group_vars/switch.yml) + converge rsc.
> 7. **A new slave SSID does NOT auto-materialize at the CAP on provisioning change alone**
>    (live 2026-09-03, guest turn-up): after adding a slave to a provisioning rule, kick the CAPsMAN
>    manager (`/interface wifi capsman set enabled=no` then `=yes`) so the CAP re-pulls and creates
>    the slave (wifi27 spalnica / wifi8 dnevna for guest), then add the CAP bridge VLAN entry
>    (`/interface bridge vlan add vlan-ids=30 tagged=ether1 untagged=<slave>` + port pvid=30).
>    See `ap_guest_delta.rsc.j2` (the idempotent, guarded delta).

Devices must re-join the right SSID (Kogler → VLAN 10 / Kogler IOT → VLAN 20 / Kogler guest → VLAN
30) to land on their VLAN.

### 1.5.5 Bring up the WG S2S tunnel (HD-91 / HD-285 two-key fix)

Each side holds a **DISTINCT** WireGuard keypair (HD-285 fix — shared key made pubkeys identical and the router tried to handshake with itself, so no handshake ever fired):

| Side | 1P key item | Own pubkey var | Peer pubkey var (the other side) |
|------|-------------|----------------|----------------------------------|
| Router (RB4011) | `wg_password` | `wg_s2s_router_public_key` | `wg_s2s_vps_public_key` |
| VPS | `wg_password_vps` | `wg_s2s_vps_public_key` | `wg_s2s_router_public_key` |

**Endpoints are DDNS tokens, not literal IPs:** VPS→router uses `wg_s2s_vps.endpoint: s.kogler.si`; router→VPS uses `wireguard_s2s_vps.remote_endpoint: vps.kogler.si` (Cloudflare A). `s.kogler.si` tracked in `cloudflare_dns/vars/main.yml`.

**Bring-up (from a session worktree, venv interpreter):**

```bash
# VPS side — wireguard role (distinct key + peer + the oneshot owns the iface):
bash scripts/ansible-run.sh playbooks/vps.yml --tags wireguard
#   the wg-ensure-s2s-peer oneshot: create-if-missing iface → address → key (wg setconf key-only) → peer (wg set) → verify.

# Router side — router role (own key from wg_password, peer = VPS key, endpoint = vps.kogler.si):
bash scripts/ansible-network-hop.sh router playbooks/router.yml
```

**Post-converge manual fixes that the role does NOT hold (live-found 2026-09-02, imperative):**

```text
# 1) If the router peer still shows the OLD/self pubkey, set it to the VPS key:
/interface wireguard peers set [find comment="vps-s2s"] public-key="<wg_s2s_vps_public_key>"
# 2) The HD-155 forward accept must sit ABOVE the Default deny inter-VLAN (else shadowed):
/ip firewall filter move <vps-accept-index> destination=<default-deny-index>   ; verify order: VPS accept directly above Default deny
```

✔-evidence (both sides must show the peer + a fresh handshake):

```text
# RB4011
/interface wireguard print           ; wg-s2s, own key ≠ peer key
/interface wireguard peer print      ; vps-s2s = VPS pubkey, endpoint vps.kogler.si, current-endpoint set
# VPS
sudo wg show wg-s2s                  ; peer = router pubkey, latest-handshake non-zero + renewed (keepalive 25)
sudo wg show wg-s2s transfer         ; rx/tx moving (data plane)
ping -c3 <router-mgmt-ip>            ; router mgmt over the tunnel (0% loss; IP = SSOT `router` mgmt row in network-addresses-generated.md)
```

> **HD-306/HD-285 mechanism note (imperative, from live 2026-09-02):** systemd 257 networkd applies the
> `.netdev` `[WireGuard] PrivateKey` but **never applies `[WireGuardPeer]`**, and strips any userspace
> `wg set peer` while it owns the iface. Fix: networkd is reduced to **create-only** (minimal `.netdev`
> + `Unmanaged=yes` `.network`); the `wg-ensure-s2s-peer` oneshot OWNS wg-s2s (create-if-missing →
> address from `wg_s2s_vps.local_ip` → key via `wg setconf` KEY-ONLY → peer via `wg set … peer` →
> verify key + peer present, exit non-zero on missing). The `wg-s2s.conf` carries the VPS key (0640).

**Authoring pitfalls (do not relearn):** ① Jinja `trim_blocks` eats a newline after `{% endfor %}` → use an explicit `{{ '\n' }}`. ② `.netdev` 0640 (`0600`+ACL → networkd `Permission denied`). ③ `[WireGuardPeer]` in `.network` is ignored. ④ Never put the `PrivateKey` in a **peer-only** `wg setconf` for the router side — the two-key role handles it.

### 1.5.6 Cutover close-out

- `validate-all.sh` green from the worktree.
- Tick the matching `- [x]` boxes in [deployment-tasks.md](deployment-tasks.md) Phase 1.5 (add
  the phase there if it isn't yet); in the ledger notes: device names, timestamps, evidence
  snippets (lease print, wireguard peer print). Secrets by 1P item+field name only.
- Trim the HD-285 `⏳` tail in [todo.md](todo.md); the row closes when §1.5.5 handshakes.
- Commit signed (`G`) on the session branch; merge to main; remove the worktree.

---

## Phase 4 — Pi Fresh Install + HA Primary (`pi.kogler.si`)

> **Depends on:** Phase 1.5 (VLANs / network reachability), Phase 2 (NAS NUT master), Phase 3 (old srv standby, Forgejo). The Pi is the HA **primary** node; oldsrv (Phase 3) is standby. Both share one `configuration.yaml` and the VIP (`ha-vip`).
> **1Password prerequisites:** `ha_api`, `ha-vrrp_password`, `nut_password`, `smtp_login` already exist; add `ha-mqtt_login` only if MQTT is introduced (out of scope).
> **Continuation:** `ha.kogler.si` → VIP becomes live here; observability (Phase 6) scrapes the HA exporter and smart-home work (Phase 7) builds on this node.

### 4.1 Flash + first-boot config `[MANUAL]`

> The Pi uses **Raspberry Pi OS Lite (64-bit, headless)** — official Debian-based image, NOT the
> Debian Installer/preseed path of nas/oldsrv (no `d-i` to answer questions, `preseed.cfg` does
> not apply); the raspi.debian.net image fails with a **rainbow screen** (kernel/firmware mismatch
> on the Pi 4) → use Pi OS Lite via Raspberry Pi Imager. Authoring spec:
> [deployment-preseed.md → Pi Image Deployment](docs/deployment-preseed.md).

1. **Download** Raspberry Pi OS Lite (64-bit) from https://www.raspberrypi.com/software/operating-systems/.
2. **Flash with Raspberry Pi Imager** to microSD (≥32 GB; 32–64 GB typical) — Imager's **⚙ advanced gear** does the headless pre-config: **Enable SSH + set user (`admin`) + preload the `ansible-admin_ssh` pubkey, hostname `pi`, timezone/locale** (writes `ssh` flag + `userconf.txt` — no manual card edit needed; the old `first-boot-config.sh` is for raspi.debian.net and **not** used here). **Do NOT boot yet.**
3. **Re-insert the SD card into the laptop** (USB adapter). The boot partition mounts as a drive/FAT32 (e.g. `E:`). From WSL, mount it:
   ```bash
   sudo mkdir -p /mnt/e && sudo mount -t drvfs E: /mnt/e
   ls /mnt/e/config.txt /mnt/e/cmdline.txt   # must exist — verifies it's the Pi boot partition
   ```
   ⚠ **WSL2 cannot see USB raw devices** — no `/dev/sdX` for the card, and cannot mount the ext4 **root** partition. Only the FAT32 boot partition (via the drive letter) is editable from WSL. That is sufficient: first-boot config needs only boot-partition files. To edit the root filesystem (e.g. `PermitRootLogin`), you'd need a native Linux host / live USB — **not needed** for the cloud-init path.
4. **Imager already pre-configured SSH + user + hostname** (step 2's ⚙ gear) — **no boot-partition edit / no `first-boot-config.sh` needed** (that script is raspi.debian.net-only). Eject safely, insert into the Pi, power on.

### 4.2 First-boot verification `[MANUAL]`

```bash
ping pi.kogler.si          # node resolves to its VLAN-10 static IP per the SSOT ([network-addresses-generated.md](docs/network-addresses-generated.md))
ssh ansible-admin@pi.kogler.si    # key-only, no password prompt
# if cloud-init worked, users exist; otherwise on the Pi:
sudo bash /boot/firstboot.sh
```

✔ SSH key-only login as `ansible-admin`; `ssh ai-debug@pi.kogler.si` refused from outside the Home VLAN (the `from="…"` restriction authored in the first-boot script).

> ⚠ Verify the **router-side DHCP reservation** for the Pi's MAC matches the SSOT node IPs (VLAN 10 + mgmt VLAN 99 — see [network-addresses-generated.md](docs/network-addresses-generated.md)) before relying on static IPs.

> **⬇ 2026-09-03: the complete imperative flow (dry-run → provision → verify → owner KNX/SSO steps)
> now lives in [`deployment-pi-provision.md`](docs/deployment-pi-provision.md)** — this section keeps the
> load-bearing ordering + session-safety notes below and links the new runbook.

### 4.3 Ansible provisioning

```bash
# from the WSL Debian runner (venv), with the 9P sync gate satisfied:
bash scripts/ansible-run.sh playbooks/raspberry_pi.yml
# first apply human-gated: dry-run (--check --diff) then single host
```

Role order is **load-bearing** (HD-185/204 render-first decision): `common` → `ai_diag` → `network` (static dual-home via **two NetworkManager keyfiles** — Pi-uses-NM, [network-rejected.md](docs/network-rejected.md) 2026-09-01; RPi OS ships NetworkManager, no systemd-networkd. The role renders `pi-eth0.nmconnection` = untagged Home on the parent (`ansible_host`, default via Home — single gateway, no `never-default`, DNS via `bootstrap_dns_servers`, DHCP off) + `pi-mgmt.nmconnection` = tagged Mgmt on `eth0.99` (`mgmt_ip`, never-default, route via the tagged leg — HD-311); session-safe — the Home IP never changes, the Mgmt IP rides the tagged sub-interface, never the untagged parent) → `nut` (client, `shutdown_delay_seconds=0`) → `docker` → **`home_assistant` → `docker_services`** → `monitoring` (Alloy only). Running `home_assistant` BEFORE `docker_services` renders `configuration.yaml` / `keepalived.conf` (+ `secrets.yaml` — renderer landed 2026-09-03, HD-185/HD-313) as **regular files** before first `compose up` — the old KOPS-063 order made Docker auto-create bind-mount dirs and HA silently ran default config. Do not reorder.

> ⚠ **Session-safety (live lessons):** (1) 2026-09-01 — do **NOT** switch the Pi's NM connection to a NEW profile id with `nmcli connection up <new-profile>` — activating a new manual profile **deactivates the DHCP connection and drops the interface**, severing the remote SSH session (Pi offline; only the router could ping it on the Home leg). (2) 2026-09-02 — the `network` role renders TWO keyfiles: `pi-eth0.nmconnection` (untagged Home parent) + `pi-mgmt.nmconnection` (tagged Mgmt `eth0.99`). Applying the changed `pi-eth0` keyfile over the wire is safe **because the connection id stays `pi-eth0` and the Home IP is unchanged** — install the file, `nmcli connection reload`, then `nmcli connection up pi-eth0` (for an already-active connection this is a re-apply, not a profile switch). The Mgmt IP lives ONLY on the tagged sub-interface, never on the untagged parent (its connected route hijacked 10.10.99.x away from the tagged leg — `router99` 'No route to host' live 2026-09-02, fixed + verified).

Pi `docker_services` = `home-assistant-primary`, `technitium-secondary`, `traefik-ha` (the minimal VIP edge). **No** pihole, **no** raspberrymatic (HD-13 parked — HmIP-HAP stays in cloud mode).

### 4.4 Verify

- `ha.kogler.si` resolves to the VIP (`ha-vip` per SSOT); `keepalived` MASTER on the Pi (priority 110 > oldsrv's 100).
- Technitium resolves `*.kogler.si` internally — **3-instance DNS HA: VPS primary (resolver = VPS public IP) / oldsrv secondary / Pi tertiary** (HD-317, 2026-09-03; IaC landland + deploy-gated — option A: single VPS-public resolver + VPS nftables source-allow + DDNS-refresh timer).
- HA web login via Authentik **native OIDC** on the `ha` route (no Forward-Auth).
- Manual failover Pi→oldsrv and back passes ([smart-home-failover.md](docs/smart-home-failover.md) runbook; HD-17 button + `ha-failover_api` pending).
- NUT client shutdown path (master = nas) · monitoring scrape of the HA exporter (Phase 6).

> **Deploy-gated:** HD-04 (HAOS→Debian+HA Container+Technitium secondary), HD-17/124 (failover
> button + keepalived hardening). See [todo.md](todo.md) rows + [home-assistant-current.md](docs/home-assistant-current.md).

---

*Last updated 2026-09-01 · imperative redeploy procedure (true zero → live) for Phases 0 + 0.5 + 1a + 1 + 1.5 + 4. Progress/history lives in [deployment-tasks.md](deployment-tasks.md) + owning docs.*

