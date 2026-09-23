# deployment-manual.md — Redeployment Runbook (True Zero → Live)

> **Charter (what belongs here and what does not).** This file is the **imperative procedure** for rebuilding
> the homelab from nothing: the ordered commands, panel settings and ✔-evidence checks a human executes. It
> carries **no knowledge, no status and no history** — no "why we chose X", no tick or hourglass markers, no dated fix
> recaps, no as-built state. Those live in exactly one place each:
>
> | Content | Home |
> |---------|------|
> | **Procedure** — ordered commands, panel settings, evidence checks | **this file** |
> | **Knowledge** — specs, designs, decisions, root causes, as-built state | the owning `docs/*.md` |
> | **Progress** — what is done / what is next | [deployment-tasks.md](deployment-tasks.md) (ledger) |
> | **Lifecycle of a work item** | [todo.md](todo.md) |
> | **What one change actually did** | the git commit |
>
> When a step needs a fact to make sense, it **links the owning doc** instead of restating it. If reality
> diverges permanently, fix the procedure here *and* the owning spec in the same change — the commit records it.
>
> **Human-only steps are tagged `**[MANUAL]**`.** Ansible commands appear here because they ARE the deploy
> procedure (the GitOps deploy button of ledger Phase 5 does not exist yet) — a from-zero rebuild is a human
> pressing keys, and this is the sequence they press them in.
>
> **Phase numbering follows the ledger exactly.** `spark` is **Phase 4b** in both documents.
>
> **Linked from:** [docs/index.md](docs/index.md), [docs/deployment.md](docs/deployment.md),
> [deployment-tasks.md](deployment-tasks.md), [CONVENTIONS.md](CONVENTIONS.md) §4

---

## Phase index (true-zero order)

| § | Phase | Host / scope | Owning spec |
|---|-------|--------------|-------------|
| 0 | Management runner (WSL Debian) | laptop | [deployment-ansible.md](docs/deployment-ansible.md) |
| 0.5 | VPS re-provision (netcup SCP) | vps | [services-vps.md](docs/services-vps.md) |
| 1 | VPS service stack | vps | [services-vps.md](docs/services-vps.md), [services-authentik.md](docs/services-authentik.md) |
| 1a | Host installs + ZFS pool bootstrap | nas, oldsrv | [hardware-nas.md](docs/hardware-nas.md), [hardware-oldsrv.md](docs/hardware-oldsrv.md) |
| 1.5 | Network redo cutover | RB4011, CRS328, APs | [network-ops.md](docs/network-ops.md), [network-vlans.md](docs/network-vlans.md) |
| 2 | NAS provision + UPS master | nas | [hardware-nas.md](docs/hardware-nas.md), [hardware-ups.md](docs/hardware-ups.md) |
| 3 | oldsrv services + first-boot tiers | oldsrv | [hardware-oldsrv.md](docs/hardware-oldsrv.md), [services-ai.md](docs/services-ai.md) |
| 4 | Pi install + HA primary | pi | [deployment-pi-provision.md](docs/deployment-pi-provision.md) |
| 4b | DGX Spark first-boot + onboarding | spark | [hardware-spark.md](docs/hardware-spark.md) |

---

## How to use

- Execute phases in order. Every step ends with a ✔-evidence check — do not proceed past red.
- Binding working rules: `bash scripts/validate-all.sh` green before every commit; secrets by
  1Password item+field name only (never values); every executed action gets an owning-doc
  status note + a commit.
- Shells: repo ops + validators from **git-bash** (Windows laptop); Ansible runs ONLY on the
  **WSL Debian runner** through [scripts/ansible-run.sh](scripts/README.md) — never pass inline
  commands to wsl.exe.
- **Ansible-run semantics** (sync gate, `--tags` surgical runs, venv interpreter): see
  [scripts/README.md](scripts/README.md) + [docs/deployment-ansible.md](docs/deployment-ansible.md) §Tags & surgical runs.
- **Run every converge DETACHED and verify the artefact, not the recap.** Foreground converges get killed
  mid-restart; a new service's tasks are skipped silently unless its own name tag is included. The two
  incantations and the reasoning: [deployment-ansible.md](docs/deployment-ansible.md) §Long converges run
  detached (HD-370 / HD-379).
  ```bash
  bash scripts/ansible-run.sh playbooks/<playbook>.yml --tags docker_services,<service-name> \
      </dev/null > /tmp/converge-"$(date +%s)".log 2>&1 &
  tail -f /tmp/converge-*.log        # poll until PLAY RECAP
  ```

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
siblings `../homelab-wt-*`. No second clone; the old `/mnt/d` drvfs path is retired. *(HD-263: the former `ansible-enhancements.md` §8.4 rationale for the ext4-primary/git-bootstrap move lives here in §0.1 + CONVENTIONS §6.)*

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

### 0.4b Windows-side GitHub SSH auth + commit signing `[MANUAL]` *(one-time)*

```powershell
bash scripts/git-bootstrap-win11.sh --ssh-auth      # idempotent
```

✔-evidence: `git ls-remote git@github.com:<owner>/homelab.git HEAD` succeeds over SSH, and a test
`git commit -S` is signed without a passphrase prompt.

The Windows desktop side differs from the WSL runner: the 1Password **desktop** app owns the GitHub keys
(`GitHub sign`, `GitHub auth`) over the Windows named-pipe agent, and signing resolves by the **public-key
string**, not a file path. Why each config line in the script is what it is — and the two failure modes
(`invalid ssh public key`, WSL networking wedges) — is in
[deployment-ansible.md](docs/deployment-ansible.md) §Windows/WSL runner host facts.

### 0.6 Seed the on-site control node (`oldsrv`, HD-407) `[MANUAL — one-time per box]`

Run this from the laptop. The two traps it exists to survive — a dual-stack runner prefers the VPS's
AAAA and every jumped leg then times out, and the Cloudflare token filters on the egress **address**,
not on "being home" — are written up with their measurements in
[deployment-ansible.md](docs/deployment-ansible.md) §Runner placement.

```bash
ssh ansible-admin@oldsrv 'git clone https://github.com/domenkogler/homelab ~/source/homelab'
#   (the read-only `github-homelab_deploy_api` token lives in a 0600 ~/.git-credentials on the box;
#    prove it is read-only: `git push` from oldsrv must 403. It did.)
op read "op://Homelab-ansible/op_api/credential" | \
  ssh ansible-admin@oldsrv 'cd ~/source/homelab && \
        bash scripts/bootstrap-runner.sh --no-upgrade --no-sudoers --token-stdin'
ssh ansible-admin@oldsrv 'cd ~/source/homelab && bash scripts/restore-runner-key.sh --force-throwaway'
ssh ansible-admin@oldsrv 'cd ~/source/homelab && bash scripts/seed-runner-ssh.sh'
ssh ansible-admin@oldsrv 'cd ~/source/homelab && bash scripts/ansible-run.sh playbooks/dns.yml --check'
#   Then one check per group, from the box:
ssh ansible-admin@oldsrv 'cd ~/source/homelab && for p in "home_servers.yml --limit oldsrv.kogler.si" \
        "vps.yml" "storage.yml --limit nas.kogler.si" "raspberry_pi.yml --limit pi.kogler.si" \
        "spark.yml --limit spark.kogler.si"; do bash scripts/ansible-run.sh playbooks/$p --check --tags common; done'
```

✔ `seed-runner-ssh.sh` prints `JUMP_OK`; every group ends `unreachable=0 failed=0` — the measured
per-group numbers and where their logs live are in
[deployment-ansible.md](docs/deployment-ansible.md) §Runner placement.
✔ `dns.yml` ends `ok=2 … failed=0`. A `9109` there means the token's IP allowlist is missing this box's
egress address — **v4 *or* v6** — and the `429 / 10502` that follows it is auth-failure throttling,
not the cause. Ask the owner to add the address, do not "fix" it by pointing the run at IPv4.
✖ `--tags docker_services` on the self host is expected RED while the runner sits on a `main` that
lacks the fix in question: a pull-only runner converges what is on main, never more.
✔ After any grant change: `python3 scripts/check_ssh_grants.py` (read-only gate over
[deployment-secrets.md](docs/deployment-secrets.md) §Who is authorized where; it revokes nothing).

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

## Phase 1 — Deploy the VPS service stack

> Everything below is a step the playbook does **not** perform: first-login wizards, panel settings and the
> manual swaps. As-built state and progress are not tracked here (ledger + owning docs).

### 1.1 Preconditions

- Phase 0 runner ready (`op` token readable; canonical key); Phase 0.5 VPS reachable as
  `ansible-admin@vps.kogler.si`.
- **Sync gate before EVERY run** (HD-212): whole-tree md5 compare Windows↔WSL must match.
- Vault coverage: `bash scripts/check-vault-items.sh` → seed gaps via
  `scripts/provision-vault.sh --create --yes` or manually. Placeholder-then-swap items a from-zero deploy
  still needs a human for: `forgejo_api` (minted in the UI, step 1.7) and the app keys listed as
  placeholder-then-swap in [deployment-secrets.md](docs/deployment-secrets.md) §Master Secret List. The catalog
  is the authority — do not hand-maintain a list here.

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

5. **Tearing down a service whose compose project still exists on the host is a manual step** — the role's
   teardown only removes projects marked `enabled: false`; a project whose files remain but that no converge
   owns is never touched. Form (worked example: the retired `dsh` / `pi-dev` harnesses):
   ```bash
   docker compose --project-directory /opt/dsh down --remove-orphans
   docker compose --project-directory /opt/pi-dev down --remove-orphans
   docker rm -f dsh dsh-tailscale pi-dev pi-dev-tailscale 2>/dev/null; true
   docker image prune -f   # or rmi the specific legacy tags
   sudo rm -rf /opt/dsh /opt/pi-dev
   ```

Verify from a tailnet device: `https://stats.kogler.si` (forward-auth → SSO) and
`https://stats.ts.kogler.si` (ACL-gated, tailnet-only).

### 1.4d Home tailnet node — `oldsrv` (HD-405)

`roles/tailscale-node` converges the node, but **nothing below is created by Ansible** — a from-scratch
rebuild fails loud without these, in this order:

1. **Declare the tag first.** `tag:dev` must exist in headscale `tagOwners` (rendered from
   `templates/docker_services/headscale/policy.hujson.j2`) **before** any key carries it — headscale refuses
   a tag no user may assign, and a rejected policy crash-loops the control plane.
2. **Mint the preauth key** on the VPS, scoped and expiring:
   ```bash
   docker exec headscale headscale preauthkeys create --user 2 --tags tag:dev --reusable --expiration 8760h -o json
   ```
   ⚠ headscale 0.29.3 emits the value under the JSON field **`key`**, NOT `secret` — a redaction filter keyed
   on `secret` prints the key. Extract the field explicitly; never widen a filter. Report ids/lengths/prefixes
   only, never the value (the leak that taught this: [docs/deployment-secrets.md](docs/deployment-secrets.md)).
3. **Seed the 1Password item** `tailscale-oldsrv_api` in `Homelab-ansible` (category API Credential, field
   `credential`) **from a template file**, so no value touches the command line, stdout or shell history:
   write a `0600` template under `/run`, `op item create --vault Homelab-ansible --category API_CREDENTIAL
   --template <file>` (service accounts require `--vault`), then `shred -u` the template. Verify by readback
   length only.
4. **Converge the node**, then read its assigned tailnet IPv4 from `headscale nodes list` and write it to
   `tailnet_oldsrv_ip` (`group_vars/all/main.yml`). Re-converge **headscale** (MagicDNS record for
   `ha.ts.kogler.si`) **and traefik-internal** (its `websecure-ts` listener binds exactly that address;
   empty renders no listener).
5. **Never enrol a home host interactively (OIDC).** A preauth-key node lands in headscale's synthetic
   `tagged-devices` user and is therefore reachable by *nobody* until an ACL names `tag:dev`; an interactive
   join lands it under the owner user and silently inherits `dst:domen:*` on every port.


### 1.4e Tailnet resolver chain — guarded headscale restart + the three-case drill (HD-415) `[MANUAL — owner present for the drill]`

> The tailnet `dns.nameservers` chain is **MagicDNS loop → the `oldsrv` node address → the VPS public**
> instance (SSOT `tailnet_oldsrv_ip` + `dns_primary_ip`; rationale in [network-dns.md](docs/network-dns.md)
> §The resolution requirement). The node entry only works together with the `udp:`-scoped `udp 53` rule in
> `templates/docker_services/headscale/policy.hujson.j2` — **neither half alone works**, and the nameserver
> entry without the ACL rule is *worse* than the old chain (queries fall into an ACL drop and the VPS
> fallback does not save them). Both halves render from the same `tailnet_oldsrv_ip` condition, so they
> cannot diverge.
> Landing either half is a headscale stop/start — every tailnet device reconnects — so it runs **only**
> behind the auto-re-enable net. Never restart headscale by hand here.

1. **Prove the auto-re-enable before the first stop** (the condition on the authorization; it costs one
   short control-plane blip — existing device sessions survive, netmap updates pause):
   ```bash
   bash scripts/guarded-converge.sh --action prove --target vps --container headscale
   # poll the printed /tmp/guarded-prove-headscale-*.log
   ```
   `prove` self-tests the watchdog, copies it to the target, arms it `setsid`+`nohup` **detached**, refuses
   to continue unless the arm is proven alive (`pgrep` + its own `armed:` log line), and only then
   `docker stop`s the container and waits. GREEN requires **both** a changed `StartedAt` **and** a
   `RE-ENABLING` line in `/tmp/headscale-watchdog.log` — a container that came back without that line
   proves nothing. ⛔ An older sequence that armed in one command and stopped in another was run live and
   left the control plane down for 2m20s after the arm silently failed: assert and act in the SAME run.
2. **Validate the candidate render with headscale's own parser, off-line.** Render the two templates to a
   scratch path (a one-off playbook using the same inventory context is enough), then run the pinned image
   against them — the container's rootfs is read-only and distroless, so `docker cp`/`docker exec sh` are
   both impossible; bind-mount instead:
   ```bash
   docker run --rm -v /tmp/render/config.yaml:/etc/headscale/config.yaml:ro \
       -v /tmp/render/policy.hujson:/etc/headscale/policy.hujson:ro \
       -v /tmp/scratch:/var/lib/headscale --entrypoint /ko-app/headscale \
       headscale/headscale:0.29.3 policy check --bypass-grpc-and-access-database-directly \
       -f /etc/headscale/policy.hujson
   ```
   Expect `Policy is valid`. Prove the check is not vacuous by re-running it on a copy with `"proto": "udp"`
   changed to a garbage protocol — that MUST fail with a `parsing policy` error naming `/acls/<n>/proto`.
   ⚠ `headscale configtest` does **not** validate `dns.nameservers` values (measured: a garbage address
   passes it silently), so its silence is not evidence about the DNS list.
3. **Converge behind the net** — one scoped run, both tag classes (the inner per-service tasks are tagged
   with the service name; `docker_services` alone is a silent no-op), scope to skip the unrelated lanes:
   ```bash
   bash scripts/guarded-converge.sh --action converge --target vps --container headscale \
        --project /opt/headscale --playbook playbooks/vps.yml --limit vps \
        --tags docker_services,headscale --extra "-e docker_services_scope=headscale"
   # poll the printed log → `RESULT: GREEN — headscale is running ... and the watchdog is disarmed`
   ```
   One restart is expected (the restart-on-config-change step); it bounces the `headscale` compose project,
   i.e. `headscale` **and** `headplane`. The wrapper's trap re-runs `compose up -d` on any exit and the
   watchdog stands down only after the post-state is verified.
4. **Verify the artefacts, not the recap:**
   ```bash
   ssh vps 'sed -n "/nameservers:/,/^  # /p" /opt/headscale/config.yaml | grep -v "^ *#"'   # loop, node, VPS public — no LAN IPs
   ssh vps 'tail -8 /opt/headscale/policy.hujson'                    # proto udp, dst <tailnet_oldsrv_ip>/32:53
   ssh vps 'docker ps --filter name=head --format "{{.Names}} {{.Status}}"; \
            docker exec headscale headscale nodes list | grep -c online'
   ```
5. **Prove the resolver path over the tailnet** (from any node of the owner's user — the ACL is scoped to
   that user, so a tagged node cannot run this test):
   ```bash
   dig +time=3 +tries=1 +short @<tailnet_oldsrv_ip> media.kogler.si A      # the home-hosted answer
   dig +time=3 +tries=1 +tcp  @<tailnet_oldsrv_ip> media.kogler.si A       # MUST fail — the grant is udp-only
   sudo nft list chain ip filter ts-forward                                 # on oldsrv
   ```
   The query arrives on `tailscale0`, is DNATed to the Technitium container and the reply leaves on
   `tailscale0`: expect the `ts-forward` *mark-accept* and *oif accept* counters to move together while the
   tailscale's anti-loop drop (`ip saddr <the tailnet range> oifname tailscale0 drop`) counter **stays at 0** (the container reply is still
   source-NATed-to-the-container at the FORWARD hook, so tailscale's anti-loop drop never sees the tailnet
   source — that is what makes a published container reachable from a tailnet address at all).
6. **The three-case drill — the row's acceptance, owner present.** Pick a home-hosted name that is NOT a
   MagicDNS `extra_record` (`media.kogler.si` / `seerr.kogler.si`): the `extra_records` set answers
   client-side and would pass without testing anything. Read the answer, not just the page:
   `ERR_NAME_NOT_RESOLVED` = resolver path broken (an HD-415 failure); connected-but-timed-out/refused = DNS
   worked and reachability is the separate, pre-existing property that the internal zone returns a **LAN**
   address, which no away device can route to.
   - **(a) On the LAN** — phone on home Wi-Fi, Tailscale *off*: the name resolves from the DHCP resolver
     (unchanged path, sanity baseline), then **Tailscale on**: it still resolves.
   - **(b) Away** — phone on cellular, Wi-Fi off, Tailscale connected: the app's DNS view lists
     `100.100.100.100`, `<tailnet_oldsrv_ip>`, `<dns_primary_ip>` and reports no `DNS unavailable`, and the
     name resolves (to the home LAN address — see the caveat above).
   - **(c) At home, home WAN pulled** *(the load-bearing case)* — pull the WAN at the edge, then on the
     phone: Tailscale still connected (it runs on its cached netmap while the control plane is unreachable —
     expect the app to warn, that is not the failure), then ping `oldsrv`'s tailnet address from the app and
     require a **direct/local** path, then resolve the name. Instrument the same case from a laptop at home
     (`tailscale ping <tailnet_oldsrv_ip>`, then the `dig` of step 5) — but do not call the case proven on
     the laptop alone.
   Restore the WAN and re-check (b). A failure in (c) is not a config bug to guess at: it means the
   direct-over-LAN leg is missing and the resolver design needs the router leg written in
   [network-dns.md](docs/network-dns.md) §The resolution requirement.


### 1.4c Technitium primary admin bootstrap + seed (VPS, HD-324)

A from-scratch VPS deploy starts Technitium with a **default `admin` user whose password is
`admin`** (the app seeds it on first boot — the container regens `auth.config`/`cache.bin`
from the image, so deleting them does NOT reset it; that's why the seed role's "empty
auth.config → bootstrap" premise only works on a truly-fresh instance). To make the
`technitium-seed` role (which logs in with the 1P `technitium_login` item) succeed, set the
admin to the 1P value via the documented API:

```bash
# on the VPS (creds never leave it):
CTR_IP=$(docker inspect technitium --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' | awk '{print $1}')
TOK=$(curl -sS -X POST "http://$CTR_IP:5380/api/user/login" --data-urlencode 'user=admin' --data-urlencode 'pass=admin' | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
curl -sS -X POST "http://$CTR_IP:5380/api/user/changePassword" \
  -H "Authorization: Bearer $TOK" \
  --data-urlencode 'pass=admin' --data-urlencode 'newPass=<1P technitium_login password>'
```

Then run the seed converge:

```bash
bash scripts/ansible-run.sh playbooks/vps.yml -l vps -t docker_services -e docker_services_scope=technitium
```

The seed creates the `kogler.si` zone + the split-horizon A records (`ha`/`dns-pi` → VIP,
dashboards → `tailnet_sidecar_ip`). Verify: `dig @159.195.111.66 {ha,dns-pi,stats,logs,csui,sec,traefik,auto}.kogler.si`
all answer. The **default `admin`/`admin` is retired after this** (verify it FAILS). A redeployer
must also remember the `dns` router needs `traefik.http.services.dns.loadbalancer.server.port="5380"`
(else the post-SSO leg 502s — Traefik auto-picks port 53).

**Pi tertiary — same admin-align + seed.** The container is named `technitium-pi` (not `technitium`) and sits on
two networks, so target it by that name and take the **first** IP:

```bash
# on the Pi (creds never leave it):
CTR_IP=$(sudo docker inspect technitium-pi --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}\n{{end}}' | awk 'NR==1{print $1}')
TOK=$(curl -sS -X POST "http://$CTR_IP:5380/api/user/login" --data-urlencode 'user=admin' --data-urlencode 'pass=admin' | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
curl -sS -X POST "http://$CTR_IP:5380/api/user/changePassword" -H "Authorization: Bearer $TOK" --data-urlencode 'pass=admin' --data-urlencode 'newPass=<1P technitium_login password>'
```

Then the Pi seed converge (idempotent):

```bash
bash scripts/ansible-run.sh playbooks/raspberry_pi.yml -e docker_services_scope=technitium-secondary
```

Verify: `dig @<Pi Home IP per SSOT> ha.kogler.si` → VIP and `dns-pi.kogler.si` → VIP, and
`curl -s -o /dev/null -w '%{http_code}' http://<pi>:5380` → 200 (the publish is IaC-managed).

**oldsrv secondary — same admin-align + seed.** The container is `technitium-oldsrv` (instance `secondary`) and
is **not published on 5380** — the API answers only on its overlay IPs. It also has no `curl`/`python`, and host
`curl` mis-reads Technitium's chunked responses, so copy a bash `/dev/tcp` HTTP helper into the container:

```bash
# on oldsrv — copy a bash /dev/tcp HTTP client into the container first
# (GET/POST + Content-Length + chunked body decode; no curl dependency):
cat > /tmp/tech_login.sh <<'OUTER'
#!/bin/bash
host=127.0.0.1; port=5380; method=$1; path=$2; body="$3"
[ -n "$body" ] && clen=$(printf '%s' "$body" | wc -c) || clen=0
req="$method $path HTTP/1.1\r\nHost: $host\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: $clen\r\nConnection: close\r\n\r\n$body"
exec 3<>/dev/tcp/$host/$port; printf '%b' "$req" >&3
out=$(timeout 5 cat <&3 2>/dev/null)
printf '%s' "$out" | sed -n '/^\r\{0,1\}$/,$p' | tail -n +2 | perl -0777 -ne '$b=$_; $b =~ s/^[0-9a-fA-F]+\r?\n//mg if $b =~ /^[0-9a-fA-F]+\r?\n/; print $b'
OUTER
docker cp /tmp/tech_login.sh technitium-oldsrv:/tech_login.sh
# login as the DEFAULT admin/admin (still bootstrapped on a fresh /etc/dns) -> token
TOK=$(docker exec technitium-oldsrv bash /tech_login.sh POST "/api/user/login" "user=admin&pass=admin" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
# set the admin to the 1P technitium_login value (creds never leave oldsrv)
docker exec technitium-oldsrv bash /tech_login.sh POST "/api/user/changePassword?token=$TOK" "pass=admin&newPass=<1P technitium_login password>"
```

Then the oldsrv seed converge (idempotent):

```bash
bash scripts/ansible-run.sh playbooks/home_servers.yml -e docker_services_scope=technitium
```

Verify: `dig @127.0.0.1 {ha,dns-pi,stats,logs,csui,sec,traefik,auto,vps,home,vpn,dns,sso,file,foto,git,bin,ai,office,pdf,chat,matrix,drop}.kogler.si` on oldsrv all answer (ha/dns-pi → VIP, dashboards → `tailnet_sidecar_ip`, public → VPS public IP). The default `admin`/`admin` is retired after this. **Container-IP reach caveat:** if the seed's `_tech_api` connect fails with "No route to host", check for **orphaned duplicate-subnet docker bridges** (stale `br-*` from a docker recreate that steal the kernel route — `docker network ls` IDs won't match `ip link` bridge IDs); `sudo ip link del br-<orphan>` restores host→container routing.

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

**TLS:** the server boot generates a persisted self-signed
`tls.crt`/`tls.key` under the config bind (one-time) and serves **HTTPS** on :51515 — the oldsrv
agent rejects plain-http. The container writes `tls-sha256` (the trust-anchor fingerprint); the
`kopia-fingerprint-sync.yml` docker_services task seeds it into 1Password
(`kopia-server_fingerprint`) and the agent pins it. On a **fresh volume** all of this happens
automatically on first start — no manual step; if you ever need to fingerprint-check:
`sudo cat /srv/docker/kopia-server/config/tls-sha256`.

**Client auth — created automatically by the boot script; verify only:**
kopia's server-auth model needs the backup client's identity (`oldsrv-agent@oldsrv.kogler.si`) to
exist BOTH in the htpasswd (`--htpasswd-file` = allowed `user@hostname` entries; the boot script
writes the server-admin entry + `kopia_agent_user`) AND as a repo user (`kopia server users add`)
whose password equals the **REPO MASTER password** (`kopia_password` — a non-repo-password user is
`access denied` at the session stage even with a matching htpasswd entry.
The boot script provisions/re-seeds the repo user idempotently (add → set fallback). If the agent
reports `access denied for oldsrv-agent@oldsrv.kogler.si`:
```bash
sudo docker exec kopia-server kopia server users add oldsrv-agent@oldsrv.kogler.si \
  --user-password="$(sudo docker exec kopia-server printenv KOPIA_PASSWORD)"
sudo docker restart kopia-server
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

### 1.11 RustDesk server — hbbs + hbbr (HD-412, VPS) `[MANUAL + Ansible]`

> Procedure only. Placement, exposure, the consent rules for the family desktops and the bandwidth
> arithmetic: [services-admin.md](docs/services-admin.md) §RustDesk. The service ships
> `enabled: false` because its compose is fail-closed on the `rustdesk_login` item — the item and the
> flag flip are ONE change, in the order below.

1. **Mint the keypair — never to session stdout.** Read the tag from the pin (never type it); the runner
   has no Docker, so the binary runs on the VPS and only stdout comes back:
   ```bash
   umask 077
   KEYDIR=$(mktemp -d); chmod 700 "$KEYDIR"
   RV=$(awk -F'"' '/^rustdesk_server_version:/{print $2}' IaC/ansible/group_vars/all/versions.yml)
   ssh vps "sudo docker run --rm --entrypoint /usr/bin/rustdesk-utils \
     rustdesk/rustdesk-server-s6:${RV} genkeypair" > "$KEYDIR/kp"      # 44 / 88 base64 chars
   ```
2. **Seed `rustdesk_login`** — manual-value path, `username` = the `Public Key:` half, `password` = the
   `Secret Key:` half. Write it by the CLI round-trip in
   [deployment-secrets.md](docs/deployment-secrets.md) §Creation & Rotation Workflow item 7 (bare create,
   then fill the built-in fields by JSON round-trip; a `fields` template appends empty duplicates, and an
   assignment argument leaks the value into `argv`). If the item already exists, stop — replacing it
   behind a running server changes nothing and rotating it orphans every enrolled client (step 9).
3. **Verify length and field shape, then destroy the plaintext** — an empty length or a duplicated field
   id means the write landed on the wrong field, and the render would silently carry empty keys:
   ```bash
   op read "op://Homelab-ansible/rustdesk_login/username" | tr -d '\n' | wc -c   # 44
   op read "op://Homelab-ansible/rustdesk_login/password" | tr -d '\n' | wc -c   # 88
   op item get rustdesk_login --vault Homelab-ansible --format json | python3 -c \
     'import json,sys; print(sorted((f["id"], len(f.get("value") or "")) for f in json.load(sys.stdin)["fields"]))'
   shred -u "$KEYDIR"/* && rmdir "$KEYDIR"
   ```
4. **Create the data dir before the first start** — it holds the private key, and Docker would otherwise
   auto-create it world-traversable:
   ```bash
   ssh vps 'sudo install -d -o root -g root -m 0700 /srv/docker/rustdesk-server/data'
   ```
5. **Flip the registry row** `rustdesk-server` → `enabled: true` in `IaC/ansible/group_vars/vps.yml`
   (same commit as the seed), then `bash scripts/check-vault-items.sh` — note that script cannot see
   this item (it greps literal `onepassword', 'NAME'`; the template uses the HD-258 `vault['…']` dict),
   so a clean report here does **not** prove the item exists. Step 3 does.
6. **Apply — first apply is human-gated** (CONVENTIONS §5 step 9). Dry-run first, **never with
   `--diff`** (the rendered compose carries the keypair — [scripts/README.md](scripts/README.md)
   Notes), then the real run **detached** (HD-370), with BOTH tag classes (`docker_services` alone
   tag-filters every inner task of the service):
   ```bash
   bash scripts/ansible-run.sh playbooks/vps.yml --limit vps \
        --tags hardening,docker_services,rustdesk-server --check
   nohup bash scripts/ansible-run.sh playbooks/vps.yml --limit vps \
        --tags hardening,docker_services,rustdesk-server \
        > /tmp/converge-vps-rustdesk-$(date +%Y%m%d-%H%M).log 2>&1 &
   # poll: tail -f /tmp/converge-vps-rustdesk-*.log → PLAY RECAP failed=0
   ```
   `hardening` is in the same run because the nftables input allow is what makes the service reachable
   at all (host networking = no docker DNAT, so the input chain is the entire gate).
7. **Verify** (all of it, or the row is not done):
   ```bash
   ssh vps 'docker ps --filter name=rustdesk-server --format "{{.Status}}"'   # Up (healthy) — the image's
   #   own HEALTHCHECK supervises both binaries; a bare `Up` with `unhealthy` = one of them is dead
   ssh vps 'docker logs rustdesk-server 2>&1 | grep -E "BANDWIDTH|LIMIT_SPEED|DOWNGRADE"'
   #   → TOTAL_BANDWIDTH: 48Mb/s · SINGLE_BANDWIDTH: 24Mb/s · LIMIT_SPEED: 8Mb/s
   #   (hbbr logs its EFFECTIVE caps at start-up; this is the only proof the caps took effect)
   ssh vps 'ls -l /srv/docker/rustdesk-server/data'   # id_ed25519 + .pub present, both 0600 root:root
   ssh vps 'nft list chain inet filter input | grep 2111'
   nc -zv -w3 <vps-public-ip> 21117 && echo relay-open
   nc -zv -w3 <vps-public-ip> 21118 || echo webclient-closed   # MUST be refused
   ```
8. **Prove the two sessions** (the row's acceptance, both need a human present):
   - **Relay path:** from a phone on mobile data, connect to a family machine enrolled per
     [services-admin.md](docs/services-admin.md) §Path B, and complete a session.
   - **Direct path with the relay uninvolved:** connect to a tailnet member by its tailnet address, and
     while the session is live read the relay's session list — it must be empty:
     `ssh vps "printf 'ls' | nc -q1 127.0.0.1 21117"`
   - Read the running totals afterwards: `ssh vps "printf 'tb' | nc -q1 127.0.0.1 21117"`.
9. **Restore** (only if /data is lost): the 1P item is the restore — wipe the data dir, re-run step 6,
   and the pair is re-seeded so enrolled clients keep working. Replacing the item instead (a rotation)
   is the one path that **orphans every client**: re-enrolment is manual, per machine
   ([deployment-secrets.md](docs/deployment-secrets.md) `rustdesk_login`).

### 1.12 Retire an unowned VPS stack (HD-394) `[MANUAL — owner OK required]`

> Applies to any live compose project that `group_vars/vps.yml` no longer describes (found by the census
> in [services-vps.md](docs/services-vps.md) §Container census). The registry cannot remove what it does not
> name, and `docker rm` alone leaves the bind dir and the rendered `/opt/<name>/` behind — so retirement
> is a recorded sequence, not a cleanup command. Removal requires an explicit owner OK (the row's gate).

1. **Re-run the census** so the removal decision is made against live state, not against the table:
   ```bash
   ssh vps 'docker ps -a --format "{{.Names}}|{{.Status}}|P={{.Label \"com.docker.compose.project\"}}"' | sort
   comm -13 <(awk -F'name: ' '/- \{ name:/{split($2,a,","); gsub(/[ ,]/,"",a[1]); print a[1]}' \
              IaC/ansible/group_vars/vps.yml | sort -u) \
            <(ssh vps 'docker ps -a --format "{{.Label \"com.docker.compose.project\"}}"' | sed '/^$/d' | sort -u)
   ```
2. **Prove the stack is empty and unconnected** (this is the whole safety argument — do it per stack
   and record the numbers, not a conclusion; script-file indirection, never inline quoting through ssh).
   For a Postgres-backed stack:
   ```bash
   cat > /tmp/retire-probe.sh <<'SH'
   set -u
   docker exec <svc> sh -c 'psql -U "$POSTGRES_USER" -Atc "select extname from pg_extension"'
   docker exec <svc> sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from information_schema.tables where table_schema not in ('"'"'pg_catalog'"'"','"'"'information_schema'"'"')"'
   docker exec <svc> sh -c 'psql -U "$POSTGRES_USER" -Atc "select usename,client_addr,state from pg_stat_activity where datname is not null"'
   grep -rl <svc> /opt/*/docker-compose.yml      # consumers: none (exclude the stack itself)
   SH
   ssh vps 'bash -s' < /tmp/retire-probe.sh
   grep -rn <svc> IaC/ansible/                   # and none in the registry/templates
   ```
   Empty + zero external connections ⇒ no restore obligation, which is what makes step 4 safe.
3. **Inventory the anonymous-volume residue without deleting anything** (231 dangling volumes are
   provenance-free; `docker volume prune` is irreversible, so it is a decision, not a step):
   ```bash
   ssh vps 'docker volume ls --format "{{.Name}}|{{.Label \"com.docker.compose.project\"}}" | awk -F"|" "$2==\"\"" | wc -l'
   ssh vps 'sudo du -sh /var/lib/docker/volumes/*/ _data 2>/dev/null | sort -h | tail -20'
   ```
   Act on it only with an owner verdict naming the volumes; the default outcome is `docker volume rm`
   of specific IDs, never `prune --all`.
4. **Take the stack down in registry order** — stop, then remove the container, then the render, then
   the data (this order keeps every step reversible until the last one):
   ```bash
   ssh vps 'cd /opt/<svc> && sudo docker compose stop && sudo docker compose down --remove-orphans'
   ssh vps 'sudo docker image rm <image:pin>'            # only if no other container uses the pin
   ssh vps 'sudo mv /opt/<svc> /opt/.retired-<svc>'      # move aside, do not delete, until the next converge is green
   ssh vps 'sudo mv /srv/docker/<svc> /srv/docker/.retired-<svc>'
   ```
5. **Prove nothing else depended on it** — converge the host and require the same roster as before
   minus the retired stack, with no container restarting:
   ```bash
   bash scripts/ansible-run.sh playbooks/vps.yml --limit vps --tags docker_services --check   # never --diff
   nohup bash scripts/ansible-run.sh playbooks/vps.yml --limit vps --tags docker_services \
        > /tmp/converge-vps-$(date +%Y%m%d-%H%M).log 2>&1 &
   ssh vps 'docker ps --format "{{.Names}}\t{{.Status}}" | sort'   # compare with the step-1 census
   ```
6. **Delete the moved-aside dirs only after step 5 is green**, and record the retirement in
   [services-rejected.md](docs/services-rejected.md) / the owning doc so the next census finds nothing
   unexplained. A stack that is removed but not written down reappears as a mystery bind dir.
7. **Do not retire these** (they look unowned and are not): `/opt/metabase` (registry entry exists,
   `enabled: false` — a flip re-renders it), and any container whose project name IS an enabled
   registry entry but whose `/opt` dir you cannot find (the render lives where the template says).

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

> **Destructive — wipefs and each pool-create block need explicit human approval.** The data-migration leg is
> **not** part of a redeploy (it is a one-time event; see the ledger Phase 2 notes). Device by-id paths and disk
> inventory: [hardware-nas.md](docs/hardware-nas.md). Pools are created EMPTY here; the
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
  per-AP so the identity is `ap-spalnica`/`ap-dnevna`/`ap-spare`) + the 2 pubkeys
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

**Run DIRECT against the device Mgmt IPs.** The laptop reaches the Mgmt-99 plane through the Windows
Mgmt99 vNIC (`wsl-nat-resolv.ps1 -EnableMgmt99`), so `ansible-run.sh` connects straight to the device
mgmt address that `network.yml` derives — no firewall surface, no hop:

```bash
# from the session worktree (NOT the primary checkout):
bash scripts/ansible-run.sh playbooks/router.yml --check --diff     # dry-run first
bash scripts/ansible-run.sh playbooks/switch.yml --check --diff
bash scripts/ansible-run.sh playbooks/router.yml                    # real
bash scripts/ansible-run.sh playbooks/switch.yml
```

> `scripts/ansible-network-hop.sh` (Pi-99 ProxyJump wrapper) is **obsolete** — it belongs to the era when the
> runner sat on VLAN 10 and the Pi was the only Mgmt client. It still exists as a fallback if the Mgmt99 vNIC
> path is unavailable; do not use it by default.

**Manual mgmt from the laptop — `~/.ssh/config` aliases (direct `.99`):** the laptop reaches the
Mgmt plane **directly** via the Windows Mgmt99 vNIC (`wsl-nat-resolv.ps1 -EnableMgmt99`) — **no ProxyJump `pi`
hop needed anymore.** Preconfigured aliases (single `id_ed25519`/`ansible-admin_ssh.pub`, direct):

```bash
# verify (RouterOS answers `:put`):
ssh router '':put OK''            # RB4011 .99.1
ssh switch '':put OK''            # CRS328 .99.2
ssh oldsrv99 echo OK              # .99.30 on-site leg (`ssh oldsrv` = the Home leg + jump)
ssh pi99 echo OK                  # Pi Mgmt .99.20 (pi = Home .1.20; the one dual-leg exception)
# WinBox: point at the device Mgmt IP directly — see .99.x in network-addresses-generated.md
#   WinBox Address=<switch .99>  (CRS328)  | <ap-dnevna .99>  etc.
# alias list = docs/network-vpn.md §The laptop alias contract (the SSOT for BOTH ~/.ssh/config files)
# .99.x IPs = network-addresses-generated.md SSOT; alias list = network-vpn.md §The laptop alias contract.
```

> The aliases keep Windows ON tagged-99 via the Mgmt99 vNIC — direct. `nas` (Home .1.10) may report
> 'No route to host' until Phase 2; `ap-spare` is a spare (offline until powered).



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

Baked into the templates — do not undo these: (a) **quote EVERY non-literal value** — the WG
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
> The `apply-converge.yml` playbook (Ansible path) SCP-uploads + verifies the key (`ssh-keygen -y` load-verify, HD-309) but its final API `/import` step needs `librouteros` in the runner interpreter — if that is missing, use the SSH-import path above (`routeros-apply-delta.sh`). ⛔ Note on that playbook's upload step: it uses `ansible.builtin.copy`, which fails on RouterOS's pseudo-filesystem (see [network-ops.md](docs/network-ops.md) §Apply workflow — "Destination / not writable"); `routeros-apply-delta.sh` takes **any** `.rsc` filename, including `rb4011_converge.rsc` itself, and is the transport that works for a full converge too.

> **1.5.3d Scoped IPv6 (Home VLAN) — enable / verify / roll back.** Design, rule order and invariants:
> [network-vlans.md](docs/network-vlans.md) §IPv6. Measured RouterOS behaviour, the outside-in probe and why
> certain hosts cannot run it: [network-ops.md](docs/network-ops.md) §IPv6. The converge's IPv6 section carries
> it, so a normal converge installs it; this is the standalone procedure for proving it or reversing it.
>
> ```bash
> # 0) Does the ISP delegate a prefix at all? A dhcp-client is the only reliable probe — an empty `available=`
> #    after ~30 s means the network offers nothing. This is the same object the converge owns, so either let
> #    the converge create it or remove the probe row afterward; never leave a half-configured client behind.
> ssh <router> '/ipv6 dhcp-client add interface=pppoe-telekom request=prefix+address pool-name=pd-wan6'
> sleep 30; ssh <router> '/ipv6 dhcp-client print detail'     # want: PD_PREFIX=<delegated prefix> + bound
>
> # 1) Render, then apply. Keep the section's internal order = dhcp-client -> filter -> address:
> #    `from-pool=` resolves only once the pool has bound, and the RA must never precede the filter.
> bash scripts/ansible-run.sh playbooks/render-converge.yml
> bash scripts/routeros-apply-delta.sh <router> rb4011_converge.rsc
>
> # 2) Device state
> ssh <router> '/ipv6 address print'                  # exactly ONE ADV=yes row: <prefix>::1/64 on vlan10-home
> ssh <router> '/ipv6 nd print'                       # vlan10-home ENABLED, advertise-dns=no, M=O=0
> ssh <router> '/ipv6 nd prefix print'                # ONE DYNAMIC row, same prefix (made by advertise=yes)
> ssh <router> '/ipv6 firewall filter print stats'    # drop rules carry bytes; the RA/DHCPv6 accepts carry traffic
> ssh <router> '/ipv6 route print'                    # the router's own default via the ISP's RA
>
> # 3) On a Home client: SLAAC took a GUA, v6 egress works, the RA installed a default
> ip -6 addr show dev <iface> | grep -E 'scope global'
> curl -6 -sS --max-time 8 https://api64.ipify.org
> curl -sS  -o /dev/null -w 'v4 still fine: %{http_code}\n' --max-time 8 https://api.ipify.org
>
> # 4) Roll back (no host-side cleanup; ra-lifetime=30m ages advertised addresses out by itself)
> ssh <router> '/ipv6 nd set [find where interface=vlan10-home] disabled=yes'
> ssh <router> '/ipv6 address remove [find where comment~"^HD-414"]'
> ```
>
> ⚠ **Rule order is the safety property here, not a style point.** The v6 filter is first-match-wins, so every
> accept (stateful, ICMPv6 types 1/2/3/4, RS/RA/NS/NA 133–136, DHCPv6 546) sits **above**
> `chain=input action=drop in-interface=pppoe-telekom`, and likewise in `forward`. An accept placed below the
> drop is never evaluated — and the failure is silent in the bad direction: a probe sees "nothing answered" and
> reads it as "the filter works".
>
> ⛔ The device-side checks above do **not** prove the inbound posture. That needs a probe from a host with
> working IPv6 outside the home network; run it per [network-ops.md](docs/network-ops.md) §IPv6 (scratch listener
> on the target, a `dst-port`-scoped temporary accept **above** the drop, check the rule's byte counters, remove
> the scratch rule in the same sitting).

✔-evidence on the RB4011:

```text
/interface wifi configuration print        ; expect the ENABLED cfg-kogler* rows (currently 2: cfg-kogler + cfg-kogler-iot)
/interface wifi capsman print              ; 'enabled: yes' (was the missing piece — APs never provisioned)
/interface wifi security print             ; expect sec-kogler* profiles (currently 2)
/interface wifi registration-table print   ; clients appear per SSID as they re-join
/interface wifi provisioning print         ; dynamic CAP entries created for each AP
```

> The **why** of every object this import creates — manager enablement, the `DP_AC` datapath workaround, radio
> CAP mode, the band-split SSID set, the switch tagged-VLAN requirement and the slave-SSID re-pull trick — is
> the steady-state contract in [network-ops.md](docs/network-ops.md) §CAPsMAN steady-state contract. Read it
> before changing anything here; each rule exists because the live network broke without it.

Devices must re-join the right SSID (Kogler → VLAN 10 / Kogler IOT → VLAN 20 / Kogler guest → VLAN
30) to land on their VLAN.

### 1.5.5 Bring up the WG S2S tunnel (HD-91 / HD-285 two-key fix)

Each side holds a **DISTINCT** keypair: router = `wg_password` (pub `wg_s2s_router_public_key`), VPS =
`wg_password_vps` (pub `wg_s2s_vps_public_key`); each side's peer is the **other** side's pubkey. Design and
failure mode: [network-vpn.md](docs/network-vpn.md) §HD-285.

**Endpoints are DDNS, never literal IPs:** VPS→router `wg_s2s_vps.endpoint: s.kogler.si` (DDNS token, tracked in
`cloudflare_dns/vars/main.yml`); router→VPS `wireguard_s2s_vps.remote_endpoint: vps.kogler.si` (Cloudflare A).

**Bring-up (from a session worktree, venv interpreter):**

```bash
# VPS side — wireguard role (distinct key + peer + the oneshot owns the iface):
bash scripts/ansible-run.sh playbooks/vps.yml --tags wireguard
#   the wg-ensure-s2s-peer oneshot: create-if-missing iface → address → key (wg setconf key-only) → peer (wg set) → verify.

# Router side — router role (own key from wg_password, peer = VPS key, endpoint = vps.kogler.si):
bash scripts/ansible-network-hop.sh router playbooks/router.yml
```

**Post-converge manual fixes the role does NOT hold** (verify these on the device after every converge):

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

> **Why the oneshot owns the interface:** systemd 257 networkd applies the `.netdev` `[WireGuard] PrivateKey`
> but **never applies `[WireGuardPeer]`**, and strips any userspace `wg set peer` while it owns the iface. So
> networkd is reduced to **create-only** (minimal `.netdev` + `Unmanaged=yes` `.network`) and the
> `wg-ensure-s2s-peer` oneshot OWNS wg-s2s (create-if-missing →
> address from `wg_s2s_vps.local_ip` → key via `wg setconf` KEY-ONLY → peer via `wg set … peer` →
> verify key + peer present, exit non-zero on missing). The `wg-s2s.conf` carries the VPS key (0640).

**Authoring pitfalls (do not relearn):** ① Jinja `trim_blocks` eats a newline after `{% endfor %}` → use an explicit `{{ '\n' }}`. ② `.netdev` 0640 (`0600`+ACL → networkd `Permission denied`). ③ `[WireGuardPeer]` in `.network` is ignored. ④ Never put the `PrivateKey` in a **peer-only** `wg setconf` for the router side — the two-key role handles it.

### 1.5.6 Cutover finalisation

- `validate-all.sh` green from the worktree.
- Tick the matching boxes in the ledger's Phase 1.5 block and record the evidence there (device names,
  timestamps, lease/wireguard prints) — never here. Secrets by 1P item+field name only.
- Close the work item in [todo.md](todo.md) once the §1.5.5 handshake holds in both directions.
- Commit signed on the session branch; merge to main; remove the worktree.

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

> **If a client NFS automount errors `Stale file handle`** (often after an export change):
> ```sh
> # on nas: re-apply exports as root and confirm the target is exported
> sudo /usr/sbin/exportfs -ra
> sudo /usr/sbin/exportfs -v        # target share must be listed
> # on the client (e.g. oldsrv): clear the stale handle, then re-trigger the mount
> sudo umount /mnt/<share>
> ls /mnt/<share>                   # re-mounts cleanly once the export is live
> ```
6. **Samba — passdb switch (HD-132/HD-360):** Samba auth is driven by `storage_samba_passdb`
   in the storage role (default `tdbsam` = local accounts; `ldapsam` = Authentik-as-LDAP, D7).
   **Do NOT flip to `ldapsam` before the Authentik side is live** — smbd fails HARD on startup
   (`pdb_init_ldapsam: NT_STATUS_CANT_ACCESS_DOMAIN_INFO`) if the outpost is unreachable
   — a tree connect fails on every share if it is set). To enable LDAP (HD-360):
   ```bash
   # 1. Authentik (VPS): add the LDAP provider + outpost + svc_samba service user/group
   #    to the ks-oidc.yml Blueprint, then apply:
   bash scripts/ansible-run.sh playbooks/authentik-blueprints.yml
   # 2. Mint a FRESH outpost token → 1Password `authentik-ldap_bind` (field=password). A stale token
   #    renders the outpost unhealthy and every bind fails — always re-mint, never reuse.
   # 3. Redeploy the ldap outpost with the new token:
   bash scripts/ansible-run.sh playbooks/vps.yml --limit vps   # (or docker compose up -d authentik-ldap on vps)
   # 4. Flip the var + converge nas:
   #    host_vars/nas.kogler.si.yml: storage_samba_passdb: ldapsam
   bash scripts/ansible-run.sh playbooks/storage.yml --limit nas
   # 5. Live-verify: mount \\nas\media with an Authentik (family) account.
   ```
   Default at deploy: `storage_samba_passdb: tdbsam` (works with the IdP offline), with
   `vfs objects = acl_xattr`. LDAP mode = `ldapsam`, gated on HD-360 — **do not flip it before the
   outpost is live**, smbd fails hard on an unreachable outpost.

---

## Phase 3 — oldsrv first-boot follow-ups (music pillar, embed fallback)

Authoring spec: [docs/services-media.md](docs/services-media.md) §Music Pillar ·
[docs/services-downloads.md](docs/services-downloads.md) §VPN & Ingress ·
[docs/deployment-secrets.md](docs/deployment-secrets.md) (new catalog rows).
All of this runs on **oldsrv** only; streaming stays on the VPS (Navidrome, HD-354).

### P3.1 Owner seeds the new 1Password items `[MANUAL]` (blocking — the render fails without them)

| Item | Kind | Notes |
|---|---|---|
| `slskd_login` | Login | Soulseek network username/password (owner-supplied) |
| `soulseek_api` | API Credential | slskd web-UI/API token (generate via `scripts/`; optional but recommended) |
| `lastfm_login` | Login | Last.fm username + API key (`username`+`credential`), owner-created |
| `metabrainz_login` | Login | ListenBrainz token (`username`+`credential`), owner-created |
| `tube-archivist_login` | Login | Tube Archivist web-UI login (`username`+`credential`) |
| `tube-archivist_ui` | API Credential | Tube Archivist UI/API token — OPTIONAL (only if the Jellyfin plugin is used later) |
| `tube-archivist-es` | API Credential | **ES `elastic` bootstrap password** (ELASTIC_PASSWORD on app + archivist-es) — catalog-generated; required by the TA env-check |
| `lidarr-url-dl_login` | Login | **Lidarr-YouTube-Downloader** web-UI login (`username`+`credential`) — entered in its Settings page at first run |
| `lidarr_api` | API Credential | **Lidarr instance key** — read from the live Lidarr `config.xml` after first
  boot, or generate + set via `scripts/` (see [scripts/README.md](scripts/README.md) — the same
  manual-value class as `sonarr_api`/`radarr_api`; NOT auto-rotatable). Used by Aurral AND lidarr-ydl |

Run `bash scripts/check-vault-items.sh --strict` before converging — it lists exactly what's missing.

Pre-create the Tube Archivist archive dir on the NAS (the compose bind-mounts it and the export root is
root-squashed, so the container cannot mkdir it):
```bash
ssh nas "sudo mkdir -p /bulk/media/tube && sudo chown 1005:1005 /bulk/media/tube"
```

### P3.2 Converge oldsrv (registry rows already in `group_vars/home_servers.yml`)

```bash
bash scripts/ansible-run.sh playbooks/home_servers.yml --tags docker_services
```

This deploys `aurral`, `slskd` (+ its `gluetun-slskd` sidecar), `lidarr-ydl` (+ its `bgutil-provider`
sidecar) and `tube-archivist` (+ `archivist-es` + `archivist-redis`) — all internal-only, web UIs
narrow-bound to the oldsrv Home-IP (homelable pattern; NO public route/cert labels). Also sets the
`vm.max_map_count` sysctl needed by Elasticsearch and recreates the tube-archivist storage dir.

### P3.3 Post-converge wiring (owner verifies)

1. **Aurral → Lidarr** — point Aurral at Lidarr (its UI: add the Lidarr instance; the compose
   already exports `LIDARR_URL` + `lidarr_api`). Verify Aurral renders recommendations + can
   submit an add request. (Compose emits the connection; the in-UI wiring is a one-time
   owner step, mirroring HD-358's `Seerr → *arr link`.)
2. **slskd → Lidarr** — in Lidarr, add Soulseek as a **download client/#2**. Verify a rare-FLAC
   search → download lands in `bulk/media/downloads/complete/music` → Lidarr imports →
   `bulk/media/music` → Box refresh (Navidrome, HD-354).
3. **lidarr-ydl → Lidarr** — first UI login, then in Lidarr register it as the Newznab indexer +
   SABnzbd-emulating download client (its web UI Settings page explains the wiring). Verify a
   YouTube-sourced album lands in `downloads/complete/music` → Lidarr imports (priority #3).
4. **Tube Archivist** — first login (`http://<oldsrv-home-ip>:8000` — narrow-bind; NO subdomain),
   add channels/playlists; the archive dir is the new `bulk/media/tube` nas subdir. Later: add it
   as a Jellyfin library via the TubeArchivist plugin (`tube-archivist_api`/`tube-archivist_ui`
   keys).
5. **Router (owner):** rate-limit each P2P service to **10 MB/s** (slskd `50300`, qBittorrent)
   and open the **LAN-side inbound port** for slskd on the egress VLAN
   ([docs/network-ops.md](docs/network-ops.md) §QoS / firewall). SABnzbd stays plain LAN.

### P3.4 Verify

- `docker ps` on oldsrv: `aurral`, `slskd`, `gluetun-slskd`, `lidarr-ydl`, `bgutil-provider`, `tube-archivist`,
  `archivist-es`, `archivist-redis` all `Up`.
- `http://<% oldsrv_home_ip %>:5030` (slskd UI), `<oldsrv_home_ip>:5005` (lidarr-ydl UI),
  `<oldsrv_home_ip>:8000` (tube-archivist UI) all answer (narrow-bind).
- Aurral recommendations render; Tube Archivist subs pull episodes on schedule.
- `bash scripts/validate-all.sh` green (unchanged by deploy; run after any repo change).

### P3.5 Ollama embed fallback — first boot + model pull `[MANUAL]`

> **The plan of record is [services-ai.md](docs/services-ai.md) §3a** (decision #27): the pinned tier —
> embeddings, rerank, STT — is **three separate llama.cpp/whisper.cpp `server-vulkan` containers on the RX 7600**
> (`embed` / `reranker` / `whisper`), NOT Ollama. Ollama `0.32.15-rocm` survives only as the documented **embed
> fallback rung**. No Ollama build exposes `/api/rerank`, so no version bump makes either leg Ollama's — do not
> re-derive the engine choice from this file, and never converge an unpinned AI leg.

Pull the one model this rung serves (one-time, no Ansible task):
```bash
ssh ansible-admin@oldsrv 'docker exec ollama ollama pull bge-m3'
ssh ansible-admin@oldsrv 'docker exec ollama ollama list'
# never pull the community STT / reranker models — neither leg is Ollama's (decision #27):
#   ssh ansible-admin@oldsrv 'docker exec ollama ollama rm sendmeaiohyeah/whisper-large-v2 qllama/bge-reranker-v2-m3:q8_0'
# Ollama holds exactly one model on disk: bge-m3, the embed fallback rung.
```

Verify the three pinned-AI containers, which are the tier — **not** Ollama (`whisper` :9000, `reranker`
:9001, `embed` :9002, all on `llm-backend`; Ollama keeps only the fallback row):

```bash
ssh ansible-admin@oldsrv 'for c in whisper reranker embed; do
  IP=$(docker inspect $c --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}");
  printf "%-9s health=" "$c"; curl -s -o /dev/null -w "%{http_code}\n" "http://$IP:$(
    case $c in whisper) echo 9000;; reranker) echo 9001;; embed) echo 9002;; esac)/health";
done'
```

✔-evidence: `200` x3, then prove the **endpoints**, not just the healthcheck:

| Leg | Call | Expected |
|-----|------|----------|
| embed | `POST /v1/embeddings {"model":"bge-m3","input":"..."}` | 1024 floats, \|\|v\|\|=1.0 |
| rerank | `POST /v1/rerank {"model":"..","query":"..","documents":[..]}` | a `relevance_score` per doc |
| STT | `POST /v1/audio/transcriptions -F file=@x.wav` | `{"text": ...}` |

Tier VRAM: `cat /sys/class/drm/card1/device/mem_info_vram_used` — the whole pinned tier is ~2.5 GiB warm
(measurements + provenance: [services-ai-bench.md](docs/services-ai-bench.md)).

**LiteLLM catalog recreate — do this step, it is not in git** (model rows live in the LiteLLM DB). Three
`POST /model/new` calls against **`lan-litellm`** on oldsrv with the master key (vault item `litellm_api`,
field `credential` — there is no `litellm_master_key` item). Exact payloads:
[services-ai.md](docs/services-ai.md) §4a. The provider prefixes are load-bearing:

| Row | Provider form | Why |
|-----|---------------|-----|
| rerank | `jina_ai/bge-reranker-v2-m3`, **path-less** `api_base` | the only shape LiteLLM's rerank client accepts |
| embed | `hosted_vllm/bge-m3` | **not** `openai/` — that provider forwards `encoding_format: null` and llama.cpp 500s |
| STT | `openai/whisper-1` with `/v1` | whisper.cpp exposes the OpenAI-shaped path |


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

> The full imperative flow (dry-run → provision → verify → the owner's KNX/SSO steps) is
> [`deployment-pi-provision.md`](docs/deployment-pi-provision.md). This section carries the ordering and the
> two rules that break the host when violated.

### 4.3 Ansible provisioning

```bash
# from the WSL Debian runner (venv), with the 9P sync gate satisfied:
bash scripts/ansible-run.sh playbooks/raspberry_pi.yml
# first apply human-gated: dry-run (--check --diff) then single host
```

Role order is **load-bearing** (HD-185/204 render-first decision): `common` → `ai_diag` → `network` (static dual-home via **two NetworkManager keyfiles** — Pi-uses-NM, [network-rejected.md](docs/network-rejected.md); RPi OS ships NetworkManager, no systemd-networkd. The role renders `pi-eth0.nmconnection` = untagged Home on the parent (`ansible_host`, default via Home — single gateway, no `never-default`, DNS via `bootstrap_dns_servers`, DHCP off) + `pi-mgmt.nmconnection` = tagged Mgmt on `eth0.99` (`mgmt_ip`, never-default, route via the tagged leg — HD-311); session-safe — the Home IP never changes, the Mgmt IP rides the tagged sub-interface, never the untagged parent) → `nut` (client, `shutdown_delay_seconds=0`) → `docker` → **`home_assistant` → `docker_services`** → `monitoring` (Alloy only). Running `home_assistant` BEFORE `docker_services` renders `configuration.yaml` / `keepalived.conf` (+ `secrets.yaml` — rendered from templates, HD-185/HD-313) as **regular files** before first `compose up` — the old KOPS-063 order made Docker auto-create bind-mount dirs and HA silently ran default config. Do not reorder.

> ⚠ **Two rules, both learned by taking the Pi offline:**
> 1. **Never activate a new NM profile id over the wire.** `nmcli connection up <new-profile>` deactivates the
>    existing connection and drops the interface mid-session. The `network` role keeps the id stable
>    (`pi-eth0`), so the safe sequence over SSH is: install the keyfile → `nmcli connection reload` →
>    `nmcli connection up pi-eth0` (a re-apply of an active connection, not a switch).
> 2. **The Mgmt IP lives only on the tagged sub-interface `eth0.99`**, never on the untagged Home parent — a
>    connected route on the parent steals `10.10.99.x` from the tagged leg and `router99` becomes unreachable.
>    The role renders both keyfiles for exactly this reason: `pi-eth0.nmconnection` (Home 10, untagged,
>    default route + DNS) and `pi-mgmt.nmconnection` (`eth0.99`, `never-default`).

Pi `docker_services` = `home-assistant-primary`, `technitium-secondary`, `traefik-ha` (the minimal VIP edge). **No** pihole, **no** raspberrymatic (HD-13 parked — HmIP-HAP stays in cloud mode).

### 4.4 Verify

- `ha.kogler.si` resolves to the VIP (`ha-vip` per SSOT); `keepalived` MASTER on the Pi (priority 110 > oldsrv's 100).
- Technitium resolves `*.kogler.si` internally — **3-instance DNS HA: VPS primary (resolver = the VPS public IP) /
  oldsrv secondary / Pi tertiary**; DHCP hands all three and is **Pi-first on VLAN 10**. Option A (single
  VPS-public resolver + VPS nftables source-allow + DDNS refresh) is the design:
  [network-dns.md](docs/network-dns.md). The split-horizon records are **seeded by the `technitium-seed` task**
  (contract checked by `scripts/check_dns_seed_drift.py`) and need the `technitium_login` item — see §1.4c.
- HA web login is **local** (owner account, `ha` route). Authentik OIDC for HA was **declined by the owner** —
  do not wire it. The SSO dashboard links HA, HA does not authenticate to Authentik.
- Manual failover Pi→oldsrv and back passes ([smart-home-failover.md](docs/smart-home-failover.md) runbook; the
  Homepage button + `ha-failover_api` gate are tracked as HD-17 / HD-217).
- NUT client shutdown path (master = nas) · monitoring scrape of the HA exporter (Phase 6, gated behind HD-14).

> Open items on this host are the ledger's Phase 4 block ([deployment-tasks.md](deployment-tasks.md)) and
> [home-assistant-current.md](docs/home-assistant-current.md).

---

---

## Phase 4b — DGX Spark (GB10) first-boot + onboarding (`spark.kogler.si`) `[MANUAL]`

> **Depends on:** Phase 1.5 (VLANs — Home VLAN 10 reachability), the `spark` rows in
> `network_static_hosts` ([`IaC/ansible/group_vars/all/main.yml`](IaC/ansible/group_vars/all/main.yml)).
> Owning spec: [docs/hardware-spark.md](docs/hardware-spark.md) (HD-335 / HD-337 / HD-359).
> The node is headless by design — a display + keyboard are needed ONCE, for the first-boot wizard
> (steps 5.1–5.3); afterwards everything runs over SSH/Ansible.

### 4b.1 First-boot wizard `[MANUAL]`

1. **Cable** the 10 GbE RJ-45 port to a Home VLAN 10 switch port; power via the 240 W USB-C PD PSU.
2. **Attach display + keyboard** and power on — the GB10 ships with DGX OS preinstalled; the
   NVIDIA first-boot setup wizard runs on first boot.
3. **Wizard choices:** language **English**, timezone **Europe/Ljubljana**, local admin account `admin` —
   password is the 1Password item **`spark_login`**; **analytics disabled**.
4. **Apply the offered updates, then let the wizard reboot.**

### 4b.2 Post-update reboot: mask auto-suspend (MANDATORY, before the box idles) `[MANUAL]`

> **Do not leave this box unattended before the masks are in.** A headless GB10 idles into **auto-suspend**,
> which kills the NIC: the node goes silent at L2 (stale lease, no ARP/ICMP) while the port link stays up, and
> only a physical power-cycle recovers it. The `spark` role enforces the masks from IaC (`spark_headless: true`,
> HD-364) — masking by hand is only the pre-first-converge window.
>
> The `spark` role enforces these masks from IaC (`spark_headless: true` masks the four targets and sets
> `default.target = multi-user`). The manual mask below is therefore **first-contact only** — the window before
> the first `spark.yml` converge; afterwards the role keeps it true and re-running the step is harmless.

```bash
ssh admin@<current-dhcp-ip>        # see the router DHCP lease (host-name thinkstationpgx-*)
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo systemctl set-default multi-user.target    # skip the graphical login on the headless box
```

✔ `systemctl status sleep.target suspend.target` — all four targets show **`masked`**;
`systemctl get-default` → `multi-user.target`.

### 4b.3 First-boot verification `[MANUAL]`

```bash
nvidia-smi        # ✔ "NVIDIA GB10", driver 580.x, CUDA Version: 13.0
nvcc --version | tail -1   # ✔ Build cuda_13.0
free -h           # ✔ ~121 Gi total (128 GB unified minus reserve)
lsblk             # ✔ single NVMe: p1 EFI (512M) + p2 root (rest) — record layout for the
                  #   spark_partition_enable inspection before the spark role converge
```

✔-evidence: driver 580.x / CUDA 13.0 · ~121 Gi unified RAM · one NVMe as p1 EFI (512 M) + p2 root. Record the
partition layout — the `spark_partition_enable` inspection depends on it.

### 4b.4 MAC → static reservation (SSOT + router) `[MANUAL]`

1. **Read the NIC MAC** from the router DHCP lease (dynamic lease on `dhcp-10`, host-name
   `thinkstationpgx-*`).
2. **SSOT:** the MAC is authored into the `spark` VLAN-10 row of `network_static_hosts`
   (mgmt VLAN-99 row stays MAC-less until the mgmt NIC is cabled).
3. **Router (WinBox/WebFig, owner step):** `IP → DHCP Server → Leases` → select the spark lease →
   **make-static**, then edit the address to the reserved spark Home static per SSOT
   ([docs/network-addresses-generated.md](docs/network-addresses-generated.md), `spark` VLAN 10).
   The spark mgmt-VLAN reservation stays pending until that leg is cabled.

✔ `ping spark.kogler.si` answers on the reserved static and the lease shows `bound` + `static`
on `dhcp-10`.

### 4b.5 First contact + Ansible provisioning `[MANUAL + Ansible]`

```bash
# 1) First-contact bootstrap (manual, ON spark as `admin` over its display/KVM):
#    served bootstrap-spark.sh over LAN HTTP from the management laptop (WSL: python -m http.server + netsh portproxy),
#    fetched AS admin, run with sudo — creates ansible-admin (key-only, NOPASSWD sudo), installs 2 keys
#    (ansible-admin_ssh + laptop-domen_ssh, from 1P Homelab-ansible), sshd hardening drop-in, masks auto-suspend,
#    writes /etc/spark-bootstrap.done. (The standalone spark/ansible/spark-bootstrap role is the same logic.)
sudo bash bootstrap-spark.sh

# 2) Verify from the runner (WSL):
ssh -o BatchMode=yes -i ~/.ssh/id_ed25519 ansible-admin@spark.kogler.si 'whoami; sudo -n true'   # spark.kogler.si = SSOT spark Home IP (network-addresses-generated.md)
#    (~/.ssh/config: Host spark → HostName spark.kogler.si (SSOT), User ansible-admin)

# 3) NVMe layering (operator, manual): DGX OS ships p1=vfat /boot/efi + p2=ext4 root (~953G).
#    SHRINK p2 offline first (recovery USB: e2fsck -f, resize2fs to ≤450G, parted shrink), then:
ssh spark 'sudo parted -s -- /dev/nvme0n1 mkpart primary xfs 944769024s 100%'
ssh spark 'sudo mkfs.xfs -f -d agcount=16 /dev/nvme0n1p3'
ssh spark 'sudo mkdir -p /mnt/spark_nvme && sudo mount /dev/nvme0n1p3 /mnt/spark_nvme'

# 4) Set spark_partition_enable: true in IaC/ansible/host_vars/spark.kogler.si.yml, then converge:
ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark.kogler.si -e ansible_host=spark.kogler.si  # SSOT IP via network_static_hosts
#    → failed=0: role skips carve (p3 exists), writes fstab + XFS dirs; docker role auto-picks
#    Ubuntu noble; mounts /mnt/spark_nvme (mount_options noatime,nodiratime — XFS rejects nobarrier).
```

✔-evidence: `failed=0`; `/mnt/spark_nvme` mounted, fstab-durable, XFS dirs present; docker installed; alloy
active. The AI stack deploys separately (`playbooks/spark.yml --tags spark-ai`).

### 4b.5b B1 benchmark — imperative run procedure `[MANUAL]`

> The harness lives in-repo at `spark/bench/` and is **copied to the box** (the box has no checkout). Run the
> sanity sequence (C1×2 + C2×2 + C3×2 + warm) plus the accuracy gate. **C3 must stay at 6×8k@c2**: the upstream
> 12×8k@c3 default exhausts the NVRM memdesc (`NV_ERR_NO_MEMORY`) and triggers a host-wide OOM on GB10 unified
> memory that kills `sshd`/`NetworkManager`/`polkitd` — the container survives its memory cage, the host does
> not. The harness preflight (`MEM_FLOOR_GB`, default 8) aborts below the floor; never lift it for C3.

```bash
# 1) copy harness + scripts to the box (has docker/jq/nvidia-smi)
scp -r spark/bench spark:/home/ansible-admin/bench

# 2) sanity sequence (accuracy gate + C1/C2/C3 ×2 fresh seeds + warm) — run detached, ~30 min
ssh spark 'cd /home/ansible-admin/bench && setsid bash -c "bash run-sanity.sh > sanity-full.log 2>&1" < /dev/null &'

# 3) single scenario for iterative tuning (env-overridable sizes; MEM_FLOOR_GB guards host RAM)
ssh spark 'cd /home/ansible-admin/bench && MEM_FLOOR_GB=8 bash run-scenario.sh B1 C2 42'

# 4) retrieve results
scp -r spark:/home/ansible-admin/bench/raw .
scp spark:/home/ansible-admin/bench/results.csv ./raw/
scp -r spark:/home/ansible-admin/bench/accuracy .
```

**CLI/API drift this harness absorbs** (re-check on every engine pin bump; results are meaningless if the
invocation silently no-ops): invoke `vllm bench serve` — `python3 -m vllm.benchmarks.serve` has no `__main__`
and **exits 0 doing nothing**; pass `--base-url` + `--endpoint /v1/chat/completions`; read snapshot metrics from
`kv_cache_usage_perc` (renamed from `gpu_cache_usage_perc`); pull result JSON with `docker exec cat` (`docker cp`
cannot see the container's tmpfs `/tmp`); key run metrics on an immutable `RUN_TS` (the snapshot `.env` clobbers
`TS`). Provenance for the numbers: [services-ai-bench.md](docs/services-ai-bench.md).


### 4b.6 DGX Dashboard LAN edge — verify (after any spark converge / reboot) `[Ansible + verify]`

> The edge 404s from the LAN whenever the file-provider rule is missing or the healthcheck/ping glue is stale —
> the spark dashboard has no Traefik labels of its own, so the route lives entirely in the generated file.
> Rule + cause: [hardware-spark.md](docs/hardware-spark.md) §Dashboard LAN edge.

```bash
ssh spark 'sysctl net.ipv4.ip_nonlocal_bind'   # must print 1 (role-owned)
ssh spark 'grep -E "ping|healthcheck|rule:" /opt/spark-dashboard/docker-compose.yml /opt/spark-dashboard/dynamic/routes.yml'  # --ping + CMD traefik healthcheck --ping + Host(spark.kogler.si); NO --api.insecure (dropped once verified)
ssh spark 'cd /opt/spark-dashboard && sudo docker compose up -d'   # re-render from latest template
curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://spark.kogler.si:11000/   # MUST be 200 (use the NAME, not the IP)
ssh spark 'docker exec traefik-spark traefik healthcheck --ping'   # "OK: http://:8080/ping", exit 0; container shows healthy
```

---

*Charter: imperative redeploy procedure only (true zero → live) for Phases 0, 0.5, 1, 1a, 1.5, 2, 3, 4 and 4b.
Progress lives in [deployment-tasks.md](deployment-tasks.md), knowledge in the owning docs, history in git.*

---

## Phase 4c — Coding cockpit on oldsrv under `domen` (HD-409 pi-web) `[MANUAL + Ansible]`

Native host processes under the unprivileged `domen` account — **not** containers, **not** behind
gateway-auth. Rationale, the auth decision and what is unproven: [`docs/services-ai.md`](docs/services-ai.md)
§9b-1. Ports come from `group_vars/all/main.yml` (`cockpit_pi_web_port: 31415`, `paseo_port: 31416`) —
**no role owns these unit files yet**, so keeping the numbers in step below is a hand step, not a converge.
Run everything as root on oldsrv (`sudo -n`); the cockpit itself always runs as `domen`.

1. **Install the Node runtime `domen` needs — do NOT use apt's Node.** pi's package declares
   `engines.node >= 22.19.0`; Debian 13 ships 20.19.2, so `apt install nodejs` produces an install that
   cannot start. Use the same shape the laptop uses (a pinned tarball, no system footprint, no third-party
   apt repo):
   ```bash
   sudo -u domen mkdir -p /home/domen/.local/share/pi-node
   sudo -u domen bash -lc 'cd ~/.local/share/pi-node && \
     curl -fsSLO https://nodejs.org/dist/v22.23.2/node-v22.23.2-linux-x64.tar.xz && \
     tar -xf node-v22.23.2-linux-x64.tar.xz && rm node-v22.23.2-linux-x64.tar.xz && \
     ./node-v22.23.2-linux-x64/bin/node -v'          # → v22.23.2
   ```
2. **Install pi, then the cockpit AS A PI PACKAGE** (it is a pi package, not a standalone daemon — the
   package pulls the Go binary and writes the user unit for you):
   ```bash
   export PATH=/home/domen/.local/share/pi-node/node-v22.23.2-linux-x64/bin:$PATH
   sudo -u domen env PATH=$PATH npm install -g @earendil-works/pi-coding-agent && sudo -u domen env PATH=$PATH pi --version
   sudo -u domen env PATH=$PATH pi install npm:@ygncode/pi-web@beta    # → ~/.pi/agent/bin/pi-web + ~/.config/systemd/user/pi-web.service
   ```
3. **Create the sessions directory BEFORE starting it** — the binary exits 1 (`sessions directory not
   found`) rather than creating it, and pi only makes it on its first run:
   `sudo -u domen mkdir -p /home/domen/.pi/agent/sessions`
4. **Render the model contract + provider auth from git — never copy a laptop file.** From a workstation
   with `op` signed in (HD-388):
   ```bash
   python3 scripts/render-pi-config.py --out /tmp/oldsrv-models.json
   python3 scripts/render-pi-config.py --vendor pi_auth --out /tmp/oldsrv-auth.json
   scp /tmp/oldsrv-models.json /tmp/oldsrv-auth.json ansible-admin@oldsrv:/tmp/
   # on oldsrv — 0600 + owned by domen, then wipe the copies:
   sudo install -m600 -o domen -g domen /tmp/oldsrv-models.json /home/domen/.pi/agent/models.json
   sudo install -m600 -o domen -g domen /tmp/oldsrv-auth.json   /home/domen/.pi/agent/auth.json
   rm -f /tmp/oldsrv-models.json /tmp/oldsrv-auth.json
   sudo -u domen env PATH=$PATH pi --list-models | head    # proves the render is what pi reads
   ```
5. **Set the token** in `/home/domen/.config/pi-web/env` as `PI_WEB_TOKEN=...` (dir 700, file 600, owner
   `domen`). A non-loopback bind is impossible without it — the binary refuses unless you pass `-insecure`,
   which you must not do here. The vault item and its minting rule:
   [`docs/deployment-secrets.md`](docs/deployment-secrets.md) `cockpit-pi-web_api` — mint it with the **same**
   value, or every paired client needs re-pairing.
6. **Bind loopback and survive logout.** The seat is published as `https://pi-oldsrv.ts.kogler.si` by
   oldsrv's own `traefik-internal` `websecure-ts` listener, which runs `network_mode: host` and therefore
   reaches the host's loopback — so the daemon needs no routable socket at all: no LAN listener, no
   `tailscale0` bind, and the tailnet ACL + TLS + `PI_WEB_TOKEN` are the only way in. Placement + rationale:
   [docs/services-ai.md](docs/services-ai.md) §9b-1. **Derive the port; never paste it** (it has an SSOT var):
   ```bash
   PORT=$(sudo awk -F: '/^cockpit_pi_web_port:/{gsub(/[ #].*/,"",$2); print $2}' \
          /home/ansible-admin/source/homelab/IaC/ansible/group_vars/all/main.yml)
   echo "bind = 127.0.0.1:$PORT"
   sudo mkdir -p /home/domen/.config/systemd/user/pi-web.service.d
   printf '[Service]\nExecStart=\nExecStart=/home/domen/.pi/agent/bin/pi-web -host 127.0.0.1 -p %s\n' "$PORT" \
     | sudo tee /home/domen/.config/systemd/user/pi-web.service.d/loopback-bind.conf
   sudo rm -f /home/domen/.config/systemd/user/pi-web.service.d/tailnet-bind.conf   # superseded by loopback-bind
   sudo chown -R domen:domen /home/domen/.config/systemd/user
   sudo loginctl enable-linger domen                    # user units must run with no session attached
   sudo -u domen XDG_RUNTIME_DIR=/run/user/$(id -u domen) systemctl --user daemon-reload
   sudo -u domen XDG_RUNTIME_DIR=/run/user/$(id -u domen) systemctl --user enable --now pi-web.service
   ```
   Remove the old `tailnet-bind.conf` drop-in: the router proxies to loopback, so a daemon still bound to the
   `tailscale0` address leaves a healthy-looking listener next to a 404ing URL.
7. **Verify** (the 401/302 pair is the whole auth contract):
   ```bash
   ss -ltnp "( sport = :$PORT )"                        # 127.0.0.1:$PORT and NOTHING else — no LAN socket
   curl -s -o /dev/null -w 'no-token %{http_code}\n'  "http://127.0.0.1:$PORT/"                                       # → 401
   curl -s -o /dev/null -w 'token %{http_code}\n'     "http://127.0.0.1:$PORT/?token=$(sudo cut -d= -f2- /home/domen/.config/pi-web/env)"  # → 302
   ```
   Then the edge, on this box (loopback reaches the tailnet listener, so this proves TLS + router + backend
   in one call without leaving home):
   ```bash
   TSIP=$(ip -4 -br addr show tailscale0 | awk '{print $3}' | cut -d/ -f1)
   curl -kIs --resolve "pi-oldsrv.ts.kogler.si:443:$TSIP" https://pi-oldsrv.ts.kogler.si/ \
     | head -1                                             # → HTTP/2 401 (or 200 on the ?token= URL)
   ```
   A 404 here = the `pi-oldsrv-ts` router is not converged yet; a TLS name mismatch = the `*.ts.kogler.si`
   wildcard is not loaded (`check_traefik_host_rules.py` catches the template shape, not the cert store).
   Final word is a **tailnet peer** — see HD-444: no node inside this fleet may reach oldsrv's tailnet node.
8. **Seat clone (the authoring repo).** oldsrv runs two clones: `/home/ansible-admin/source/homelab`
   **converges**, `/home/domen/source/homelab` **is what the seat edits** — roles, update rules and why they
   are separate are in [docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement. If the
   seat clone is absent (`ls /home/domen/source/homelab`), create it:
   ```bash
   sudo -u domen git clone https://github.com/domenkogler/homelab.git /home/domen/source/homelab
   ```
   ⚠ Gated on the git-credential decision in HD-449(a): the runner's read-only
   `github-homelab-deploy_api` store lives under `ansible-admin` at 0600 and must **not** be copied into
   `domen` to make this step pass. Either `domen` gets its own read-only credential, or the clone is
   pull-only over a protocol that needs none.

9. **Stop / roll back:** `sudo -u domen XDG_RUNTIME_DIR=/run/user/$(id -u domen) systemctl --user disable
   --now pi-web.service`, then remove the drop-in to return to the installer's loopback-only default.
