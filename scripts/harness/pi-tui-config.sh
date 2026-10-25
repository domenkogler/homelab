#!/usr/bin/env bash
# =====================================================================
# pi-tui-config.sh — prove and repair ONE key of the seat TUI config:
#   ~/.pi/agent/open-tui.json -> footerSegments.hostname == true      (HD-1110)
#
# WHY A SCRIPT FOR ONE KEY
# ------------------------
# The seat TUI is the pi package `pi-open-tui` (pin `pi_host_tui_npm_*`), and its footer
# is what answers "which box am I typing to" — the job `pi-agent/extensions/host-status.ts`
# used to do with `ctx.ui.setStatus`, retired by HD-1110. The mechanism is now the package's
# own footer segment (`extensions/open-tui/footer.ts`: `os.hostname()` truncated to the short
# form). So installing the package is NOT enough: pi-open-tui's `DEFAULT_CONFIG` ships
# `footerSegments.hostname: false`, and a seat that only ran `pi install` gets a footer with
# no machine in it — a silent loss of the invariant docs/harness-pi-seat-identity.md §5a calls "the only
# place that fact is written down", and the loss lands exactly where nobody looks: on the
# SSH legs, where the prompt is gone. Hence a check, not a README line.
#
# WHY ONLY ONE KEY
# ----------------
# Everything else in that file is machine-local tuning the operator changes through pi's
# `/open-tui` command, and the package REWRITES the file on every settings change. A
# byte-compare drift gate would therefore fight the extension's own settings UI — the
# same boundary harness-pi-seats.md §5 draws for settings.json ("the block is the part that must
# match", no renderer by design). So this script asserts ONE invariant and preserves every
# other key it did not come to set.
#
# MODES
#   --check (default)  report MISSING / OK / DRIFT / INVALID. MISSING and INVALID exit 1;
#                      a DRIFT is report-only unless --strict — the same exit-code contract
#                      as sync-skills.sh / sync-extensions.sh / install-tmux-conf.sh.
#   --check --strict   also exit 1 on a DRIFT. Gate use (validate-all.sh item 30).
#   --push             set the ONE key, create the file when absent, preserve every other
#                      key. A file that does not PARSE is a REFUSAL, never a rewrite.
#   --self-test        sandboxed canaries in a temp dir; asserts both halves of every
#                      invariant, including "a file we cannot parse is not overwritten".
#
# Exit codes: 0 OK / repaired · 1 drift(strict), missing, invalid, or a refusal ·
#             2 SKIP — NOTHING was read: no node on PATH, or node died without printing a verdict
#                 line (a SKIP is never a pass, and never a claim about the file's bytes).
#
# Env (sandbox hooks only): REPO, PI_TUI_CONFIG (default $HOME/.pi/agent/open-tui.json),
# PI_TUI_NODE (which node to run; the self-test uses it to prove the SKIP arm).
# Portability: bash + node (every pi seat has node — pi's own shebang is `#!/usr/bin/env
# node`); `$HOME`/self-derived paths only, no Windows idiom.
#
# Owning rule: docs/harness-pi-seat-identity.md §5a · CONVENTIONS §6 (repo = SSOT).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed
# from a depth — "one level above me" is what turns a folder move into green-while-nothing.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO (an inherited $REPO still wins)
CONF="${PI_TUI_CONFIG:-$HOME/.pi/agent/open-tui.json}"
KEY_PATH="footerSegments.hostname"

MODE="check"; STRICT=0

err()  { printf 'pi-tui-config: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }

usage() {
  cat <<'EOF'
usage: pi-tui-config.sh [--check [--strict]] | --push | --self-test

  --check          (default) report ~/.pi/agent/open-tui.json -> footerSegments.hostname
  --check --strict exit 1 on a drift too (gate use)
  --push           ensure the key is true; create the file if absent; keep every other key
  --self-test      sandboxed canaries (temp HOME; never touches ~/.pi)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --push)      MODE="push" ;;
    --self-test) MODE="selftest" ;;
    --help|-h)   usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

# The read is done by node (the only runtime guaranteed next to pi). Where it is missing or
# broken NOTHING was read, and a silent 0 here would be a gate that passes by not running.
# PI_TUI_NODE is the sandbox hook (it wins outright); PI_TUI_NODE_PREFIX points the pinned-prefix
# search at a sandbox dir. Otherwise: HD-446's node lesson — `ssh seat '…'` is a NON-interactive
# non-login shell that reads NO profile, so PATH may not carry node even on a seat that runs pi
# perfectly (measured on the oldsrv cockpit leg 2026-10-09, where this plane answered SKIP while the
# settings plane on the same leg read the file fine). The pinned seat prefix is searched BEFORE PATH,
# exactly as pi-settings-config.sh does it.
NODE="${PI_TUI_NODE:-}"
if [ -z "$NODE" ]; then
  for c in "${PI_TUI_NODE_PREFIX:-$HOME/.local/share/pi-node}/current/bin/node" "$(command -v node 2>/dev/null || true)" "$(command -v node.exe 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { NODE="$c"; break; }
  done
fi
require_node() {
  if [ -z "$NODE" ] || ! "$NODE" -e 'process.exit(0)' >/dev/null 2>&1; then
    info "SKIP: no usable node (looked for '${NODE:-PATH node}', then the pinned seat prefix) — $CONF was NOT read; a SKIP is not a pass"
    return 2
  fi
  return 0
}

# --- the read: print "state" and nothing else ---------------------------------
# ok | missing | drift | invalid | no-verdict
# `no-verdict` is NOT `invalid`: an rc-blind read used to answer "not parseable JSON" for a node that
# had simply died (a crash, an unreadable path, or the shape that cost the Win11 seat a session — a
# Windows node.exe reached from a WSL bash, which cannot open the POSIX paths and exits with a stack
# trace). Accusing the operator's config of the probe's own death is the failure this line exists to
# prevent; nothing was read, so nothing may be claimed about the file.
read_state() {
  local out
  out="$("$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    // The verdict ENDS this program by BREAKING OUT, never by process.exit(): process.exit() discards
    // stdout bytes still buffered when stdout is a PIPE, and a command substitution IS a pipe — a
    // verdict whose bytes never landed is a verdict that never happened (docs/harness-pi-seats.md §5).
    // Top-level `return` is illegal under `node -e`, hence the labelled block.
    VERDICT: {
    if (!fs.existsSync(p)) { console.log("missing"); break VERDICT; }
    let c;
    try { c = JSON.parse(fs.readFileSync(p, "utf8")); }
    catch { console.log("invalid"); break VERDICT; }
    console.log(c && c.footerSegments && c.footerSegments.hostname === true ? "ok" : "drift");
    }
  ' "$CONF")" || { echo "no-verdict"; return; }        # node died: NO verdict exists (its own error, printed above, is the cause)
  [ -n "$out" ] || { printf 'no-verdict'; return 0; }   # a silent 0 read nothing either
  # BYTES ARE NOT A VERDICT (docs/harness-pi-seats.md §5): text that is not a state word is a lost
  # read, not a state.
  case "$out" in
    ok|missing|drift|invalid) printf '%s' "$out"; return 0 ;;
  esac
  printf 'no-verdict'
}

# --- the write: ONE key, everything else preserved ----------------------------
# A missing file becomes the MINIMAL override `{"footerSegments":{"hostname":true}}` —
# pi-open-tui deep-merges this file over its own DEFAULT_CONFIG, so a minimal override
# stays correct when upstream adds keys (a full copy of today's defaults would not).
write_key() {
  "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    // Same shape as read_state: end by breaking out, and set the STATUS rather than forcing an exit —
    // process.exit() drops piped stdout; only stderr matters to this program, and nothing is buffered
    // away when the program ends by breaking out (VERDICT below).
    VERDICT: {
    let c = {};
    if (fs.existsSync(p)) {
      try { c = JSON.parse(fs.readFileSync(p, "utf8")); }
      catch { console.error("unparseable"); process.exitCode = 3; break VERDICT; }
      if (c === null || typeof c !== "object" || Array.isArray(c)) { console.error("not an object"); process.exitCode = 3; break VERDICT; }
    }
    c.footerSegments = (c.footerSegments && typeof c.footerSegments === "object" && !Array.isArray(c.footerSegments)) ? c.footerSegments : {};
    c.footerSegments.hostname = true;
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n", "utf8");   // same shape the extension writes
    }
  ' "$CONF" 2>/dev/null
}

do_check() {
  require_node || return $?
  local st; st="$(read_state)"
  case "$st" in
    ok)      info "OK: $KEY_PATH is true in $CONF (the footer names this machine)" ; return 0 ;;
    missing) err "MISSING: no $CONF — the TUI footer will NOT name the machine (pi-open-tui defaults hostname to false). Run 'pi-tui-config.sh --push'"
             return 1 ;;
    drift)   err "DRIFT: $CONF has $KEY_PATH not true — the seat footer is anonymous (docs/harness-pi-seat-identity.md §5a)"
             [ "$STRICT" -eq 1 ] && return 1
             info "reported, not failed (add --strict for the gate form)"; return 0 ;;
    invalid) err "INVALID: $CONF is not parseable JSON — fix it by hand; this script will NOT rewrite a file it cannot read"
             return 1 ;;
    *)       err "NO VERDICT: node returned no verdict line — $CONF was NOT read; a broken probe, not a broken config file (a node error above, if any, is the cause)"
             return 2 ;;
  esac
}

do_push() {
  require_node || return $?
  local st; st="$(read_state)"
  # NEVER write over an unread file: `missing` is the only empty-file state this writes into, and a
  # probe that died must not be "fixed" by a write.
  [ "$st" = "no-verdict" ] && { err "NO VERDICT: nothing was read, so nothing is written to $CONF"; return 2; }
  [ "$st" = "ok" ] && { info "in place: $KEY_PATH is true"; return 0; }
  if [ "$st" = "invalid" ]; then
    err "REFUSAL: $CONF does not parse — refusing to overwrite it (fix the JSON, then --push)"
    return 1
  fi
  mkdir -p "$(dirname "$CONF")" 2>/dev/null || true
  write_key || { err "could not write $CONF"; return 1; }
  # A lost read-back is named as such (docs/harness-pi-seats.md §5): the write DID happen, so printing
  # "still reads 'no-verdict'" would describe a state nobody computed, and a SKIP would hide
  # a half-verified write.
  st="$(read_state)"
  [ "$st" != "no-verdict" ] || { err "wrote $CONF, but the read-back produced NO VERDICT — $CONF is unverified; run --check before trusting this line"; return 1; }
  [ "$st" = "ok" ] || { err "wrote $CONF but $KEY_PATH still reads '$st'"; return 1; }
  info "set $KEY_PATH=true in $CONF (other keys preserved; a missing file becomes the minimal override)"
  return 0
}

# --- self-test: sandboxed, temp paths only ------------------------------------
self_test() {
  local tmp fails=0
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  run_at() { local f="$1"; shift
    PI_TUI_CONFIG="$f" bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$@" >/dev/null 2>&1; }

  # No usable node means this case cannot run here, which is the rc 2 boundary --check / --push
  # already answer with (a runner account with no node read this leg RED because this line returned 1 — a seat
  # with no node has no way to cure a red, and a standing red is how a gate gets ignored).
  require_node >/dev/null 2>&1 || {
    info "SKIP: node is unusable on this seat (PATH and the pinned prefix both missed); the pi-open-tui footer self-test ran nothing and proves nothing"
    return 2
  }

  # 1. rest state -> GREEN, and --push is a byte-exact no-op (idempotence).
  printf '{\n  "inlineFooter": false,\n  "footerSegments": { "cwd": true, "hostname": true, "gitBranch": true },\n  "telemetry": { "enabled": true }\n}\n' > "$tmp/rest.json"
  run_at "$tmp/rest.json" --check --strict && info "rest-state       GREEN" \
    || { err "canary: a compliant config failed its own check"; fails=$((fails+1)); }
  cp "$tmp/rest.json" "$tmp/rest.before"
  run_at "$tmp/rest.json" --push
  cmp -s "$tmp/rest.before" "$tmp/rest.json" && info "push-idempotent  GREEN (byte-exact no-op)" \
    || { err "canary: --push rewrote a compliant file (churn on every seat run)"; fails=$((fails+1)); }

  # 2. hostname false, other keys present -> strict MUST fail; --push repairs the ONE key.
  mk_tuned() { printf '{\n  "inlineFooter": false,\n  "cursorStyle": "block",\n  "footerSegments": { "cwd": true, "hostname": %s, "gitBranch": true },\n  "telemetry": { "enabled": true, "tps": true }\n}\n' "$1" > "$2"; }
  mk_tuned false "$tmp/drift.json"
  if run_at "$tmp/drift.json" --check --strict; then err "canary passed: hostname:false stayed green"; fails=$((fails+1)); else info "drift-canary     caught"; fi
  if run_at "$tmp/drift.json" --check; then info "report-only      GREEN (drift does not fail a human run)"; else err "canary: --check without --strict failed a report-only state"; fails=$((fails+1)); fi
  if ! run_at "$tmp/drift.json" --push; then err "canary: --push could not repair hostname:false"; fails=$((fails+1)); fi
  "$NODE" -e '
    const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const ok = c.footerSegments.hostname === true && c.inlineFooter === false && c.cursorStyle === "block"
      && c.footerSegments.cwd === true && c.footerSegments.gitBranch === true
      && c.telemetry.enabled === true && c.telemetry.tps === true;
    process.exit(ok ? 0 : 1);
  ' "$tmp/drift.json" && info "surgical-write   GREEN (only the one key moved)" \
    || { err "canary: --push changed a key it did not come to set"; fails=$((fails+1)); }

  # 3. missing file -> strict MUST fail; --push creates the MINIMAL override (deep-merged
  #    over the package defaults upstream, so it must not carry a copy of those defaults).
  if run_at "$tmp/none.json" --check --strict; then err "canary passed: MISSING file stayed green"; fails=$((fails+1)); else info "missing-canary   caught"; fi
  if ! run_at "$tmp/none.json" --push; then err "canary: --push did not create a missing file"; fails=$((fails+1)); fi
  "$NODE" -e '
    const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const keys = Object.keys(c);
    process.exit(keys.length === 1 && keys[0] === "footerSegments" && c.footerSegments.hostname === true ? 0 : 1);
  ' "$tmp/none.json" && info "minimal-create   GREEN (override carries only the required key)" \
    || { err "canary: the created file is not the minimal override"; fails=$((fails+1)); }

  # 4. unparseable file -> check fails AND --push REFUSES (never rewrite what we cannot read).
  printf '{ "footerSegments": { hostname: } }\n' > "$tmp/bad.json"
  cp "$tmp/bad.json" "$tmp/bad.before"
  if run_at "$tmp/bad.json" --check --strict; then err "canary passed: unparseable JSON stayed green"; fails=$((fails+1)); else info "invalid-canary   caught"; fi
  if run_at "$tmp/bad.json" --push; then err "canary passed: --push overwrote an unparseable file"; fails=$((fails+1)); else info "refusal-canary   caught"; fi
  if cmp -s "$tmp/bad.before" "$tmp/bad.json"; then info "file-untouched   GREEN"; else err "canary: a REFUSAL still modified the file"; fails=$((fails+1)); fi

  # 5. unusable node -> SKIP (rc 2), never a pass. Without this arm the whole script could
  #    "pass" on a seat by reading nothing.
  rc=0
  PI_TUI_NODE="$tmp/there-is-no-such-node" PI_TUI_CONFIG="$tmp/rest.json" \
    bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --check --strict >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && info "skip-arm         GREEN (rc 2 = SKIP, not a pass)" \
    || { err "canary: the no-node path returned $rc — a SKIP must be 2, never 0 or 1"; fails=$((fails+1)); }

  # 5b. a NON-LOGIN leg: PATH carries no node, but the pinned seat prefix does (HD-446). The seat
  #     must be READ, not SKIPPED. Deleting the pinned-prefix leg from the lookup reddens this arm:
  #     the search finds nothing and the script answers rc 2.
  mkdir -p "$tmp/prefix/current/bin"
  real_node="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
  sysbin="/usr/bin:/bin"
  if [ -z "$real_node" ]; then
    info "pinned-node      SKIP — no node on this host to stage the fixture with"
  elif env PATH="$sysbin" sh -c 'command -v node' >/dev/null 2>&1; then
    info "pinned-node      SKIP — node is in $sysbin here, the bare-PATH fixture would prove nothing"
  else
    ln -sf "$real_node" "$tmp/prefix/current/bin/node"
    rc=0
    env -u PI_TUI_NODE PATH="$sysbin" PI_TUI_NODE_PREFIX="$tmp/prefix" PI_TUI_CONFIG="$tmp/rest.json" \
      "$(command -v bash)" "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --check >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 2 ] && info "pinned-node      GREEN (the seat prefix is read when PATH is bare)" \
      || { err "canary: a bare-PATH leg SKIPPED although the pinned prefix holds node (HD-446)"; fails=$((fails+1)); }
  fi

  # 5c. a node that ANSWERS require_node's probe and THEN dies -> rc 2 NO VERDICT, and the words
  #     "not parseable" must not appear. The accusation this arm holds down once sent an operator to
  #     fix a file the script had never opened (an rc-blind read mapped a dead node to `invalid`).
  #     Both halves — the rc AND the words — plus the write guard: a probe that died may not "fix" a
  #     file it has not read.
  printf '#!/bin/sh\nif [ "$#" -le 2 ]; then exit 0; fi\necho "fake-node: the fixture cannot open the file" >&2\nexit 1\n' > "$tmp/dying-node"
  chmod +x "$tmp/dying-node" 2>/dev/null || true
  rc=0; out5c=""
  out5c="$(PI_TUI_NODE="$tmp/dying-node" PI_TUI_CONFIG="$tmp/rest.json" \
            bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --check --strict 2>&1)" || rc=$?
  if [ "$rc" -ne 2 ]; then
    err "canary: a node that died without a verdict returned $rc — nothing was read, so it must be 2"; fails=$((fails+1))
  else
    case "$out5c" in
      *NO\ VERDICT*) case "$out5c" in
        *INVALID*|*"not parseable"*|*OK:*|*DRIFT*) err "canary: a dead probe still printed a verdict about $CONF"; fails=$((fails+1)) ;;
        *) info "no-verdict         GREEN (rc 2, and no claim about the file)" ;;
      esac ;;
      *) err "canary: the dead-probe path printed no NO VERDICT line"; fails=$((fails+1)) ;;
    esac
  fi
  cp -p "$tmp/rest.json" "$tmp/rest5c.before" 2>/dev/null || : > "$tmp/rest5c.before"
  PI_TUI_NODE="$tmp/dying-node" PI_TUI_CONFIG="$tmp/rest.json" \
    bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --push >/dev/null 2>&1 || rc=$?
  cmp -s "$tmp/rest5c.before" "$tmp/rest.json" \
    && info "no-verdict-write   GREEN (a probe that died wrote nothing)" \
    || { err "canary: --push wrote $CONF although node had died"; fails=$((fails+1)); }

  # 5d. a record that arrives WITH bytes but with NO state word in it (docs/harness-pi-seats.md §5,
  #     reproduced on the win11 seat 2026-10-21, where the settings leg answered "the keys still
  #     read '' ()" for a lost head). Bytes are not a verdict — the vocabulary is. rc 2, no
  #     claim about the file, and no write.
  printf '#!/bin/sh\nif [ "$#" -le 2 ]; then exit 0; fi\nprintf "\\n_orphaned_after_a_lost_head\\n"\nexit 0\n' > "$tmp/headlost-node"
  chmod +x "$tmp/headlost-node" 2>/dev/null || true
  local _o5d="" _rc5d=0
  _rc5d=0
  _o5d="$(PI_TUI_NODE="$tmp/headlost-node" PI_TUI_CONFIG="$tmp/rest.json" \
          bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --check --strict 2>&1)" || _rc5d=$?
  if [ "$_rc5d" -ne 2 ]; then
    err "canary: a verdict with no state word returned $_rc5d — bytes are not a verdict, so it must be 2"; fails=$((fails+1))
  else
    case "$_o5d" in
      *NO\ VERDICT*) case "$_o5d" in
        *INVALID*|*"not parseable"*|*"still reads"*|*OK:*|*DRIFT*) err "canary: a head-less verdict still printed a verdict about $CONF"; fails=$((fails+1)) ;;
        *) info "lost-head          GREEN (rc 2, and no claim about the file)" ;;
      esac ;;
      *) err "canary: the head-lost path printed no NO VERDICT line"; fails=$((fails+1)) ;;
    esac
  fi
  cp -p "$tmp/rest.json" "$tmp/rest5d.before" 2>/dev/null || : > "$tmp/rest5d.before"
  PI_TUI_NODE="$tmp/headlost-node" PI_TUI_CONFIG="$tmp/rest.json" \
    bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --push >/dev/null 2>&1 || true
  cmp -s "$tmp/rest5d.before" "$tmp/rest.json" \
    && info "lost-head-write    GREEN (--push wrote nothing on a verdict with no state word)" \
    || { err "canary: --push wrote $CONF on a verdict that carried no state word"; fails=$((fails+1)); }

  # 5e. no verdict path forces an exit: process.exit() drops stdout bytes still buffered when
  #     stdout is a pipe, so read_state/write_key end by breaking out of a labelled block.
  # The scan covers the VERDICT MACHINERY only — everything above self_test(), whose own assertions
  # may exit with a status because they print nothing. Prose that merely NAMES process.exit is not a
  # call, and require_node's `-e 'process.exit(0)'` probe is allowed: it prints nothing, so it has
  # nothing to lose. Why the awk carries no comments: a `#` inside a single-quoted program embedded in
  # "$( )" costs bash 5.3 the quote tracking for the rest of the line, and the awk parentheses then
  # become shell syntax — the arm dies as a syntax error, not as a verdict.
  local _forced=""
  _forced="$(awk 'index($0, "self_test() {") == 1 { exit }
                 /process\.exit\(/ {
                   line = $0
                   if (line ~ /^[[:space:]]*(\/\/|#)/) next
                   if (line ~ /-e .process\.exit\(0\)/) next
                   printf "L%s:", NR; sub(/^[[:space:]]+/, "", line); printf "%s ", line
                 }' "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")")" || true
  if [ -n "$_forced" ]; then
    err "canary: a verdict path forces an exit — piped stdout can be dropped, use 'break VERDICT' ($_forced)"; fails=$((fails+1))
  else
    info "drain-no-exit      GREEN (no verdict path calls process.exit)"
  fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# ================================ dispatch ======================================
case "$MODE" in
  selftest) self_test; exit $? ;;
  check)    do_check; exit $? ;;
  push)     do_push; exit $? ;;
esac
