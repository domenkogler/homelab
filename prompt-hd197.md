# prompt-hd197 — Scripts hygiene pass

> **Role:** Task handoff for **HD-197** (todo.md §2.3). Checklist from `scripts.md` findings F2,
> F3, F5, F6, F10 + the gate addition. **Linked from:** [todo.md](todo.md) (HD-197).

## Items

1. **F2 `validate_doc_templates.py`:** parse `network_vlans`/`network_static_hosts`/`network_ranges`
   from `group_vars/all.yml` with PyYAML (drop the hardcoded copies) — or, if kept as smoke test,
   relabel docstring + scripts/README honestly. Also: canonical `ansible_managed` mock
   ("Ansible managed", not the retired string), `Path(__file__)` root instead of CWD-relative, fix
   the phantom `ha.kogler.si` hostvars key, explicit exit codes with a friendly failure message.
2. **F3 `render_rack_connections.py`:** emit the canonical `# Ansible managed` header line first
   (CONVENTIONS §8.2); regenerate `docs/network-rack-generated.md` in the same change.
3. **F5 `check_doc_ips.py`:** scan all canonical root .md + IaC/**/*.md; exempt changelog.md
   (append-only history) and the existing EXEMPT set; remove the stale "once Doco-CD activates"
   docstring tail.
4. **F6 `check_doc_map.py`:** replace ROOT_SCAN allowlist with "all root *.md except prompt-*";
   drop phantom ROOT_DOCS entries (`CHANGELOG.md`, `prompt-next.md`, `readme.md`).
5. **F10:** move `scripts/*-s*.txt` + `smart-report-*.txt` → `reports/`; update scripts/README
   pointer; fix collect-smart.ps1 "Windows 10" → 11.
6. **Gate addition:** `ansible-playbook --syntax-check` across all playbooks inside
   validate-all.sh — WSL/CI-gated (skip gracefully on native Windows like the renderers do);
   document in scripts/README.

## Validation

- Each checker change: red/green test (break a file → gate fails → restore).
- `bash scripts/validate-all.sh` green at the end, new checks active.
- todo HD-197 ✅; changelog row.
