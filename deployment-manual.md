# deployment-manual.md — Redeployment Runbook (True Zero → Live)

> **Role:** Imperative, phase-by-phase **procedure** for redeploying the homelab from true zero —
> exact commands, panel settings, and the verification evidence each step must produce before the
> next step runs. Deliberately free of progress markers and fix history: progress checkboxes live in
> [deployment-tasks.md](deployment-tasks.md) (ledger), execution history in
> [deployment-journal.md](deployment-journal.md) (as-built), desired-state specs in the owning
> `docs/*.md`. If reality diverges permanently, fix the procedure here (or the owning spec) in the
> same change and journal the event.
> **Linked from:** [docs/index.md](docs/index.md), [docs/deployment.md](docs/deployment.md),
> [deployment-tasks.md](deployment-tasks.md), [CONVENTIONS.md](CONVENTIONS.md) §4

---

## How to use

- Execute phases in order. Every step ends with a ✔-evidence check — do not proceed past red.
- Binding working rules: `bash scripts/validate-all.sh` green before every commit; secrets by
  1Password item+field name only (never values); every executed action gets a journal entry
  (raw notes → the DATA feed in [prompt-journal.md](prompt-journal.md)).
- Shells: repo ops + validators from **git-bash** (Windows laptop); Ansible runs ONLY on the
  **WSL Debian runner** through [scripts/ansible-run.sh](scripts/README.md) — never pass inline
  commands to wsl.exe.
- ⚠ **9P staleness — sync gate before playbook runs (HD-212, decided 2026-08-22):** the
  runner reads the repo **natively under WSL ext4 now (HD-259 primary `/home/domen/source/homelab`)** — the
  `/mnt/d` drvfs 9P staleness window is closed, so the whole-tree hash compare is no longer required before
  every playbook run. Retained only for the residual case of a `/mnt/d` working copy:
  1. Whole-tree compare from the repo root on BOTH sides — must be equal:
     `git ls-files -z | xargs -0 md5sum --text | md5sum`  
  2. Mismatch → force-invalidate, re-hash after each:
     `wsl -d Debian -u root -- bash -c 'echo 3 > /proc/sys/vm/drop_caches'`; still stale → inside WSL
     `sudo umount /mnt/d && sudo mount -t drvfs D: /mnt/d`.
  3. Both fail to clear → migrate the runner clone natively into WSL (pre-authorized, no re-ask).
- Quick turnover while iterating on a failing step: re-run from a named task —
  `bash scripts/ansible-run.sh playbooks/<playbook>.yml --start-at-task="<task name>"`.
- **Surgical `--tags` runs — union semantics (HD-220 wiring):** tag selection is a UNION across
  every task carrying ANY requested tag; adding tags only ADDS work, it never narrows it.
  Role-level tags (`vps.yml`: `[common] [docker] [hardening] [network] [cifs] [wireguard]
  [docker_services] [monitoring]`) attach to all tasks directly in the role but do NOT cascade
  through dynamic `include_tasks:` into file contents — so inside `docker_services`, per-service
  tasks (tagged `{{ svc.name }}`) are reachable ONLY when the filter names BOTH the role and the
  service. A service tag alone (`--tags opencloud`) matches nothing and is a SILENT NO-OP.
  Canonical forms:
  - whole VPS converge: no `--tags`
  - one role: `--tags monitoring`
  - one compose service (+ its edge/dynamic-file companions):
    `--tags "docker_services,<service>"` — add `,traefik` whenever Traefik dynamic-file
    templates changed (routes/middlewares/tls live under the `traefik` service dir), e.g.
    `--tags "docker_services,onlyoffice-docs,traefik"`;
    add `,authentik` / `,secret-egress` to include the Authentik pre-pass/glue lanes
  - discovery first: `--list-tags`, `--list-tasks --tags <filter>` (confirm what WILL run)
  Full semantics, wiring map and gotchas: [docs/deployment-ansible.md](docs/deployment-ansible.md) §Tags & surgical runs.

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
> Reusable recovery patterns from past incidents: authorized_keys repair (journal Phase 1.0,
> HD-209) and `nft flush ruleset` for a deploy-induced firewall lockout (journal Phase 1).

---

## Phase 1a — Homelab host installs (oldsrv / nas)

> **Official path: preseeded AUTOMATED install — RE-PROVEN 2026-08-23 on nas** (Automated entry,
> ZERO interactive questions end-to-end incl. the keyed late_command; success factors: wired-only
> NIC, ata-model_serial by-id resolves in d-i udev, `file=` patched entries, explicit medium choice
> via the iLO one-time boot menu). **INTERACTIVE + catch-up script remains the proven fallback**
> (same-day oldsrv precedent: four delivery mechanisms failed in one evening — netcfg WLAN loop,
> `file=` mount-timing on the FAT32 layout, d-i udev lacking `nvme-eui.*` links so the seeded disk
> path matched nothing, plus a two-sticks incident where the target booted an unrelated USB; the eui
> trap is installer-environment-only — full udev on the installed systems resolves it fine).
> Execution record: [deployment-journal.md](deployment-journal.md) §Phase 1a.
>
> **Prerequisites:** owning hardware doc ([hardware-oldsrv.md](docs/hardware-oldsrv.md) /
> [hardware-nas.md](docs/hardware-nas.md)) at hand · working `op` session on the laptop ·
> **exactly ONE USB stick** plugged into the target (two-sticks = wrong-medium boots).

### 1a.0 NAS ZFS pool bootstrap (one-time, BEFORE the nas installer boots) `[MANUAL]`

> As executed 2026-08-23 (data-migration leg of that day's run is NOT part of a redeploy —
> execution record: [deployment-journal.md §Phase 1a](deployment-journal.md); hardware spec +
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
#    (zfs receive does NOT create intermediate datasets — learned live 2026-08-23)
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

> **nas exception (two-stick install, owner decision 2026-08-23):** the nas installs with TWO USB
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
    - If asked *"Force UEFI installation?"* → **No** (keeps BIOS/CSM + MGR-in-MBR consistent with prior installs; journal the answer each time).
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
7. Journal entry + ledger tick in the same change (deployment-journal.md rules).

> **Re-proven on nas 2026-08-23:** the full hands-off chain works on the FAT32-extracted DVD layout (`file=` patched entries loaded, early_command runtime by-id resolution, static bootdev pin, keyed late_command). Still unproven: the initrd-injection route (initrd.gz rebuild worked mechanically but was never needed nor booted). Single-stick discipline vs the nas two-stick exception stands (§1a.2); preseed disk paths use model_serial by-id (never eui — d-i udev lacks those links).

---

## Phase 1 — Deploy the VPS service stack

> Stack went live 2026-08-22 (33/35 Up; journal §Phase 1 R1–R5). This section captures the
> **settled initialization path** — what a redeployer runs beyond the playbook itself.
> Final Verify-block evidence pass pending two owner inputs (see 1.8).

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
- **Human-user policy (owner decision 2026-08-23):** every new HUMAN user is created as **Internal
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

# 2) known_hosts — ssh-keyscan FROM THE VPS HANGS SILENTLY on box:23 (netcup egress quirk,
#    verified 2026-08-23). Take the entry from the LAPTOP's known_hosts instead:
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
  A plain docker restart does NOT wipe the inet filter table (verified 2026-08-23).
- **VPS reboot checklist** (~2 min): `docker ps` roster complete; inet filter present with
  input policy drop; ip nat has dnat entries; sso/git return 302.
- **Renovate repo-error diagnosis** (FATAL summary hides cause):
  `docker compose -f /opt/renovate/docker-compose.yml run --rm -e LOG_LEVEL=debug renovate`
- **Stale compose env:** container env older than rendered file (compose sees no change):
  `docker compose -f /opt/<svc>/docker-compose.yml up -d --force-recreate`.
*Last updated 2026-08-23 · Phases 0 + 0.5 + 1a complete (incl. 1a.0 pool bootstrap as executed); Phase 1 written from the settled 2026-08-22 initialization path (stack live, Verify evidence pass pending two owner inputs).*
