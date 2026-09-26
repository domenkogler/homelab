#!/usr/bin/env bash
# Repo validation gate — run before committing any change.
#   bash scripts/validate-all.sh          (Linux, macOS, Windows git-bash)
#
# Runs every automated checker referenced in docs/index.md → Conventions:
#   1. validate-docker-services.py  — compose templates + group_vars list
#   2. validate_blueprints.py       — Authentik ks-oidc.yml blueprint shape
#   3. check_doc_ips.py            — no internal IP literals outside the SSOT
#   3b. check_traefik_host_rules.py — no whitespace inside a Host() rule (HD-432: a
#                                     template-space bug made ha.ts.kogler.si unmatchable
#                                     for months while every converge reported success)
#   4. validate_doc_templates.py   — SSOT doc templates render with group_vars
#   5. validate-secrets.py         — no literal credentials in group_vars/templates
#   6. check_doc_map.py            — docs/index.md document map matches docs/ tree
#   7. check_generated_suffix.py    — every machine-generated doc carries the -generated suffix
#   8. check_vault_name.py          — vault is 'Homelab-ansible' (no bare Homelab refs, HD-189)
#   8b. check_ledger_state.py       — deployment-tasks.md is a LEDGER: deploy-gated items are
#                                     checkboxes, every OPEN one has a live todo.md row, every tick
#                                     carries a date (no HD status prose pasted into the blocks)
#   8c. check_runbook_purity.py     — deployment-manual.md is PROCEDURE: no status glyphs, no
#                                     dated/execution history, no duplicate headings, and its phase
#                                     numbering matches the ledger's (HD-253-class drift gate)
#   8d. check_vault_docs.py         — every vault item the IaC reads has a row in the secrets master
#                                     list (an undocumented prerequisite fails a true-zero deploy)
#   9. check_placeholders.py        — placeholder tokens only in designated bootstrap files (HD-201)
#  10. guard-session.sh             — session-discipline hard-gate + sandboxed self-test (HD-253):
#                                     --validate-mode fails on primary+main+DIRTY; clean-main
#                                     merge-station runs pass silently; self-test fixture asserts
#                                     the guard contract inside throwaway temp repos
#  10b. guarded-converge.sh --self-test — the post-converge liveness verdict must
#                                     refuse a crash-looping container (HD-436: a
#                                     service that exits at every start still reports
#                                     Running=true between crashes; the pinned
#                                     headscale does exactly that when both
#                                     extra-record settings are set)
#  11. testdata/check-vault-items/run.sh — check-vault-items.sh scanner self-test
#                                     (HD-244/245): *_item registry-key parsing + --strict
#                                     contract asserted on a committed synthetic mini-tree
#  12. Portability sweep — bash -n (all POSIX/bash shebang scripts) + python3 -m py_compile
#                                     (all scripts/*.py), so scripts cannot regress on the
#                                     Debian/WSL ext4 primary (HD-256); bash -n is a no-op on
#                                     hosts without bash (CI/Linux only, never Windows)
#  13. sync-skills.sh --check --strict — skill drift gate (HD-254): repo skills/ must equal
#                                     ~/.pi/agent/skills (repo = SSOT). Guarded: when
#                                     $HOME/.pi/agent/skills is absent (bare CI / non-pi laptop)
#                                     the gate SKIPs so a pi-less host never breaks validation;
#                                     on a pi-configured runner deploy is via sync-skills.sh --push.
#  14. check_todo_done.py            — todo.md §4(a) sweep: flag rows marked DONE/✅ that were
#                                     not deleted (fully-done rows must be removed; only
#                                     deploy-gated rows with a real ⏳ tail stay), and stale ⏳
#                                     markers inside struck/rejected/parked fragments (2026-09-08)
#                                     + `--self-test`: the marker GRAMMAR (case-sensitive,
#                                     word-boundary). A completion marker is a ✅/✔ glyph or an
#                                     UPPERCASE word — lowercase prose is never a claim, so
#                                     "the live config", "deliver", "olive" and a var named
#                                     `OLLAMA_KEEP_ALIVE` cannot accuse an open row of being done
#  15. check_secrets.py              — secret-SHAPE scanner over the TRACKED TIP incl. the
#                                     members of tracked .tar/.tar.gz/.zip (added 2026-09-18 after
#                                     a live spark-llm_api bearer reached origin/main inside bench
#                                     logs — validate-secrets.py only covers group_vars/roles/, so
#                                     artifacts and logs were ungated). Masked output; unreadable
#                                     archives fail too
#  16. check_self_converge_guard.py — HD-413 guardrail completeness (static): every playbook
#                                     that applies a lockout-capable role (network / storage /
#                                     wireguard / vps-hardening) imports the self-converge
#                                     guard, and imports it in pre_tasks; every lockout role
#                                     has its own guard task whose tag list equals the role's
#                                     complete selectable vocabulary, recomputed from the role
#                                     dirs; no default()/failed_when in the guard (HD-399 rule);
#                                     a role that writes under --check may not claim check_safe
#  17. testdata/self-converge-guard/run.sh — HD-413 guardrail BEHAVIOUR (runtime, WSL/CI-gated):
#                                     executes the real guard against a throwaway inventory
#                                     (this host = the controller, plus a decoy that is not) and
#                                     asserts the refuse/allow verdict for 14 invocations. The
#                                     static gate above cannot see a wrong Jinja predicate: the
#                                     first draft compared `ansible_run_tags == ['all']`, which
#                                     is always False because that magic var is a TUPLE, and
#                                     passed every static check while allowing an unfiltered
#                                     self-converge of the netdev role
#  18. check_merge_markers.py        — HD-453: no merge-conflict marker may reach a commit
#                                     (`<<<<<<<` / `>>>>>>>` / `|||||||`, plus git's exact-width
#                                     `=======` divider). A `>>>>>>>` line once survived a bad
#                                     rebase into a rebased commit of a root view file and every
#                                     gate stayed green; the gate scans the WORKING TREE, so it
#                                     also fires before the commit that would ship the marker.
#                                     `--self-test` proves it red on each marker shape and green
#                                     on the near-misses that would otherwise mute it (a Markdown
#                                     setext `=` heading; the repo's 50–60-char `=` banners in
#                                     tracked raw evidence — a first draft matching `^={7,}`
#                                     reported 78 false positives on its first run)
#  19. check_iac_backend_strings.py   — HD-404 ratchet: the number of `Prometheus|Loki` mentions
#                                     under IaC/ansible/{playbooks,group_vars} may not exceed the
#                                     recorded floor (HD-342 replaced them with VictoriaMetrics +
#                                     VictoriaLogs; the six stale claims HD-404 fixed were all in
#                                     that corpus). A RATCHET, not a per-line lie-detector: an
#                                     assertion-shaped regex caught 2 of the 4 real violations and
#                                     an allowlist would mute the gate — both measured, both in the
#                                     script's docstring. `--show` re-derives the count; the
#                                     self-test refuses a floor red at rest or absurdly loose
#  19. check_iac_backend_strings.py   — HD-404 ratchet: the count of `Prometheus|Loki` mentions under
#                                     IaC/ansible/{playbooks,group_vars} may not exceed the recorded
#                                     floor (HD-342 replaced them with VictoriaMetrics + VictoriaLogs;
#                                     the six stale claims HD-404 fixed all lived in that corpus).
#                                     A RATCHET, not a per-line lie-detector — measured: an
#                                     assertion-shaped regex caught 2 of the 4 real violations, and an
#                                     allowlist over the 28 mostly-legitimate mentions would mute the
#                                     gate (the HD-417 lesson). `--show` re-derives the count; the
#                                     self-test refuses a floor red at rest or absurdly loose
#  20. check_md_tables.py             — HD-417: no markdown table row may be WIDER than its own header.
#                                     Two misses in one session on 2026-09-21 (a swallowed newline merged two
#                                     registry rows; a description quoting `vllm|sglang` widened a 3-cell row to
#                                     12) both passed every validator because nothing counts cells. Wider-only on
#                                     purpose: 14 NARROWER rows are legal GFM (short rows, struck-through PARKED
#                                     rows) and asserting equality printed 41 findings in 12 files — a gate that
#                                     shouts gets muted. `--self-test` plants a stray pipe (inside a code span,
#                                     where it still cuts) and a merged row, and asserts clean tables stay clean
#  21. knx-hass-gen.py --self-test    — HD-439: the KNX generator's own address guard. `--check` (manual, needs
#                                     xknxproject + the .knxproj) asserts every address the generator emits is
#                                     PUBLISHED IN THE ETS PROJECT — the one invention risk left is the 19-address
#                                     hand-typed sensor appendix, because HA fails per-entity on an address the
#                                     bus does not know. This item runs the pure-stdlib half, because the runner
#                                     has no xknxproject and nothing in the repo declares it
#                                     (import xknxproject fails here — measured 2026-09-25)
#   + ansible-playbook --syntax-check across all playbooks (WSL/CI-gated, HD-197)
#
# Exit 0 only when all pass. `set -e` stops at the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."

# Python launcher: prefer python3 (Linux/CI), fall back to py -3 (Windows).
# PYTHONUTF8=1 keeps Windows console output from crashing on non-ASCII.
if command -v python3 >/dev/null 2>&1; then
  PY="python3"
elif command -v py >/dev/null 2>&1; then
  PY="py -3"
else
  echo "error: no python3 or py on PATH" >&2
  exit 1
fi
export PYTHONUTF8=1

echo "== guard-session.sh --validate-mode (session-discipline hard gate, HD-253) =="
bash scripts/guard-session.sh --validate-mode

echo "== guard-session.sh --self-test (sandboxed guard fixture, HD-253) =="
bash scripts/guard-session.sh --self-test

echo "== guarded-converge.sh --self-test (post-converge liveness verdict, HD-436) =="
bash scripts/guarded-converge.sh --self-test

echo "== validate-docker-services.py =="
$PY scripts/validate-docker-services.py

echo "== validate_blueprints.py =="
$PY scripts/validate_blueprints.py

echo "== check_doc_ips.py =="
$PY scripts/check_doc_ips.py

echo "== check_traefik_host_rules.py =="
$PY scripts/check_traefik_host_rules.py

echo "== validate_doc_templates.py =="
$PY scripts/validate_doc_templates.py

echo "== validate-secrets.py =="
$PY scripts/validate-secrets.py

echo "== check_doc_map.py =="
$PY scripts/check_doc_map.py

echo "== check_generated_suffix.py =="
$PY scripts/check_generated_suffix.py

echo "== check_vault_name.py =="
$PY scripts/check_vault_name.py

echo "== check_ledger_state.py (ledger = checkboxes, open rows only, ticks dated) =="
$PY scripts/check_ledger_state.py

echo "== check_runbook_purity.py (runbook = imperative procedure only) =="
$PY scripts/check_runbook_purity.py

echo "== check_vault_docs.py (every IaC-read vault item is documented) =="
$PY scripts/check_vault_docs.py

echo "== check_placeholders.py =="
$PY scripts/check_placeholders.py

echo "== check_todo_done.py (CONVENTIONS §4(a) done-row sweep) =="
$PY scripts/check_todo_done.py

echo "== check_todo_done.py --self-test (marker grammar: glyphs or UPPERCASE words, never prose) =="
$PY scripts/check_todo_done.py --self-test

echo "== check_secrets.py (secret shapes in the tracked tip, archive members included) =="
$PY scripts/check_secrets.py

echo "== check_dns_seed_drift.py (Technitium split-horizon seed contract, HD-341 parity) =="
$PY scripts/check_dns_seed_drift.py

echo "== check_self_converge_guard.py (HD-413 guardrail completeness, static) =="
# Runs on any host with python3+PyYAML — it reads YAML, it does not need Ansible.
$PY scripts/check_self_converge_guard.py

echo "== testdata/check-vault-items/run.sh (scanner self-test, HD-244/245) =="

echo "== testdata/self-converge-guard/run.sh (HD-413 verdict matrix, runtime) =="
# Needs a functional ansible-playbook (it EXECUTES the guard) — SKIPs itself on hosts where
# Ansible is absent/non-functional (native Windows) or `uname` is missing, like the syntax gate.
bash scripts/testdata/self-converge-guard/run.sh

echo "== portability sweep (bash -n + python3 -m py_compile, HD-256) =="
# bash -n every POSIX/bash shebang script under scripts/ (incl. the testdata runner).
# bash-shebang scripts must parse cleanly on the Debian/WSL ext4 primary (HD-259);
# POSIX 'sh' scripts (collect-disk-facts.sh, collect-smart-live.sh) are checked here
# too because bash is a POSIX superset and the repo gates run under bash. Silent no-op
# on hosts without bash (Windows) — those scripts are exercised under WSL/CI.
if command -v bash >/dev/null 2>&1; then
  bash_fail=0
  for f in scripts/*.sh scripts/testdata/check-vault-items/run.sh \
           scripts/testdata/self-converge-guard/run.sh; do
    [ -f "$f" ] || continue
    case "$(head -n1 "$f")" in
      *bash|*sh)
        bash -n "$f" >/dev/null 2>&1 || { echo "bash -n FAIL: $f" >&2; bash_fail=$((bash_fail+1)); }
        ;;
    esac
  done
  [ "$bash_fail" -eq 0 ] || exit 1
  echo "OK: all bash/sh scripts pass bash -n"
else
  echo "SKIP: bash not on PATH — bash -n sweep runs under WSL/CI"
fi

# python3 -m py_compile every scripts/*.py (byte-compiles to gitignored __pycache__).
if command -v python3 >/dev/null 2>&1; then
  py_fail=0
  for f in scripts/*.py; do
    [ -f "$f" ] || continue
    python3 -m py_compile "$f" >/dev/null 2>&1 || { echo "py_compile FAIL: $f" >&2; py_fail=$((py_fail+1)); }
  done
  [ "$py_fail" -eq 0 ] || exit 1
  echo "OK: all scripts/*.py compile under python3"
else
  echo "SKIP: python3 not on PATH — py_compile sweep skipped"
fi

echo "== sync-skills.sh --check --strict (skill drift gate, HD-254) =="
# repo skills/ must equal ~/.pi/agent/skills (repo = SSOT). Guarded: a host without a
# pi agent (bare CI / non-pi laptop) has no ~/.pi/agent/skills — the gate SKIPs there so
# it never breaks validation on a stateless runner; on a pi-configured primary the check
# is real and deploy is an explicit 'sync-skills.sh --push'.
if [ -d "$HOME/.pi/agent/skills" ]; then
  bash scripts/sync-skills.sh --check --strict
else
  echo "SKIP: no ~/.pi/agent/skills on this host (bare CI / non-pi laptop) — skill gate runs where pi is configured"
fi

echo "== check_iac_backend_strings.py (HD-404: retired-backend mentions may not regrow) =="
$PY scripts/check_iac_backend_strings.py

echo "== check_iac_backend_strings.py --self-test (HD-404 ratchet canary) =="
$PY scripts/check_iac_backend_strings.py --self-test

echo "== knx-hass-gen.py --self-test (HD-439: emitted addresses must exist in the ETS project) =="
$PY scripts/knx-hass-gen.py --self-test

echo "== check_md_tables.py (HD-417: no table row wider than its header) =="
$PY scripts/check_md_tables.py

echo "== check_md_tables.py --self-test (HD-417 cell-count canary) =="
$PY scripts/check_md_tables.py --self-test

echo "== check_iac_backend_strings.py (HD-404: retired-backend names may not regrow) =="
$PY scripts/check_iac_backend_strings.py

echo "== check_iac_backend_strings.py --self-test (HD-404 ratchet canary) =="
$PY scripts/check_iac_backend_strings.py --self-test

echo "== check_merge_markers.py (HD-453: no conflict markers in tracked files) =="
$PY scripts/check_merge_markers.py

echo "== check_merge_markers.py --self-test (HD-453 canary) =="
$PY scripts/check_merge_markers.py --self-test

echo "== ansible-playbook --syntax-check (WSL/CI-gated) =="
# HD-197: catch unresolvable modules / broken YAML in every playbook at gate time.
# Requires the Ansible venv (WSL/CI); skipped gracefully on native Windows like the
# Ansible render path (see scripts/README.md).
# HD-256: like ansible-run.sh, export ANSIBLE_CONFIG + ANSIBLE_ROLES_PATH so the
# role path resolves when running from the repo root on the Debian/WSL primary
# (otherwise ansible finds no config here and every `roles: - xxx` fails to resolve).
REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$REPO_ROOT/IaC/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO_ROOT/IaC/ansible/roles"
if command -v ansible-playbook >/dev/null 2>&1 && ansible-playbook --version >/dev/null 2>&1; then
  for pb in IaC/ansible/site.yml IaC/ansible/playbooks/*.yml; do
    ansible-playbook -i IaC/ansible/inventory.ini "$pb" --syntax-check >/dev/null
  done
  echo "OK: all playbooks pass --syntax-check"
else
  echo "SKIP: ansible-playbook not functional on this host (absent or native-Windows WinError 87) — syntax gate runs under WSL/CI"
fi

echo "OK: all validators passed"
