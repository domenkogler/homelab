# scripts/ — Homelab automation, linters & renderers

> **Role:** Reference map for the scripts in this directory — validation gate, SSOT renderers,
> and small utilities. Read it to pick the right script for a task (or avoid re-implementing one).
> **Linked from:** `CONVENTIONS.md` (§8) · `docs/index.md` (Conventions) · `README.md`
> **Authoritative specs:** owning docs named inline per script — concrete values always live in IaC
> (`group_vars/*.yml`, `host_vars/*.yml`, `rack-connections.json`), never in a generated doc.

Every script here is part of one of three groups: **validation** (the fail-closed repo gate), **render** (IaC/SSOT → generated docs), or a **standalone utility**. The single entry point for validation is
[`validate-all.sh`](validate-all.sh). The single unified render entry is [`render_all.py`](render_all.py) (HD-163) — a pure-Python umbrella over the 5 generated-doc renders below, with **no Ansible / WSL / 1Password CLI dependency**.

---

## Validation gate

**Never commit without it. `validate-all.sh` runs every linter below and must end green.**

| Script | What it checks | Owning spec |
|--------|----------------|-------------|
| [`validate-all.sh`](validate-all.sh) | **Repo gate** — runs all validators in order (`set -e`, stops at first failure), incl. the HD-253 session-discipline hard-gate + self-test. Run `bash scripts/validate-all.sh`. | `CONVENTIONS.md` §4, `docs/index.md` Conventions |
| [`validate-docker-services.py`](validate-docker-services.py) | **Compose templates** — every `docker_services` template referenced by a group_vars list (count derived, orphan-dir lint): file exists, Jinja renders (mocked 1Password; context loaded from `versions.yml` + `all.yml` SSOT so it cannot drift, HD-189), YAML parses, structural checks (external networks, Traefik labels), source-level bug scan (`default=` param, host-net vs `network_mode: host`). Fail-loud on malformed group_vars YAML. | `docs/deployment-compose.md`, `docs/services.md` |
| [`validate_blueprints.py`](validate_blueprints.py) | **Authentik Blueprint shape** — local loader for custom YAML tags (`!KeyOf`, `!Find`, …) + structural checks (flow slugs `default-` prefixed, provider↔app binding). HD-149. | `docs/services-authentik.md` |
| [`check_doc_ips.py`](check_doc_ips.py) | **No IP literals outside the SSOT** — internal IPv4 ranges live only in `docs/network-addresses-generated.md` + IaC; every other doc refers by hostname/role. HD-152. | `docs/index.md` Conventions, `docs/network-addresses-generated.md` |
| [`validate_doc_templates.py`](validate_doc_templates.py) | **SSOT templates render** — `network-addresses.md.j2` + `inventory.md.j2` render with real `group_vars` context (no missing strict-undefined). | `docs/deployment-ansible.md` |
| [`validate-secrets.py`](validate-secrets.py) | **No literal secrets** — flags PEM/OpenSSH blocks + literal `*_password/_secret/_token/_api_key` values in group_vars/host_vars/role defaults+tasks+vars, `roles/*/files/*` and every rendered template (`templates/**/*.j2`) (HD-189); exempts Jinja `{{ ... }}` / `lookup(...)` values, env-var indirections and boolean/numeric policy flags (integrated `default('')`) | `CONVENTIONS.md` §Secrets, `docs/deployment-secrets.md` |
| [`check_doc_map.py`](check_doc_map.py) | **Docs reachable + links valid** — every doc under `docs/` reachable from `docs/index.md` (and vice-versa) + repo-wide `.md` link resolution. HD-152 + HD-173. | `docs/index.md` |
| [`check_generated_suffix.py`](check_generated_suffix.py) | **`-generated` suffix discipline** — every machine-produced doc carries `-generated.md`, no hand-authored doc carries it. Keeps `EXPECTED_GENERATED` in sync with `docs/index.md` map. | `CONVENTIONS.md` §8.2 |
| [`check_vault_name.py`](check_vault_name.py) | **Vault name = `Homelab-ansible`** — flags a bare `Homelab` vault reference (prose/comments/op:// URIs) in canonical docs, IaC yml/j2 and scripts/*.py; changelog.md exempt (append-only history). HD-189. | `docs/deployment-secrets.md`, `CONVENTIONS.md` §1 |
| [`check_placeholders.py`](check_placeholders.py) | **Placeholder discipline (B5)** — greppable bootstrap placeholder tokens (the B5 set: `REPLACE_ME`-style markers, disk-serial stubs, 1Password pubkey stubs — full list in the script) may appear only in the designated bootstrap artifacts + the owning spec that quotes them (`docs/deployment-preseed.md`; the round-2 audit reports that also quoted the set were fold+deleted by HD-203); anywhere else fails the gate. Mirrors the runtime assertions in `IaC/host/post_install.sh` + `pi/first-boot-config.sh`. HD-201. | `docs/deployment-preseed.md` |
| [`guard-session.sh`](guard-session.sh) | **Session-discipline gate (HD-253)** — pre-edit guard refuses ANY edit-context while the PRIMARY checkout (`git-dir == git-common-dir`) sits on `main`; `--validate-mode` (wired into `validate-all.sh`) hard-fails only on primary+main+DIRTY; clean-main merge-station exempt; session worktrees + detached HEAD/CI pass through. Refusals print the exact `git worktree add ../homelab-wt-<date>-<HHMM>` remediation with live timestamp + coordination info (status, per-file last-commit). `--self-test` runs a sandboxed fixture (temp repos) inside the gate. Owning rule: CONVENTIONS §6. | `CONVENTIONS.md` §6 |
| `ansible-playbook --syntax-check` (in `validate-all.sh`) | **Playbook syntax gate** — every playbook must parse + resolve modules. WSL/CI-gated: skipped with a note when ansible is absent or broken natively on Windows (WinError 87). HD-197. | `docs/deployment-ansible.md` |

---

## Renderers (IaC / SSOT → generated docs)

> Direction of truth is **IaC → generated MD** (never the reverse). These write `*-generated.md` files
> that must not be hand-edited. Re-render and `git diff --exit-code` to detect drift.

| Script | Renders | SSOT → outputs | Why it's needed (vs Ansible) |
|--------|--------|-----------------|----------------------------|
| [`render_network_addresses.py`](render_network_addresses.py) | `docs/network-addresses-generated.md` | `group_vars/all/main.yml` + host_vars (`oldsrv`/`pi` DNS) → generated doc | **Windows fallback** — Ansible crashes natively on this host (`os.get_blocking` → WinError 87); this refreshes the doc without WSL/Ansible |
| [`render_rack_connections.py`](render_rack_connections.py) | `docs/network-rack-generated.md` + `docs/rack-layout.mmd` | `docs/rack-connections.json` (parsed from `docs/assets/Rack.canvas`) → generated docs | **Different SSOT** (rack JSON, not group_vars) — not covered by `render-docs.yml` |

> Ansible equivalents: `IaC/ansible/playbooks/render-docs.yml` renders the same *group_vars*-derived
> docs on Linux/CI or in WSL (`wsl.exe -d Debian`). `render_all.py` makes the Python path the
> primary one (including the inventory + subscriptions renders that previously existed only as
> Ansible tasks). `render_rack_connections.py` has **no** Ansible
> counterpart. See [`docs/deployment-ansible.md`](../docs/deployment-ansible.md).

---

## Utilities

| Script | What it does | Owning spec |
|--------|--------------|-------------|
| [`gen-htpasswd.py`](gen-htpasswd.py) | **bcrypt htpasswd line** for Prometheus `basic_auth_users` — `gen-htpasswd.py USERNAME [PASSWORD]`; cost 12. Seed `prometheus-internal_api` (HD-59). | `docs/deployment-compose.md`, `docs/deployment-secrets.md` |
| [`provision-secrets.py`](provision-secrets.py) | **1Password item create/rotate helper** for the `Homelab-ansible` vault — **safe-by-default** (bare run is a no-op help; every write needs an explicit flag + `--yes`). `--list` shows the generated-item catalog; `--create` seeds missing generated items (never overwrites); `--rotate ITEM` / `--rotate-all` regenerate values in place, refusing externally-coupled items (`wg_password`, DB passwords, `authentik_password`, `kopia_password`, `matrix_password`). Rotation + Ansible: 1Password is the SSOT, so after rotating a 1P item re-run the affected Ansible role to re-render compose/config with the new value. Needs a write-scoped `OP_SERVICE_ACCOUNT_TOKEN`; fails closed without it. | `docs/deployment-secrets.md` |
| [`ansible-run.sh`](ansible-run.sh) | **Playbook runner for the WSL Debian runner** — wraps venv activation, the read-scope SA token and explicit `ANSIBLE_CONFIG`/`ANSIBLE_ROLES_PATH` exports (Ansible ignores cwd config on world-writable `/mnt` drives). Usage: `bash scripts/ansible-run.sh playbooks/vps.yml [--check]`; from Windows via `wsl -d Debian -- bash /mnt/d/.../scripts/ansible-run.sh …`. Run only after the 9P sync gate clears (whole-tree hash compare Windows↔WSL — see [deployment-manual.md](../deployment-manual.md) How-to-use, HD-212). Fails loud when Phase 0 bootstrap is missing. | `deployment-tasks.md` Phase 0/1 |
| [`git-bootstrap.sh`](git-bootstrap.sh) | **Debian/WSL-side primary-repo setup** — makes WSL ext4 (`~/source/homelab`) the primary SSOT clone (pi.dev + Ansible + editing) instead of the slow `/mnt/d` drvfs mount. Idempotent: `clone` on first run, skip on later; sets local `git user.name/email`; `update`/`pull` do `git fetch` + `git pull --ff-only origin main` (brings in remote changes for review in VSCode WSL Remote); `--reload` is informational. Env-overridable: `SRC`, `REPO`, `REMOTE`, `GITUSER`, `GITEMAIL`. Read-only pull needs no GitHub auth; push needs a credential helper/token. Nudges the session-worktree discipline (CONVENTIONS §6) instead of editing on `main`. Rationale + caveats: `ansible-enhancements.md §8.4`. | `ansible-enhancements.md` §8.4 |
| [`provision-vault.sh`](provision-vault.sh) | **Vault item seeder wrapper** — pulls the write-scoped SA token transiently from the VPS (`/etc/op/provision-token`, HD-143) over SSH and runs `provision-secrets.py --create --yes`. `--dry-run` lists the catalog. Run from the WSL runner. | `docs/deployment-secrets.md` |
| [`restore-runner-key.sh`](restore-runner-key.sh) | **Canonical runner-key restore** — after a true-zero WSL rebuild, replaces bootstrap.sh's throwaway `~/.ssh/id_ed25519` with the vault-canonical `ansible-admin_ssh` key (1Password = source of truth) and verifies the fingerprint. | `docs/1password.md`, `deployment-tasks.md` Phase 0 |
| [`check-vault-items.sh`](check-vault-items.sh) | **Vault coverage diff** — items required by the enabled services vs the vault, excluding glue-auto-seeded OIDC items. Scans per-service template dirs PLUS shared top-level templates and the VPS group_vars context (blind-spot fix 2026-08-22 — `ha-failover_api`, `cloudflare_api` class), AND the `*_item:`-class registry keys (`db_item`, `db_ro_item`, ...) parsed per-entry from ENABLED entries in `group_vars/vps.yml` + `home_servers.yml` — deploy-service.yml consumes those dynamically (`svc.<key>` lookups), so a literal-lookup grep can never see them (HD-244, live-found while seeding `metabase-forgejo_ro`). Items minted by deploy-time glues are EXCLUDED from MISSING: OIDC client items via literal name pairs in `authentik-secret-egress.sh.j2`; LiteLLM scoped keys via their group_vars SSOT — every spec record inside a top-level `*_scoped_keys:` list routes its `vault_item:` into the GLUE set, while `db_item`/`db_ro_item` on service entries stay NEEDED (owner-seeded catalog items; the litellm glue template is Jinja-rendered and carries no greppable literals; gap live-found 2026-08-26). Non-VPS role items (router/nut/Pi) deliberately out of scope. Flags: `--strict` exits non-zero when the MISSING-and-not-glue list is non-empty (default informational); `--root DIR` + `--fake-vault FILE` drive the committed self-test (`scripts/testdata/check-vault-items/run.sh`, wired into validate-all.sh — proves the registry-key catch AND the no-false-positive/glue-exclusion paths without touching the real vault). Run before a deploy to get the exact "create these" list. | `deployment-tasks.md` Phase 1, `scripts/testdata/check-vault-items/` |
| [`ak-shell.sh`](ak-shell.sh) | **Authentik container shell** — runs a Python snippet inside `authentik-worker` (VPS) over the runner's key-file SSH, base64-safe (no multi-layer quoting). Call INSIDE WSL via script-file indirection; **arg mode is the reliable path** — stdin (`-`) mode fails intermittently through the cmd→wsl chain (Wave-3 R5). Used for token minting / model queries / one-shot fixes — see `docs/services-authentik.md` live-deploy findings. | `docs/services-authentik.md` |
| [`collect-smart-live.sh`](collect-smart-live.sh) | **SMART report** from a SystemRescue live ISO on the NAS (HP MicroServer Gen8) — `smartctl --scan` across internal + SilverStone miniSAS bays → `/tmp/smart-report-*.txt` (host, disk map, SMART attrs). | `docs/hardware-nas.md` |
| [`collect-disk-facts.sh`](collect-disk-facts.sh) | **Phase 1a read-only disk-facts collector** for a Debian installer/live USB (pre-reinstall facts on oldsrv/nas; generalized sibling of `collect-smart-live.sh` that writes to the stick instead of /tmp): `/dev/disk/by-id/` ↔ device reverse map (HD-128 NVMe by-id capture — the doc values are Windows-derived EUI64, unverified on Linux), model/serial/size/transport per disk, SMART key attrs + full `smartctl -x` dump when smartmontools is present, `lsblk`/`blkid`/`nvme list` context (existing-FS awareness before the Pool-Creation Runbook's wipefs step). Writes `disk-facts-<label>-<ts>.txt` to the root of the writable USB stick (auto-detects mounted removable media or auto-mounts a boot-stick partition; loud fallback if none — a plain dd'd ISO9660 stick is read-only by design). POSIX sh — runs in the d-i busybox console (`Ctrl+Alt+F2`) and live sessions alike. Usage: `sudo sh collect-disk-facts.sh [oldsrv\|nas]`. Strictly read-only toward disks. | `deployment-tasks.md` Phase 1a, `docs/hardware-oldsrv.md`, `docs/hardware-nas.md` (HD-207 runbook pre-flight), `todo.md` HD-128/HD-207 |

The raw SMART/drive data snapshots live in [`reports/`](../reports/) (`laptop-sda.txt`,
`laptop-sdb.txt`, `oldsrv-sda.txt`, `oldsrv-sdb.txt`, `smart-report-*.txt`,
`disk-facts-oldsrv-*.txt` from collect-disk-facts.sh, `DOMENPC-cpuz.txt`) — CI / audit
inputs, not tools. `collect-smart.ps1` is the Windows PowerShell sibling of
`collect-smart-live.sh` (same purpose, runs from Windows instead of a live ISO).

---

## Notes & conventions

- **Never edit a `-generated` doc directly** — change the SSOT (`group_vars/*.yml`, `rack-connections.json`) and re-render, then `git diff --exit-code` to confirm.
- **No secrets outside 1Password `Homelab-ansible`.** Render scripts that need one (e.g. `render-routeros.yml` → device `.rsc`) resolve via `lookup(...)`; the pure-Python renderers here intentionally touch **no** secrets (they read only the YAML/JSON SSOT).
- **Windows vs Linux:** the Python scripts run cross-platform (PyYAML + Jinja2). Ansible playbooks (`render-docs.yml`, `render-routeros.yml`) require WSL/CI on this machine.
- **Validator wiring:** anything added to `validate-all.sh` must be listed here; keep the comment block in `validate-all.sh` in sync.
- **Config / "what reads what":** `CONVENTIONS.md` §8 is the canonical index of rules these scripts enforce; this file is a *map* — the owning specs remain authoritative.

---

*Last updated 2026-08-26 · scripts/ has no separate CI hook beyond `validate-all.sh`.*