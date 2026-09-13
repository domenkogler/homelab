# spark-bootstrap role — one-shot automation identity + SSH key + hardening bootstrap

First-contact role for a **fresh NVIDIA DGX Spark (GB10, DGX OS / Ubuntu)**: creates the Ansible
automation user, injects the homelab admin public key, and applies sshd hardening — the Ansible
precondition for every other `spark-*` role (`spark-base` expects `ansible` to exist, be sudoer, and
be in the `docker` group).

**Run ONCE, by hand, over SSH as a privileged user** after DGX OS install (headless, 10 GbE on the
LAN). Afterwards normal Ansible takes over; nothing in this role may depend on Ansible existing.

## Operators

- `ansible_{user,group}` — inventory/group_vars overrides.
- `spark_bootstrap_ssh_keys` — list of `{ comment, key }` **authorized_keys** lines to install
  (default = the homelab `~/.ssh/id_ed25519.pub` — see `defaults/main.yml`).
- `spark_bootstrap_pubkey_source` — absolute path of the local public key used by the playbook.
- `spark_bootstrap_setup_python` — install `python3`/`python3-apt` (DGX OS ships it; kept idempotent).
- `spark_bootstrap_env` — extra key→line mappings (e.g. proxies) rendered into `/etc/environment`.

## Verification (playbook)

`spark-bootstrap-playbook.yml --tags verify` — refuses: root login, password auth, empty
authorized_keys. Confirms: `ansible` user present + sudo NOPASSWD + docker group, `ansible_python_interpreter` resolves, key login works. Post-run:
`ssh ansible@<spark-ip> whoami && ssh ansible@<spark-ip> sudo -n true`.

## Security stance (matches repo convention)

- Non-root automation user, **no interactive shell** (`/usr/sbin/nologin`), `AllowUsers ansible`,
  `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3` (drop-in
  `/etc/ssh/sshd_config.d/50-homelab-hardening.conf`), sudo **NOPASSWD** (Ansible needs it).
- **Fail-loud** idempotency: the role **refuses** to run against an already-bootstrapped box
  (`/etc/spark-bootstrap.done` exists) without `-e reset=1` — prevents accidental key churn/re-run.
- No secrets in the role: keys are provided via operator-supplied pubkeys / operator vault item
  (`spark_bootstrap_ssh_keys`), never generated or embedded here.