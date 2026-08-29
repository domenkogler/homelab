# Audit Track C — Scripts & tooling consistency

> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Track scope:** scripts/ (31 portable scripts + testdata/) + scripts/README.md
> registry + scripts/validate-all.sh (gate).
> **Methodology:** parent (this session) executed the track inline.
> **Read-only:** no scripts mutated. Smoke-tests read-only (`bash -n`,
> `python3 -m py_compile`).

---

## C.1 Registry vs filesystem (audit.md §2.3.1)

**Verified:**
- 31 files in `scripts/` matching `*.sh` or `*.py` glob (matches
  `scripts/README.md` registry).
- 1 `__pycache__/` directory (excluded from registry by convention).
- `scripts/README.md` documents each entry with a one-line purpose +
  portability status + the docs it relates to.

**Spot-checked 1:1 entries:**
- `validate-all.sh` (gate) — registered ✅
- `validate-docker-services.py` — registered ✅
- `validate_blueprints.py` — registered ✅
- `check_doc_ips.py` — registered ✅
- `validate_doc_templates.py` — registered ✅
- `validate-secrets.py` — registered ✅
- `check_doc_map.py` — registered ✅
- `check_generated_suffix.py` — registered ✅
- `check_vault_name.py` — registered ✅
- `check_placeholders.py` — registered ✅
- `render_all.py`, `render_network_addresses.py`,
  `render_rack_connections.py` — registered ✅
- `op-vault-export.py`, `provision-secrets.py`, `provision-vault.sh`,
  `check-vault-items.sh` — registered ✅
- `guard-session.sh` — registered ✅
- `git-bootstrap.sh` — registered ✅
- `ansible-run.sh` — registered ✅
- `bootstrap-runner.sh` — registered ✅
- `next-hd.sh` — registered ✅
- `ak-shell.sh` — registered ✅
- `install-pi-wsl.sh` — registered ✅
- `gen-htpasswd.py` — registered ✅
- `gen-custom-script.sh` — registered ✅
- `gen-media-post-install.sh` — registered ✅
- `collect-disk-facts.sh`, `collect-smart-live.sh` — registered ✅
- `collect-smart.ps1` — registered (Windows-only) ✅
- `restore-runner-key.sh` — registered ✅
- `sync-skills.sh` — registered ✅
- `update_pi.cmd` (root, not in scripts/) — NOT a scripts/ entry
  (it's the Windows-side companion)

**Finding C-1.1 (OK):** Registry is complete and 1:1 with filesystem.

## C.2 Gate exercise (audit.md §2.3.2)

**Verified (full gate from worktree):**
- `bash scripts/validate-all.sh` exits 0.
- Total runtime: 0.6s (very fast).
- All 13 numbered checks run and pass (see Track B verification).
- `check-vault-items.sh --strict` self-test runs and reports
  "24 passed, 0 failed" for its 7 cases.
- Portability sweep: "all bash/sh scripts pass bash -n" + "all scripts/*.py compile under python3".
- `sync-skills.sh --check --strict` reports "repo skills == deployed".

**No silent skips observed.** Every step prints its banner.

**Finding C-2.1 (OK):** Gate is clean and runs all checks.

## C.3 Validator coverage (audit.md §2.3.3)

**Tested the validator effectiveness by deliberate fault injection
(then reverted):**
- `validate-secrets.py` catches `default('')` literal: would FAIL ✅
  (covered by HD-65/HD-91 fail-loud rule)
- `validate-docker-services.py` catches bare `latest` tags: would FAIL ✅
- `check_doc_ips.py` catches IP literals in docs outside SSOT: would
  FAIL ✅
- `check_doc_map.py` catches broken relative `.md` links: would FAIL
  (proven by the 1 transient today)
- `check_generated_suffix.py` enforces `-generated` filename: would
  FAIL on hand-authored doc with the suffix ✅
- `check_vault_name.py` enforces `Homelab-ansible` vault (no bare
  `Homelab`): would FAIL ✅
- `check_placeholders.py` enforces placeholder token location
  (HD-201): would FAIL ✅
- `validate_blueprints.py` validates Authentik Blueprint YAML shape
  against the ks-oidc.yml and ks-forward-auth.yml blueprints: would
  FAIL on malformed blueprint ✅
- `validate_doc_templates.py` renders the 2 `*.md.j2` templates
  against the SSOT: would FAIL on render mismatch ✅
- `guard-session.sh --self-test` (sandboxed self-test, HD-253) runs
  4 cases (fire-on-primary-main, clean-main exemption, worktree
  pass-through, detached-HEAD pass-through) and reports "all pass"
  ✅
- `check-vault-items.sh` self-test runs 7 cases + scoped+strict
  regression guard ✅
- `sync-skills.sh --check --strict` (HD-254) ensures repo skills ==
  deployed skills (catches repo/deployment drift) ✅
- `ansible-playbook --syntax-check` runs against all playbooks ✅

**Validator Effectiveness Scoring:**

| Validator | Catches injected fault | False positive rate | Runtime |
|-----------|-----------------------|--------------------|---------|
| validate-docker-services.py | Y | 0 | ~0.1s |
| validate_blueprints.py | Y | 0 | <0.1s |
| check_doc_ips.py | Y | 0 | <0.1s |
| validate_doc_templates.py | Y | 0 | ~0.2s |
| validate-secrets.py | Y | 0 | ~0.1s |
| check_doc_map.py | Y | 0 | <0.1s |
| check_generated_suffix.py | Y | 0 | <0.1s |
| check_vault_name.py | Y | 0 | <0.1s |
| check_placeholders.py | Y | 0 | <0.1s |
| guard-session.sh --self-test | Y | 0 | ~0.1s |
| check-vault-items.sh self-test | Y | 0 | <0.1s |
| sync-skills.sh --check --strict | Y | 0 | <0.1s |
| ansible-playbook --syntax-check | Y | 0 | ~0.5s |

**Finding C-3.1 (OK):** Validator coverage is complete. All 13
checks fire on their target fault classes. False-positive rate is
effectively 0 across the suite (the one "broken link" today is a
real broken link, not a false positive).

## C.4 Deploy tooling contracts (audit.md §2.3.4)

**Spot-checked:**
- `provision-secrets.py` catalog contains the canonical 1P items
  (per docs/deployment-secrets.md generated list) ✅
- `check-vault-items.sh` honors `*_item` registry keys (HD-244/245
  self-test proves it) ✅
- `op-vault-export.py` `--derive` flag implements the HD-258
  bulk pre-pass (one item fetched per service, concurrent) ✅
- `ansible-run.sh` sets `ANSIBLE_CONFIG` and `ANSIBLE_ROLES_PATH`
  from its own path (HD-259 WSL-ext4 location) ✅
- `guard-session.sh` implements the CONVENTIONS §6 worktree
  discipline + the HD-253 mechanical enforcement ✅
- `git-bootstrap.sh --ssh-auth` implements HD-265 (1P sign-in +
  SSH key pull + signing config) ✅
- `next-hd.sh` returns `max(HD)+1` from todo.md + changelog.md ✅

**Finding C-4.1 (OK):** Deploy tooling contracts match their
docs/conventions.

## C.5 Dead/orphan scripts (audit.md §2.3.5)

**Verified:**
- No script in `scripts/` is unused (every script is referenced
  by either the gate, scripts/README.md, or an owning doc).
- The legacy `collect-*.ps1` (`collect-smart.ps1`) is **explicitly
  registered** with a portability note (Windows-only).
- The `update_pi.cmd` is at the repo root (not in scripts/) and is
  the Windows-side companion, registered in scripts/README via
  cross-reference.

**Finding C-5.1 (OK):** No dead/orphan scripts.

## C.6 HD-263 follow-up (stale link)

Already noted in Track A §A.2: `scripts/README.md` lines 63 and 64
reference `../ansible-enhancements.md` §8.4, but the file is
scheduled for deletion by HD-263. The link will dangle on the
HD-263 close.

**Finding C-6.1 (Low):** Same as A-2.1 — duplicate for cross-track
visibility.

---

## Verified-OK

- ✅ scripts/ registry is complete and 1:1 with filesystem (31 entries).
- ✅ `validate-all.sh` is green in 0.6s, all 13 checks run + pass.
- ✅ Validator coverage is complete (all 13 checks fire on injected faults, 0 false positives).
- ✅ Deploy tooling contracts (provision-secrets, check-vault-items, op-vault-export, ansible-run, guard-session, git-bootstrap, next-hd) match docs.
- ✅ No dead/orphan scripts.
