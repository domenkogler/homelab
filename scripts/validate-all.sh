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
#                                     contract asserted on a committed synthetic mini-tree.
#                                     ⚠ It was ADVERTISED AND NOT RUN from the day it was numbered:
#                                     the header echoed, then nothing invoked it (only the
#                                     portability `bash -n` sweep touched the file). 2026-10-09.
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
#                                     archives fail too. + `--self-test`: the shapes are run through
#                                     a literal PREFILTER for speed (16.5 s -> 5.0 s of a 58 s gate),
#                                     so the self-test proves every shape still fires, on a plain
#                                     file AND inside an archive member, plus a case-folded shape
#                                     (`PAſSWORD`, which a lower() prefilter skips) and a MUTATED
#                                     prefilter literal that must lose the hit — a wrong literal has
#                                     to fail the gate, not quietly narrow the scanner.
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
#                                     asserts the refuse/allow verdict for 18 legs (`grep -c
#                                     '^expect '` — the header said 14 for a while and rotted).
#                                     The legs are independent and side-effect free, so they
#                                     LAUNCH concurrently now: 11.4 s -> 3.4 s, with the verdict
#                                     assertions unchanged and printed in the declared order
#                                     (mutation-checked: flipped expectation, neutered DUMMY
#                                     output, and a leg whose rc never arrives — all three go RED)
#                                     The static gate above cannot see a wrong Jinja predicate: the
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
#                                     (a machine-local file one seat carries on purpose) is reported
#                                     as LOCAL and does NOT fail the gate, or that seat would fail
#                                     forever and the gate would get muted (the HD-417 failure mode).
#                                     The ONE exception is the script's RETIRED list (HD-1110): names
#                                     the repo deleted — host-status.ts, remote-bash.ts, both retired
#                                     2026-10-08 — which --push removes and --check --strict fails
#                                     while still deployed, because --push preserving a deployed-only
#                                     file would otherwise keep a deleted extension loaded forever.
#                                     --self-test asserts all three halves (missing fails, extra is
#                                     kept, retired is removed). Guarded like item 13: with no
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
#  31. check_todo_done.py --refs   — a `prompt*.md` brief may only name a row that EXISTS.
#                                     CONVENTIONS §4 DELETES a closed row and renumbers a colliding
#                                     id, so every brief that named one keeps a pointer to nothing —
#                                     and no gate looked. The status-claim half of this checker is
#                                     blind to it by construction: a false pointer is usually a
#                                     HISTORICAL mention of closed work, never an open-work claim.
#                                     On its first run (at be7a4684) every finding was exactly that
#                                     class. FAILs naming `file:line`.
#                                     ⚠ Asymmetric ON PURPOSE, keep it that way: a STATUS claim is
#                                     read from `prompt.md` alone (that file IS the handoff), a
#                                     REFERENCE is checked across every root brief (a dead id
#                                     misleads whoever reads it). Root-level only, non-recursive: a
#                                     `prompt.md` under `brainstorming/obsolete/` is a frozen
#                                     artifact, not a handoff. Both directions are canaried by the
#                                     `check_todo_done.py --self-test` item, which also refuses a
#                                     real brief that dangles (the fixture green must not be the
#                                     only proof the pass can be green). Milliseconds: a glob over
#                                     the briefs, no subprocess, so the pool does not notice it.
#   + ansible-playbook --syntax-check across all playbooks (WSL/CI-gated, HD-197) — its stderr is
#                                     kept and the duplicate-mapping-key warning fails the run, the
#                                     second witness for HD-1098 (it sees role task files as ansible
#                                     loads them, at no extra ansible cost). PLAYBOOKS RUN IN
#                                     PARALLEL since 2026-10-09 (8.4 s -> 3.0 s on 8 cores): the cost
#                                     was 17 × interpreter startup, not work; each leg keeps its own
#                                     stderr file, so the duplicate-key witness is unchanged.
#
# HOW THIS RUNS (2026-10-09, HD-1117): the items above are QUEUED and run CONCURRENTLY,
#   8 in flight on an 8-core runner — 32 s -> 12 s. They are independent: every check is
#   read-only over the repo (the sweeps write only gitignored __pycache__, the self-tests
#   sandbox in temp dirs / private sockets, nothing here writes to the tree).
#   The numbered list above is the WHY of each check and is HISTORICAL — item numbers moved
#   when the long legs were moved to the front of the queue; `--list` prints the real set,
#   in launch order. Long items first, because queue order IS the schedule.
#
# Exit 0 only when all pass. ⚠ It no longer stops at the first failure: `set -e` could not
# survive a pool, and stopping early was worth less than the answer — one broken file used to
# hide the other nine. Every item runs, every failure prints with its own output, and the run
# ends with the list of what failed. `--serial` restores one-at-a-time (33 s) for bisecting a
# host that misbehaves under concurrency; `--only <substring>` runs a subset.
#
# ⚠ A gate that is not invoked is the same as a gate that is deleted, and this file proved it
#   on itself: while removing a DUPLICATED `check_iac_backend_strings.py` block (HD-404) the
#   edit matched both copies and deleted BOTH — every run from 223b571b to 17d8dd13 was green
#   while item 19 ran never, and the self-test that is supposed to catch a muted ratchet was
#   muted with it. The parallel rewrite restored it; `--list | wc -l` (59) against a previous
#   commit is now the audit that catches this class — do not trust the numbered comments.
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
  echo "launcher: ~/ansible-venv activated — python3=$(command -v python3) ansible-playbook=$(command -v ansible-playbook || echo absent)" >&2
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


# --- CLI: --list (print the items and stop), --only SUBSTR (run a subset),          #
#     --serial (one at a time, the pre-parallel behaviour, for bisecting an issue).  #
ONLY=""; LIST=0; SERIAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list)   LIST=1 ;;
    --serial) SERIAL=1 ;;
    --only)   shift; [ $# -gt 0 ] || { echo "error: --only needs a substring" >&2; exit 2; }; ONLY="$1" ;;
    --only=*) ONLY="${1#--only=}" ;;
    -h|--help) echo "usage: bash scripts/validate-all.sh [--list] [--only SUBSTRING] [--serial]"; exit 0 ;;
    *) echo "note: ignoring unknown argument '$1'" >&2 ;;
  esac
  shift
done

# SERIAL, FIRST, FAIL-FAST — nothing else should run if this fails: HD-253 session
# discipline. --validate-mode hard-fails on primary+main+DIRTY; a clean-main merge-station
# run stays exempt, session worktrees and detached-HEAD/CI pass through.
if [ "$LIST" != 1 ]; then
  echo "== guard-session.sh --validate-mode (session-discipline hard gate, HD-253) =="
  bash scripts/guard-session.sh --validate-mode
fi

# --------------------------------------------------------------------------- #
# Runner — the checks below are QUEUED and run CONCURRENTLY.                #
#                                                                           #
# WHY: the gate was 58 s and the trace said why — ~50 items, of which a dozen cost   #
# 0.3–5 s and thirty cost 20–80 ms, and ALL of them were waiting on each other.      #
# The checks are independent: every one of them is read-only over the repo (the two  #
# sweeps write only gitignored __pycache__, the self-tests sandbox themselves in      #
# temp dirs / private sockets, and nothing here writes to the tree). Parallelism is   #
# therefore free: 32 s → single digits, with no change to what is checked.            #
#                                                                                    #
# SEMANTICS CHANGED, on purpose: `set -e` used to stop at the FIRST failure, so one  #
# broken file hid the other nine. Now every item runs and the report prints every     #
# failure with its own output. Exit is 0 only when all passed. `--serial` restores    #
# the old one-at-a-time behaviour for debugging.                                      #
#                                                                                    #
# Two things stay SERIAL and fail fast, because everything else depends on them:      #
# the interpreter preflight above (a gate that cannot import is not a gate) and       #
# `guard-session.sh --validate-mode` (a primary+main+dirty checkout must not spend    #
# 10 s discovering that its edits are in the wrong place).                            #
# --------------------------------------------------------------------------- #
RUN="$(mktemp -d)"; trap 'rm -rf "$RUN"' EXIT
MAXPAR=4
command -v nproc >/dev/null 2>&1 && MAXPAR="$(nproc)"
[ "$SERIAL" = 1 ] && MAXPAR=1
# The two ansible legs spawn children of their own; give them half the pool each so a
# nested fan-out cannot multiply the process count past the cores (8 slots → 4 each).
GATE_NPAR=4
command -v nproc >/dev/null 2>&1 && GATE_NPAR="$(( $(nproc) / 2 > 2 ? $(nproc) / 2 : 2 ))"
export GATE_NPAR
echo "gate: $MAXPAR items in flight (GATE_NPAR=$GATE_NPAR for the ansible legs)" >&2

n_items=0; labels=(); pids=(); states=()

_queue() {
  local label="$1"; shift
  local i=$n_items; n_items=$((n_items+1))
  labels+=("$label")
  if [ "$LIST" = 1 ]; then states+=("listed"); pids+=("0"); return 0; fi
  if [ -n "$ONLY" ] && [[ "$label" != *"$ONLY"* ]]; then states+=("filtered"); pids+=("0"); return 0; fi
  ( "$@" >"$RUN/$i.log" 2>&1; echo "$?" >"$RUN/$i.rc" ) &
  local pid=$!
  states+=("run"); pids+=("$pid")
  printf '  -> %2d  %s\n' "$i" "$label" >&2
  if [ "$MAXPAR" -le 1 ]; then
    wait "$pid" >/dev/null 2>&1 || true     # --serial: block here, no polling in the loop
  else
    while [ "$(jobs -rp | wc -l)" -ge "$MAXPAR" ]; do sleep 0.05; done
  fi
}

# item "<label>" <command...>   — one command, run in the background
item() { local label="$1"; shift; _queue "$label" "$@"; }

# item_blk "<label>" <function> — a multi-command block; the function is defined above
item_blk() { _queue "$1" "$2"; }

_report() {
  local i rc fails=0 ran=0 filt=0
  for i in "${!labels[@]}"; do
    local label="${labels[$i]}"
    case "${states[$i]}" in
      listed)   continue ;;
      filtered) filt=$((filt+1)); continue ;;
    esac
    printf '\n== %s ==\n' "$label"
    wait "${pids[$i]}" >/dev/null 2>&1 || true
    rc="$(cat "$RUN/$i.rc" 2>/dev/null || echo 1)"
    [ -f "$RUN/$i.log" ] && cat "$RUN/$i.log"
    ran=$((ran+1))
    if [ "$rc" != "0" ]; then
      printf 'FAILED (rc %s): %s\n' "$rc" "$label"
      fails=$((fails+1))
    fi
  done
  [ "$fails" -eq 0 ] || { printf '\n%d of %d items FAILED:\n' "$fails" "$ran"
    for i in "${!labels[@]}"; do
      [ "${states[$i]}" = "run" ] || continue
      [ "$(cat "$RUN/$i.rc" 2>/dev/null || echo 1)" != "0" ] && printf '  - %s\n' "${labels[$i]}"
    done; exit 1; }
  [ "$filt" -gt 0 ] && echo "($filt items filtered by --only)"
  echo "OK: all validators passed"
}

# --------------------------------------------------------------------------- #
# Blocks too big to be a single `item` line. They are the SAME commands that   #
# used to sit inline; moving them here is what lets them run in the background. #
# --------------------------------------------------------------------------- #

# The HD-413 guard fixture and the playbook syntax loop each fan out over ansible
# themselves. GATE_NPAR bounds that fan-out when the parent pool is smaller than the
# box, so the two legs together stay inside the core count.
blk_guard_fixture() {
  bash scripts/testdata/self-converge-guard/run.sh
}

blk_ansible_syntax() {
  # HD-256: like ansible-run.sh, export ANSIBLE_CONFIG + ANSIBLE_ROLES_PATH so the
  # role path resolves when running from the repo root on the Debian/WSL primary
  # (otherwise ansible finds no config here and every `roles: - xxx` fails to resolve).
  # Kept INSIDE this item: the other items must not inherit an Ansible environment they
  # never asked for.
  local REPO_ROOT; REPO_ROOT="$(pwd)"
  export ANSIBLE_CONFIG="$REPO_ROOT/IaC/ansible/ansible.cfg"
  export ANSIBLE_ROLES_PATH="$REPO_ROOT/IaC/ansible/roles"
  if command -v ansible-playbook >/dev/null 2>&1 && ansible-playbook --version >/dev/null 2>&1; then
    # Measured on the 8-core runner: serial 8.4 s, concurrent 3.0 s, and per playbook
    # 0.37-1.5 s of which ~95 % is ansible-playbook interpreter startup — there is no
    # work here to optimise, only waiting. Syntax-checking is read-only and every
    # playbook gets its own stderr/rc file, so the duplicate-key witness below still sees
    # exactly what ansible printed for each playbook, and one playbook cannot affect another's rc.
    local SC_DIR; SC_DIR="$(mktemp -d)"; trap 'rm -rf "$SC_DIR"' EXIT
    local names=() files=() i=0 pb n rc_all=0 rc
    for pb in IaC/ansible/site.yml IaC/ansible/playbooks/*.yml; do
      n="pb$i"
      ( ansible-playbook -i IaC/ansible/inventory.ini "$pb" --syntax-check \
          >/dev/null 2>"$SC_DIR/$n.err"; echo "$?" > "$SC_DIR/$n.rc" ) &
      names+=("$n"); files+=("$pb"); i=$((i+1))
      while [ "$(jobs -rp | wc -l)" -ge "$GATE_NPAR" ]; do sleep 0.05; done
    done
    wait
    # HD-1098: ansible's own parser is the second witness for duplicate mapping keys. It
    # prints `Found duplicate mapping key … Using last defined value only.` on stderr and
    # carries on, so the warning has to be caught here or the FIRST definition stays dead.
    for j in "${!names[@]}"; do
      n="${names[$j]}"; pb="${files[$j]}"; rc=0
      [ -f "$SC_DIR/$n.rc" ] && rc="$(cat "$SC_DIR/$n.rc")" || rc=1
      if grep -q "Found duplicate mapping key" "$SC_DIR/$n.err" 2>/dev/null; then
        echo "FAIL: ansible reported a duplicate mapping key while parsing $pb — it keeps the LAST"
        echo "      definition and drops the first, so the earlier one is dead (HD-1098):"
        grep -A3 "Found duplicate mapping key" "$SC_DIR/$n.err" | sed 's/^/  /'
        exit 1
      fi
      if [ "$rc" -ne 0 ]; then
        # unchanged HD-197 semantics: a real syntax failure still fails this item (the
        # duplicate-key leg above must not have turned this loop into a warning collector)
        echo "FAIL: ansible-playbook --syntax-check failed for $pb (rc $rc)" >&2
        cat "$SC_DIR/$n.err" >&2
        rc_all="$rc"
      fi
    done
    [ "$rc_all" -eq 0 ] || exit "$rc_all"
    echo "OK: all playbooks pass --syntax-check (parallel, $GATE_NPAR at a time)"
  else
    echo "SKIP: ansible-playbook not functional on this host (absent or native-Windows WinError 87) — syntax gate runs under WSL/CI"
  fi
}

# Portability sweep, HD-256. Split into its two halves so they overlap: both used to
# sit in one serial block. bash -n is a no-op on hosts without bash (Windows); the
# py_compile half deliberately uses python3, not $PY — the claim is about python3.
blk_bash_n_sweep() {
  if command -v bash >/dev/null 2>&1; then
    local f bash_fail=0
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
}

blk_py_compile_sweep() {
  if command -v python3 >/dev/null 2>&1; then
    local f py_fail=0
    for f in scripts/*.py; do
      [ -f "$f" ] || continue
      python3 -m py_compile "$f" >/dev/null 2>&1 || { echo "py_compile FAIL: $f" >&2; py_fail=$((py_fail+1)); }
    done
    [ "$py_fail" -eq 0 ] || exit 1
    echo "OK: all scripts/*.py compile under python3"
  else
    echo "SKIP: python3 not on PATH — py_compile sweep skipped"
  fi
}

# The seat/host-state gates: each SKIPs where the thing it checks is absent, so a
# stateless runner is never broken by them (and a SKIP is printed, never counted green).
blk_skills_drift() {
  if [ -d "$HOME/.pi/agent/skills" ]; then
    bash scripts/sync-skills.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/skills on this host (bare CI / non-pi laptop) — skill gate runs where pi is configured"
  fi
}

blk_extensions_check() {
  if [ -d "$HOME/.pi/agent/extensions" ]; then
    bash scripts/sync-extensions.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/extensions on this host — extension gate runs where pi is configured (deploy: sync-extensions.sh --push)"
  fi
}

blk_tmux_check() {
  if [ -f "$HOME/.tmux.conf" ]; then
    bash scripts/install-tmux-conf.sh --check --strict
  else
    echo "SKIP: no ~/.tmux.conf on this host — the seat harness gate runs where tmux is installed (deploy: install-tmux-conf.sh --push)"
  fi
}

# rc 2 = no pi binary here = SKIP, printed and never counted green (CONVENTIONS: a SKIP
# is not a pass). BEHIND and AHEAD are both drift — a seat ahead of its pin is the shape
# every file plane misses.
blk_pi_self_check() {
  local rc_piself=0
  bash scripts/pi-self-update.sh --check --strict || rc_piself=$?
  case "$rc_piself" in
    0) echo "OK: the pi build on this host equals pi_host_npm_version" ;;
    2) echo "SKIP: no pi binary on this host — the pi-self plane runs where pi is installed (pi-seat-sync.sh --push)" ;;
    *) echo "FAIL: the pi build drifts from pi_host_npm_version — run: bash scripts/pi-self-update.sh --push"; exit 1 ;;
  esac
}

blk_pi_settings_check() {
  if [ -f "$HOME/.pi/agent/settings.json" ]; then
    bash scripts/pi-settings-config.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/settings.json on this host — the settings plane runs where pi is configured (deploy: pi-seat-sync.sh --push)"
  fi
}

blk_pi_tui_check() {
  if [ -f "$HOME/.pi/agent/open-tui.json" ]; then
    bash scripts/pi-tui-config.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/open-tui.json on this host — the TUI footer gate runs where pi-open-tui is installed"
  fi
}

# The font plane is the one item that is allowed to be red without failing the gate, and
# that is deliberate (the Windows leg is scripts/win/install-nerd-font.ps1). It is printed
# as a NOTE so a green run still says which plane it did not prove.
blk_font_check() {
  if [ -d "${NERD_FONT_DIR:-$HOME/.local/share/fonts}" ] || command -v fc-list >/dev/null 2>&1; then
    NERD_FONT_DIR="${NERD_FONT_DIR:-$HOME/.local/share/fonts}"/JetBrainsMono-Nerd-Font \
      bash scripts/install-nerd-font.sh --check --strict \
      || echo "NOTE: the font plane is not green on this host — on the Windows seat the leg that matters is scripts/win/install-nerd-font.ps1"
  else
    echo "SKIP: no user font dir / no fontconfig here — the font plane runs where the TUI's glyphs are drawn"
  fi
}

# --------------------------------------------------------------------------- #
# The queue. Longest items FIRST — the pool launches in this order, so putting #
# the multi-second items here is the scheduling, not a priority system.        #
# --------------------------------------------------------------------------- #

# The two ansible legs (each fans out internally).
item_blk "testdata/self-converge-guard/run.sh (HD-413 verdict matrix, runtime)" blk_guard_fixture
item_blk "ansible-playbook --syntax-check (WSL/CI-gated)" blk_ansible_syntax

# The corpus walkers.
item "check_secrets.py (secret shapes in the tracked tip, archive members included)" $PY scripts/check_secrets.py
item "check_secrets.py --self-test (the speed prefilter must not have narrowed a shape)" $PY scripts/check_secrets.py --self-test
item "check_yaml_dup_keys.py (HD-1098: a duplicate YAML key is a silent no-op)" $PY scripts/check_yaml_dup_keys.py
item "check_yaml_dup_keys.py --self-test (HD-1098 canaries + corpus probe)" $PY scripts/check_yaml_dup_keys.py --self-test
item "check_zone_kogler_si_parity.py (derived zone answers what the hand-authored sources did, HD-436)" $PY scripts/check_zone_kogler_si_parity.py
item "check_zone_kogler_si_parity.py --self-test" $PY scripts/check_zone_kogler_si_parity.py --self-test
item "check_dns_seed_drift.py (Technitium split-horizon seed contract, HD-341 parity)" $PY scripts/check_dns_seed_drift.py
item "check_self_converge_guard.py (HD-413 guardrail completeness, static)" $PY scripts/check_self_converge_guard.py
item "validate-docker-services.py" $PY scripts/validate-docker-services.py
item "spark-llm-render-matrix.py (HD-489: every profile must RENDER, not just validate)" $PY scripts/spark-llm-render-matrix.py
item "check_doc_path_refs.py (HD-490: a path a doc cites must exist)" $PY scripts/check_doc_path_refs.py
item "check_doc_path_refs.py --self-test (HD-490 canary)" $PY scripts/check_doc_path_refs.py --self-test
item "validate_doc_templates.py" $PY scripts/validate_doc_templates.py
item "check_vault_name.py" $PY scripts/check_vault_name.py
item "check_placeholders.py" $PY scripts/check_placeholders.py
item "bash -n sweep (HD-256 portability, all scripts/*.sh)" blk_bash_n_sweep
item "python3 -m py_compile sweep (HD-256 portability, all scripts/*.py)" blk_py_compile_sweep

# Seat planes — self-tests run everywhere (sandboxed), the --check half SKIPs per host.
item "install-nerd-font.sh --self-test (HD-1110: the pinned nerd-font release + sha256 manifest)" bash scripts/install-nerd-font.sh --self-test
item "pi-settings-config.sh --self-test (HD-1110: the harness keys of ~/.pi/agent/settings.json)" bash scripts/pi-settings-config.sh --self-test
item "pi-tui-config.sh --self-test (HD-1110: the pi-open-tui footer hostname key)" bash scripts/pi-tui-config.sh --self-test
item "pi-seat-sync.sh --self-test (HD-1110: the fan-out driver verdicts, on stubbed seats)" bash scripts/pi-seat-sync.sh --self-test
item "pi-self-update.sh --self-test (HD-1115: BEHIND and AHEAD are both drift)" bash scripts/pi-self-update.sh --self-test
item "install-tmux-conf.sh --self-test (HD-1085: config == repo AND actually takes effect)" bash scripts/install-tmux-conf.sh --self-test
item "install-tmux-conf.sh --check --strict (seat tmux drift)" blk_tmux_check
item "pi-self-update.sh --check --strict (the pi build vs pi_host_npm_version)" blk_pi_self_check
item "pi-settings-config.sh --check --strict (settings.json vs settings-ssot.json)" blk_pi_settings_check
item "pi-tui-config.sh --check --strict (open-tui.json footer key)" blk_pi_tui_check
item "install-nerd-font.sh --check --strict (font dir vs pin)" blk_font_check
item "sync-skills.sh --check --strict (skill drift gate, HD-254)" blk_skills_drift
item "sync-extensions.sh --self-test (HD-254 family: missing fails, extra kept, retired removed)" bash scripts/sync-extensions.sh --self-test
item "sync-extensions.sh --check --strict (repo pi-agent/extensions == deployed)" blk_extensions_check

# Everything else — cheap, but they add up, so they are in the pool too.
item "guard-session.sh --self-test (sandboxed guard fixture, HD-253)" bash scripts/guard-session.sh --self-test
item "guarded-converge.sh --self-test (post-converge liveness verdict, HD-436)" bash scripts/guarded-converge.sh --self-test
item "git-bootstrap.sh --self-test (each 1Password refusal state says the right thing)" bash scripts/git-bootstrap.sh --self-test
item "testdata/check-vault-items/run.sh (scanner self-test, HD-244/245)" bash scripts/testdata/check-vault-items/run.sh
item "validate_blueprints.py" $PY scripts/validate_blueprints.py
item "check_doc_ips.py" $PY scripts/check_doc_ips.py
item "check_traefik_host_rules.py" $PY scripts/check_traefik_host_rules.py
item "validate-secrets.py" $PY scripts/validate-secrets.py
item "check_doc_map.py" $PY scripts/check_doc_map.py
item "check_generated_suffix.py" $PY scripts/check_generated_suffix.py
item "check_ledger_state.py (ledger = checkboxes, open rows only, ticks dated)" $PY scripts/check_ledger_state.py
item "check_runbook_purity.py (runbook = imperative procedure only)" $PY scripts/check_runbook_purity.py
item "check_vault_docs.py (every IaC-read vault item is documented)" $PY scripts/check_vault_docs.py
item "check_todo_done.py (CONVENTIONS §4(a) done-row sweep)" $PY scripts/check_todo_done.py
item "check_todo_done.py --refs (an HD id named by any root prompt brief must still be a row)" $PY scripts/check_todo_done.py --refs
item "check_todo_done.py --self-test (marker grammar + reference-existence canaries, both directions)" $PY scripts/check_todo_done.py --self-test
item "check_merge_markers.py (HD-453: no conflict markers in tracked files)" $PY scripts/check_merge_markers.py
item "check_merge_markers.py --self-test (HD-453 canary)" $PY scripts/check_merge_markers.py --self-test
item "check_md_tables.py (HD-417 width rule + 2026-10-06 duplicate-key rule)" $PY scripts/check_md_tables.py
item "check_md_tables.py --self-test (HD-417 cell-count canary + duplicate-key canary)" $PY scripts/check_md_tables.py --self-test
item "check_iac_backend_strings.py (HD-404: retired-backend mentions may not regrow)" $PY scripts/check_iac_backend_strings.py
item "check_iac_backend_strings.py --self-test (HD-404 ratchet canary)" $PY scripts/check_iac_backend_strings.py --self-test
item "check_spark_llm_gate.py (HD-469: spark LLM profile matrix + gate canaries)" $PY scripts/check_spark_llm_gate.py
item "knx-hass-gen.py --self-test (HD-439: emitted addresses must exist in the ETS project)" $PY scripts/knx-hass-gen.py --self-test
item "laptop-llm.py gate --self-test (HD-474: laptop serving-leg gate must be PROVEN OFFLINE)" $PY scripts/laptop-llm.py gate --self-test
item "laptop-llm.py probe-client (HD-474: client contract may not drift ahead of the engine)" $PY scripts/laptop-llm.py probe-client
item "gate7-read.py --self-test (HD-489 gate-7 bucketing: mixed-pid artifact, bounded fill, leak)" $PY spark/bench/gate7-read.py --self-test

# --------------------------------------------------------------------------- #
# Drain and report.                                                           #
# --------------------------------------------------------------------------- #
if [ "$LIST" = 1 ]; then
  for i in "${!labels[@]}"; do printf '%2d  %s\n' "$i" "${labels[$i]}"; done
  exit 0
fi
wait
_report
