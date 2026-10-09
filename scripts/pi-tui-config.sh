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
# no machine in it — a silent loss of the invariant docs/pi-harness.md §5a calls "the only
# place that fact is written down", and the loss lands exactly where nobody looks: on the
# SSH legs, where the prompt is gone. Hence a check, not a README line.
#
# WHY ONLY ONE KEY
# ----------------
# Everything else in that file is machine-local tuning the operator changes through pi's
# `/open-tui` command, and the package REWRITES the file on every settings change. A
# byte-compare drift gate would therefore fight the extension's own settings UI — the
# same boundary pi-harness.md §5 draws for settings.json ("the block is the part that must
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
#             2 SKIP — no node on PATH, so NOTHING was read (a SKIP is never a pass).
#
# Env (sandbox hooks only): REPO, PI_TUI_CONFIG (default $HOME/.pi/agent/open-tui.json),
# PI_TUI_NODE (which node to run; the self-test uses it to prove the SKIP arm).
# Portability: bash + node (every pi seat has node — pi's own shebang is `#!/usr/bin/env
# node`); `$HOME`/self-derived paths only, no Windows idiom.
#
# Owning rule: docs/pi-harness.md §5a · CONVENTIONS §6 (repo = SSOT).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
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
# ok | missing | drift | invalid  (invalid = unreadable JSON, not a missing key)
read_state() {
  local out
  out="$("$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    if (!fs.existsSync(p)) { console.log("missing"); process.exit(0); }
    let c;
    try { c = JSON.parse(fs.readFileSync(p, "utf8")); }
    catch { console.log("invalid"); process.exit(0); }
    console.log(c && c.footerSegments && c.footerSegments.hostname === true ? "ok" : "drift");
  ' "$CONF" 2>/dev/null)" || { echo "invalid"; return; }
  printf '%s' "${out:-invalid}"
}

# --- the write: ONE key, everything else preserved ----------------------------
# A missing file becomes the MINIMAL override `{"footerSegments":{"hostname":true}}` —
# pi-open-tui deep-merges this file over its own DEFAULT_CONFIG, so a minimal override
# stays correct when upstream adds keys (a full copy of today's defaults would not).
write_key() {
  "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    let c = {};
    if (fs.existsSync(p)) {
      try { c = JSON.parse(fs.readFileSync(p, "utf8")); }
      catch { console.error("unparseable"); process.exit(3); }
      if (c === null || typeof c !== "object" || Array.isArray(c)) { console.error("not an object"); process.exit(3); }
    }
    c.footerSegments = (c.footerSegments && typeof c.footerSegments === "object" && !Array.isArray(c.footerSegments)) ? c.footerSegments : {};
    c.footerSegments.hostname = true;
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n", "utf8");   // same shape the extension writes
  ' "$CONF" 2>/dev/null
}

do_check() {
  require_node || return $?
  local st; st="$(read_state)"
  case "$st" in
    ok)      info "OK: $KEY_PATH is true in $CONF (the footer names this machine)" ; return 0 ;;
    missing) err "MISSING: no $CONF — the TUI footer will NOT name the machine (pi-open-tui defaults hostname to false). Run 'pi-tui-config.sh --push'"
             return 1 ;;
    drift)   err "DRIFT: $CONF has $KEY_PATH not true — the seat footer is anonymous (docs/pi-harness.md §5a)"
             [ "$STRICT" -eq 1 ] && return 1
             info "reported, not failed (add --strict for the gate form)"; return 0 ;;
    *)       err "INVALID: $CONF is not parseable JSON — fix it by hand; this script will NOT rewrite a file it cannot read"
             return 1 ;;
  esac
}

do_push() {
  require_node || return $?
  local st; st="$(read_state)"
  [ "$st" = "ok" ] && { info "in place: $KEY_PATH is true"; return 0; }
  if [ "$st" = "invalid" ]; then
    err "REFUSAL: $CONF does not parse — refusing to overwrite it (fix the JSON, then --push)"
    return 1
  fi
  mkdir -p "$(dirname "$CONF")" 2>/dev/null || true
  write_key || { err "could not write $CONF"; return 1; }
  st="$(read_state)"
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

  require_node || { err "self-test needs node — it cannot prove anything without it"; return 1; }

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

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# ================================ dispatch ======================================
case "$MODE" in
  selftest) self_test; exit $? ;;
  check)    do_check; exit $? ;;
  push)     do_push; exit $? ;;
esac
