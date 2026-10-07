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
#                                     Second half (2026-10-06): a row whose FIRST CELL IS A LINK is an identity,
#                                     so one table may not carry the same link twice — added because
#                                     scripts/README.md listed install-pi-wsl.sh on two rows with every gate
#                                     green. Link-keyed only, measured: the loose "any repeated first cell" form
#                                     prints 58 findings here and would be muted; this form is 0 at rest and
#                                     still catches the real pair.
#  21. knx-hass-gen.py --self-test    — HD-439: the KNX generator's own address guard. `--check` (manual, needs
#                                     xknxproject + the .knxproj) asserts every address the generator emits is
#                                     PUBLISHED IN THE ETS PROJECT — the one invention risk left is the 19-address
#                                     hand-typed sensor appendix, because HA fails per-entity on an address the
#                                     bus does not know. This item runs the pure-stdlib half, because the runner
#                                     has no xknxproject and nothing in the repo declares it
#                                     (import xknxproject fails here — measured 2026-09-25)
#  22. check_spark_llm_gate.py        — HD-469: the spark LLM profile gate must be PROVEN OFFLINE.
#                                     `roles/spark-llm-profile` is the only thing between a one-var flip
#                                     and a global OOM that Docker reports as `OOMKilled: false`, yet its
#                                     live test costs a ~20-minute engine boot on the box that serves the
#                                     operator. The checker evaluates the ROLE'S OWN patterns (extracted
#                                     from the task YAML, never re-typed) + the group_vars constants over
#                                     every authored profile, then breeds a canary per invariant and
#                                     REFUSES a canary that passes — a gate that cannot fail is not a
#                                     gate (CONVENTIONS §6). PyYAML-only: no Ansible, no network, no box
#  23. laptop-llm.py gate --self-test — HD-474: the laptop serving-leg invariants must be
#                                     PROVEN OFFLINE, same rule as item 22. The deploy-time `gate`
#                                     is EXPECTED to fail on an unprobed box (uncertified profiles,
#                                     an unpinned LM Studio auto-updater, pending probes), so what is
#                                     committed as a hard gate is the canary self-test: 13 canaries,
#                                     one per invariant, each must FAIL. A budget that exceeds the
#                                     iGPU carve, a client window above num_ctx, an image claim on a
#                                     GGUF with no projector on disk, q8_0 KV without flash attention
#                                     (llama.cpp silently ignores it), MTP+mmproj (unsupported
#                                     together) and `certified: true` without evidence each get a
#                                     canary. Stdlib + PyYAML, no server, no token, no Windows.
#  24. laptop-llm.py probe-client       — HD-474: the client contract may not drift AHEAD of the
#                                     engine. Compares providers.laptop-lmstudio in models-spec.yml
#                                     against the ACTIVE profile (contextWindow / maxTokens / input
#                                     / reasoning). Offline: no request leaves the box. Skips itself
#                                     on a host the provider is not scoped to (`hosts:`), so CI and
#                                     the oldsrv cockpit are unaffected.

#  25. spark-llm-render-matrix.py       — HD-489: every authored profile must RENDER offline.
#  26. check_doc_path_refs.py            — HD-490: every local path a doc or IaC comment cites
#                                     resolves to something in the tree (621 files, 539 targets).
#                                     Links resolve from the containing file, bare paths from the repo
#                                     root; generated-doc templates resolve from the document
#                                     render-docs.yml puts them into. Globs, placeholders, the frozen
#                                     archives, git-ignored generated files and prose that says the
#                                     file is missing are exempt, each for a stated reason.
#                                     `--self-test` breeds a dangling ref and refuses a green run.
#  27. sync-extensions.sh --self-test + --check --strict — extension drift gate (HD-254 family):
#                                     repo pi-agent/extensions/ must equal ~/.pi/agent/extensions.
#                                     Deliberately NOT identical to item 13: a DEPLOYED-ONLY extension
#                                     (remote-bash.ts on the Win11 host — Windows sshpass.exe and
#                                     drive-letter paths, out of the repo on purpose) is reported as
#                                     LOCAL and does NOT fail the gate, or the laptop seat would fail
#                                     forever and the gate would get muted (the HD-417 failure mode). --self-test
#                                     asserts both halves. Guarded like item 13: with no
#                                     ~/.pi/agent/extensions on the host, the check SKIPs.
#                                     16 arms × the same docker-compose.yml.j2 the engine
#                                     boots from, with the parity assertions that keep the
#                                     four certified lanes byte-identical to what serves today.
#  28. check_zone_kogler_si_parity.py — HD-436: deriving the `kogler.si` answer plane from ONE list
#                                     must not CHANGE an answer. A static contract checker proves a row
#                                     follows the rules; it cannot see an answer PLANE change: an early
#                                     draft of the derivation dropped apex/litellm/logs from the primary
#                                     (a `when` gate comparing `item.name` against a var that resolved to
#                                     the STRING repr of a list, so `in` became a SUBSTRING test) and
#                                     `check_dns_seed_drift.py` — which only knew literal inline `loop:`
#                                     lists — reported '43 records' from the hand-authored era while
#                                     reading ZERO rows from the derived one. RED on the branch, GREEN on
#                                     main: a contract gate and the thing it guards can both be blind.
#                                     This gate diffs derived-vs-golden (the pre-derivation output,
#                                     captured in scripts/testdata/), fails on a dropped name, a changed
#                                     IP, a name moving between the plain and `.ts` namespaces, a
#                                     consumer that answers nothing, and a golden field silently dropped
#                                     from a row. `--self-test` proves it refuses all five.
#  29. install-tmux-conf.sh --self-test + --check --strict — seat terminal-harness gate
#                                     (HD-1085): repo pi-agent/tmux/tmux.conf == ~/.tmux.conf AND the
#                                     config actually TAKES EFFECT. The "and" is the whole item: a tmux
#                                     config that errors mid-load leaves the options at their DEFAULTS
#                                     while the caller gets exit 0 and empty stderr, so a byte-compare
#                                     of two identical files can sit next to a seat with no mouse and
#                                     no clipboard (measured six ways, docs/pi-harness.md §5b). The
#                                     self-test therefore mutates FIXTURES, not the checker: seven
#                                     canaries, two of them a byte-identical SSOT/target pair that is
#                                     inert by construction (one bad command mid-file; the nested
#                                     wrapped if-shell that broke the live seat) — a `cmp` says SAME on
#                                     both and the gate must still go RED. Plus the OSC 52 canary: same
#                                     fixture with the `Ms` override stripped must emit NOTHING, or the
#                                     emission arm is passing for the wrong reason. Drift check guarded
#                                     like items 13/27: with no ~/.tmux.conf on the host it SKIPs (a
#                                     stateless runner has no seat here); ineffectiveness fails in every
#                                     mode because it is a defect, not a seat state.
#  30. check_yaml_dup_keys.py    — HD-1098: no YAML mapping may declare the same key twice.
#                                     Ansible resolves a duplicate key by KEEPING THE LAST one and
#                                     printing `[WARNING]: Found duplicate mapping key … Using last
#                                     defined value only.` — the playbook still runs, --syntax-check
#                                     still passes, so the FIRST definition is dead text that keeps
#                                     looking authoritative (CONVENTIONS §6's silent-failure class).
#                                     Three were live on 2026-10-08, none caught by any gate: a task
#                                     in roles/monitoring with two `tags:` (HD-450's hygiene-exporter
#                                     task silently lost the `hygiene` tag) and two fragment vars in
#                                     group_vars/spark.yml defined twice by a duplicated section.
#                                     Walks the RAW node tree (compose_all), not loader hooks — a hook
#                                     version of this check saw 1 of the 3. `--self-test` breeds the
#                                     canary shapes, pins the legal near-misses (merge keys `<<`,
#                                     sibling mappings, multi-doc, Jinja scalars) and proves the
#                                     corpus was actually walked. Archives (brainstorming/,
#                                     docs/assets/references/, reports/) are excluded by path.
#   + ansible-playbook --syntax-check across all playbooks (WSL/CI-gated, HD-197) — its stderr is
#                                     kept and the duplicate-mapping-key warning fails the run, the
#                                     second witness for HD-1098 (it sees role task files as ansible
#                                     loads them, at no extra ansible cost).
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

# Activate the runner venv when this host has one (2026-10-06). WHY this exists: the Python
# validators import jinja2 + PyYAML at module scope, and on a Debian/WSL seat those arrive ONLY as
# pip deps of `pip install ansible` inside ~/ansible-venv (bootstrap-runner.sh §3) — dpkg has never
# carried python3-jinja2/python3-yaml here. The venv enters PATH through the
# `source ~/ansible-venv/bin/activate` line bootstrap-runner.sh appends to ~/.bashrc, and a
# NON-interactive shell never reaches that line: ~/.bashrc's own interactivity guard returns first.
# Measured consequence: from cron/pi/a converge the gate died at validate-docker-services.py line 26
# (`from jinja2 import ...` ModuleNotFoundError) while the SAME commit run from an interactive shell
# went green two hours earlier, and the ansible --syntax-check half degraded to SKIP for the same
# reason (ansible-playbook lives in the same bin/). That is "validates on my machine" in a gate, and
# a green-red-per-invocation gate is not a gate. Sourced exactly like ansible-run.sh; NEVER required,
# so a bare CI runner keeps its system python3 instead of failing on a missing venv.
if [ "$PY" = "python3" ] && [ -f "$HOME/ansible-venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  . "$HOME/ansible-venv/bin/activate"
  echo "launcher: ~/ansible-venv activated — python3=$(command -v python3) ansible-playbook=$(command -v ansible-playbook || echo absent)"
fi

# Preflight, before 20 validators can fail one at a time: the interpreter chosen above must carry
# what the validators import at module scope. Without this the first signal is a traceback fifteen
# steps deep, which reads like a broken validator rather than a missing venv (that is precisely how
# the 2026-10-06 incident got misread).
if ! "$PY" -c "import jinja2, yaml" >/dev/null 2>&1; then
  echo "FAIL: launcher '$PY' has no jinja2/PyYAML — the Python validators cannot run." >&2
  echo "      On a Debian/WSL runner both arrive as pip deps of ansible inside ~/ansible-venv:" >&2
  echo "        bash scripts/bootstrap-runner.sh          # or: source ~/ansible-venv/bin/activate" >&2
  echo "      On a bare CI host:  python3 -m pip install jinja2 PyYAML" >&2
  echo "      Refusing to continue: a gate that cannot import is not a gate." >&2
  exit 1
fi

echo "== guard-session.sh --validate-mode (session-discipline hard gate, HD-253) =="
bash scripts/guard-session.sh --validate-mode

echo "== guard-session.sh --self-test (sandboxed guard fixture, HD-253) =="
bash scripts/guard-session.sh --self-test

echo "== guarded-converge.sh --self-test (post-converge liveness verdict, HD-436) =="
bash scripts/guarded-converge.sh --self-test

echo "== git-bootstrap.sh --self-test (each 1Password refusal state says the right thing) =="
# HD-485 runner lesson: one grep of `op vault list` was answering three different questions, so
# the script told a signed-in operator to sign in, on a loop. The fixtures are throwaway and the
# children run under a sandbox HOME/SRC, so this is offline and side-effect-free.
bash scripts/git-bootstrap.sh --self-test

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

echo "== check_zone_kogler_si_parity.py (derived zone answers what the hand-authored sources did, HD-436) =="
$PY scripts/check_zone_kogler_si_parity.py
$PY scripts/check_zone_kogler_si_parity.py --self-test

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

echo "== check_md_tables.py (HD-417 width rule + 2026-10-06 duplicate-key rule) =="
$PY scripts/check_md_tables.py

echo "== check_md_tables.py --self-test (HD-417 cell-count canary + duplicate-key canary) =="
$PY scripts/check_md_tables.py --self-test

echo "== check_iac_backend_strings.py (HD-404: retired-backend names may not regrow) =="
$PY scripts/check_iac_backend_strings.py

echo "== check_iac_backend_strings.py --self-test (HD-404 ratchet canary) =="
$PY scripts/check_iac_backend_strings.py --self-test

echo "== check_merge_markers.py (HD-453: no conflict markers in tracked files) =="
$PY scripts/check_merge_markers.py

echo "== check_merge_markers.py --self-test (HD-453 canary) =="
$PY scripts/check_merge_markers.py --self-test

echo "== check_spark_llm_gate.py (HD-469: spark LLM profile matrix + gate canaries) =="
$PY scripts/check_spark_llm_gate.py

echo "== check_doc_path_refs.py (HD-490: a path a doc cites must exist) =="
# Docs and IaC comments cite several hundred paths between them, and until this item existed
# nothing in the repo looked at a single one of them — which is how a lane brief shipped
# `scripts/llm_serving_bench.py`, a tool that was never in the tree, as if it were the harness
# for a 20-minute boot leg. First run: 47 stale citations, all fixed.
$PY scripts/check_doc_path_refs.py

echo "== check_doc_path_refs.py --self-test (HD-490 canary) =="
$PY scripts/check_doc_path_refs.py --self-test

echo "== check_yaml_dup_keys.py (HD-1098: a duplicate YAML key is a silent no-op) =="
$PY scripts/check_yaml_dup_keys.py

echo "== check_yaml_dup_keys.py --self-test (HD-1098 canaries + corpus probe) =="
$PY scripts/check_yaml_dup_keys.py --self-test

echo "== spark-llm-render-matrix.py (HD-489: every profile must RENDER, not just validate) =="
# The gate proves the ARITHMETIC; this proves the RENDER. A profile can satisfy every
# invariant and still render an engine that boots for 20 minutes and then cannot find its
# PLE table, because the catalogue references images and host roots by NAME and only the
# compose template turns those names into paths. Runs the real template, offline, per arm.
$PY scripts/spark-llm-render-matrix.py

echo "== laptop-llm.py gate --self-test (HD-474: laptop serving-leg gate must be PROVEN OFFLINE) =="
# Deliberately NOT the deploy-time `gate`: on a box whose probes have never run, that gate fails
# on purpose (uncertified profiles + unpinned auto-updating engine). The hard gate is the canary
# self-test — the invariants must be proven to bite. See scripts/README.md.
$PY scripts/laptop-llm.py gate --self-test

echo "== laptop-llm.py probe-client (HD-474: client contract may not drift ahead of the engine) =="
# Offline drift check against models-spec.yml; self-skips off the scoped host (`hosts:`).
$PY scripts/laptop-llm.py probe-client

echo "== sync-extensions.sh (HD-254 family: repo pi-agent/extensions == deployed) =="
# Item 13's sibling for hand-written extensions. The self-test runs everywhere (it is
# sandboxed in a temp dir and touches nothing), because an unchecked drift detector
# cannot be trusted to keep detecting; the drift check itself is guarded like the skill
# gate — no ~/.pi/agent/extensions means no pi seat here, so it SKIPs rather than
# breaking validation on a stateless runner.
bash scripts/sync-extensions.sh --self-test
if [ -d "$HOME/.pi/agent/extensions" ]; then
  bash scripts/sync-extensions.sh --check --strict
else
  echo "SKIP: no ~/.pi/agent/extensions on this host — extension gate runs where pi is configured (deploy: sync-extensions.sh --push)"
fi

echo "== install-tmux-conf.sh (HD-1085: repo pi-agent/tmux/tmux.conf == ~/.tmux.conf AND effective) =="
# The self-test runs everywhere: it is sandboxed in a temp dir, starts its own throwaway
# servers on private sockets, and touches no real ~/.tmux.conf. It exists because a tmux
# config that fails mid-load returns 0 and leaves the defaults standing — so the ONLY
# proof is loading the file and reading the options back, which is what these canaries
# do (and what caught this script's own first bug: `-eq 1` against a failure COUNT also
# matches the SKIP code 2, which made the inert canaries pass).
bash scripts/install-tmux-conf.sh --self-test
if [ -f "$HOME/.tmux.conf" ]; then
  bash scripts/install-tmux-conf.sh --check --strict
else
  echo "SKIP: no ~/.tmux.conf on this host — the seat harness gate runs where tmux is installed (deploy: install-tmux-conf.sh --push)"
fi

echo "== ansible-playbook --syntax-check (WSL/CI-gated) =="
# HD-197: catch unresolvable modules / broken YAML in every playbook at gate time.
# Requires the Ansible venv (WSL/CI); skipped gracefully on native Windows like the
# Ansible render path (see scripts/README.md).
# 23. HD-489/HD-380 gate-7 reader: the bucketing bug this tool exists to prevent was a real
# false-RED (a naive (max-first)/hours over the live CSV printed 2,663 MiB/h because gpu_top_pid
# is not always the engine), so the classifier and its "empty window is never a pass" rule are
# gated here rather than trusted. Read-only over the CSV; synthetic fixtures only.
echo "== gate7-read.py --self-test (HD-489 gate-7 bucketing: mixed-pid artifact, bounded fill, leak) =="
python3 spark/bench/gate7-read.py --self-test

# HD-256: like ansible-run.sh, export ANSIBLE_CONFIG + ANSIBLE_ROLES_PATH so the
# role path resolves when running from the repo root on the Debian/WSL primary
# (otherwise ansible finds no config here and every `roles: - xxx` fails to resolve).
REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$REPO_ROOT/IaC/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO_ROOT/IaC/ansible/roles"
if command -v ansible-playbook >/dev/null 2>&1 && ansible-playbook --version >/dev/null 2>&1; then
  # HD-1098: ansible's own parser is the second witness for duplicate mapping keys. It prints
  # `Found duplicate mapping key … Using last defined value only.` on stderr and carries on, so
  # the warning has to be caught here or the FIRST definition silently stays dead.
  ANSIBLE_ERR_LOG="$(mktemp)"
  for pb in IaC/ansible/site.yml IaC/ansible/playbooks/*.yml; do
    rc=0
    ansible-playbook -i IaC/ansible/inventory.ini "$pb" --syntax-check >/dev/null 2>"$ANSIBLE_ERR_LOG" || rc=$?
    if grep -q "Found duplicate mapping key" "$ANSIBLE_ERR_LOG"; then
      echo "FAIL: ansible reported a duplicate mapping key while parsing $pb — it keeps the LAST"
      echo "      definition and drops the first, so the earlier one is dead (HD-1098):"
      grep -A3 "Found duplicate mapping key" "$ANSIBLE_ERR_LOG" | sed 's/^/  /'
      rm -f "$ANSIBLE_ERR_LOG"; exit 1
    fi
    if [ "$rc" -ne 0 ]; then
      # unchanged HD-197 semantics: a real syntax failure still stops the run (the duplicate-key
      # leg above must not have turned this loop into a warning collector)
      cat "$ANSIBLE_ERR_LOG" >&2
      rm -f "$ANSIBLE_ERR_LOG"; exit "$rc"
    fi
  done
  rm -f "$ANSIBLE_ERR_LOG"
  echo "OK: all playbooks pass --syntax-check"
else
  echo "SKIP: ansible-playbook not functional on this host (absent or native-Windows WinError 87) — syntax gate runs under WSL/CI"
fi

echo "OK: all validators passed"
