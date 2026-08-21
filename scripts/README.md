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
| [`validate-all.sh`](validate-all.sh) | **Repo gate** — runs all 9 validators in order (`set -e`, stops at first failure). Run `bash scripts/validate-all.sh`. | `CONVENTIONS.md` §4, `docs/index.md` Conventions |
| [`validate-docker-services.py`](validate-docker-services.py) | **Compose templates** — every `docker_services` template referenced by a group_vars list (count derived, orphan-dir lint): file exists, Jinja renders (mocked 1Password; context loaded from `versions.yml` + `all.yml` SSOT so it cannot drift, HD-189), YAML parses, structural checks (external networks, Traefik labels), source-level bug scan (`default=` param, host-net vs `network_mode: host`). Fail-loud on malformed group_vars YAML. | `docs/deployment-compose.md`, `docs/services.md` |
| [`validate_blueprints.py`](validate_blueprints.py) | **Authentik Blueprint shape** — local loader for custom YAML tags (`!KeyOf`, `!Find`, …) + structural checks (flow slugs `default-` prefixed, provider↔app binding). HD-149. | `docs/services-authentik.md` |
| [`check_doc_ips.py`](check_doc_ips.py) | **No IP literals outside the SSOT** — internal IPv4 ranges live only in `docs/network-addresses-generated.md` + IaC; every other doc refers by hostname/role. HD-152. | `docs/index.md` Conventions, `docs/network-addresses-generated.md` |
| [`validate_doc_templates.py`](validate_doc_templates.py) | **SSOT templates render** — `network-addresses.md.j2` + `inventory.md.j2` render with real `group_vars` context (no missing strict-undefined). | `docs/deployment-ansible.md` |
| [`validate-secrets.py`](validate-secrets.py) | **No literal secrets** — flags PEM/OpenSSH blocks + literal `*_password/_secret/_token/_api_key` values in group_vars/host_vars/role defaults+tasks+vars, `roles/*/files/*` and every rendered template (`templates/**/*.j2`) (HD-189); exempts Jinja `{{ ... }}` / `lookup(...)` values, env-var indirections and boolean/numeric policy flags (integrated `default('')`) | `CONVENTIONS.md` §Secrets, `docs/deployment-secrets.md` |
| [`check_doc_map.py`](check_doc_map.py) | **Docs reachable + links valid** — every doc under `docs/` reachable from `docs/index.md` (and vice-versa) + repo-wide `.md` link resolution. HD-152 + HD-173. | `docs/index.md` |
| [`check_generated_suffix.py`](check_generated_suffix.py) | **`-generated` suffix discipline** — every machine-produced doc carries `-generated.md`, no hand-authored doc carries it. Keeps `EXPECTED_GENERATED` in sync with `docs/index.md` map. | `CONVENTIONS.md` §8.2 |
| [`check_vault_name.py`](check_vault_name.py) | **Vault name = `Homelab-ansible`** — flags a bare `Homelab` vault reference (prose/comments/op:// URIs) in canonical docs, IaC yml/j2 and scripts/*.py; changelog.md exempt (append-only history). HD-189. | `docs/deployment-secrets.md`, `CONVENTIONS.md` §1 |
| [`check_placeholders.py`](check_placeholders.py) | **Placeholder discipline (B5)** — greppable bootstrap placeholder tokens (the B5 set: `REPLACE_ME`-style markers, disk-serial stubs, 1Password pubkey stubs — full list in the script) may appear only in the designated bootstrap artifacts + the owning spec that quotes them (`docs/deployment-preseed.md`; the round-2 audit reports that also quoted the set were fold+deleted by HD-203); anywhere else fails the gate. Mirrors the runtime assertions in `IaC/host/post_install.sh` + `pi/first-boot-config.sh`. HD-201. | `docs/deployment-preseed.md` |
| `ansible-playbook --syntax-check` (in `validate-all.sh`) | **Playbook syntax gate** — every playbook must parse + resolve modules. WSL/CI-gated: skipped with a note when ansible is absent or broken natively on Windows (WinError 87). HD-197. | `docs/deployment-ansible.md` |

---

## Renderers (IaC / SSOT → generated docs)

> Direction of truth is **IaC → generated MD** (never the reverse). These write `*-generated.md` files
> that must not be hand-edited. Re-render and `git diff --exit-code` to detect drift.

| Script | Renders | SSOT → outputs | Why it's needed (vs Ansible) |
|--------|--------|-----------------|----------------------------|
| [`render_network_addresses.py`](render_network_addresses.py) | `docs/network-addresses-generated.md` | `group_vars/all.yml` + host_vars (`oldsrv`/`pi` DNS) → generated doc | **Windows fallback** — Ansible crashes natively on this host (`os.get_blocking` → WinError 87); this refreshes the doc without WSL/Ansible |
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
| [`collect-smart-live.sh`](collect-smart-live.sh) | **SMART report** from a SystemRescue live ISO on the NAS (HP MicroServer Gen8) — `smartctl --scan` across internal + SilverStone miniSAS bays → `/tmp/smart-report-*.txt` (host, disk map, SMART attrs). | `docs/hardware-nas.md` |

The raw SMART/drive data snapshots live in [`reports/`](../reports/) (`laptop-sda.txt`,
`laptop-sdb.txt`, `oldsrv-sda.txt`, `oldsrv-sdb.txt`, `smart-report-*.txt`) — CI / audit
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

*Last updated 2026-08-21 · scripts/ has no separate CI hook beyond `validate-all.sh`.*