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
# VERDICTS
# --------
#   --check            OK / DRIFT / MISSING / INVALID (report-only)
#   --check --strict   exit 1 on a drift too (gate form; validate-all item 31)
#   --push             write the payload, 0600, keep a timestamped backup
#                      (the extension file holds no secrets today, but 0600 is
#                      the ownership default for anything under ~/.pi/agent)
#   --self-test        sandboxed canaries; both halves of every rule above
#
# Exit codes: 0 OK / repaired · 1 drift(strict), missing, invalid, refusal ·
#             2 SKIP — no usable node, so nothing was read.
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
                     against the `_subagentConfig` block of pi-agent/settings-ssot.json
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

# --- the compare / the write (ONE node program, two actions) ------------------
# STATE<TAB>detail    ok | drift | missing | invalid
run_node() {
  local action="$1"
  "$NODE" -e '
    const fs = require("fs");
    const [ssotPath, confPath, action] = process.argv.slice(1);
    const ssot = JSON.parse(fs.readFileSync(ssotPath, "utf8"));
    if (!ssot._subagentConfig || typeof ssot._subagentConfig !== "object") {
      console.log("missing\t_subagentConfig block absent from the SSOT"); process.exit(0);
    }
    const want = JSON.stringify(ssot._subagentConfig, null, 2) + "\n";
    const state = (s, d) => { console.log(s + "\t" + d); };
    if (!fs.existsSync(confPath)) { state("missing", ""); process.exit(0); }
    let cur;
    try { cur = fs.readFileSync(confPath, "utf8"); }
    catch { state("invalid", ""); process.exit(0); }
    let parsed;
    try { parsed = JSON.parse(cur); }
    catch { state("invalid", ""); process.exit(0); }
    if (typeof parsed !== "object" || parsed === null) { state("invalid", ""); process.exit(0); }
    if (JSON.stringify(parsed, null, 2) + "\n" === want) { state("ok", ""); process.exit(0); }
    state("drift", "_subagentConfig"); process.exit(0);
  ' "$SSOT" "$CONF" "$action"
}
invoke() {
  local out l1
  out="$(run_node "$1")"
  l1="${out%%$'\n'*}"
  STATE="${l1%%$'\t'*}"
  DETAIL="${l1#*$'\t'}"; [ "$DETAIL" = "$l1" ] && DETAIL=""
}

do_check() {
  require_node || return $?
  invoke check
  case "$STATE" in
    ok)      info "OK: $CONF carries the _subagentConfig payload of pi-agent/settings-ssot.json"; return 0 ;;
    drift)   err "DRIFT: these keys differ from the SSOT payload: $DETAIL"
             [ "$STRICT" -eq 1 ] && return 1
             info "reported, not failed (add --strict for the gate form; --push converges)"; return 0 ;;
    missing) err "MISSING: no $CONF — the subagent payload is not installed (run --push, or an install-pi-*.sh)"; return 1 ;;
    *)       err "INVALID: $CONF is not parseable JSON — fix it by hand; this script will not rewrite a file it cannot read"; return 1 ;;
  esac
}

do_push() {
  require_node || return $?
  local stamp _d
  invoke push
  case "$STATE" in
    ok)      info "in place: $CONF carries the _subagentConfig payload ($CONF)"; return 0 ;;
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
  invoke check
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
  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

case "$MODE" in
  selftest) self_test; exit $? ;;
  check)    do_check; exit $? ;;
  push)     do_push; exit $? ;;
esac