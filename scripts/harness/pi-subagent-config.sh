#!/usr/bin/env bash
# =====================================================================
# pi-subagent-config.sh — the `subagent` plane: render the child-runtime
#   payload for the pi-subagents extension (HD-1153).
#
# WHAT THIS OWNS
# --------------
#   pi-agent/settings-ssot.json `_subagentConfig`  ->  ~/.pi/agent/extensions/subagent/config.json
# on every pi.dev seat. The child-lane contract (O10/O11) carries the run
# deadline and the two-child ceiling; the extension reads them from THIS file.
# The payload lives under an underscore in the SSOT precisely because the
# settings plane owns the UN-prefixed keys of ~/.pi/agent/settings.json and
# nothing else — this arm owns the extension file instead.
#
# WHAT `_note` IS, AND WHY IT IS NOT COMPARED
# --------------------------------------------
#   The payload carries one prose key, `_note`, that the extension never reads: it is a pointer
#   to the docs that explain the numbers. Those docs live in the DOCS tree, so a prose-only rename
#   there rewrites the SSOT's note and — when the verdict byte-compared the whole block — reddened
#   the `subagent` plane on EVERY seat not pushed since. HD-1119(a) did exactly that on 2026-10-19:
#   two seats read DRIFT with `differing keys: ['_note']` and every functional value identical, and
#   no offline gate could predict it because the value it compares lives in a seat's HOME.
#   So: the COMPARE ignores `_note`; `--push` still WRITES the whole payload, note included, so a
#   push refreshes the prose. Every other key — known or not — is compared exactly, so a real knob
#   still reddens, and `--self-test` proves BOTH halves (a moved key behind a changed note is still
#   a RED that names the key). The owning rule is docs/harness-pi-seats.md §1.
#
# VERDICTS
# --------
#   --check            OK / DRIFT / MISSING / INVALID (report-only)
#   --check --strict   exit 1 on a drift too (the seat-leg form; validate-all runs no seat-byte
#                      item for this plane — the fan-out `pi-seat-sync.sh --plane subagent` is the
#                      leg that reaches a seat, and `check_subagent_contract.py` proves only that
#                      this arm exists, never what a seat holds)
#   --push             write the payload, 0600, keep a timestamped backup
#                      (the extension file holds no secrets today, but 0600 is
#                      the ownership default for anything under ~/.pi/agent)
#   --self-test        sandboxed canaries; both halves of every rule above
#
# Exit codes: 0 OK / repaired · 1 drift(strict), missing, invalid, refusal ·
#             2 SKIP — nothing was read: no usable node, or node died without a verdict line
#                 (a SKIP is never a pass, and never a claim about the payload file's bytes).
#
# Env (sandbox hooks only): REPO, PI_SUBAGENT_CONF (default
# $HOME/.pi/agent/extensions/subagent/config.json), PI_NODE.
#
# Owning rule: docs/harness-pi-seats.md §1 + docs/harness-pi-engines.md §6 · CONVENTIONS §6 (repo = SSOT).
set -uo pipefail

# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed.
_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
SCRIPT_DIR="$_hl_d"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO (an inherited $REPO still wins)
SSOT="$REPO/pi-agent/settings-ssot.json"
CONF="${PI_SUBAGENT_CONF:-$HOME/.pi/agent/extensions/subagent/config.json}"

MODE="check"; STRICT=0
err()  { printf 'pi-subagent-config: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }
usage() {
  cat <<'EOF'
usage: pi-subagent-config.sh [--check [--strict] | --push] [--self-test]

  --check            (default) compare ~/.pi/agent/extensions/subagent/config.json
                     against the `_subagentConfig` block of pi-agent/settings-ssot.json.
                     The prose key `_note` is NOT compared (the extension does not read it);
                     every other key is compared exactly
  --check --strict   exit 1 on a drift too (gate use)
  --push             write the payload; keep every key; keep a timestamped backup
  --self-test        sandboxed canaries (temp files; never touches ~/.pi)
EOF
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)        MODE="check" ;;
    --strict)       STRICT=1 ;;
    --push)         MODE="push" ;;
    --self-test)    MODE="selftest" ;;
    --help|-h)      usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

[ -f "$SSOT" ] || { err "no settings SSOT at $SSOT — run from a homelab clone"; exit 1; }

# node: pi's own shebang is `#!/usr/bin/env node`, so a seat always HAS node — but a
# non-interactive non-login shell may not carry it on PATH (HD-446). Same ordered probe
# as the settings plane; the pinned prefix first, then PATH.
NODE="${PI_NODE:-}"
if [ -z "$NODE" ]; then
  _cand="$HOME/.local/share/pi-node/current/bin/node"
  if [ -x "$_cand" ]; then NODE="$_cand"; else
    for c in "$(command -v node 2>/dev/null || true)" "$(command -v node.exe 2>/dev/null || true)"; do
      [ -n "$c" ] && [ -x "$c" ] && { NODE="$c"; break; }
    done
  fi
fi
require_node() {
  if [ -z "$NODE" ] || ! "$NODE" -e 'process.exit(0)' >/dev/null 2>&1; then
    info "SKIP: no usable node (looked for '${NODE:-none}') — $CONF was NOT read; a SKIP is not a pass"
    return 2
  fi
  return 0
}

# --- the compare (ONE node program; the write below is the other half) --------
# STATE<TAB>detail    ok | drift | missing | invalid
#   ok   + detail ""      = equal on everything, prose included
#   ok   + detail "_note" = equal on every key the extension READS; the deployed note lags
#   drift+ + detail        = the names of the keys that differ, `_note` never among them
run_node() {
  "$NODE" -e '
    const fs = require("fs");
    const [ssotPath, confPath] = process.argv.slice(1);
    // `_note` is documentation carried inside the payload, not a knob: the extension reads none
    // of it and it cites docs that live elsewhere. Byte-comparing it turned a prose-only rename
    // into seat-plane drift on every seat not yet pushed (HD-1119(a), 2026-10-19, two seats).
    // It is therefore excluded from the COMPARE only — `--push` writes it. Rule: docs/harness-pi-seats.md §1.
    const NOTE = "_note";
    const j = (v) => JSON.stringify(v, null, 2);
    const fn = (o) => { const c = Object.assign({}, o); delete c[NOTE]; return c; };
    const ssot = JSON.parse(fs.readFileSync(ssotPath, "utf8"));
    const state = (s, d) => { console.log(s + "\t" + d); };
    if (!ssot._subagentConfig || typeof ssot._subagentConfig !== "object") {
      state("missing", "_subagentConfig block absent from the SSOT"); process.exit(0);
    }
    const wantAll = ssot._subagentConfig, want = fn(wantAll);
    if (!fs.existsSync(confPath)) { state("missing", ""); process.exit(0); }
    let cur;
    try { cur = fs.readFileSync(confPath, "utf8"); }
    catch { state("invalid", ""); process.exit(0); }
    let parsed;
    try { parsed = JSON.parse(cur); }
    catch { state("invalid", ""); process.exit(0); }
    if (typeof parsed !== "object" || parsed === null) { state("invalid", ""); process.exit(0); }
    const got = fn(parsed);
    if (j(got) === j(want)) { state("ok", j(parsed) === j(wantAll) ? "" : NOTE); process.exit(0); }
    // name the keys that differ — the old body printed the BLOCK name here, and "these keys
    // differ: _subagentConfig" is what sent a lane looking for a key that had not moved.
    const names = Array.from(new Set(Object.keys(want).concat(Object.keys(got)))).sort();
    state("drift", names.filter((k) => j(want[k]) !== j(got[k])).join(", ") || "(shape)");
    process.exit(0);
  ' "$SSOT" "$CONF"
}
invoke() {
  # An EMPTY verdict is its own state, not `invalid`. node's exit status used to be dropped here, so
  # a node that died after answering require_node's probe — the shape a WSL bash reaches when pwsh's
  # `bash` is C:\WINDOWS\system32\bash.exe and the Windows node.exe behind it cannot open the POSIX
  # paths — left STATE empty, and do_check's catch-all reported "not parseable JSON" about a file it
  # had never opened. rc 2 = nothing was read.
  local out l1 rc=0
  out="$(run_node)" || rc=$?
  if [ -z "$out" ]; then
    err "NO VERDICT: node (rc $rc) wrote no verdict line — $CONF was NOT read; a broken probe, not a broken payload file"
    STATE="no-verdict"; return 2
  fi
  l1="${out%%$'\n'*}"
  STATE="${l1%%$'\t'*}"
  DETAIL="${l1#*$'\t'}"; [ "$DETAIL" = "$l1" ] && DETAIL=""
  # Explicit 0: the `[ … ] &&` above is the last command and is FALSE for a clean `ok` verdict, and
  # do_check/do_push now branch on invoke's rc — a verdict must not arrive with a failed status.
  return 0
}

do_check() {
  require_node || return $?
  invoke || return $?
  case "$STATE" in
    ok)      info "OK: $CONF carries the _subagentConfig payload of pi-agent/settings-ssot.json"
             # Honest about the one thing the compare deliberately does not look at: prose only.
             [ "$DETAIL" = "_note" ] && info "the deployed _note prose lags the SSOT; --push refreshes it (the compare ignores it by design)"
             return 0 ;;
    drift)   err "DRIFT: these keys differ from the SSOT payload: ${DETAIL:-the payload shape}"
             [ "$STRICT" -eq 1 ] && return 1
             info "reported, not failed (add --strict for the gate form; --push converges)"; return 0 ;;
    missing) err "MISSING: no $CONF — the subagent payload is not installed (run --push, or an install-pi-*.sh)"; return 1 ;;
    invalid) err "INVALID: $CONF is not parseable JSON — fix it by hand; this script will not rewrite a file it cannot read"; return 1 ;;
    *)       err "NO VERDICT: the compare returned no state — $CONF was NOT read, so nothing here is a verdict about it"; return 2 ;;
  esac
}

do_push() {
  require_node || return $?
  local stamp _d
  # The compare here decides only WHETHER IT MAY WRITE (a file it cannot parse is a refusal) and
  # whether the target directory must exist. `ok` with the `_note` detail means the functional
  # payload is already right but the PROSE lags — and --push writes the WHOLE payload, so it
  # refreshes the note anyway. Only a byte-for-byte equal file is left alone (no spurious backup).
  invoke || return $?
  case "$STATE" in
    ok)      [ -n "$DETAIL" ] || { info "in place: $CONF carries the _subagentConfig payload ($CONF)"; return 0; } ;;
    invalid) err "REFUSAL: $CONF does not parse — refusing to overwrite it"; return 1 ;;
    missing) _d="${CONF%/*}"; [ "$_d" != "$CONF" ] || _d=.
             mkdir -p "$_d" 2>/dev/null || true
             ;;
  esac
  # a write happened: keep the pre-change file nameable
  printf -v stamp '%(%Y%m%d-%H%M%S)T' -1
  [ -f "$CONF" ] && cp -p "$CONF" "$CONF.pre-subagent-$stamp" 2>/dev/null || true
  "$NODE" -e '
    const fs = require("fs");
    const [ssotPath, confPath] = process.argv.slice(1);
    const ssot = JSON.parse(fs.readFileSync(ssotPath, "utf8"));
    const payload = ssot._subagentConfig || {};
    fs.mkdirSync(require("path").dirname(confPath), { recursive: true });
    fs.writeFileSync(confPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
    try { fs.chmodSync(confPath, 0o600); } catch {}
  ' "$SSOT" "$CONF"
  invoke
  [ "$STATE" = ok ] || { err "wrote $CONF but the payload still reads '$STATE' ($DETAIL)"; return 1; }
  info "wrote $CONF from pi-agent/settings-ssot.json _subagentConfig (backup: ${CONF##*/}.pre-subagent-$stamp)"
  return 0
}

# --- self-test ---------------------------------------------------------------
self_test() {
  local tmp fails=0 rc=0
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  trap "rm -rf '$tmp'" RETURN
  require_node || { err "self-test needs node — it cannot prove anything without it"; return 1; }
  # a compliant file == the SSOT payload
  "$NODE" -e '
    const fs=require("fs"), path=require("path");
    const ssot=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const payload=ssot._subagentConfig||{};
    fs.mkdirSync(path.dirname(process.argv[2]),{recursive:true});
    fs.writeFileSync(process.argv[2], JSON.stringify(payload,null,2)+"\n","utf8");
  ' "$SSOT" "$tmp/good.json"
  # 1. compliant -> OK (strict too)
  if PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict >/dev/null 2>&1; then
    info "rest-state       GREEN"; else err "canary: a compliant file failed its own check"; fails=$((fails+1)); fi
  # 2. drifted key -> strict RED, report-only GREEN, --push repairs ONLY the payload
  "$NODE" -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));c.timeoutMs=123;fs.writeFileSync(process.argv[1],JSON.stringify(c,null,2)+"\n")' "$tmp/good.json" 2>/dev/null || true
  if PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check >/dev/null 2>&1; then
    info "report-only      GREEN (drift does not fail a human run)"; else err "canary: report-only check failed a drifted state"; fails=$((fails+1)); fi
  if PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict >/dev/null 2>&1; then
    err "canary: a drifted payload stayed green under --strict"; fails=$((fails+1)); else info "key-drift        caught"; fi
  if PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --push >/dev/null 2>&1; then :; else err "canary: --push failed"; fails=$((fails+1)); fi
  "$NODE" -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));if(c.timeoutMs===123){process.exit(1)}' "$tmp/good.json" && info "key-repair        GREEN" || { err "canary: --push did not repair the payload"; fails=$((fails+1)); }
  # 3. missing -> strict RED; --push creates it
  if PI_SUBAGENT_CONF="$tmp/none.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict >/dev/null 2>&1; then
    err "canary: MISSING stayed green"; fails=$((fails+1)); else info "missing-canary   caught"; fi
  if PI_SUBAGENT_CONF="$tmp/none.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --push >/dev/null 2>&1; then
    [ -f "$tmp/none.json" ] && info "missing-create   GREEN" || { err "canary: --push created no file"; fails=$((fails+1)); }
  else err "canary: --push did not create the file"; fails=$((fails+1)); fi
  # 4. unparseable -> RED, REFUSAL leaves the bytes alone
  printf '{ "timeoutMs": , }\n' > "$tmp/bad.json"; cp "$tmp/bad.json" "$tmp/bad.before"
  if PI_SUBAGENT_CONF="$tmp/bad.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict >/dev/null 2>&1; then
    err "canary: unparseable stayed green"; fails=$((fails+1)); else info "invalid-canary   caught"; fi
  if PI_SUBAGENT_CONF="$tmp/bad.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --push >/dev/null 2>&1; then
    err "canary: --push overwrote an unparseable file"; fails=$((fails+1)); else info "refusal-canary   caught"; fi
  if cmp -s "$tmp/bad.before" "$tmp/bad.json"; then info "file-untouched   GREEN"; else err "canary: a REFUSAL still modified the file"; fails=$((fails+1)); fi
  # 5. no usable node -> rc 2 SKIP
  rc=0
  PI_NODE="$tmp/there-is-no-such-node" PI_SUBAGENT_CONF="$tmp/good.json" \
    bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then info "skip-arm         GREEN (rc 2 = SKIP, not a pass)"; else err "canary: the no-node path returned $rc — a SKIP must be 2"; fails=$((fails+1)); fi
  # 5b. a node that answers require_node's probe and THEN dies -> rc 2 NO VERDICT, and never the
  #     INVALID text. An rc-blind `invoke` mapped a dead node to "not parseable JSON" — an accusation
  #     about a file the script never opened — so this arm asserts the rc AND the words it must not
  #     print, and that --push wrote nothing in that state (CONVENTIONS §6: both halves).
  printf '#!/bin/sh\nif [ "$#" -le 2 ]; then exit 0; fi\necho "fake-node: the fixture cannot open the SSOT" >&2\nexit 1\n' > "$tmp/dying-node"
  chmod +x "$tmp/dying-node" 2>/dev/null || true
  local _o5=""
  rc=0
  _o5="$(PI_NODE="$tmp/dying-node" PI_SUBAGENT_CONF="$tmp/good.json" \
          bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict 2>&1)" || rc=$?
  if [ "$rc" -ne 2 ]; then
    err "canary: a node that died without a verdict returned $rc — nothing was read, so it must be 2"; fails=$((fails+1))
  else
    case "$_o5" in
      *NO\ VERDICT*) case "$_o5" in
        *INVALID*|*"not parseable"*|*OK:*|*DRIFT*) err "canary: a dead probe still printed a verdict about the payload file"; fails=$((fails+1)) ;;
        *) info "no-verdict         GREEN (rc 2, no claim about the file)" ;;
      esac ;;
      *) err "canary: the dead-probe path printed no NO VERDICT line"; fails=$((fails+1)) ;;
    esac
  fi
  cp -p "$tmp/good.json" "$tmp/good5.before" 2>/dev/null || : > "$tmp/good5.before"
  PI_NODE="$tmp/dying-node" PI_SUBAGENT_CONF="$tmp/good.json" \
    bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --push >/dev/null 2>&1 || true
  cmp -s "$tmp/good5.before" "$tmp/good.json" \
    && info "no-verdict-write   GREEN (a probe that died wrote nothing)" \
    || { err "canary: --push wrote $CONF although node had died"; fails=$((fails+1)); }
  # 6. THE NOTE CLASS (HD-1119(a), measured 2026-10-19): a doc path lives inside `_subagentConfig._note`
  #    and the plane byte-compared the payload, so a PROSE-ONLY rename in the docs tree reddened the
  #    `subagent` plane on two seats whose functional values were identical. Both halves, per
  #    CONVENTIONS §6 — the exclusion must be narrow, not blind, so each half has a canary:
  #    (a) prose-only    -> still GREEN under --strict  (deleting the exclusion reddens THIS arm)
  #    (b) prose + a key -> still RED, naming the KEY  (widening the exclusion reddens THIS arm)
  note_set() { "$NODE" -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));c._note=process.argv[2];fs.writeFileSync(process.argv[1],JSON.stringify(c,null,2)+"\n")' "$1" "$2"; }
  local _out
  note_set "$tmp/good.json" "Installed by the subagent seat plane — why each value: the harness doc section this copy kept after the docs were renamed."
  _out=""
  if _out="$(PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict 2>&1)"; then
    case "$_out" in
      *"_note prose lags"*) info "note-only        GREEN (a renamed doc path cannot redden a seat; the lag is printed)" ;;
      *) err "canary: a note-only difference passed silently — the honest lag line is gone"; fails=$((fails+1)) ;;
    esac
  else err "canary: a note-only difference reddened the plane — the exclusion is gone"; fails=$((fails+1)); fi
  "$NODE" -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));c._note="a note reworded when the docs were renamed";c.timeoutMs=123;fs.writeFileSync(process.argv[1],JSON.stringify(c,null,2)+"\n")' "$tmp/good.json"
  _out="$(PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    err "canary: a moved key hidden behind a changed note read OK — the compare is blind, not narrow"; fails=$((fails+1))
  else
    case "$_out" in
      *timeoutMs*) info "note-cannot-mask GREEN (strict RED, and it names timeoutMs, not the block)" ;;
      *) err "canary: the DRIFT line does not name the key that differs: $_out"; fails=$((fails+1)) ;;
    esac
  fi
  # an extra key the SSOT does not carry is not documentation, whatever it is called
  "$NODE" -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));delete c._note;c.seatLocalKnob=1;fs.writeFileSync(process.argv[1],JSON.stringify(c,null,2)+"\n")' "$tmp/good.json"
  if PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --check --strict >/dev/null 2>&1; then
    err "canary: an unknown extra key read OK — the payload is not open-ended"; fails=$((fails+1))
  else info "unknown-key      caught (a key the SSOT does not carry is still drift)"; fi
  # --push writes the WHOLE payload: a note-only-lagging seat gets its prose back, not just its knobs
  note_set "$tmp/good.json" "a note from before the rename"
  if PI_SUBAGENT_CONF="$tmp/good.json" bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" --push >/dev/null 2>&1 \
     && "$NODE" -e 'const fs=require("fs");const a=JSON.parse(fs.readFileSync(process.argv[1],"utf8"))._subagentConfig._note;const b=JSON.parse(fs.readFileSync(process.argv[2],"utf8"))._note;process.exit(a===b?0:1)' "$SSOT" "$tmp/good.json"; then
    info "push-writes-note GREEN (the exclusion is in the compare, never in the write)"
  else err "canary: --push no longer writes the whole payload — _note stayed stale through a push"; fails=$((fails+1)); fi
  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

case "$MODE" in
  selftest) self_test; exit $? ;;
  check)    do_check; exit $? ;;
  push)     do_push; exit $? ;;
esac